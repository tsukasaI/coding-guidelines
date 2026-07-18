# Frontend common rules

Rules shared by every frontend guide. Load this file with any frontend task,
together with `principles.md`, `languages/typescript.md`, and the framework
guide. Where this file says "the framework's primitive", the framework guide
names the concrete mechanism. For lint/format/pre-commit setup, see
`languages/typescript.md`'s Tooling section and `patterns/tooling.md`.

## Domain logic

- Domain logic (pricing, validation, state machines) lives in plain TS
  modules per `languages/typescript.md`, outside the framework, so it is
  testable without rendering. Components and framework primitives bind UI to
  it; they MUST NOT contain business rules.

## Data fetching

- All data access goes through the app's typed API port, schema-validated at
  the boundary per `languages/typescript.md`. Components NEVER call `fetch`
  with raw URLs and NEVER cast responses.
- NEVER fetch inside a reactive side-effect primitive (`useEffect`, `$effect`,
  `createEffect`) with hand-rolled loading/error state: it races, bypasses
  the framework's caching and Suspense/streaming, and duplicates state the
  data layer already owns. Use the framework's data-loading primitive
  (server loading, a query library, `load`, `createResource` — see the
  framework guide).

## Injection and global state

- Framework context is the composition-root conduit: providers at the root
  inject ports, services, theme, and the current user — principles.md
  sanctions this as explicit wiring. Context is not a state manager.
- Colocate state in the lowest component/primitive that owns it; lift only
  when genuinely shared. Server data stays in the data layer's cache — NEVER
  copy it into client state or a store.

## Testing

- Test components through accessible output (Testing Library queries by
  role/name), never through internals or implementation details.
- Fake at the port or network seam (hand-written port fakes, MSW). NEVER mock
  internal components or the framework's own primitives.
