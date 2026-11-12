---
paths:
  - "**/*.rs"
  - "**/Cargo.toml"
---

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
- Name a leaf module's file after its primary item (`mod order_book` in
  `order_book.rs`). Non-leaf modules hold only `mod` declarations and
  re-exports, not API implementations.
- Imports: NEVER use glob imports (`use foo::*`) except `use super::*` in an
  inline `mod tests`, and `pub use child::*` re-exports in a non-leaf module
  (enforced: `clippy::wildcard_imports`, which exempts exactly those two).
  Keep one module per `use` statement (no `::` inside `{..}`). Import traits
  inside the function that uses them unless the whole file does.
- Call free functions through their module (`mem::swap(..)`, `fs::read(..)`);
  name types unqualified (`HashMap`), except ambiguous ones (`io::Error`,
  `fmt::Result`).

Ref: The Rust Book ch. 11.3 (test organization); Rust API Guidelines
(future-proofing); Google Rust Style Guide (code organization).

## Composition and dependency injection

- Per principles.md "Composition root": wire everything in `main`,
  constructing concrete adapters and passing them into constructors. No
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
- Per principles.md "Parse, don't validate": constructors return
  `Result<Self, Error>` and are the only way to obtain the type (C-VALIDATE).

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

- Use a newtype, not a `type` alias, whenever the name carries meaning the
  compiler should enforce. Prefer named fields over tuple structs and
  tuples, except single-field newtypes and very local values.
- Prefer unique ownership and borrowing over `Rc`/`Arc`; reach for shared
  ownership only when the alternative is unreasonably complex. Cloning an
  `Rc`/`Arc` is expected; `.clone()` on anything else means a real deep copy.

Ref: Rust API Guidelines C-NEWTYPE, C-VALIDATE, C-CTOR; Google Rust Style
Guide (types, ownership and borrowing).

## API design

"Library code" below means a crate or module whose callers you don't
control. Application code (one crate, one binary) applies the same rules
where they cost nothing and skips premature generality.

- Accept the most flexible borrowed type: `&str` not `&String`, `&[T]` not
  `&Vec<T>`, `&T` not `&Box<T>`, `Option<&T>` not `&Option<T>`.
  (enforced: `clippy::ptr_arg`, `clippy::borrowed_box`, `clippy::ref_option`.)
- Library code SHOULD return iterators (`impl Iterator<Item = T>` or a
  concrete iterator type) over `Vec<T>`, and accept `impl IntoIterator` when
  it only iterates. Application code MAY return `Vec<T>` and take slices.
- `impl Into<T>` parameters are for library APIs where call-site ergonomics
  matter; application code almost never uses them (they cost
  monomorphized code size and hide the conversion).
- Use an `enum` parameter instead of `bool` when the meaning isn't obvious at
  the call site: `render(Mode::Draft)`, not `render(true)`.
- Failure reporting: `Option` when absence is the only failure and obvious
  from the name; `Result` when the caller needs to know why; `panic!` only
  for bugs (see Error handling).
- Implement std traits instead of bespoke methods (`impl FromStr`, not
  `fn parse_from(&str)`; `impl Display`, not `fn to_text()`). Keeping an
  inherent method alongside the trait impl is fine. Pair an important `From`
  impl with a named constructor (`from_foo()`) so call sites can be explicit.
- `#[derive]` whenever the derived impl is correct; NEVER hand-write what a
  derive produces. Trait choice: `Copy` only if the type will stay `Copy`
  (error enums without payloads usually can); `Clone` for everything except
  handles to external resources; `Default` when a default state exists
  (always for all-public-field options structs); `PartialEq`/`PartialOrd`
  unless total equality/order really holds, then add `Eq`/`Ord`; `Hash` +
  `Eq` for types likely to be map keys.
- Define a trait only for generic code, `impl Trait`/`dyn Trait` in
  signatures, or an extension trait. NEVER use a trait just to group
  methods. Extension traits on foreign types carry an `Ext` suffix
  (`StrExt`) and are not used as generic bounds or `dyn` types.
- Public enums, and public structs with public fields, that other teams or
  crates consume get `#[non_exhaustive]` so adding a variant/field is not a
  breaking change. App-internal types don't need it.
- `#[must_use]` on functions whose ignored return value is a bug (pure
  computations, a `bool` saying whether the operation happened) and on types that are useless
  unless consumed (error types, guards, lazy computations, builders).
- Mark a public `fn` `const` only if you commit to keeping it `const`;
  removing `const` later is a breaking change.
- Overload operators only for their mathematical/logical meaning.
- Treat `#[doc(hidden)]` items of crates you don't own as private.

Naming (beyond the Rust API Guidelines C-CASE):

- Conversion methods follow the std `self` conventions: `as_` (borrowed →
  borrowed, free), `to_` (borrowed → owned or expensive), `into_` (consumes
  `self`). (enforced: `clippy::wrong_self_convention`.)
- Constructors: `new()`, `new_with_foo()`, `try_new()` when it returns
  `Result`. Accessors: `foo()` / `foo_mut()` / `set_foo()` /
  `take_foo()` / `replace_foo()`, never `get_foo()`. A type with `len()`
  also has `is_empty()` (enforced: `clippy::len_without_is_empty`).
- Lifetimes get descriptive names (`'conn`, `'src`); `'a`/`'b` only for up to
  two lifetimes in a small local scope, and `'_` where elision allows.
- Generic parameters are short and hint at their bound (`R: OrderRepo`,
  `E: Error`); `T`/`U` only when unbounded.
- NEVER abbreviate with project-local acronyms or dropped letters
  (`ordr_cnt`). Widely known ones (`Ip`, `Http`, `Id`) are fine.

```rust
// Bad: owned params, bool flag, get_ prefix, Vec where an iterator fits
pub fn render(lines: &Vec<String>, draft: bool) -> Vec<String> { ... }
impl Order { pub fn get_total(&self) -> Cents { ... } }

// Good
pub enum Mode { Draft, Final }
pub fn render<'src>(lines: &'src [String], mode: Mode)
    -> impl Iterator<Item = &'src str> { ... }
impl Order { pub fn total(&self) -> Cents { ... } }
```

Ref: Rust API Guidelines C-CONV, C-GETTER, C-COMMON-TRAITS, C-STRUCT-PRIVATE;
Google Rust Style Guide (function inputs and outputs, traits, naming, other
Rust features).

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
- Per principles.md "Errors as values" (translate at boundaries): adapters
  map `sqlx::Error` into their own error type (`RepoError::NotFound`); driver
  error types MUST NOT appear in port signatures.

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

## Implementation

- Write enough explicit types that a reader can tell what was inferred,
  especially for `.into()`, `.parse()`, `.collect()`, and long iterator
  results. Annotate the binding (`let n: u32 = s.parse()?;`); when a
  turbofish is forced, fill only what's needed (`collect::<Vec<_>>()`).
- Prefer pattern matching over check-then-unwrap: `if let Some(x) = opt`,
  not `if opt.is_some() { opt.unwrap() }`. (enforced:
  `clippy::unnecessary_unwrap`.)
- Give `assert!`/`assert_eq!` a message that says why the condition must
  hold, with the values involved, not a restatement of the condition.
- Keep combinator chains short. Use a `for` loop when the body has side
  effects or branches, never combinators in a `for` header, and avoid
  `Iterator::for_each` (enforced: `clippy::needless_for_each`).
  Short reductions (`any`, `all`, `sum`, `map(..).collect()`) are fine.
- Build strings with `format!`/`write!` when joining more than two pieces or
  substituting values, not `+`. The lint is stricter than this rule: it
  flags any `String + &str`, so a single append uses `push_str` (enforced:
  `clippy::string_add`).
- When matching a foreign `#[non_exhaustive]` enum, list every variant you
  know of; the required `_` arm then catches only variants added later. Use
  `if let` when you care about one variant.
- NEVER call `std::panic::catch_unwind` in first-party code (enforced:
  `clippy::disallowed_methods` via `templates/clippy.toml.example`). The
  only exception is defense in depth that correctness never relies on and
  that still holds under `panic = "abort"`; it needs `#[expect]` with a
  reason.
- NEVER reach inside a poisoned `Mutex`/`RwLock` (`PoisonError::into_inner`):
  the protected data may be mid-update. Propagate or panic instead.
- NEVER run code before `main` (`ctor`-style life-before-main crates).
  Initialize explicitly from the composition root.
- `unsafe` is forbidden by default (see Tooling). Under a documented
  exception: use it only when no safe implementation exists (performance
  reasons need a benchmark), wrap it in a safe abstraction, isolate it in its
  own module or crate, and put a `// SAFETY:` comment on every `unsafe`
  block explaining why the invariants hold (enforced:
  `clippy::undocumented_unsafe_blocks`). `unsafe fn`/`unsafe trait` document
  their caller obligations under a `# Safety` heading.
- Prefer, in order: plain Rust, `macro_rules!`, build-time code generation,
  procedural macros. Each step up costs tooling support and reviewability.
- No unstable (`#![feature]`) features; this guide targets stable Rust.

Ref: Google Rust Style Guide (implementation concerns, concurrency, macros,
other Rust features).

## Documentation

- Every public item gets a `///` doc comment; modules and crates get `//!`.
  Write Markdown with full sentences. Implementation notes use `//`.
  (enforced: `missing_docs`, rustc, in `[lints.rust]`.)
- Document the failure contract: `# Errors` for every `Result`-returning
  public fn, `# Panics` for every one that can panic on bad input, `# Safety`
  for every `unsafe` one. (enforced: `clippy::missing_errors_doc`,
  `clippy::missing_panics_doc`, `clippy::missing_safety_doc`.)
- Include runnable examples for non-trivial public APIs (doctests are tests).
- NEVER write docs that restate the item name ("Returns the id." on `id()`)
  or explain language basics. A one-line doc that adds no information is
  worse than `#[expect(missing_docs, reason = "...")]` on a self-evident item.
- Prefer plain doc comments over macro-generated documentation.

Ref: The rustdoc book (documentation tests); Google Rust Style Guide (when
and how to write documentation).

## Testing

- Test through the public API. Integration tests in `tests/` can only see
  public items — treat that constraint as the design pressure it is. In-file
  unit tests MAY touch private helpers, but if most tests need privates, the
  module boundary is wrong.
- Per principles.md "Testing policy": domain types take plain asserts; the
  fake at a trait seam is an in-memory `OrderRepo` backed by `HashMap`.
  NEVER introduce a trait just so a test can mock a concrete collaborator.
- Test error paths as first-class cases: `assert!(matches!(err, RepoError::NotFound))`.
- Prefer plain `assert_eq!`/`matches!` over assertion-DSL crates; add
  property-based tests (proptest) for parsers and invariant-heavy types.

## Tooling

- `rustfmt` runs with the Google Rust Style Guide's settings
  (`templates/rustfmt.toml.example`) and nothing else: `max_width = 100`
  (already rustfmt's default, so not written) and `hex_literal_case =
  "Lower"`. Its upstream changelog stabilizes it in rustfmt 1.10.0, but the
  rustfmt 1.10.0 bundled with rustc 1.99.0 still rejects it as nightly-only
  and warns on every run, so the version number alone does not settle it:
  run `cargo fmt --check` once and omit `rustfmt.toml` while the stable
  toolchain warns. Google's other two, `format_macro_matchers = true` and
  `imports_granularity = "Module"`, are nightly-only and stay commented out:
  on stable rustfmt they print a warning on every run. Without them, the
  one-module-per-`use` rule above is code-review-only. Don't add project
  overrides beyond this set; canonical formatting is the point.
- `#[rustfmt::skip]` only for deliberate manual alignment (tables,
  matrices) or generated code, never for personal style.
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
  slower than a local hook should be — they MAY run in CI rather than the
  mandatory pre-commit hook, unlike rustfmt/clippy which are
  pre-commit-mandatory. A project without CI MUST run both from a lefthook
  `pre-push` job (`templates/lefthook.yml.example`, `patterns/tooling.md`).
- The current cherry-pick set (`templates/cargo-lints.toml.example`) adds:
  `module_name_repetitions` (module-name stutter, mirrors go.md's
  `revive.exported`), `print_stdout`/`print_stderr` (production code
  logs, it doesn't print), `wildcard_imports`, `indexing_slicing`
  (`v[i]` panics on out-of-bounds; prefer `.get()`), and
  `allow_attributes`/`allow_attributes_without_reason` (forces
  `#[expect(lint, reason = "...")]` over a bare `#[allow(lint)]`, so every
  suppression carries a reason that can be reviewed or expired).
  `[lints.rust] unsafe_code = "forbid"` is also mandatory unless the
  project has a documented, narrowly-scoped exception: `forbid` cannot be
  locally overridden by `#[allow(unsafe_code)]` (that's the point), so a
  real exception means downgrading the crate-wide lint to `deny` instead.
- Lints added for the Google Rust Style Guide rules: `[lints.rust]
  missing_docs`; `missing_panics_doc`, `fn_params_excessive_bools` (bool
  flags), `ref_option` (`&Option<T>` params), `needless_for_each` (all
  pedantic); `clone_on_ref_ptr` (write `Arc::clone(&x)` so shared-pointer
  clones read differently from deep copies), `string_add`,
  `undocumented_unsafe_blocks` (only live under the `unsafe_code`
  exception) (all restriction); and `disallowed-methods` for
  `std::panic::catch_unwind` in `templates/clippy.toml.example`. Several
  Google rules are already covered by the default groups: `ptr_arg`,
  `borrowed_box`, `wrong_self_convention`, `len_without_is_empty`,
  `should_implement_trait`, `derivable_impls`, `unnecessary_unwrap`,
  `missing_safety_doc`.
- `ref_option` skips exported functions while clippy's
  `avoid-breaking-exported-api` is `true` (its default). A
  library crate whose public API is still unreleased can set it to `false`.
- `exhaustive_enums`/`exhaustive_structs` (restriction) fire on every `pub`
  item, which over-reaches in an application crate. Enable them only in a
  library crate consumed by other teams; the template ships them commented
  out. `non_exhaustive_omitted_patterns` needs a nightly feature gate, so
  match arms on foreign `#[non_exhaustive]` types are code-review-only.
- NEVER enable `missing_const_for_fn` (nursery): it pushes `const` onto
  public fns, contradicting the commit-before-`const` rule above. Same for
  `derive_partial_eq_without_eq` (nursery), which contradicts "`PartialEq`
  unless total equality really holds".
- `redundant_clone` lives in the nursery group and has known false
  positive/negative reports upstream; it's still cherry-picked individually
  (not via a blanket `clippy::nursery`) because it directly targets the
  `.clone()`-to-silence-the-borrow-checker anti-pattern below, treat a hit
  as a design signal to check, same as any nursery lint's noisier output.
- `unwrap_used`/`expect_used`/`indexing_slicing`/`dbg_macro`/`print_stdout`/
  `print_stderr` denies would also fire inside `#[cfg(test)]` code without
  `templates/clippy.toml.example`'s `allow-*-in-tests` keys. Those keys
  cover in-crate `#[cfg(test)]` code and `#[test]` functions, including
  those in `tests/`; non-test helpers in `tests/`, and `examples/` and
  `benches/`, stay subject to the deny. The template holds the observed
  behaviour and the clippy version it was observed on.
- No clippy lint exists for the `Rc<RefCell<T>>`-object-graph or
  crate-wide-mega-error-enum anti-patterns below; both stay code-review-only.

Ref: doc.rust-lang.org/clippy (lint groups, `[lints]` table);
rust-lang.github.io/rustfmt (option stability); rustsec.org;
github.com/EmbarkStudios/cargo-deny; github.com/rust-lang/rust-clippy/issues/13981
(clippy.toml test-scoping keys skip non-test helpers in tests/, and
examples/, benches/).

## Anti-patterns AI agents produce in Rust

1. **`.clone()` to silence the borrow checker**: cloning at every error
   instead of restructuring ownership (move the value, take `&`/`&mut`,
   or return data instead of holding references). Treat a lifetime fight as
   a design signal, not a clone site.
2. **`unwrap()` on fallible paths**: compiles, then panics in production on
   the first odd input. Every `unwrap` outside tests needs to be `?`, a
   `match`, or an `expect` with a provable-invariant justification.
3. **OO translation layers**: `Box<dyn Trait>` fields everywhere, a
   `get_x`/`set_x` pair for every field, `Rc<RefCell<T>>` entity graphs. Rust rewards owned data and
   plain functions; one trait per genuine seam is the ceiling, not the floor.
4. **One giant error enum** re-exported crate-wide so `?` always works:
   callers can no longer tell which failures are actually possible. Give each
   seam its own small error type; adapters own the `From` impls that convert.
5. **Stringly-typed everything**: `Result<T, String>`, `HashMap<String, Value>`
   passed through the domain, IDs as `String`. Parse into newtypes and enums
   at the boundary; strings stop at the edge.
6. **Silently dropping `Err` from fallible iterators**: `.filter_map(Result::ok)`,
   `.flatten()` over `Result`s, or `if let Ok(x) = ...` discard the `Err`
   arm without a decision. Handle each `Err`, or collect failures alongside
   successes and report them.
7. **`usize` `+` for counters over external data** (byte totals across
   inputs): wraps on 32-bit targets and panics in debug builds. Use `u64`
   with `saturating_add` (or `checked_add` when overflow must be reported).
