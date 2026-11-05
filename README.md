# coding-guidelines

Opinionated coding guidelines for backend (TypeScript, Go, Rust) and frontend
(React, Svelte, Solid) work. The primary consumer is an AI coding agent that
loads these files as context from a project's `CLAUDE.md` / `AGENTS.md`; the
secondary consumer is a human studying the architecture decisions.

Rules are normative (MUST / SHOULD / NEVER), grounded in primary sources
(official docs, style guides, and team blogs), and kept short enough to load
selectively. Where a rule follows from a specific source, the section ends
with a reference line.

## How to consume this repo

**AI agents** — load the minimum set for the task at hand:

| Task | Load |
|---|---|
| Any backend/shared code change | `principles.md` + the language file for the task's language |
| Go service | `principles.md`, `languages/go.md` |
| Rust service/library | `principles.md`, `languages/rust.md` |
| TypeScript backend/shared code | `principles.md`, `languages/typescript.md` |
| React UI | `principles.md`, `languages/typescript.md`, `frontend/common.md`, `frontend/react.md` |
| Svelte UI | `principles.md`, `languages/typescript.md`, `frontend/common.md`, `frontend/svelte.md` |
| Solid UI | `principles.md`, `languages/typescript.md`, `frontend/common.md`, `frontend/solid.md` |
| Architecture / layout decisions | `principles.md` first, then the language file |
| DB access / schema change | `principles.md`, the language file, `patterns/persistence.md` |
| HTTP endpoint or API client | `principles.md`, the language file, `patterns/http.md` |
| Setting up OpenAPI/SQL codegen | `patterns/codegen.md` + the language file |
| Setting up or auditing lint/format/pre-commit tooling | `patterns/tooling.md` + the language file(s) |

When several rows match, use the most specific one. Do not load all files at
once; each language file is self-contained on top of `principles.md`. See
`templates/CLAUDE.md.example` for how a project should reference this repo.

**Humans** — read `principles.md` end to end once; treat the guide files as
lookup references. Language files cover project layout, composition/DI, domain
modelling, error handling, and testing; frontend files cover component
boundaries, state management, data fetching, and context/global state. Every
guide ends with the anti-patterns AI agents most often produce in that stack.

## Philosophy (summary; rules live in `principles.md`)

1. [Dependencies point inward](principles.md#dependency-direction): the domain imports nothing from the edges.
2. [One composition root](principles.md#composition-root): all wiring in one place, no DI containers.
3. [Consumers own their ports](principles.md#dependency-direction); adapters implement them at the edge.
4. [Parse, don't validate](principles.md#parse-dont-validate): boundaries yield typed values or errors, once.
5. [Invalid states unrepresentable](principles.md#parse-dont-validate) before runtime checks.
6. [Errors are values](principles.md#errors-as-values); panics are for bugs.
7. [Translate errors at boundaries](principles.md#errors-as-values), handle each exactly once.
8. [Test public APIs](principles.md#testing-policy); fake only at architectural seams.
9. [Derive, don't sync](frontend/common.md#derive-dont-sync): UI state is computed, not mirrored.
10. [Simplicity](principles.md#simplicity): pay for abstractions; climb the reuse ladder first.

## Layout

```
principles.md            language-agnostic core (read first)
languages/go.md          Go
languages/rust.md        Rust (2024 edition)
languages/typescript.md  TypeScript (strict, ESM)
frontend/common.md       rules shared by all frontend guides
frontend/react.md        React 19+ (Compiler assumed)
frontend/svelte.md       Svelte 5 (runes)
frontend/solid.md        Solid 1.9+ (2.0 beta not covered)
patterns/persistence.md  DB access: repositories, transactions, migrations
patterns/http.md         HTTP server & client patterns
patterns/codegen.md      schema-first code generation (OpenAPI, SQL)
patterns/tooling.md      lint/format tool choice and status, mandatory pre-commit + gitleaks
templates/CLAUDE.md.example  how a project references this repo
scripts/check-enforced-tags.sh  checks (enforced: ...) tags name real template rules
```
