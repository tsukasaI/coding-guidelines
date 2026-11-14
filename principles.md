# Principles

Language-agnostic rules that every guide in this repository specializes.
Precedence when guides appear to conflict: frontend guide > language guide >
patterns guide (`patterns/`) > this file — the more specific guide encodes the
same principle under tighter constraints.

## Terminology

Use these terms consistently; do not introduce synonyms.

- **Domain**: the code that expresses business rules and types. Pure; no I/O.
- **Boundary**: any point where data enters or leaves the process (HTTP, DB,
  queue, file, env, user input).
- **Port**: an interface the domain/application layer *defines* to express a
  capability it needs (e.g. `OrderRepository`).
- **Adapter**: a concrete implementation of a port living at the edge (e.g.
  `PostgresOrderRepository`).
- **Composition root**: the single place — the program entry point — where
  concrete adapters are constructed and wired into the code that needs them.

Ref: Hexagonal (Ports & Adapters) Architecture
(https://alistair.cockburn.us/hexagonal-architecture/); Composition Root
(https://blog.ploeh.dk/2011/07/28/CompositionRoot/). The Domain and Boundary
definitions are house rules.

## Dependency direction

- Dependencies MUST point inward: adapters depend on ports; ports and the
  domain depend on nothing outward (no framework, driver, or transport types).
- The domain MUST NOT import HTTP, SQL, serialization, or framework packages.
  Why: the domain is the part you test exhaustively and change most; coupling
  it to an edge technology makes both harder.
- Ports MUST be defined next to the code that consumes them, not next to the
  adapter that implements them. The consumer owns the contract.
- Ports SHOULD be minimal: only the operations the consumer actually calls.
  A 20-method "repository interface" is an adapter's API leaking inward.
- Atomicity is a port capability: express a transaction as one method on a
  port, or as a `UnitOfWork` port owned by the application layer. Driver
  transaction types MUST NOT appear in port signatures (details:
  `patterns/persistence.md`).

Ref: The Clean Architecture, the Dependency Rule
(https://blog.cleancoder.com/uncle-bob/2012/08/13/the-clean-architecture.html);
Hexagonal (Ports & Adapters) Architecture
(https://alistair.cockburn.us/hexagonal-architecture/). The consumer-owned
port and minimal-port rules are house rules.

## Composition root

- All wiring — constructing adapters, injecting them into services — MUST
  happen in the composition root (`main`, the server entry file, etc.).
- Dependencies MUST be passed explicitly (constructor arguments, function
  parameters, a deps object). NEVER resolve them from global mutable state,
  a service locator, or a DI container. Why: explicit wiring is readable,
  compile-time checked, and trivially swappable in tests.
- Code outside the composition root MUST NOT know which concrete adapter it
  is using.
- A UI framework's context/provider is NOT a service locator when it only
  carries values constructed at the composition root down the tree (ports,
  theme, current user). Providing at the root is explicit wiring; resolving
  ad-hoc dependencies from context deep in the tree is NOT allowed.
- The logger is an ordinary injected dependency, built in the composition
  root. A process-wide structured logger configured once at startup is the
  single sanctioned exception to the global-state ban for dependencies. The
  frontend guides separately carve out module-level client UI state stores
  (see `frontend/*.md`): UI state is not a dependency, and ports and services
  still arrive by injection.
- Configuration (env vars, flags, config files) MUST be read once, at the
  composition root, parsed into a typed config value, and passed down.
  NEVER read env vars from arbitrary depths of the codebase.

Ref: Composition Root (https://blog.ploeh.dk/2011/07/28/CompositionRoot/);
Service Locator is an Anti-Pattern
(https://blog.ploeh.dk/2010/02/03/ServiceLocatorisanAnti-Pattern/); The
Twelve-Factor App, III. Config (https://12factor.net/config).

## Parse, don't validate

- Every boundary MUST parse raw input into a domain type in one step. A
  successful parse yields a value whose type guarantees its invariants;
  a failed parse yields an error at the boundary.
- After the boundary, code MUST be able to trust its inputs. Do not re-check
  invariants the type already guarantees ("defensive re-validation" is a smell
  that the type is too weak).
- Prefer types that make invalid states unrepresentable over runtime checks:
  a non-empty list type over `if len == 0`, a sum type over a struct of
  mutually exclusive optionals, a `UserId` over a raw string.
- Raw primitives (string, int) from a boundary MUST NOT travel more than one
  layer inward. Wrap them at the edge.

Ref: Parse, don't validate
(https://lexi-lambda.github.io/blog/2019/11/05/parse-don-t-validate/).

## Errors as values

- Expected failures (not found, invalid input, conflict, timeout) MUST be
  represented as values in the return path — `error`, `Result`, a
  discriminated union — so the caller is forced to handle them.
- Exceptions/panics are reserved for bugs and unrecoverable states
  (impossible branch reached, corrupted invariant). NEVER use them for
  control flow of expected failures.
- Errors MUST be translated at layer boundaries: an adapter returns
  domain-meaningful errors (e.g. `ErrNotFound`), not driver errors; the
  transport layer maps domain errors to protocol responses (404, exit code).
  Why: callers should branch on your contract, not your dependency's.
- Add context when crossing a boundary (which operation, which entity), but
  handle each error exactly once — either log it or return it, NEVER both.

Ref: Errors are values (https://go.dev/blog/errors-are-values); The Rust
Book ch. 9, Error Handling
(https://doc.rust-lang.org/book/ch09-00-error-handling.html). Translating
errors at layer boundaries and the handle-once rule are house rules.

## Testing policy

- Test through the public API of a module/package/crate. Tests MUST NOT reach
  into private internals; if you feel the need, the public API is missing a
  seam or the module is too big. (Language files carve narrow exceptions:
  Rust in-file unit tests, Go `_internal_test.go`.)
- Mock/fake ONLY at architectural seams — the ports defined above
  (persistence, external services, clock, randomness). NEVER mock types you
  don't own or internal collaborators two layers down. Why: tests coupled to
  internals break on refactor without catching regressions.
- Prefer fakes (in-memory implementations with real behavior) over
  record/replay mocks. A fake survives refactors; an expectation script
  re-states the implementation.
- Test behavior, not implementation: assert on outputs and observable state
  transitions, not on which internal methods were called.
- The domain, being pure, SHOULD be tested with plain unit tests and no test
  doubles at all. If domain tests need mocks, dependency direction is broken.
- Tests MUST be independent: no ordering assumptions, no mutable state shared
  between tests. Each test owns its fixtures.
- Each behavior MUST be tested once, through the highest public function
  that exercises it. Re-testing the same input class at a lower layer, or
  through a second entry point, is duplication: it adds runtime and makes
  every spec change edit several tests without catching more regressions.
- NEVER test code you don't own. Don't write tests for a library or platform
  API (date/time APIs, HTTP clients, parsers); test your own function that
  uses it, through that function's inputs and outputs. This is the same rule
  as "never mock types you don't own", applied to choosing what to test.
- Snapshots SHOULD be reserved for output that explicit assertions can't
  express readably (a generated file, a rendered document). NEVER snapshot
  what an explicit assertion next to it already pins, and avoid snapshots a
  reviewer can't judge from the diff (one-line JSON, opaque numbers).
- Every test MUST be able to fail. After writing one, briefly break the code
  it guards (drop a sort, flip a comparison) and confirm the test fails. A
  test that passes against broken code is cost without coverage.

Ref: Test Behavior, Not Implementation
(https://testing.googleblog.com/2013/08/testing-on-toilet-test-behavior-not.html);
Prefer Testing Public APIs Over Implementation-Detail Classes
(https://testing.googleblog.com/2015/01/testing-on-toilet-prefer-testing-public.html);
Software Engineering at Google ch. 13, Test Doubles
(https://abseil.io/resources/swe-book/html/ch13.html).

## Simplicity

- Introduce an abstraction (port, layer, generic parameter) only when there is
  a concrete second use or a genuine seam (I/O, external service). NEVER add
  speculative indirection for flexibility's sake — the rule Go restates for
  interfaces (none before a consumer needs one) and Rust for traits (only at
  genuine seams).
- Code MUST be written for the reader: prefer boring, explicit code over
  clever constructs. Optimize only after measuring.

Ref: Yagni (https://martinfowler.com/bliki/Yagni.html).

### Reuse ladder

Before writing new code, take the first option that fully works:

1. Does it need to exist at all? Skip unrequested features and options, and
   name what you skipped so the requester can ask for it.
2. Something already in this codebase (helper, component, pattern), used the
   way the surrounding code uses it.
3. The standard library or platform feature, unless the project has its own.
4. An already-installed dependency. NEVER add a dependency for a few lines.
5. Otherwise, the minimum code that works.

- The target is a minimal solution, not minimal effort: every caller, test,
  and fixture the change breaks is still in scope.
- NEVER cut for simplicity: validation at trust boundaries, error handling
  that prevents data loss, security, accessibility, and anything the
  requester explicitly asked for.

Ref: DietrichGebert/ponytail (MIT), reuse ladder and never-cut list
(https://github.com/DietrichGebert/ponytail).
