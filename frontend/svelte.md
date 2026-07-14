# Svelte

Specializes `principles.md` and `languages/typescript.md` for Svelte.
Baseline: Svelte 5 with runes (+ SvelteKit for apps), TypeScript strict.
Svelte 4 syntax — `export let`, `$:` reactive statements, store-first state,
slots — MUST NOT be written in new code; it appears below only as "do not use".

## Component boundaries

- One responsibility per component; split when unrelated concerns share a
  file or a `.svelte` file's `<script>` outgrows its markup.
- Domain logic (pricing, validation, state machines) lives in plain TS
  modules per `languages/typescript.md`; components bind UI to it. Reusable
  reactive logic goes in `.svelte.ts` modules — runes work there too.
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
- Shared client state: export `$state` from a `.svelte.ts` module and import
  it where needed — this replaces most Svelte 4 stores. Stores remain valid
  only for complex async streams or RxJS interop.
- Cross-tree injection (current user, services) uses `setContext`/`getContext`
  from a layout/root component — Svelte's composition-root conduit. Fast-
  changing values don't belong there.

Ref: svelte.dev/docs/svelte/$state, /$derived, /$effect ("When not to use
$effect"), /stores.

## Data fetching

- In SvelteKit, data loading belongs in `load` functions (`+page.ts` /
  `+page.server.ts`), typed and schema-validated at the boundary per
  `languages/typescript.md`. Components receive `data` as props.
- Server-only concerns (secrets, DB access) MUST live in `+page.server.ts` /
  `$lib/server/` so they never reach the client bundle.
- Mutations go through form actions (progressive enhancement via `use:enhance`)
  or explicit API-port calls — components never `fetch` raw URLs.
- NEVER fetch in `onMount`/`$effect` with hand-rolled loading flags when a
  `load` function can do it; for component-local async, prefer `{#await}`
  blocks over manual state triples.

Ref: svelte.dev/docs/kit/load; svelte.dev/docs/kit/form-actions.

## Error handling

- Expected failures are values: `load` returns typed error info or throws
  SvelteKit's `error(status)` to render the nearest `+error.svelte`; form
  actions return `fail(status, data)` for the form to display.
- `+error.svelte` per route section bounds blast radius, like an error
  boundary. Component code must not swallow errors silently.

## Testing

- Domain logic in plain TS modules is unit-tested without Svelte.
- Reactive logic in `.svelte.ts` gets its own tests; component tests render
  and assert on accessible output (Testing Library), not on internals.
- Fake at ports/network seams (e.g. MSW, stubbed `load` inputs); `load`
  functions are plain functions — test them by calling them with fake events.

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
