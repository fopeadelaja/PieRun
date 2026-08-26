# SnackRun

An office snack-ordering app. Colleagues order snacks from their phones, one admin
buys them, hands them out, and the system keeps track of who has paid.

It replaces a WhatsApp group. The ordering half is convenience; the half that earns
its keep is the running tally of **who has had their snacks and hasn't paid**.

---

## Stack

| Layer | Choice |
|---|---|
| Frontend | React + Vite |
| Backend | Node + Express |
| Database | PostgreSQL 16 |
| Architecture | Modular monolith — one deployable, five logical modules |

Deliberately not microservices. The complexity here is in the business rules, not the
infrastructure, and distributed services would add operational cost for no benefit at
this scale (~30 users, a handful of orders a day).

---

## Layout

```
pierun/
├── client/                    React + Vite
│   ├── src/
│   │   ├── pages/             one folder per screen
│   │   ├── components/
│   │   ├── api/               fetch wrappers, one file per backend module
│   │   └── lib/money.js       money formatting — see "Money" below
│   └── vite.config.js
│
├── server/
│   ├── src/
│   │   ├── modules/
│   │   │   ├── users/
│   │   │   ├── snacks/
│   │   │   ├── orders/
│   │   │   ├── payments/
│   │   │   └── notifications/
│   │   ├── db/index.js        connection pool
│   │   ├── middleware/        auth, error handling
│   │   ├── app.js             express app, route mounting
│   │   └── server.js          entry point
│   ├── migrations/
│   │   └── 001_init.sql       the schema
│   └── tests/
│
├── docs/                      design decisions, invariants, use cases
└── README.md
```

Every module has the same three files:

```
modules/orders/
├── routes.js      HTTP: parse input, check who's asking, call the service, format the reply
├── service.js     business logic. Owns transactions. Where the rules live.
└── repo.js        database access only. No business logic. No transactions of its own.
```

**The dependency rule:** `routes → service → repo → db`. Nothing points backwards.

**The module boundary rule:** a module may call another module's *service*, never its
*repo*, and never its tables directly. If `orders` needs snack prices, it calls
`snacks.getForOrder()` — it does not `SELECT * FROM snacks`. This is the only thing
keeping the monolith modular; break it and you have a big ball of mud with folders.

---

Verify the schema applied correctly:

Every statement in that file *should* produce an error — it's a list of illegal states,
and each error is a constraint doing its job.

## Money — read this before writing any code that touches an amount

Money is `NUMERIC(12,2)` in Postgres and **must never become a JavaScript number.**

A JS `number` is a float, and floats can't represent decimal fractions exactly:
`0.1 + 0.2` is `0.30000000000000004`. That drift breaks settlement — an order that is
fully paid can fail its `paid >= total` comparison while both figures *display* as
₦7,200.60, and you will lose a day finding it.

// ✅ database → Decimal
const total = new Decimal(row.total)          // row.total is "7200.60"

// ✅ Decimal → JSON, as a string
res.json({ total: total.toFixed(2) })         // "7200.60"

// ❌ never
const total = parseFloat(row.total)
const total = Number(row.total)
res.json({ total: 7200.60 })                  // client JSON.parse makes it a float again
```

On the client, money is a **string** for display and a `Decimal` if you need arithmetic.
Format with `₦` and two decimals: `₦1,200.50`.

---

## Domain rules you have to know

Full reasoning is in `docs/DESIGN-DECISIONS.md`. These are the ones that will bite you
within the first week:

**An order has two independent states.** Its lifecycle (`PENDING` → `ACCEPTED` →
`COMPLETED`, plus `REJECTED` and `CANCELLED`) says nothing about payment. Settlement is
computed separately from the payments applied to it. "Delivered and owes ₦3,201" is a
normal, common state. There is no `PAID` order status.

**Acceptance is the freeze point.** While an order is pending it has only an *estimated*
total, and its collection date is recalculated live. At acceptance, in one transaction,
the prices are copied from the catalog into the order, the total is fixed, and the date
is written. After that none of them can move, no matter what happens to the catalog.

**Settlement is derived, never stored.** `SELECT ... FROM order_settlement` computes it
from `orders.total` minus confirmed allocations. Never add a `reconciliation` column —
it would be a second source of truth that can silently drift from the first.

**Payment happens outside the system.** People transfer money in their own banking app.
This app records two separate claims: `reported_amount` (what the user says they sent)
and `received_amount` (what the admin verified on the bank statement). Only
`received_amount` ever enters a calculation.

**Money is applied oldest-order-first.** The user never picks which order they're paying
for. A single payment can settle several orders; several payments can settle one order.
Overpayment is kept as a tip — there are no refunds.

---

## Convention: every state change is a conditional update

Never check-then-act. Two requests can both pass the check before either one acts.

```js
// ❌ broken — the world can change between the two lines
const order = await repo.findById(id)
if (order.status === 'PENDING') {
  await repo.setStatus(id, 'ACCEPTED')
}

// ✅ the check is part of the act
const { rowCount } = await client.query(
  `UPDATE orders SET status = 'ACCEPTED', accepted_at = now()# PieRun

Office snack ordering. Colleagues order, one admin buys and hands out, the system tracks
who has paid. Replaces the WhatsApp group.

React + Vite + TS · Node + Express + TS · PostgreSQL 16 · modular monolith.

---

## Run it

```bash
# database (once)
createdb pierun
psql -d pierun -f server/migrations/001_init.sql

# every time
cd server && npm run dev      # :3000
cd client && npm run dev      # :5173
```

`server/.env`:
```
DATABASE_URL=postgres://localhost:5432/pierun
JWT_SECRET=change-me
PORT=3000
```

**Installing Postgres:** macOS `brew install postgresql@16 && brew services start postgresql@16`.
Ubuntu `sudo apt install postgresql-16` then `sudo -u postgres createuser -s $USER`.
Windows: installer from postgresql.org, tick "Add to PATH".

**Reset the database:**
```bash
dropdb pierun && createdb pierun && psql -d pierun -f server/migrations/001_init.sql
```

**Check the schema is sane** — every statement in this file should error, that's the point:
```bash
psql -d pierun -f server/tests/invariants.sql
```

---

## Layout

```
client/src/{pages,components,api,lib}
server/src/modules/{users,snacks,orders,payments,notifications}/{routes,service,repo}.ts
server/migrations/001_init.sql
shared/types.ts          API types imported by both sides
docs/
```

`routes → service → repo → db`, never backwards. Services own transactions; repos don't.
One module calls another module's **service**, never its repo or its tables — that rule is
the only thing making this modular rather than a big ball of mud with folders, and you'll
be tempted to break it at 11pm.

---

## Two things that will cost you a day

**Money is a string, never a `number`.** `pg` returns `NUMERIC` as a string on purpose —
JS numbers are floats and `0.1 + 0.2 = 0.30000000000000004`. If you `parseFloat` it, a
fully-paid order can fail `paid >= total` while both figures *print* as ₦7,200.60.

```ts
const total = new Decimal(row.total)      // ✅
res.json({ total: total.toFixed(2) })     // ✅ string on the wire
const total = parseFloat(row.total)       // ❌
```

Type money as `string` in `shared/types.ts` and TypeScript blocks the bug for you.

**Ids are strings too.** `BIGINT` also comes back as a string, because it can exceed JS's
safe integer range. Type every id as `string` and don't fight it.

---

## Rules you'll second-guess in three weeks

**Order status says nothing about payment.** Two independent axes. `PENDING → ACCEPTED →
COMPLETED` (+ `REJECTED`, `CANCELLED`) is delivery; settlement is computed separately.
There is no `PAID` status. "Delivered and owes ₦3,201" is normal and common.

**Acceptance is the freeze point.** Pending orders have an *estimated* total and a live
collection date. At acceptance, in one transaction: copy prices from the catalog, fix the
total, write the date. Nothing moves after that.

**Settlement is derived, never stored.** `order_settlement` computes it. Do not add a
`reconciliation` column — you already talked yourself out of it, and the reason was that a
mistyped amount then needs a backwards state transition to correct.

**Only `received_amount` counts.** `reported_amount` is what the user claims; it never
enters a calculation.

**Oldest order first, and overpayment is a tip.** The user never picks which order they're
paying for. No refunds.

---

## Every state change is a conditional update

```ts
const { rowCount } = await client.query(
  `UPDATE orders SET status = 'ACCEPTED', accepted_at = now()
    WHERE id = $1 AND status = 'PENDING'`, [id]
)
if (rowCount === 0) throw new ConflictError('This order was already handled')
```

Never read-then-write — two requests can both pass the check before either acts. Applies
to all four order transitions and payment confirmation.

---

## Build order

1. **Now:** browse → cart → submit → my orders → order detail; admin accept queue,
   shopping list, hand-out list, chase list. Usable without payments.
2. **Next:** recording and verifying payments.
3. **Then stop and give it to five colleagues for a week.** Parts of the design are wrong
   and only real use will say which.

Worth real tests: accept order, confirm payment, edit received amount. The rest is CRUD.

---

## Docs

- `docs/DESIGN-DECISIONS.md` — 24 decisions with reasoning. Read before reversing one.
- `docs/INVARIANTS.md` — 46 rules; the `APP`-tagged ones are your test list.
- `docs/USE-CASES-critical.md` — the three hard operations, step by step.
- `docs/design-brief.html` — screens and states.
- `server/migrations/001_init.sql` — annotated with the invariant each constraint implements.

## Still undecided

- **Auth.** Email + password + JWT is plenty for 30 people. Decide before the first
  protected route.
- **Notifications.** In-app only for now; keep the delivery channel swappable so WhatsApp
  can slot in later.
    WHERE id = $1 AND status = 'PENDING'`,
  [id]
)
if (rowCount === 0) throw new ConflictError('This order was already handled')
```

`rowCount === 0` means someone else got there first — the user cancelled it, or the
admin double-clicked. Return a clear message; don't send a duplicate notification.

This applies to all four order transitions and to payment confirmation.

---

## API

| Method | Path | Who | What |
|---|---|---|---|
| `POST` | `/auth/login` | anyone | |
| `GET` | `/snacks` | user | orderable snacks today |
| `POST` | `/orders` | user | submit an order |
| `GET` | `/orders/mine` | user | own orders with settlement |
| `GET` | `/orders/:id` | user | one order in full |
| `POST` | `/orders/:id/cancel` | user | pending orders only |
| `POST` | `/payments` | user | record a transfer |
| `GET` | `/notifications` | user | |
| `GET` | `/admin/orders/pending` | admin | accept queue |
| `POST` | `/admin/orders/:id/accept` | admin | the freeze |
| `POST` | `/admin/orders/:id/reject` | admin | |
| `POST` | `/admin/orders/:id/complete` | admin | delivered |
| `GET` | `/admin/shopping-list?date=` | admin | rolled up by snack |
| `GET` | `/admin/handout?date=` | admin | rolled up by person |
| `GET` | `/admin/payments/pending` | admin | claims to verify |
| `POST` | `/admin/payments/:id/confirm` | admin | records received amount, allocates |
| `GET` | `/admin/chase-list` | admin | who owes what |
| `PATCH` | `/admin/snacks/:id` | admin | price, availability, retire |
| `PATCH` | `/admin/settings` | admin | workdays, cutoff |

---

## Testing

```bash
cd server && npm test
```

Three operations are worth real test coverage. Everything else is CRUD:

1. **Accept order** — the freeze, and the conditional update
2. **Confirm payment** — oldest-first allocation, and the tip left unallocated
3. **Edit received amount** — de-allocate, re-allocate, notify anyone whose order re-opened

`docs/INVARIANTS.md` lists 46 rules. The ones tagged `APP` are not enforced by the
database and exist only as tests — start there.

---

## Build order

**Week 1** — browse snacks, cart, submit, my orders, order detail; admin accept queue,
shopping list, hand-out list, chase list. This is usable: orders in, snacks out, debts
visible.

**Week 2** — recording payments and verifying them.

**Then** — put it in front of five colleagues for a week before building anything else.
Some of the design is wrong and only real use will say which parts.

---

## Docs

| File | What it's for |
|---|---|
| `docs/DESIGN-DECISIONS.md` | 24 decisions with reasoning. Read when you wonder "why is it like this?" |
| `docs/INVARIANTS.md` | 46 rules and where each is enforced |
| `docs/USE-CASES-critical.md` | the three hard operations, step by step |
| `docs/design-brief.html` | screens and states, for UI work |
| `server/migrations/001_init.sql` | the schema — annotated with the invariant each constraint implements |
