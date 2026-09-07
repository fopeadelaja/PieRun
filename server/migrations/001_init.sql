-- ============================================================================
-- PieRun — PostgreSQL schema
--
-- Every constraint is tagged with the invariant it implements (F5, S4, R2 …)
-- from INVARIANTS.md. Anything in that list WITHOUT a tag here is enforced in
-- application code and needs a test instead — that mapping is the point of
-- reading this file next to the invariant list.
-- ============================================================================

CREATE TYPE order_status   AS ENUM ('PENDING','ACCEPTED','COMPLETED','REJECTED','CANCELLED');
CREATE TYPE payment_status AS ENUM ('PENDING_CONFIRMATION','CONFIRMED','REJECTED');
CREATE TYPE weekday        AS ENUM ('MON','TUE','WED','THU','FRI','SAT','SUN');


-- ----------------------------------------------------------------------------
-- users
--
-- Note what happened to the Admin subtype: once work_days and cutoff moved to
-- `settings` (D-012), Admin had no attributes left. Inheritance modelling a
-- type with no distinct data is just a role flag.
-- ----------------------------------------------------------------------------
CREATE TABLE users (
  id            BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,   -- surrogate (D-024),
  first_name    TEXT NOT NULL CHECK (length(trim(first_name)) > 0),
  last_name     TEXT NOT NULL CHECK (length(trim(last_name)) > 0),
  email         TEXT NOT NULL UNIQUE,                              -- R8: natural key
  password_hash TEXT NOT NULL,
  is_admin      BOOLEAN NOT NULL DEFAULT FALSE,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- D-012: at most one admin. A partial unique index on a constant expression is
-- the standard way to say "at most one row satisfying this predicate."
CREATE UNIQUE INDEX one_admin_only ON users ((TRUE)) WHERE is_admin;


-- ----------------------------------------------------------------------------
-- settings — R5: exactly one row, forever
-- ----------------------------------------------------------------------------
CREATE TABLE settings (
  id         BOOLEAN PRIMARY KEY DEFAULT TRUE CHECK (id),          -- R5 singleton trick
  work_days  weekday[] NOT NULL CHECK (array_length(work_days,1) > 0),  -- T5
  cutoff     TIME NOT NULL DEFAULT '09:00',                        -- D-022
  timezone   TEXT NOT NULL DEFAULT 'Africa/Lagos',                 -- T7
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO settings (work_days) VALUES (ARRAY['MON','TUE','THU']::weekday[]);


-- ----------------------------------------------------------------------------
-- snacks — never hard-deleted (R7). The two flags are independent (D-021a);
-- orderability is the AND, derived at read time.
-- ----------------------------------------------------------------------------
CREATE TABLE snacks (
  id           BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  name         TEXT NOT NULL UNIQUE,
  price        NUMERIC(12,2) NOT NULL CHECK (price > 0),           -- F1, D-015
  is_available BOOLEAN NOT NULL DEFAULT TRUE,
  is_retired   BOOLEAN NOT NULL DEFAULT FALSE,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);


-- ----------------------------------------------------------------------------
-- orders
--
-- The biconditional CHECKs below are the most useful pattern in this file:
--     CHECK ( (some_condition) = (column IS NOT NULL) )
-- reads as "this column is populated EXACTLY when that condition holds." It
-- catches both halves of the bug — a missing value and a value that shouldn't
-- be there — where two separate CHECKs would only catch one.
-- ----------------------------------------------------------------------------
CREATE TABLE orders (
  id               BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id          BIGINT NOT NULL REFERENCES users(id) ON DELETE RESTRICT,  -- R1
  status           order_status NOT NULL DEFAULT 'PENDING',
  estimated_total  NUMERIC(12,2) NOT NULL CHECK (estimated_total > 0),       -- S6, D-018
  total            NUMERIC(12,2) CHECK (total > 0),
  fulfillment_date DATE,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  accepted_at      TIMESTAMPTZ,
  rejected_at      TIMESTAMPTZ,
  cancelled_at     TIMESTAMPTZ,
  completed_at     TIMESTAMPTZ,

  -- S5: the total exists exactly when it has been frozen
  CONSTRAINT total_iff_accepted CHECK (
    (status IN ('ACCEPTED','COMPLETED')) = (total IS NOT NULL)
  ),
  -- T1: likewise the fulfillment date (derived on read while PENDING)
  CONSTRAINT date_iff_accepted CHECK (
    (status IN ('ACCEPTED','COMPLETED')) = (fulfillment_date IS NOT NULL)
  ),
  -- T3: each timestamp exists exactly when its state has been reached
  CONSTRAINT ts_accepted  CHECK ((status IN ('ACCEPTED','COMPLETED')) = (accepted_at  IS NOT NULL)),
  CONSTRAINT ts_rejected  CHECK ((status = 'REJECTED')                = (rejected_at  IS NOT NULL)),
  CONSTRAINT ts_cancelled CHECK ((status = 'CANCELLED')               = (cancelled_at IS NOT NULL)),
  CONSTRAINT ts_completed CHECK ((status = 'COMPLETED')               = (completed_at IS NOT NULL)),

  -- T4: monotonic lifecycle
  CONSTRAINT ts_after_created CHECK (accepted_at IS NULL OR accepted_at >= created_at),
  CONSTRAINT ts_after_accept  CHECK (completed_at IS NULL OR accepted_at IS NULL
                                     OR completed_at >= accepted_at)
);

CREATE INDEX orders_by_user   ON orders (user_id, status);
CREATE INDEX orders_admin_queue ON orders (status, fulfillment_date)
  WHERE status IN ('PENDING','ACCEPTED');


-- ----------------------------------------------------------------------------
-- order_items
--
-- R2: PK (order_id, snack_id) — a snack appears at most once per order; two of
-- the same snack is quantity = 2, never two rows.
--
-- ON DELETE RESTRICT on snack_id is R7 enforced by the database: the delete
-- physically cannot succeed once history exists. Every FK's ON DELETE clause is
-- a business decision, not a technical default.
-- ----------------------------------------------------------------------------
CREATE TABLE order_items (
  order_id BIGINT NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
  snack_id BIGINT NOT NULL REFERENCES snacks(id) ON DELETE RESTRICT,   -- R7
  quantity INT NOT NULL CHECK (quantity > 0),                          -- F2
  price    NUMERIC(12,2) CHECK (price > 0),
  total    NUMERIC(12,2),

  PRIMARY KEY (order_id, snack_id),                                    -- R2

  -- F3: total = quantity × price, and both are NULL together until acceptance.
  -- Same NULL trap as in `payments` — without the IS NOT NULL guards, a priced
  -- item with a NULL total evaluates to FALSE OR NULL = NULL and is accepted.
  CONSTRAINT total_is_product CHECK (
    (price IS NULL AND total IS NULL)
    OR (price IS NOT NULL AND total IS NOT NULL AND total = quantity * price)
  )
);

-- S4 (price populated exactly when the ORDER is accepted) cannot be a CHECK —
-- it references another table. This is where CHECK runs out and triggers begin.
CREATE OR REPLACE FUNCTION enforce_price_freeze() RETURNS TRIGGER AS $$
DECLARE s order_status;
BEGIN
  SELECT status INTO s FROM orders WHERE id = NEW.order_id;
  IF (s IN ('ACCEPTED','COMPLETED')) <> (NEW.price IS NOT NULL) THEN
    RAISE EXCEPTION
      'S4 violated: order % is %, but item price is %',
      NEW.order_id, s, COALESCE(NEW.price::text, 'NULL');
  END IF;
  RETURN NEW;
END $$ LANGUAGE plpgsql;

CREATE CONSTRAINT TRIGGER trg_price_freeze
  AFTER INSERT OR UPDATE ON order_items
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE FUNCTION enforce_price_freeze();


-- ----------------------------------------------------------------------------
-- payments
-- ----------------------------------------------------------------------------
CREATE TABLE payments (
  id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id         BIGINT NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
  reported_amount NUMERIC(12,2) NOT NULL CHECK (reported_amount > 0),  -- F9
  received_amount NUMERIC(12,2) CHECK (received_amount >= 0),          -- F9
  status          payment_status NOT NULL DEFAULT 'PENDING_CONFIRMATION',
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  confirmed_at    TIMESTAMPTZ,

  -- NOTE the explicit IS NOT NULL guards below. A CHECK constraint passes when
  -- it evaluates to NULL, not just when it evaluates to TRUE. Written as
  --     status <> 'CONFIRMED' OR received_amount > 0
  -- a CONFIRMED row with received_amount = NULL gives FALSE OR NULL = NULL,
  -- and the row is accepted. Any CHECK touching a nullable column needs this.
  CONSTRAINT confirmed_shape CHECK (          -- P2
    status <> 'CONFIRMED'
      OR (received_amount IS NOT NULL AND received_amount > 0
          AND confirmed_at IS NOT NULL)
  ),
  CONSTRAINT rejected_shape CHECK (           -- P3, D-017: rejection = no money arrived
    status <> 'REJECTED'
      OR (received_amount IS NOT NULL AND received_amount = 0)
  ),
  CONSTRAINT pending_shape CHECK (            -- P4
    status <> 'PENDING_CONFIRMATION'
      OR (received_amount IS NULL AND confirmed_at IS NULL)
  )
);

CREATE INDEX payments_by_user ON payments (user_id, status);


-- ----------------------------------------------------------------------------
-- order_payments — the M:N allocation table
-- ----------------------------------------------------------------------------
CREATE TABLE order_payments (
  order_id       BIGINT NOT NULL REFERENCES orders(id)   ON DELETE RESTRICT,
  payment_id     BIGINT NOT NULL REFERENCES payments(id) ON DELETE CASCADE,
  amount_applied NUMERIC(12,2) NOT NULL CHECK (amount_applied > 0),   -- F5
  PRIMARY KEY (order_id, payment_id)                                  -- R3
);

CREATE INDEX order_payments_by_payment ON order_payments (payment_id);

-- F6 and F7 are AGGREGATE invariants — they constrain a SUM across rows, which
-- a CHECK constraint fundamentally cannot express. This is the single most
-- important limitation to internalise about CHECK: it sees one row at a time.
--
-- DEFERRABLE INITIALLY DEFERRED matters here. UC-2 inserts allocation rows one
-- at a time; an immediate trigger would fire mid-loop against a half-written
-- state. Deferring to COMMIT checks the finished result, which is the only
-- moment the invariant is meaningfully true.
CREATE OR REPLACE FUNCTION enforce_allocation_limits() RETURNS TRIGGER AS $$
DECLARE
  allocated NUMERIC(12,2);
  received  NUMERIC(12,2);
  ord_total NUMERIC(12,2);
BEGIN
  -- F6: cannot allocate money that was never received
  SELECT COALESCE(SUM(amount_applied),0) INTO allocated
    FROM order_payments WHERE payment_id = NEW.payment_id;
  SELECT received_amount INTO received
    FROM payments WHERE id = NEW.payment_id;

  IF allocated > COALESCE(received, 0) THEN
    RAISE EXCEPTION 'F6 violated: payment % allocated % but received %',
      NEW.payment_id, allocated, received;
  END IF;

  -- F7: no over-allocation; surplus stays unallocated as a tip (D-002)
  SELECT COALESCE(SUM(amount_applied),0) INTO allocated
    FROM order_payments WHERE order_id = NEW.order_id;
  SELECT total INTO ord_total FROM orders WHERE id = NEW.order_id;

  IF allocated > ord_total THEN
    RAISE EXCEPTION 'F7 violated: order % has % applied against a total of %',
      NEW.order_id, allocated, ord_total;
  END IF;

  RETURN NEW;
END $$ LANGUAGE plpgsql;

CREATE CONSTRAINT TRIGGER trg_allocation_limits
  AFTER INSERT OR UPDATE ON order_payments
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE FUNCTION enforce_allocation_limits();


-- ----------------------------------------------------------------------------
-- payment_amendments — append-only audit of receivedAmount edits (D-020a, F13)
-- ----------------------------------------------------------------------------
CREATE TABLE payment_amendments (
  id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  payment_id BIGINT NOT NULL REFERENCES payments(id) ON DELETE RESTRICT,
  old_amount NUMERIC(12,2) NOT NULL,
  new_amount NUMERIC(12,2) NOT NULL,
  reason     TEXT NOT NULL CHECK (length(trim(reason)) > 0),
  amended_by BIGINT NOT NULL REFERENCES users(id),
  amended_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT amount_actually_changed CHECK (new_amount <> old_amount)
);

-- Append-only enforced by privilege, not convention. Grant INSERT and SELECT
-- to the application role and nothing else.
REVOKE UPDATE, DELETE ON payment_amendments FROM PUBLIC;


-- ----------------------------------------------------------------------------
-- notifications — a real entity (D-011)
-- ----------------------------------------------------------------------------
CREATE TABLE notifications (
  id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id    BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,   -- R6
  type       TEXT NOT NULL,
  body       TEXT NOT NULL,
  payload    JSONB NOT NULL DEFAULT '{}',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  read_at    TIMESTAMPTZ
);

CREATE INDEX notifications_unread ON notifications (user_id, created_at DESC)
  WHERE read_at IS NULL;


-- ============================================================================
-- Derived reads
--
-- D-007 said reconciliation is derived rather than stored. This view IS that
-- decision — the single place settlement is computed, so it can never drift
-- from itself. Note the FILTER: only CONFIRMED payments count (F8).
-- ============================================================================
CREATE VIEW order_settlement AS
SELECT
  o.id                AS order_id,
  o.user_id,
  o.status,
  o.total,
  o.fulfillment_date,
  COALESCE(SUM(op.amount_applied) FILTER (WHERE p.status = 'CONFIRMED'), 0) AS applied,
  o.total
    - COALESCE(SUM(op.amount_applied) FILTER (WHERE p.status = 'CONFIRMED'), 0)
                      AS outstanding
FROM orders o
LEFT JOIN order_payments op ON op.order_id = o.id
LEFT JOIN payments p        ON p.id = op.payment_id
WHERE o.status IN ('ACCEPTED','COMPLETED')
GROUP BY o.id;


-- UC-O-9, the chase list: the single most valuable screen in the product, and
-- the thing the WhatsApp process could never produce.
CREATE VIEW chase_list AS
SELECT u.first_name,u.last_name, u.email, s.order_id, s.fulfillment_date, s.outstanding
FROM order_settlement s
JOIN users u ON u.id = s.user_id
WHERE s.status = 'COMPLETED' AND s.outstanding > 0
ORDER BY u.last_name, u.first_name, s.fulfillment_date;


-- ============================================================================
-- Left to application code (each needs a test — nothing structural stops them)
--
--   S1, S2, P1   state transition legality  → conditional UPDATE + rowcount check
--   S3, A1, A2   authorization
--   A4           admin may not place orders
--   F10          reportedAmount never enters a calculation
--   F11          FIFO ordering and tiebreak
--   F15          notify on un-settlement
--   R4           an order has at least one item
--   R7a          server-side availability validation at submission
--   T2, T6, T7   workday / cutoff / timezone logic
--
-- Everything above this line the database guarantees. Everything below it, a
-- future bug can break in silence. That difference is why the tags exist.
-- ============================================================================
