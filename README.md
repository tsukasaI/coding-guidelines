# coding-guidelines

Opinionated coding guidelines for backend (TypeScript, Go, Rust) and frontend
(React, Svelte, Solid) work. The primary consumer is an AI coding agent that
loads these files as context from a project's `CLAUDE.md` / `AGENTS.md`; the
secondary consumer is a human studying the architecture decisions.

Rules are normative (MUST / MUST NOT / SHOULD / MAY / NEVER), grounded in
primary sources (official docs, style guides, and team blogs), and kept short
enough to load selectively. The words follow
[RFC 2119](https://www.rfc-editor.org/rfc/rfc2119): MUST is an absolute
requirement, MUST NOT an absolute prohibition, SHOULD a strong default that
may be departed from for a stated reason, and MAY a truly optional choice.
NEVER is this repository's emphatic form of MUST NOT, used where a rule
is a hard ban. Where a rule follows from a specific source, its section
ends with a reference line of URLs; where the rule is this repository's own
judgment, the line reads `Ref: house rule (no external source).`

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

When several rows match, load the union of the matching rows; a more specific
row replaces the general one it extends. Do not load all files at
once; each language file is self-contained on top of `principles.md`. See
`templates/CLAUDE.md.example` for how a project should reference this repo.

**Auto-loading in Claude Code.** The owner's dotfiles link `principles.md`,
the three `languages/` files, `frontend/common.md` and `frontend/svelte.md`
into `~/.claude/rules/coding-guidelines/` (cloud sessions fetch them at a
pinned commit). `principles.md` loads in every session; the others carry
`paths:` frontmatter, so each loads only when a matching file is read; each file's `paths:`
frontmatter is the source of truth for which files trigger it. A
project then imports only what extensions cannot select: `frontend/react.md`
or `frontend/solid.md` (both use `.tsx`) and the `patterns/` files.

**Ownership boundary.** This repo owns what code should look like: principles,
language and framework conventions, patterns, and lint/format/CI settings. How
an AI agent behaves (permissions, git workflow, review process, precedence
when existing code violates a rule here) belongs to the agent's own
configuration, and this repo does not restate it.

Deliberate exceptions, kept here because each is inseparable from the code
rule it qualifies:

- The hook-bypass policy in `patterns/tooling.md` (humans only, NEVER
  agents): it defines what "hooks are a zero-warnings gate" means.
- The requester-communication clauses of the reuse ladder in `principles.md`
  ("name what you skipped" and "anything the requester explicitly asked
  for"): they bound what the ladder may cut.

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
frontend/solid.md        Solid 1.9+ (2.0 is a release candidate; this guide targets 1.9)
patterns/persistence.md  DB access: repositories, transactions, migrations
patterns/http.md         HTTP server & client patterns
patterns/codegen.md      schema-first code generation (OpenAPI, SQL)
patterns/tooling.md      lint/format tool choice and status, mandatory pre-commit + gitleaks
templates/CLAUDE.md.example  how a project references this repo
scripts/check-enforced-tags.sh  checks (enforced: ...) tags name real template rules
templates/golangci.yaml.example  Go lint config
templates/cargo-lints.toml.example, clippy.toml.example, rustfmt.toml.example, deny.toml.example
                         Rust lint, format and dependency config
templates/oxlintrc.json.example, oxlintrc.react.json.example, oxfmtrc.json.example, tsconfig.json.example
                         TypeScript / React lint, format and compiler config
templates/eslint.svelte.config.example, eslint.solid.config.example
                         ESLint fallback for Svelte / Solid template linting
templates/lefthook.yaml.example pre-commit hooks for a project
templates/gitleaks.toml.example secret-scanning config for a project
lefthook.yaml            this repo's own pre-commit hooks
.gitleaks.toml           this repo's own gitleaks config
```
