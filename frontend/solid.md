# Solid

Specializes `principles.md`, `languages/typescript.md`, and
`frontend/common.md` for Solid.
Baseline: solid-js 1.9+ (Solid 2.0 is still beta — do not target it),
TypeScript strict.

The one mental model that prevents most bugs: **components run once**. There
is no re-render. Reactivity lives in signals and the tracking scopes that read
them (JSX expressions, memos, effects) — not in re-executing function bodies.

`oxlint` has no built-in Solid plugin yet (open, unresolved upstream
discussion) — keep `eslint-plugin-solid` running as a fallback. See
`patterns/tooling.md`.

## Component boundaries

- Components are setup functions: wire signals, memos, and handlers, return
  JSX. Splitting components is for organization only — unlike React it has no
  performance meaning, so split by responsibility, never "to reduce renders".
- Domain logic lives in plain TS modules (see `frontend/common.md`);
  reusable reactive logic goes in custom primitives (`createCheckout()`),
  Solid's equivalent of custom hooks.
- NEVER destructure `props` or spread them into a plain object
  (`const p = { ...props }`): both read the reactive getters once, severing
  reactivity. Access `props.x` inside the tracking scope that needs it.
  JSX spread (`<input {...rest} />`) is fine — the compiler keeps it reactive.
- Defaults and splitting MUST go through `mergeProps` / `splitProps`, which
  preserve getter reactivity.

```tsx
// Bad: destructuring reads once at setup; UI never updates
function Price({ amount, currency }: PriceProps) { ... }

// Good: keep the props object; defaults via mergeProps
function Price(raw: PriceProps) {
  const props = mergeProps({ currency: "USD" }, raw);
  return <span>{format(props.amount, props.currency)}</span>;
}
```

- Use control-flow components — `<Show>`, `<For>`, `<Switch>` — instead of
  ternaries and `array.map` in JSX: they reconcile fine-grained instead of
  recreating DOM. NEVER early-return from a component body based on a signal;
  the condition would be read once, untracked.

Ref: docs.solidjs.com/concepts/components/props.

## State management

- `createSignal` for atomic values; `createStore` for nested/keyed state with
  fine-grained updates (`setState("todos", i, "done", true)`).
- Store mutation through path setters is idiomatic, not a violation of the
  TS guide's immutability rule: the store proxy IS the reactive store, and
  path setters are how fine-grained updates propagate. Plain domain objects
  outside signals/stores stay immutable.
- Derive, don't sync — and in Solid, "derive" means *a function*:

```tsx
const [items, setItems] = createSignal<Item[]>([]);

// Bad: computed once at setup, never updates
const total = items().reduce((s, i) => s + i.price, 0);

// Bad: effect writing a signal to derive state
createEffect(() => setTotal(items().reduce((s, i) => s + i.price, 0)));

// Good: plain derived function — cheap computation
const total = () => items().reduce((s, i) => s + i.price, 0);

// Good: createMemo — expensive computation or many readers
const total = createMemo(() => items().reduce((s, i) => s + i.price, 0));
```

- Plain derived functions re-run per read; `createMemo` caches and recomputes
  once per dependency change. Default to the plain function; memoize when the
  computation is expensive or read from multiple tracking scopes.
- `createEffect` is for side effects on external systems (DOM measurement,
  imperative libs, logging). NEVER set signals inside `createEffect` to derive
  state — that is what memos are for, and it invites loops and extra work.
- Colocate signals in the component or primitive that owns them; lift to a
  shared custom primitive or module-level signal only when actually shared.

Ref: docs.solidjs.com/concepts/derived-values/memos, /concepts/effects.

## Data fetching

- Async data goes through `createResource` (or the framework's loader —
  SolidStart route `load`/`query`): it ties the request to a source signal,
  re-fetches when it changes, and integrates with `<Suspense>` and
  `<ErrorBoundary>`.
- NEVER fetch inside `createEffect` with hand-rolled loading/error signals —
  it races and bypasses Suspense (the docs position `createResource` as the
  correct alternative).
- The fetcher calls the app's typed API port per `frontend/common.md`, never
  raw `fetch` + `as` in components.

```tsx
const [order] = createResource(orderId, (id) => api.fetchOrder(id));
// <Suspense fallback={<Spinner/>}> {order()?.total} </Suspense>
```

Ref: docs.solidjs.com/reference/basic-reactivity/create-resource.

## Context and global state

- Module-level signals/stores are Solid's simplest global state: a
  `createStore` exported from a plain TS module is fine for genuinely global
  client state — fine-grained subscriptions mean no over-render tax.
- Use context (`createContext`/`useContext`) for injection — services, API
  ports, theme, current user — provided at the composition root; and for
  state scoped to a subtree with multiple instances (each provider is its own
  scope; a module-level signal would be accidentally shared).
- Server data belongs in resources/route loaders, not copied into stores.

## Error handling

- Expected failures are values: resources expose `error`; render failure
  branches with `<Show>`/`<Switch>` as ordinary UI states.
- Wrap routable regions in `<ErrorBoundary fallback={...}>` so a thrown bug
  degrades a panel, not the app. Handler errors are handled in the handler.

## Testing

- Domain logic: plain TS unit tests, no Solid involved.
- Custom primitives: test inside `createRoot` so ownership/disposal work.
- Components: render and assert on accessible output; fake at the
  port/network seam per `frontend/common.md`.

## Anti-patterns AI agents produce in Solid

1. **React reflexes**: destructuring props, `useEffect`-style effect+setState
   derivation, early returns on conditions, expecting the body to re-run.
   Components run once; everything dynamic must be read inside a tracking scope.
2. **Derived value computed at setup**: `const total = items().length * 2` in
   the component body — frozen forever. Make it a function or a memo.
3. **`array.map` and ternaries in JSX** instead of `<For>`/`<Show>`: recreates
   DOM per change and, with `.map`, loses fine-grained updates.
4. **Fetching in effects**: `createEffect` + loading/error signals instead of
   `createResource`; races, no Suspense integration.
5. **Signal-call amnesia**: passing `items` where `items()` is needed (or
   calling it once and storing the result), then "reactivity doesn't work".
   A signal is a getter; read it where you need tracking, pass the getter
   where the callee needs to track.
