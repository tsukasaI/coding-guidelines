# Svelte

Specializes `principles.md`, `languages/typescript.md`, and
`frontend/common.md` for Svelte.
Baseline: Svelte 5 with runes (+ SvelteKit for apps), TypeScript strict.
Svelte 4 syntax — `export let`, `$:` reactive statements, store-first state,
slots — MUST NOT be written in new code; it appears below only as "do not use".

`oxlint` doesn't lint `.svelte` template syntax yet (it only covers
`<script>` blocks) — keep `eslint-plugin-svelte` running until native
support ships. Formatting is unaffected: `oxfmt` already handles `.svelte`
files. See `patterns/tooling.md`.

## Component boundaries

- One responsibility per component; split when unrelated concerns share a
  file or a `.svelte` file's `<script>` outgrows its markup.
- Domain logic lives in plain TS modules (see `frontend/common.md`);
  components bind UI to it. Reusable reactive logic goes in `.svelte.ts`
  modules — runes work there too.
- Props are declared by destructuring `$props()` with defaults; type them
  explicitly. (Unlike Solid, destructuring props is the documented pattern.)

```svelte
<script lang="ts">
  let { order, onconfirm }: { order: Order; onconfirm: () => void } = $props();
</script>
```

- Pass UI fragments as snippets and render with `{@render ...}`; slots are
  deprecated in Svelte 5. Callback props replace `createEventDispatcher`.
- Use `$bindable` sparingly: two-way flow on many props makes data flow
  unpredictable (the docs' own warning). Default to value-down, callback-up.

Ref: svelte.dev/docs/svelte/$props, /snippet, /$bindable.

## State management (runes)

- `$state` declares reactive state; objects and arrays become deeply reactive
  proxies. Mutate them directly (`todos.push(t)`) — that is idiomatic, not a
  violation of the immutability rule in the TS guide, because the proxy IS
  the reactive store. Use `$state.raw` for large values you replace wholesale.
- Do not destructure reactive objects: the extracted bindings stop updating.
  Access fields through the object, or destructure inside `$derived`.
- Derive, don't sync: anything computable from other state is `$derived` (or
  `$derived.by` for multi-step). Derived expressions MUST be side-effect free.

```svelte
<script lang="ts">
  // Bad: $effect to synchronise state (docs explicitly warn against this)
  let total = $state(0);
  $effect(() => { total = items.reduce((s, i) => s + i.price, 0); });

  // Good: derived
  let total = $derived(items.reduce((s, i) => s + i.price, 0));
</script>
```

- `$effect` is an escape hatch for synchronizing with external systems (DOM
  measurement, third-party widgets, analytics). NEVER use it to update state
  from other state, and NEVER for logic that belongs in an event handler.

Ref: svelte.dev/docs/svelte/$state, /$derived, /$effect ("When not to use
$effect").

## Context and global state

- Shared client state lives in `.svelte.ts` modules — this replaces most
  Svelte 4 stores (stores remain valid only for complex async streams or
  RxJS interop). State that is ever reassigned cannot be exported directly
  (compile error `state_invalid_export`): export an object whose properties
  you mutate, or export getter/setter functions.

```ts
// Bad: reassigned state cannot cross the module boundary
export let user = $state<User | null>(null); // state_invalid_export

// Good: export an object and mutate its properties
export const session = $state({ user: null as User | null });
```

- Module-level reactive state is UI state, not a dependency. Services and
  ports are injected with `setContext` from the layout/root component —
  Svelte's composition-root conduit (sanctioned by principles.md).
- Context is scoped per component tree; module state is shared process-wide.
  On the server that means it leaks between requests — keep per-request data
  in `load` results or context, never in module state.
- Server data stays in `load` results — do not copy it into module state.

Ref: svelte.dev/docs/svelte/stores; svelte.dev/docs/kit/state-management.

## Data fetching

- In SvelteKit, data loading belongs in `load` functions (`+page.ts` /
  `+page.server.ts`), typed and schema-validated at the boundary per
  `languages/typescript.md`. Components receive `data` as props.
- Server-only concerns (secrets, DB access) MUST live in `+page.server.ts` /
  `$lib/server/` so they never reach the client bundle.
- Mutations go through form actions (progressive enhancement via `use:enhance`)
  or the typed API port per `frontend/common.md` — components never `fetch`
  raw URLs.
- NEVER fetch in `onMount`/`$effect` with hand-rolled loading flags when a
  `load` function can do it; for component-local async, prefer `{#await}`
  blocks over manual state triples.

Ref: svelte.dev/docs/kit/load; svelte.dev/docs/kit/form-actions.

## Error handling

- Expected failures stay values inside app code. `load` and form actions are
  the transport boundary, so `error(status)` (renders the nearest
  `+error.svelte`) and `fail(status, data)` are the sanctioned translation of
  an expected failure into the protocol — the same boundary translation a
  handler does when mapping domain errors to status codes, not
  exception-based control flow.
- `+error.svelte` per route section bounds blast radius, like an error
  boundary. Component code must not swallow errors silently.

## Testing

- Domain logic in plain TS modules is unit-tested without Svelte.
- Reactive logic in `.svelte.ts` gets its own tests; component tests render
  and assert on accessible output (Testing Library), not on internals.
- Fake at the port/network seam per `frontend/common.md`; `load` functions
  are plain functions — test them by calling them with fake events.

## Anti-patterns AI agents produce in Svelte

1. **Svelte 4 reflexes**: `export let`, `$:` statements, `createEventDispatcher`,
   `<slot>`, writable stores for everything. Training data is full of it;
   Svelte 5 code uses `$props()`, `$derived`, callback props, snippets, and
   module-level `$state`.
2. **`$effect` as glue**: deriving state, mirroring props into state, chaining
   updates. Use `$derived`; reserve `$effect` for external systems.
3. **Destructured reactivity loss**: `const { items } = cart` (or spreading
   props/state) and then wondering why the UI is stale. Keep the object
   reference; destructure only inside `$derived`.
4. **`bind:` everywhere**: two-way binding on every prop until data flow is
   untraceable. Default to one-way + callback props; `$bindable` only for
   genuine input-like components.
5. **Store ceremony for local state**: creating a writable store (plus
   subscribe/unsubscribe) where a `$state` variable — or a `.svelte.ts`
   module for sharing — is the whole answer.
