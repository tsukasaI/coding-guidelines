# Code generation (schema-first)

Operational rules for generating code from schemas. Load when setting up or
changing OpenAPI/SQL codegen. Decided stance: **schema-first** — the OpenAPI
document and the SQL schema/queries are the source of truth, and code is
generated from them. Code-first generation (emitting a spec from handlers or
a DB schema from TS types) is permitted only for internal, single-consumer
APIs, and MUST be recorded as an exception in the project's CLAUDE.md.

## The schemas

- The OpenAPI spec and migration SQL live in VCS and are reviewed like code —
  a spec change IS the API change; the diff to generated code is its
  consequence, not the review target.
- Lint the spec in CI (spectral is the common choice) so style and
  breaking-change checks run before any code is generated.
- Version the API in the spec (paths or headers); breaking changes get a new
  version, not an edited schema that generated clients silently absorb.

## What gets generated

| Source | Language | Tool | Output |
|---|---|---|---|
| OpenAPI | Go | oapi-codegen (strict-server mode, `net/http`) | server interfaces, typed client, models |
| OpenAPI | TypeScript | openapi-typescript + openapi-fetch | types + typed fetch client |
| OpenAPI | Rust | progenitor | typed client |
| SQL | Go | sqlc | typed query layer |
| SQL | Rust | sqlx macros (compile-time check against schema) | checked queries + committed `.sqlx` data |
| SQL | TypeScript | pgtyped | types for SQL queries |

- Rust has no mature OpenAPI→server-stub generator: implement axum handlers
  by hand against the spec and add contract tests that replay the spec's
  examples/paths against the running server. (Code-first utoipa exists but
  inverts the source of truth — see the stance above.)

## Operational rules

- Generated code is committed. CI regenerates and fails on drift
  (`sqlc diff`; for others: run the generator, then `git diff --exit-code`).
  Why: reviewers see the real consequence of a schema change, and builds
  don't depend on generator availability.
- NEVER hand-edit generated files. Customization goes through generator
  config, type-mapping options, or OpenAPI overlays. A hand edit survives
  exactly one regeneration.
- Pin generator versions (`go.mod` tool dependency, lockfile entry) and
  upgrade them as deliberate, reviewed changes. An unpinned generator makes
  CI drift-checks flap.
- Mark generated files as generated (standard headers do this) and exclude
  them from lint and review attention — but they still compile and still
  count as the adapter layer.
- Generated types are transport/storage DTOs, NOT domain types. The boundary
  still parses them into domain values (parse, don't validate). A generated
  client type proves what the wire promised, not what the domain requires.

Ref: docs.sqlc.dev (diff/vet); github.com/oapi-codegen/oapi-codegen;
openapi-ts.dev; docs.rs/sqlx (offline mode); pgtyped.dev;
github.com/oxidecomputer/progenitor.

## Anti-patterns AI agents produce around codegen

1. **Hand-editing generated output** to fix a name or add a method — erased
   on the next regeneration. Change the schema or the generator config.
2. **Treating generated DTOs as domain models**: passing the OpenAPI response
   struct through the whole app. Parse it at the boundary like any other
   wire data.
3. **Skipping the drift check**: regenerating locally "when needed" — the
   spec and the code quietly diverge. Drift fails CI, not code review.
4. **Regenerating with whatever version is installed**: diffs full of
   generator-version noise. Pin, and upgrade explicitly.
5. **Writing the client by hand next to a spec** that could generate it —
   every hand-written endpoint is a transcription error waiting to happen.
