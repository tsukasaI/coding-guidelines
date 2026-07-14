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
  need a comment justifying why narrowing is impossible.

Ref: devblogs.microsoft.com/typescript (6.0 and 7.0 announcements);
typescriptlang.org/tsconfig.

## Project layout

- Group by domain feature (`src/order/`, `src/billing/`), not by kind
  (`src/types/`, `src/interfaces/`, `src/utils/`). Types live next to the
  functions that use them.
- Each feature exposes a deliberate public surface via its top module; deep
  imports into another feature's internals are forbidden.
- No barrel files that re-export the world; they create cycles and defeat
  tree-shaking. Export from the feature root only what other features need.

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
