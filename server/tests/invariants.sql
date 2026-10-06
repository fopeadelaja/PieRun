-- ============================================================================
-- PieRun — schema invariant tests
--
-- Every statement below the SETUP block is a deliberate violation of one
-- tagged invariant from 001_init.sql and MUST produce an ERROR.
--
-- Run:   psql -U postgres -d pierun -f server/tests/invariants.sql   (from repo root)
-- Read:  every "## <tag>" label should be followed by an ERROR line.
--        A label followed by "INSERT 0 1" / "UPDATE 1" / "DELETE 1" means the
--        schema let a bad row through. That is a schema bug.
--
-- Mechanics:
--   ON_ERROR_ROLLBACK on  -> psql wraps each statement in a savepoint, so a
--                            failed statement does not abort the transaction.
--   SET CONSTRAINTS ALL IMMEDIATE -> the deferred constraint triggers (S4, F6,
--                            F7) fire at end of statement instead of at COMMIT,
--                            so they can be tested one statement at a time.
--   ROLLBACK at the end   -> the database is left exactly as it was found.
--
-- Not testable here:
--   REVOKE UPDATE, DELETE ON payment_amendments. Superusers bypass privilege
--   checks. Test it later, connected as the application role.
-- ============================================================================

\set ON_ERROR_ROLLBACK on
\set ON_ERROR_STOP off
\pset footer off

BEGIN;

-- ----------------------------------------------------------------------------
-- SETUP: valid rows the violations need. If any of these fail, stop and fix
-- the setup; every later result is meaningless.
-- ----------------------------------------------------------------------------
\echo '## SETUP (no errors expected in this block)'

INSERT INTO users (first_name, last_name, username, password_hash, is_admin)
VALUES ('Setup', 'User',  'setup', 'x', FALSE),
       ('Setup', 'Admin', 'admin', 'x', TRUE);

INSERT INTO snacks (name, price) VALUES ('Setup Snack A', 100.00), ('Setup Snack B', 50.00);

-- a PENDING order (estimate only, nothing frozen)
INSERT INTO orders (user_id, estimated_total)
VALUES ((SELECT id FROM users WHERE username = 'setup'), 200.00);

-- two ACCEPTED orders (totals frozen)
INSERT INTO orders (user_id, status, estimated_total, total, fulfillment_date, accepted_at)
VALUES ((SELECT id FROM users WHERE username = 'setup'),
        'ACCEPTED', 200.00, 200.00, CURRENT_DATE, now()),
       ((SELECT id FROM users WHERE username = 'setup'),
        'ACCEPTED', 500.00, 500.00, CURRENT_DATE, now());

-- one item on the first accepted order, prices frozen
INSERT INTO order_items (order_id, snack_id, quantity, price, total)
VALUES ((SELECT id FROM orders WHERE status = 'ACCEPTED' AND total = 200.00),
        (SELECT id FROM snacks WHERE name = 'Setup Snack A'), 2, 100.00, 200.00);

-- a CONFIRMED payment of 200 and a CONFIRMED payment of 1000
INSERT INTO payments (user_id, reported_amount, received_amount, status, confirmed_at)
VALUES ((SELECT id FROM users WHERE username = 'setup'), 200.00,  200.00,  'CONFIRMED', now()),
       ((SELECT id FROM users WHERE username = 'setup'), 1000.00, 1000.00, 'CONFIRMED', now());

-- a PENDING_CONFIRMATION payment (nothing received yet)
INSERT INTO payments (user_id, reported_amount)
VALUES ((SELECT id FROM users WHERE username = 'setup'), 100.00);

-- 100 of the 200 payment applied to the 200 order
INSERT INTO order_payments (order_id, payment_id, amount_applied)
VALUES ((SELECT id FROM orders   WHERE status = 'ACCEPTED' AND total = 200.00),
        (SELECT id FROM payments WHERE received_amount = 200.00), 100.00);

-- from here on, deferred triggers fire per statement
SET CONSTRAINTS ALL IMMEDIATE;

-- ============================================================================
-- users
-- ============================================================================
\echo '## users: first_name must not be blank'
INSERT INTO users (first_name, last_name, username, password_hash) VALUES ('', 'X', 'u1', 'x');

\echo '## users: first_name must not be whitespace only'
INSERT INTO users (first_name, last_name, username, password_hash) VALUES ('   ', 'X', 'u2', 'x');

\echo '## users: last_name must not be blank'
INSERT INTO users (first_name, last_name, username, password_hash) VALUES ('X', '', 'u3', 'x');

\echo '## R8: username is unique'
INSERT INTO users (first_name, last_name, username, password_hash) VALUES ('X', 'X', 'setup', 'x');

\echo '## R8: username is unique case-insensitively (SETUP vs setup)'
INSERT INTO users (first_name, last_name, username, password_hash) VALUES ('X', 'X', 'SETUP', 'x');

\echo '## D-012: at most one admin'
INSERT INTO users (first_name, last_name, username, password_hash, is_admin) VALUES ('X', 'X', 'admin2', 'x', TRUE);

\echo '## D-012: cannot promote a second admin by UPDATE either'
UPDATE users SET is_admin = TRUE WHERE username = 'setup';

\echo '## R1: a user with orders cannot be deleted'
DELETE FROM users WHERE username = 'setup';

-- ============================================================================
-- settings
-- ============================================================================
\echo '## R5: cannot insert a second settings row (id = TRUE)'
INSERT INTO settings (id, work_days) VALUES (TRUE, ARRAY['MON']::weekday[]);

\echo '## R5: cannot insert a settings row with id = FALSE'
INSERT INTO settings (id, work_days) VALUES (FALSE, ARRAY['MON']::weekday[]);

\echo '## T5: work_days must not be empty'
UPDATE settings SET work_days = ARRAY[]::weekday[];

-- ============================================================================
-- snacks
-- ============================================================================
\echo '## F1: price must be positive (zero)'
INSERT INTO snacks (name, price) VALUES ('Free Snack', 0);

\echo '## F1: price must be positive (negative)'
INSERT INTO snacks (name, price) VALUES ('Paid Snack', -1.00);

\echo '## snacks: name is unique'
INSERT INTO snacks (name, price) VALUES ('Setup Snack A', 10.00);

\echo '## R7: a snack with order history cannot be deleted'
DELETE FROM snacks WHERE name = 'Setup Snack A';

-- ============================================================================
-- orders
-- ============================================================================
\echo '## R1: order must reference an existing user'
INSERT INTO orders (user_id, estimated_total) VALUES (999999999, 100.00);

\echo '## S6: estimated_total must be positive'
INSERT INTO orders (user_id, estimated_total)
VALUES ((SELECT id FROM users WHERE username = 'setup'), 0);

\echo '## orders: frozen total must be positive'
INSERT INTO orders (user_id, status, estimated_total, total, fulfillment_date, accepted_at)
VALUES ((SELECT id FROM users WHERE username = 'setup'), 'ACCEPTED', 100.00, 0, CURRENT_DATE, now());

\echo '## S5: PENDING order must not have a total'
INSERT INTO orders (user_id, estimated_total, total)
VALUES ((SELECT id FROM users WHERE username = 'setup'), 100.00, 100.00);

\echo '## S5: ACCEPTED order must have a total'
INSERT INTO orders (user_id, status, estimated_total, fulfillment_date, accepted_at)
VALUES ((SELECT id FROM users WHERE username = 'setup'), 'ACCEPTED', 100.00, CURRENT_DATE, now());

\echo '## T1: PENDING order must not have a fulfillment_date'
INSERT INTO orders (user_id, estimated_total, fulfillment_date)
VALUES ((SELECT id FROM users WHERE username = 'setup'), 100.00, CURRENT_DATE);

\echo '## T1: ACCEPTED order must have a fulfillment_date'
INSERT INTO orders (user_id, status, estimated_total, total, accepted_at)
VALUES ((SELECT id FROM users WHERE username = 'setup'), 'ACCEPTED', 100.00, 100.00, now());

\echo '## T3: PENDING order must not have accepted_at'
INSERT INTO orders (user_id, estimated_total, accepted_at)
VALUES ((SELECT id FROM users WHERE username = 'setup'), 100.00, now());

\echo '## T3: ACCEPTED order must have accepted_at'
INSERT INTO orders (user_id, status, estimated_total, total, fulfillment_date)
VALUES ((SELECT id FROM users WHERE username = 'setup'), 'ACCEPTED', 100.00, 100.00, CURRENT_DATE);

\echo '## T3: REJECTED order must have rejected_at'
INSERT INTO orders (user_id, status, estimated_total)
VALUES ((SELECT id FROM users WHERE username = 'setup'), 'REJECTED', 100.00);

\echo '## T3: PENDING order must not have rejected_at'
INSERT INTO orders (user_id, estimated_total, rejected_at)
VALUES ((SELECT id FROM users WHERE username = 'setup'), 100.00, now());

\echo '## T3: CANCELLED order must have cancelled_at'
INSERT INTO orders (user_id, status, estimated_total)
VALUES ((SELECT id FROM users WHERE username = 'setup'), 'CANCELLED', 100.00);

\echo '## T3: COMPLETED order must have completed_at'
INSERT INTO orders (user_id, status, estimated_total, total, fulfillment_date, accepted_at)
VALUES ((SELECT id FROM users WHERE username = 'setup'), 'COMPLETED', 100.00, 100.00, CURRENT_DATE, now());

\echo '## T3: ACCEPTED order must not have completed_at'
INSERT INTO orders (user_id, status, estimated_total, total, fulfillment_date, accepted_at, completed_at)
VALUES ((SELECT id FROM users WHERE username = 'setup'), 'ACCEPTED', 100.00, 100.00, CURRENT_DATE, now(), now());

\echo '## T4: accepted_at cannot precede created_at'
INSERT INTO orders (user_id, status, estimated_total, total, fulfillment_date, accepted_at)
VALUES ((SELECT id FROM users WHERE username = 'setup'), 'ACCEPTED', 100.00, 100.00, CURRENT_DATE, now() - interval '1 day');

\echo '## T4: completed_at cannot precede accepted_at'
INSERT INTO orders (user_id, status, estimated_total, total, fulfillment_date, accepted_at, completed_at)
VALUES ((SELECT id FROM users WHERE username = 'setup'), 'COMPLETED', 100.00, 100.00, CURRENT_DATE, now(), now() - interval '1 hour');

\echo '## orders: an order with allocated payments cannot be deleted'
DELETE FROM orders WHERE status = 'ACCEPTED' AND total = 200.00;

-- ============================================================================
-- order_items
-- ============================================================================
\echo '## R2: same snack twice on one order'
INSERT INTO order_items (order_id, snack_id, quantity, price, total)
VALUES ((SELECT id FROM orders WHERE status = 'ACCEPTED' AND total = 200.00),
        (SELECT id FROM snacks WHERE name = 'Setup Snack A'), 1, 100.00, 100.00);

\echo '## F2: quantity must be positive'
INSERT INTO order_items (order_id, snack_id, quantity)
VALUES ((SELECT id FROM orders WHERE status = 'PENDING'),
        (SELECT id FROM snacks WHERE name = 'Setup Snack A'), 0);

\echo '## order_items: frozen price must be positive'
INSERT INTO order_items (order_id, snack_id, quantity, price, total)
VALUES ((SELECT id FROM orders WHERE status = 'ACCEPTED' AND total = 500.00),
        (SELECT id FROM snacks WHERE name = 'Setup Snack A'), 2, 0, 0);

\echo '## F3: total must equal quantity * price'
INSERT INTO order_items (order_id, snack_id, quantity, price, total)
VALUES ((SELECT id FROM orders WHERE status = 'ACCEPTED' AND total = 500.00),
        (SELECT id FROM snacks WHERE name = 'Setup Snack A'), 2, 100.00, 150.00);

\echo '## F3 (NULL trap): price set but total NULL'
INSERT INTO order_items (order_id, snack_id, quantity, price, total)
VALUES ((SELECT id FROM orders WHERE status = 'ACCEPTED' AND total = 500.00),
        (SELECT id FROM snacks WHERE name = 'Setup Snack A'), 2, 100.00, NULL);

\echo '## F3 (NULL trap): total set but price NULL'
INSERT INTO order_items (order_id, snack_id, quantity, price, total)
VALUES ((SELECT id FROM orders WHERE status = 'ACCEPTED' AND total = 500.00),
        (SELECT id FROM snacks WHERE name = 'Setup Snack A'), 2, NULL, 200.00);

\echo '## S4 (trigger): item on a PENDING order must not have a price'
INSERT INTO order_items (order_id, snack_id, quantity, price, total)
VALUES ((SELECT id FROM orders WHERE status = 'PENDING'),
        (SELECT id FROM snacks WHERE name = 'Setup Snack A'), 2, 100.00, 200.00);

\echo '## S4 (trigger): item on an ACCEPTED order must have a price'
INSERT INTO order_items (order_id, snack_id, quantity)
VALUES ((SELECT id FROM orders WHERE status = 'ACCEPTED' AND total = 500.00),
        (SELECT id FROM snacks WHERE name = 'Setup Snack B'), 2);

-- ============================================================================
-- payments
-- ============================================================================
\echo '## F9: reported_amount must be positive'
INSERT INTO payments (user_id, reported_amount)
VALUES ((SELECT id FROM users WHERE username = 'setup'), 0);

\echo '## F9: received_amount cannot be negative'
INSERT INTO payments (user_id, reported_amount, received_amount, status, confirmed_at)
VALUES ((SELECT id FROM users WHERE username = 'setup'), 100.00, -1.00, 'CONFIRMED', now());

\echo '## P2 (NULL trap): CONFIRMED with received_amount NULL'
INSERT INTO payments (user_id, reported_amount, received_amount, status, confirmed_at)
VALUES ((SELECT id FROM users WHERE username = 'setup'), 100.00, NULL, 'CONFIRMED', now());

\echo '## P2: CONFIRMED with received_amount = 0'
INSERT INTO payments (user_id, reported_amount, received_amount, status, confirmed_at)
VALUES ((SELECT id FROM users WHERE username = 'setup'), 100.00, 0, 'CONFIRMED', now());

\echo '## P2: CONFIRMED without confirmed_at'
INSERT INTO payments (user_id, reported_amount, received_amount, status)
VALUES ((SELECT id FROM users WHERE username = 'setup'), 100.00, 100.00, 'CONFIRMED');

\echo '## P3: REJECTED with money received'
INSERT INTO payments (user_id, reported_amount, received_amount, status)
VALUES ((SELECT id FROM users WHERE username = 'setup'), 100.00, 50.00, 'REJECTED');

\echo '## P3 (NULL trap): REJECTED with received_amount NULL'
INSERT INTO payments (user_id, reported_amount, received_amount, status)
VALUES ((SELECT id FROM users WHERE username = 'setup'), 100.00, NULL, 'REJECTED');

\echo '## P4: PENDING_CONFIRMATION with a received_amount'
INSERT INTO payments (user_id, reported_amount, received_amount)
VALUES ((SELECT id FROM users WHERE username = 'setup'), 100.00, 100.00);

\echo '## P4: PENDING_CONFIRMATION with confirmed_at'
INSERT INTO payments (user_id, reported_amount, confirmed_at)
VALUES ((SELECT id FROM users WHERE username = 'setup'), 100.00, now());

-- ============================================================================
-- order_payments
-- ============================================================================
\echo '## F5: amount_applied must be positive'
INSERT INTO order_payments (order_id, payment_id, amount_applied)
VALUES ((SELECT id FROM orders   WHERE status = 'ACCEPTED' AND total = 500.00),
        (SELECT id FROM payments WHERE received_amount = 1000.00), 0);

\echo '## R3: same payment applied to the same order twice'
INSERT INTO order_payments (order_id, payment_id, amount_applied)
VALUES ((SELECT id FROM orders   WHERE status = 'ACCEPTED' AND total = 200.00),
        (SELECT id FROM payments WHERE received_amount = 200.00), 50.00);

\echo '## order_payments: must reference an existing order'
INSERT INTO order_payments (order_id, payment_id, amount_applied)
VALUES (999999999, (SELECT id FROM payments WHERE received_amount = 1000.00), 10.00);

\echo '## F6 (trigger): cannot allocate more than was received (200 received, 100 applied, 300 more)'
INSERT INTO order_payments (order_id, payment_id, amount_applied)
VALUES ((SELECT id FROM orders   WHERE status = 'ACCEPTED' AND total = 500.00),
        (SELECT id FROM payments WHERE received_amount = 200.00), 300.00);

\echo '## F6 (trigger): cannot allocate from an unconfirmed payment (received NULL)'
INSERT INTO order_payments (order_id, payment_id, amount_applied)
VALUES ((SELECT id FROM orders   WHERE status = 'ACCEPTED' AND total = 500.00),
        (SELECT id FROM payments WHERE status = 'PENDING_CONFIRMATION'), 50.00);

\echo '## F7 (trigger): cannot apply more than the order total (500 total, 600 applied)'
INSERT INTO order_payments (order_id, payment_id, amount_applied)
VALUES ((SELECT id FROM orders   WHERE status = 'ACCEPTED' AND total = 500.00),
        (SELECT id FROM payments WHERE received_amount = 1000.00), 600.00);

-- ============================================================================
-- payment_amendments
-- ============================================================================
\echo '## payment_amendments: reason must not be blank'
INSERT INTO payment_amendments (payment_id, old_amount, new_amount, reason, amended_by)
VALUES ((SELECT id FROM payments WHERE received_amount = 200.00), 200.00, 250.00, '   ',
        (SELECT id FROM users WHERE username = 'admin'));

\echo '## payment_amendments: amount must actually change'
INSERT INTO payment_amendments (payment_id, old_amount, new_amount, reason, amended_by)
VALUES ((SELECT id FROM payments WHERE received_amount = 200.00), 200.00, 200.00, 'typo',
        (SELECT id FROM users WHERE username = 'admin'));

\echo '## payment_amendments: amended_by must be an existing user'
INSERT INTO payment_amendments (payment_id, old_amount, new_amount, reason, amended_by)
VALUES ((SELECT id FROM payments WHERE received_amount = 200.00), 200.00, 250.00, 'typo', 999999999);

-- ============================================================================
-- notifications
-- ============================================================================
\echo '## R6: notification must reference an existing user'
INSERT INTO notifications (user_id, type, body) VALUES (999999999, 'TEST', 'x');

\echo '## END: rolling back all setup rows'
ROLLBACK;
