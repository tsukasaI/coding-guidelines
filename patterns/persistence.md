# Persistence

Specializes `principles.md` for database access. Load with the language file
for the task. Schema-first: the SQL schema and queries are the source of
truth; typed access code is generated from them (`patterns/codegen.md`).

## Repository design

- One repository port per aggregate root, defined by its consumer, with only
  the methods that consumer calls. NEVER a repository per table.
- Repositories accept and return domain types. Row/record structs are
  adapter-internal; converting a row into a domain value is a parse — it goes
  through the domain constructor and can fail (a corrupt row is a boundary
  error, not a panic).
- Read models MAY bypass the domain: a report/list view gets its own small
  read port returning purpose-built DTOs. Do not reconstruct aggregates just
  to flatten them again.
- Express query intent in the port (`OrdersWithLines(ctx, month)`), NEVER
  lazy navigation from entities. N+1 is solved in the adapter with joins or
  batching, invisible to the consumer.

Ref: Repository (https://martinfowler.com/eaaCatalog/repository.html); DDD
Aggregate (https://martinfowler.com/bliki/DDD_Aggregate.html); CQRS
(https://martinfowler.com/bliki/CQRS.html). The consumer-defined port and
repository-per-aggregate-not-table rules are house rules.

## Transactions

- Atomicity is a port capability (principles.md "Dependency direction", which
  bans driver transaction types in port signatures). Two forms: one
  transactional method on a single port, or a `UnitOfWork` port owned by the
  application layer.
- One use case = at most one transaction. Keep it short: NEVER make network
  calls, dispatch domain events, or run logging loops inside the transaction.

```go
// Good: the port exposes atomicity as intent; the adapter owns the driver tx
type Checkout interface {
    // PlaceOrder persists the order and decrements stock atomically.
    PlaceOrder(ctx context.Context, o order.Order) error
}

// Adapter (the only place that sees pgx.Tx):
func (s *PgStore) PlaceOrder(ctx context.Context, o order.Order) error {
    return pgx.BeginFunc(ctx, s.pool, func(tx pgx.Tx) error {
        if err := insertOrder(ctx, tx, o); err != nil { return err }
        return decrementStock(ctx, tx, o.Lines)
    })
}
```

- When several repositories must commit together, that is one aggregate
  boundary drawn wrong or a `UnitOfWork` port, NEVER a driver transaction
  threaded through two ports.

Ref: Unit of Work (https://martinfowler.com/eaaCatalog/unitOfWork.html). The
port-level atomicity and one-transaction-per-use-case rules are house rules.

## Migrations

- Migrations are versioned SQL files, committed to VCS, forward-only. NEVER
  edit a migration that has been applied; write a new one. Treat a migration
  as applied once it is merged to the default branch or run against any
  shared database; one that exists only on an unmerged branch may be edited.
- One schema change per migration, named for its intent.
- Zero-downtime changes follow expand–contract: add the new column/table,
  dual-write, backfill, switch reads, then drop the old one — each step its
  own migration and deploy.

Ref: Evolutionary Database Design (https://martinfowler.com/articles/evodb.html);
Parallel Change, expand and contract
(https://martinfowler.com/bliki/ParallelChange.html). The forward-only and
never-edit-an-applied-migration rules are house rules.

## Tools

| Language | Query layer | Migrations |
|---|---|---|
| Go | sqlc (typed Go generated from SQL) on pgx | golang-migrate or goose |
| Rust | sqlx `query!`/`query_as!` (compile-time checked; commit the `.sqlx` offline data from `cargo sqlx prepare`) | `sqlx::migrate!` with `migrations/` |
| TypeScript | pgtyped (types generated from SQL queries); kysely as the typed query builder where queries must be composed dynamically | any versioned-SQL runner; keep files in `migrations/` |

- All three follow the same rule: SQL is written by hand and checked against
  the real schema; the typed access layer is generated, NEVER hand-rolled
  string concatenation. Generated-code handling rules: `patterns/codegen.md`.

- pgtyped's release activity: see "Tool status" in `patterns/tooling.md`
  before adopting it in a new project.

Ref: sqlc (https://docs.sqlc.dev/en/latest/); sqlx offline mode
(https://docs.rs/sqlx/latest/sqlx/macro.query.html) and `migrate!`
(https://docs.rs/sqlx/latest/sqlx/macro.migrate.html); PgTyped
(https://pgtyped.dev/); OWASP SQL Injection Prevention Cheat Sheet
(https://cheatsheetseries.owasp.org/cheatsheets/SQL_Injection_Prevention_Cheat_Sheet.html).

## Anti-patterns AI agents produce around persistence

1. **ORM-entity-as-domain-object**: annotated persistence classes doubling as
   domain types, dragging the driver into the domain. Keep row types in the
   adapter and parse into domain types.
2. **Driver transaction through the port**: `tx pgx.Tx` / `tx: Transaction`
   parameters on port methods (see Transactions above and principles.md).
3. **Repository-per-table with CRUD×N**: mechanical `GetX/SaveX/DeleteX` for
   every table. Ports exist per aggregate and per consumer need.
4. **Hand-built SQL strings** with interpolated input: NEVER do this
   (injection); parameterize, or better, use the generated query layer.
5. **Editing an applied migration** to "fix" it. Applied migrations are
   history; write the next one.
