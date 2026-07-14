# Principles

Language-agnostic rules that every guide in this repository specializes. When a
language guide and this file appear to conflict, the language guide wins — it
encodes the same principle under that language's constraints.

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

## Composition root

- All wiring — constructing adapters, injecting them into services — MUST
  happen in the composition root (`main`, the server entry file, etc.).
- Dependencies MUST be passed explicitly (constructor arguments, function
  parameters, a deps object). NEVER resolve them from global mutable state,
  a service locator, or a DI container. Why: explicit wiring is readable,
  compile-time checked, and trivially swappable in tests.
- Code outside the composition root MUST NOT know which concrete adapter it
  is using.
- Configuration (env vars, flags, config files) MUST be read once, at the
  composition root, parsed into a typed config value, and passed down.
  NEVER read env vars from arbitrary depths of the codebase.

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
  handle each error exactly once — either log it or return it, never both.

## Testing policy

- Test through the public API of a module/package/crate. Tests MUST NOT reach
  into private internals; if you feel the need, the public API is missing a
  seam or the module is too big.
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

## Simplicity

- Introduce an abstraction (port, layer, generic parameter) only when there is
  a concrete second use or a genuine seam (I/O, external service). NEVER add
  speculative indirection "for flexibility".
- Duplication is cheaper than the wrong abstraction. Rule of thumb: extract
  after the third occurrence, not the first.
- Code MUST be written for the reader: prefer boring, explicit code over
  clever constructs. Optimize only after measuring.
