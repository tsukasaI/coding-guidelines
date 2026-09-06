# Rust

Specializes `principles.md` for Rust. Baseline: current stable Rust, 2024
edition (stabilized in 1.85). Design with ownership first: DDD patterns are
adapted to the borrow checker, never translated from OO.

## Project layout

- One crate is the default. Split into a workspace only when crates have
  genuinely independent consumers or compile-time pain demands it.
- Binaries MUST stay thin: `main.rs` parses config/args, builds dependencies,
  and calls into `lib.rs`. All logic lives in the library crate so integration
  tests can reach it.
- Organize modules by domain concept (`order`, `billing`), not by structural
  role (`models`, `traits`, `utils`). A `utils` module is a naming failure.
- Keep items private by default; export deliberately from the crate root.
  Public structs SHOULD have private fields with constructors and accessors,
  so invariants and future changes stay inside the module (C-STRUCT-PRIVATE).
- Unit tests live in-file (`#[cfg(test)] mod tests`); integration tests in
  `tests/`, which compiles each file as a separate crate against the public API.

Ref: The Rust Book ch. 11.3 (test organization); Rust API Guidelines
(future-proofing).

## Composition and dependency injection

- Wire everything in `main` (the composition root): construct concrete
  adapters, pass them into constructors. No DI framework, no registry, no
  `lazy_static`/`OnceLock` service singletons.
- Ports are traits — defined ONLY at genuine seams: persistence, external
  services, clock, randomness. Everything else depends on concrete types.
- Prefer generics (`struct Service<R: OrderRepo>`) over `dyn Trait` for ports:
  static dispatch, no allocation, inlining. Reach for `Box<dyn OrderRepo>`
  only when you need runtime selection of implementations, heterogeneous
  collections, or generics measurably hurt compile times / binary size.
- Consumers own their trait: define `OrderRepo` next to the service that uses
  it, implement it in the adapter module/crate.
- Async seams use `async fn` in traits. Async-fn traits are not
  dyn-compatible without boxing — one more reason ports default to generics.

```rust
// Good: trait at the seam, generic service, wired in main
trait OrderRepo {
    fn get(&self, id: OrderId) -> Result<Order, RepoError>;
    fn save(&self, order: &Order) -> Result<(), RepoError>;
}

pub struct CheckoutService<R: OrderRepo> { repo: R }

impl<R: OrderRepo> CheckoutService<R> {
    pub fn new(repo: R) -> Self { Self { repo } }
}

fn main() -> anyhow::Result<()> {
    let cfg = Config::from_env()?;              // parse env once, here
    let repo = PgOrderRepo::connect(&cfg.db)?;  // concrete
    run(CheckoutService::new(repo))             // fields stay private
}
```

Ref: The Rust Book ch. 18.2 (trait objects vs generics trade-offs).

## Domain modelling

- Newtype every domain primitive: `struct OrderId(Uuid)`, `struct Cents(i64)`.
  Mixing up arguments becomes a compile error (C-NEWTYPE).
- Parse, don't validate: constructors return `Result<Self, Error>` and are the
  only way to obtain the type. Prefer static enforcement (the type can't hold
  an invalid value) over runtime checks scattered at call sites (C-VALIDATE).

```rust
// Bad: raw primitives, validity checked "somewhere"
fn charge(user: String, amount: i64) { ... }

// Good: invalid values cannot be constructed
pub struct Email(String);
impl Email {
    pub fn parse(raw: &str) -> Result<Self, EmailError> {
        raw.contains('@')
            .then(|| Self(raw.to_owned()))
            .ok_or(EmailError::MissingAt)
    }
}
```

- Make invalid states unrepresentable with enums, not flag fields. A struct of
  mutually exclusive `Option`s is a sum type in denial.

```rust
// Bad: what does shipped_at + cancelled_at both Some mean?
struct Order { shipped_at: Option<DateTime>, cancelled_at: Option<DateTime> }

// Good: states are exclusive by construction
enum OrderState { Pending, Shipped { at: DateTime }, Cancelled { at: DateTime } }
```

- Aggregates are owned data: the root struct owns its children (`Vec<Line>`),
  and all mutation goes through `&mut self` methods that maintain invariants.
  The borrow checker then enforces single-writer access for free. NEVER build
  `Rc<RefCell<...>>` object graphs to imitate OO entity references — refer
  across aggregates by ID instead.
- Domain modules MUST NOT depend on driver/framework crates (`sqlx`, `axum`,
  `serde` transport DTOs). Adapters map between wire/storage types and domain
  types at the edge.

Ref: Rust API Guidelines C-NEWTYPE, C-VALIDATE, C-CTOR.

## Error handling

- Expected failures return `Result`; propagate with `?`. Returning `Result` is
  the default for any function that can fail ("To panic! or Not to panic!").
- Library-style crates (domain, adapters, anything with callers that branch)
  define dedicated error types with `thiserror`. Application edges (`main`,
  handlers, CLI commands) MAY use `anyhow`, adding context per hop.
- `panic!`/`unwrap`/`expect` are for bugs and broken invariants only. NEVER
  unwrap on I/O, parsing, or any input-derived path. `expect("reason")` is
  acceptable where the invariant is locally provable — say why in the message.
  (enforced: `clippy::unwrap_used`, `clippy::expect_used`, scoped away from
  `#[cfg(test)]` code by `templates/clippy.toml.example`.)
- Keep error enums per module/seam, not one crate-wide mega-enum: a caller of
  `Email::parse` should not have to match on `DatabaseUnavailable`.
- Translate at boundaries: adapters map `sqlx::Error` into their own error
  type (`RepoError::NotFound`); transport maps domain errors to status codes.
  Driver error types MUST NOT appear in port signatures.

```rust
// Good: the port's error names no driver type; the adapter converts
#[derive(Debug, thiserror::Error)]
pub enum RepoError {
    #[error("order not found")]
    NotFound,
    #[error("storage failure")]
    Storage(#[source] Box<dyn std::error::Error + Send + Sync>),
}

// adapter module — the only place that names sqlx
impl From<sqlx::Error> for RepoError {
    fn from(e: sqlx::Error) -> Self {
        match e {
            sqlx::Error::RowNotFound => RepoError::NotFound,
            e => RepoError::Storage(Box::new(e)),
        }
    }
}

// application edge
let order = repo
    .get(id)
    .with_context(|| format!("loading order {id}"))?;
```

Ref: The Rust Book ch. 9.2–9.3; thiserror/anyhow docs ("library" vs
"application" framing is the crates' own).

## Testing

- Test through the public API. Integration tests in `tests/` can only see
  public items — treat that constraint as the design pressure it is. In-file
  unit tests MAY touch private helpers, but if most tests need privates, the
  module boundary is wrong.
- Domain types and logic are pure: test them with plain asserts, no doubles.
- Fake at trait seams only: an in-memory `OrderRepo` backed by `HashMap` for
  service tests. NEVER introduce a trait just so a test can mock a concrete
  collaborator.
- Test error paths as first-class cases: `assert!(matches!(err, RepoError::NotFound))`.
- Prefer plain `assert_eq!`/`matches!` over assertion-DSL crates; add
  property-based tests (proptest) for parsers and invariant-heavy types.

## Tooling

- `rustfmt` runs at its default settings — no `rustfmt.toml` overrides.
  Canonical formatting is the point; a project-specific style config just
  reintroduces the bikeshedding rustfmt exists to end.
- `clippy`'s default groups (`correctness`, `suspicious`, `complexity`,
  `perf`, `style`) are promoted to deny (`-D warnings`) in the pre-commit
  hook. Add a small, explicit, cherry-picked set of pedantic/nursery/
  restriction lints via Cargo's `[lints.clippy]` table (stable since 1.74) —
  `clippy::unwrap_used`, `clippy::expect_used` (outside `#[cfg(test)]`),
  `clippy::missing_errors_doc`, `clippy::dbg_macro`, `clippy::todo`,
  `clippy::unimplemented` are a reasonable starting set. This reinforces,
  rather than restates, the `unwrap()` anti-pattern below — the lint makes
  it a compile-time-visible warning instead of a code-review catch.
- NEVER blanket-enable `clippy::pedantic` or `clippy::nursery` as whole
  groups: both upstream docs and community practice warn against it —
  `pedantic` has intentional false positives, `nursery` lints are
  explicitly unstable/buggy. Cherry-pick individual lints instead.
- `cargo-deny` (`deny.toml`: licenses, bans, advisories, sources) and
  `cargo-audit` (RustSec advisories) cover supply-chain checks. Both are
  slower than a local hook should be — they MAY run in CI only rather than
  the mandatory pre-commit hook, unlike rustfmt/clippy which are
  pre-commit-mandatory (see `patterns/tooling.md`).
- The current cherry-pick set (`templates/cargo-lints.toml.example`) adds:
  `module_name_repetitions` (module-name stutter, mirrors go.md's
  `revive.exported`), `print_stdout`/`print_stderr` (production code
  logs, it doesn't print), `wildcard_imports`, `indexing_slicing`
  (`v[i]` panics on out-of-bounds; prefer `.get()`), and
  `allow_attributes`/`allow_attributes_without_reason` (forces
  `#[expect(lint, reason = "...")]` over a bare `#[allow(lint)]`, the same
  suppression-audit-trail requirement `security.md` states generally).
  `[lints.rust] unsafe_code = "forbid"` is also mandatory unless the
  project has a documented, narrowly-scoped exception: `forbid` cannot be
  locally overridden by `#[allow(unsafe_code)]` (that's the point), so a
  real exception means downgrading the crate-wide lint to `deny` instead.
- `redundant_clone` lives in the nursery group and has known false
  positive/negative reports upstream; it's still cherry-picked individually
  (not via a blanket `clippy::nursery`) because it directly targets the
  `.clone()`-to-silence-the-borrow-checker anti-pattern below, treat a hit
  as a design signal to check, same as any nursery lint's noisier output.
- `unwrap_used`/`expect_used`/`dbg_macro`/`print_stdout`/`print_stderr`
  denies would also fire inside `#[cfg(test)]` code without
  `templates/clippy.toml.example`'s `allow-*-in-tests` keys. Those keys
  cover both in-crate `#[cfg(test)]` modules and `#[test]` functions in
  `tests/`; a non-test helper function in `tests/`, plus anything in
  `examples/` or `benches/`, is NOT covered (open upstream issue
  rust-clippy#13981) and stays subject to the deny, same as any other
  caller of the public API.
- No clippy lint exists for the `Rc<RefCell<T>>`-object-graph or
  crate-wide-mega-error-enum anti-patterns below; both stay code-review-only.

Ref: doc.rust-lang.org/clippy (lint groups, `[lints]` table); rustsec.org;
github.com/EmbarkStudios/cargo-deny; github.com/rust-lang/rust-clippy/issues/13981
(clippy.toml test-scoping keys don't cover tests/examples/benches).

## Anti-patterns AI agents produce in Rust

1. **`.clone()` to silence the borrow checker**: cloning at every error
   instead of restructuring ownership (move the value, take `&`/`&mut`,
   or return data instead of holding references). Treat a lifetime fight as
   a design signal, not a clone site.
2. **`unwrap()` on fallible paths**: compiles, then panics in production on
   the first odd input. Every `unwrap` outside tests needs to be `?`, a
   `match`, or an `expect` with a provable-invariant justification.
3. **OO translation layers**: `Box<dyn Trait>` fields everywhere, getter/
   setter impls, `Rc<RefCell<T>>` entity graphs. Rust rewards owned data and
   plain functions; one trait per genuine seam is the ceiling, not the floor.
4. **One giant error enum** re-exported crate-wide so `?` always works:
   callers can no longer tell which failures are actually possible. Give each
   seam its own small error type; adapters own the `From` impls that convert.
5. **Stringly-typed everything**: `Result<T, String>`, `HashMap<String, Value>`
   passed through the domain, IDs as `String`. Parse into newtypes and enums
   at the boundary; strings stop at the edge.
