# React

Specializes `principles.md` and `languages/typescript.md` for React.
Baseline: React 19+, React Compiler enabled, TypeScript strict, function
components only.

## Rules of React (non-negotiable)

- Components and hooks MUST be pure during render: same props/state → same
  JSX; no side effects, no mutation of props, state, or values returned by
  hooks.
- Only React calls components: never invoke a component as a plain function,
  never pass hooks around as values.
- Hooks are called at the top level only — not in loops, conditions, or
  nested functions.

Ref: react.dev/reference/rules.

## Component boundaries

- Components follow the single-responsibility test used everywhere else: one
  reason to change. Split when a component renders unrelated concerns or when
  state used by one branch forces re-render of another.
- Separate view from logic: extract non-trivial state machines and event logic
  into custom hooks (`useCheckout()`), keep components mostly markup. Domain
  logic (pricing, validation) lives outside React entirely — plain TS modules
  per `languages/typescript.md` — so it is testable without rendering.
- Props are the component's public API: keep them minimal and typed; NEVER
  pass a grab-bag object "for flexibility". Prefer `children`/composition
  over boolean-prop configuration explosions.
- With a framework that provides Server Components: default to server
  components; add `"use client"` only at genuinely interactive leaves. Keep
  the client boundary as low in the tree as possible — data access stays on
  the server side of it.

Ref: react.dev/reference/rsc/server-components; react.dev/learn/thinking-in-react.

## State management

- Derive, don't sync. If a value can be computed from props or existing state,
  compute it during render. NEVER mirror props into state and NEVER use
  `useEffect` + `setState` to keep two pieces of state aligned.

```tsx
// Bad: synced copy, one render behind, two sources of truth
const [fullName, setFullName] = useState("");
useEffect(() => { setFullName(`${first} ${last}`); }, [first, last]);

// Good: derived during render
const fullName = `${first} ${last}`;
```

- Structure state by the official principles: group values that change
  together; avoid contradictions (impossible combinations → discriminated
  union state); avoid redundant state (computable → derive); avoid
  duplication (store IDs, not copies of objects); avoid deep nesting.
- Colocate: state lives in the lowest component that needs it. Lift to the
  closest common parent only when two components must share it — each piece
  of state has exactly one owner.
- To reset a subtree's state when identity changes, change its `key` — do not
  write effects that reset fields one by one.
- Event logic belongs in event handlers, not effects. If code runs "because
  the user did X", it is a handler; effects are only for synchronizing with
  external systems (subscriptions, imperative widgets, analytics).
- Assume the React Compiler: do NOT write `useMemo`/`useCallback`/`memo` in
  new code unless profiling shows the compiler needs help; do not strip
  existing memoization from old code without measuring.

Ref: react.dev/learn/you-might-not-need-an-effect;
react.dev/learn/choosing-the-state-structure; react.dev/blog (React Compiler 1.0).

## Data fetching

- NEVER hand-roll fetch-in-`useEffect` with loading/error `useState` triples:
  it races, refetches on every remount, and caches nothing. The official docs
  themselves list its downsides and point to better options.
- Order of preference: (1) the framework's server-side loading (Server
  Components / route loaders); (2) an established async-state library
  (TanStack Query or SWR) for client-side caching, deduplication, and
  revalidation; (3) only in a tiny dependency-free app, one custom hook that
  centralizes cancellation and caching — never per-component effects.
- Fetching code calls the app's API-client port (typed, schema-validated per
  `languages/typescript.md`) — components never call `fetch` with raw URLs.
- Mutations invalidate or update the relevant queries at the mutation site;
  do not sprinkle refetch calls through unrelated components.

Ref: react.dev/learn/you-might-not-need-an-effect (fetching);
react.dev/learn/synchronizing-with-effects.

## Context and global state

- Reach for context only for genuinely tree-wide, slowly-changing values:
  theme, locale, current user, an injected service/client. Context is React's
  composition-root conduit — inject port implementations via a provider at
  the root.
- Context is not a state manager: every consumer re-renders on change, so
  fast-changing values (form input, cursor, list filters) MUST NOT live in
  one. Before adding a store or context, try lifting state or passing
  `children`; most "prop drilling" pain is a composition problem.
- If server data is cached in a query library, do not duplicate it into a
  global store — the cache is the single source of truth; a separate store
  re-introduces sync bugs.
- A dedicated client-state store (e.g. Zustand) is a last resort for real
  cross-cutting client state (multi-panel editor state); it holds client
  state only, never copies of server data.

Ref: react.dev/learn/passing-data-deeply-with-context ("Before you use context").

## Error handling

- Expected failures (query errored, form invalid) are values in props/state —
  render them as normal UI branches.
- Error boundaries catch render-time bugs: place one per routable region so a
  crash degrades a panel, not the page. Event-handler and async errors are
  NOT caught by boundaries — handle them where they occur and set state.

## Testing

- Test components through their public API: render, interact, assert on the
  accessible output (Testing Library queries by role/name) — never on
  internal state, hook order, or implementation details.
- Domain logic extracted to plain TS is unit-tested without React; custom
  hooks with real logic get `renderHook` tests; components get behavior tests.
- Fake at the port: stub the API client or query layer (e.g. MSW at the
  network seam), not internal components. Snapshot tests only for genuinely
  static markup.

## Anti-patterns AI agents produce in React

1. **Effect-as-glue**: `useEffect` to derive state, propagate props to state,
   or chain updates (effect sets A, second effect reacts to A…). Derive during
   render, handle events in handlers, reset with `key`.
2. **Fetch-in-effect triples** (`data`/`loading`/`error` useState + fetch in
   `useEffect`) in every component. Use the framework loader or a query
   library through the API port.
3. **Manual memoization reflex**: wrapping every value in `useMemo`, every
   function in `useCallback`, every component in `memo`. The compiler does
   this; unmeasured manual memoization is noise that can block better output.
4. **Monolithic page components**: 400-line components mixing data fetching,
   domain rules, and markup with a dozen `useState`s. Extract hooks and plain
   TS modules; split by responsibility.
5. **Context as app-wide store**: shoving all state into one provider (or
   adding Redux by default), re-rendering the whole tree per keystroke.
   Colocate state; use context for injection and slow tree-wide values only.
