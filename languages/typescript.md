# TypeScript

Specializes `principles.md` for TypeScript. Baseline: TypeScript 7 (native
compiler, GA July 2026), ESM only, strict only. Style: functional-first —
modules of functions and plain data, not class hierarchies.

## Compiler baseline

- `strict: true`, `module: "esnext"` (or `nodenext` for Node libraries), and
  an es2025+ target are the TS 6.0 defaults — MUST NOT be weakened. Never set
  `strict: false` or reintroduce CommonJS output.
- Enable beyond `strict`: `noUncheckedIndexedAccess` (indexing returns
  `T | undefined`), `exactOptionalPropertyTypes` (absent ≠ explicitly
  `undefined`), `verbatimModuleSyntax` (forces `import type`; emitted modules
  match source syntax 1:1).
- Options removed in TS 7 (`baseUrl`, `target: es5`, `moduleResolution: node10`,
  namespaces-as-modules) MUST NOT appear in new configs.
- TS 7.0 ships without a stable programmatic API (planned for 7.1). Projects
  whose tooling consumes the TS API — Svelte/Vue/Astro/MDX integrations,
  Angular template checking, webpack loaders, language-service plugins —
  SHOULD stay on 6.x until 7.1.
- `any` is banned in first-party code; use `unknown` and narrow. `as` casts
  need a comment justifying why narrowing is impossible. (enforced:
  `typescript/no-explicit-any` in `templates/oxlintrc.json.example`; the
  comment-on-`as` requirement has no linter, code review still catches it.)

Ref: devblogs.microsoft.com/typescript (6.0 and 7.0 announcements);
typescriptlang.org/tsconfig.

## Tooling

- `oxlint` + `oxfmt` are the default lint/format stack — Rust-based, with
  native React and React Hooks rules (no gap for plain TS/React). Format
  and lint both MUST fail the pre-commit hook on any warning, not only
  errors (see `patterns/tooling.md`).
- Type-aware linting runs through `tsgolint`, a separate Go binary built on
  `typescript-go` (this baseline's own "Corsa" engine) rather than the old
  tsc programmatic API. This is why it works with the TS7 baseline above
  without needing the 6.x carve-out: unlike `typescript-eslint`, it isn't
  one of the "tooling that consumes the TS API" cases. It covers 59/61 of
  `typescript-eslint`'s type-aware rules; use `strict-type-checked` +
  `stylistic-type-checked` as the reference severity bar for what "maximal
  strictness" means here.
- oxlint's ESLint-plugin compatibility layer (v9+ plugin API) is alpha —
  existing ESLint plugins mostly work through it, but treat that as
  unproven, not load-bearing.
- Biome is a fallback only, for projects where the oxlint plugin layer
  proves unstable — not a co-equal default. It has its own type-aware
  inference but the same framework-coverage gaps as oxlint (see
  `patterns/tooling.md` for the Svelte/Solid specifics).
- `categories.style` MUST be `error`, not `warn`, per the maximal-strictness
  stance in `patterns/tooling.md`; there is no severity carve-out for style.
- `oxc/no-barrel-file` is a native oxlint rule (the `oxc` plugin, not the
  compat layer) and can enforce the no-barrel-file rule today; it's a
  module-count heuristic, not literal "re-exports everything" detection,
  tune the rule's `threshold` option for a project's actual index-module
  size.
  Import-cycle detection (`import/no-cycle`) still needs the `import`
  plugin, which stays on oxlint's alpha JS-plugin layer as of 2026.
- `tsconfig.json` is itself a mechanical gate: `strict`,
  `noUncheckedIndexedAccess`, `exactOptionalPropertyTypes`,
  `verbatimModuleSyntax`, and `noImplicitOverride` are enforced by the
  compiler, not a linter (`templates/tsconfig.json.example`).
- No oxlint rule enforces "dependencies are function parameters, no DI
  container, no import-time side effects"; that stays code-review-only.

Ref: oxc.rs (oxlint, oxfmt, tsgolint docs, no-barrel-file, JS Plugins
Alpha); typescript-eslint.io (strict-type-checked, stylistic-type-checked);
biomejs.dev.

## Project layout

- Group by domain feature (`src/order/`, `src/billing/`), not by kind
  (`src/types/`, `src/interfaces/`, `src/utils/`). Types live next to the
  functions that use them.
- Each feature exposes a deliberate public surface via its top module; deep
  imports into another feature's internals are forbidden. (enforced,
  partial: `eslint/no-restricted-imports` can only match a path pattern, it
  has no concept of "a feature's internals" on its own. Put non-public
  modules under an `internal/` subdirectory per feature
  (`src/order/internal/*`) so the rule in
  `templates/oxlintrc.json.example` has something literal to match; a
  feature that doesn't follow that convention isn't covered.)
- No barrel files that re-export the world; they create cycles and defeat
  tree-shaking. Export from the feature root only what other features need.
  (enforced: `oxc/no-barrel-file`, native, no compat-layer plugin needed;
  import-cycle detection itself needs `import/no-cycle` behind oxlint's
  alpha JS-plugin layer, see Tooling below)

## Composition and dependency injection

- Dependencies are function parameters — usually one `deps` object. Effectful
  modules export factories: `makeCheckout(deps): Checkout`. Pure modules
  export plain functions.
- All wiring happens in the composition root (the entry file). NEVER use DI
  containers, decorator injection, or module-level singletons that construct
  their own dependencies on import. Import-time side effects are banned.
- Ports are TypeScript interfaces (or object types) defined next to the
  consumer; adapters implement them at the edge.
- Read and parse env/config once at the composition root into a typed config
  object. `process.env` MUST NOT appear outside it.

```ts
// Bad: module constructs its own deps at import time
export const db = new Pool({ connectionString: process.env.DB_URL });

// Good: factory takes a deps object; main wires it
export interface OrderRepo {
  byId(id: OrderId): Promise<Order | undefined>;
  save(order: Order): Promise<void>;
}

export function makeCheckout(deps: { repo: OrderRepo; clock: () => Date }) {
  return {
    async place(draft: OrderDraft): Promise<Result<Order, CheckoutError>> { ... },
  };
}

// main.ts — composition root
const cfg = parseConfig(process.env);
const repo = makePgOrderRepo(pgPool(cfg.db));
const checkout = makeCheckout({ repo, clock: () => new Date() });
```

## Domain modelling

- Model closed variants as discriminated unions and switch on the tag; get
  exhaustiveness by assigning the leftover to `never` in the default branch.
  (enforced: `typescript/switch-exhaustiveness-check`, type-aware, catches a
  missing case even before the `never` assignment would)

```ts
type Payment =
  | { kind: "card"; last4: string }
  | { kind: "invoice"; dueDate: Date };

function fee(p: Payment): number {
  switch (p.kind) {
    case "card": return 30;
    case "invoice": return 0;
    default: {
      const exhaustive: never = p; // compile error when a variant is added
      throw new Error(`unreachable: ${exhaustive}`);
    }
  }
}
```

- Brand IDs and domain primitives so structurally-identical strings can't be
  mixed up. (Branding is a community pattern, not a language feature — use one
  helper and reuse it.)

```ts
type Brand<T, B extends string> = T & { readonly __brand: B };
type UserId = Brand<string, "UserId">;

// The single sanctioned bare `as`: a brand has no runtime representation,
// so the one constructor per brand is the only place a cast can live.
const UserId = (s: string) => s as UserId;
```

- Prefer unions over structs of mutually exclusive optionals; prefer
  `readonly` fields and arrays in domain types; treat all data as immutable —
  produce new values, don't mutate inputs.
- Use `satisfies` to check a value against a type without widening its
  inferred type.
- NEVER use TS `enum` or `namespace` in new code: they are non-erasable syntax
  that survives compilation. Use union-of-literals (with a `const` object for
  values) and plain modules.

Ref: TS Handbook (narrowing, discriminated unions, `satisfies`).

## Boundaries and validation

- Every I/O boundary (HTTP body, query params, env, DB rows, queue messages,
  third-party API responses) MUST be parsed with a schema library (zod 4 or
  valibot 1) into a typed value. `JSON.parse(...) as Foo` is a lie, not a parse.
- Derive static types from schemas (`z.infer`) so the runtime check and the
  type can't drift apart.
- Parse with `safeParse` (or the valibot equivalent) and translate failures
  into the boundary's error value, keeping expected failures as values. A
  throwing `.parse` is reserved for startup config, where invalid input is a
  deploy bug, not an expected failure.
- Validate at the boundary only; internal functions trust their typed inputs
  (see principles.md "Parse, don't validate").

```ts
// Good: schema is the single source of truth at the edge
const OrderDraft = z.object({
  userId: z.string().min(1).transform(UserId), // the brand constructor
  lines: z.array(Line).nonempty(),
});
type OrderDraft = z.infer<typeof OrderDraft>;
```

## Error handling

- Expected failures are values: return a discriminated `Result` union from
  domain and application functions, so callers must branch.

```ts
type Result<T, E> = { ok: true; value: T } | { ok: false; error: E };
type CheckoutError =
  | { kind: "out_of_stock"; sku: string }
  | { kind: "payment_declined" };
```

- `throw` is reserved for bugs and unrecoverable states; edge frameworks that
  communicate via exceptions get a translation layer at the adapter.
- `catch (e)` binds `unknown` under strict settings — narrow before use;
  NEVER access `e.message` unchecked, and never swallow: rethrow, translate
  into a `Result`, or handle.
- An `async` call MUST be awaited, returned, or explicitly discarded (`void
  fireAndForget()`); a bare unawaited call silently drops its rejection.
  (enforced: `typescript/no-floating-promises`, type-aware)
- Translate at boundaries: adapters map driver/HTTP errors into the port's
  error union; the transport layer maps domain errors to status codes.

Ref: typescriptlang.org/tsconfig (`useUnknownInCatchVariables`, part of `strict`).

## Testing

- Test through each feature's public surface; no reaching into internals, no
  spying on a module's private functions (if you need `vi.spyOn` internals,
  the seam is missing).
- Fake at ports: hand-written in-memory `OrderRepo` over auto-mock frameworks.
  Pure domain functions need no doubles at all.
- Schema round-trips make good table tests: valid inputs parse, invalid inputs
  produce the expected issues.
- Type-level regressions: use `expect-type`-style assertions (or `satisfies`)
  for load-bearing inferred types.

## Anti-patterns AI agents produce in TypeScript

1. **`as` to make errors go away**: casting `JSON.parse`, `unknown`, or a
   half-built object to the target type. Parse with a schema or narrow with a
   type guard; every `as` is a hole in the type system.
2. **Class-and-decorator DI habits**: `@Injectable()` services, containers,
   or exported singleton instances. Wire plain factories in the composition
   root instead.
3. **Optional-field sprawl**: one interface with ten `?` fields covering
   several actual states. Split into a discriminated union; make impossible
   combinations unrepresentable.
4. **Hand-rolled boundary checks** (`if (typeof body.email === "string")`)
   drifting from the type they claim to guarantee. One schema per boundary,
   type inferred from it.
5. **TS `enum`, `namespace`, and CommonJS patterns** (`require`, `module.exports`,
   default-export objects as pseudo-modules) in new code. ESM named exports,
   literal unions, plain objects.
