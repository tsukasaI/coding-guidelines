---
paths:
  - "**/*.tsx"
  - "**/*.jsx"
  - "**/*.svelte"
  - "**/*.svelte.ts"
  - "**/*.svelte.js"
  - "**/+*.ts"
  - "**/+*.js"
  - "**/hooks.*.ts"
---

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

Ref: house rule (no external source).

## Derive, don't sync

- Anything computable from props or other state MUST be derived, not stored.
  NEVER keep a copy of a prop in state to stay in sync with it, and NEVER use
  a reactive side-effect primitive (`useEffect`, `$effect`, `createEffect`)
  to write one piece of state from another. Why: a synced copy lags one
  update behind and creates two sources of truth. The framework guide names
  the derivation primitive (render-time computation, `$derived`, a function
  or `createMemo`).
- Exception: a deliberately detached seed read once (an edit-form draft).
  Name the prop `initialX`/`defaultX` and reset the state with `key`, not an
  effect.

Ref: You Might Not Need an Effect
(https://react.dev/learn/you-might-not-need-an-effect); Svelte `$derived`
(https://svelte.dev/docs/svelte/$derived); Solid memos
(https://docs.solidjs.com/concepts/derived-values/memos).

## Data fetching

- All data access goes through the app's typed API port, schema-validated at
  the boundary per `languages/typescript.md`. Components NEVER call `fetch`
  with raw URLs and NEVER cast responses.
- NEVER fetch inside a reactive side-effect primitive (`useEffect`, `$effect`,
  `createEffect`) with hand-rolled loading/error state: it races, bypasses
  the framework's caching and Suspense/streaming, and duplicates state the
  data layer already owns. Use the framework's data-loading primitive
  (server loading, a query library, `load`, `createResource` — see the
  framework guide). Sole exception: the single centralized custom hook that
  `frontend/react.md` allows in a tiny app with no other server-state needs.

Ref: You Might Not Need an Effect, "Fetching data"
(https://react.dev/learn/you-might-not-need-an-effect); SvelteKit loading
data (https://svelte.dev/docs/kit/load); Solid `createResource`
(https://docs.solidjs.com/reference/basic-reactivity/create-resource). The
typed API port requirement is a house rule.

## Injection and global state

- Framework context is the composition-root conduit: providers at the root
  inject ports, services, theme, and the current user — principles.md
  sanctions this as explicit wiring. Context is not a state manager.
- Colocate state in the lowest component/primitive that owns it; lift only
  when genuinely shared. Server data stays in the data layer's cache — NEVER
  copy it into client state or a store to display it. Exception: an editable
  draft or optimistic value that is meant to diverge until saved; keep it
  local and discard it on success.

Ref: Passing Data Deeply with Context
(https://react.dev/learn/passing-data-deeply-with-context); SvelteKit state
management (https://svelte.dev/docs/kit/state-management); Solid context
(https://docs.solidjs.com/concepts/context). Treating context as the
composition-root conduit is a house rule.

## Testing

- Test components through accessible output (Testing Library queries by
  role/name), NEVER through internals or implementation details.
- Fake at the port or network seam (hand-written port fakes, MSW). NEVER mock
  internal components or the framework's own primitives.

Ref: Testing Library guiding principles
(https://testing-library.com/docs/guiding-principles); Testing Library query
priority (https://testing-library.com/docs/queries/about#priority); Mock
Service Worker philosophy (https://mswjs.io/docs/philosophy).

## Anti-patterns AI agents produce in frontend code

1. **Business rules in components**: pricing, validation, or state-machine
   logic written inside a component or framework primitive instead of a plain
   TS module.
2. **Mirrored state**: a prop or other state copied into local state and kept
   in sync by an effect, instead of being derived.
3. **Fetch-in-effect with hand-rolled loading/error state**, or raw `fetch`
   with a cast response, bypassing the typed API port and the framework data
   layer.
4. **Context or store as a state manager**: server data copied into client
   state, or one provider holding everything, instead of colocated state.
5. **Mocking internals in tests**: mocking internal components or framework
   primitives, or asserting on implementation details, instead of faking at
   the port or network seam.
