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
| Any code change | `principles.md` + the one language file |
| Go service | `principles.md`, `languages/go.md` |
| Rust service/library | `principles.md`, `languages/rust.md` |
| TypeScript backend/shared code | `principles.md`, `languages/typescript.md` |
| React UI | `principles.md`, `languages/typescript.md`, `frontend/react.md` |
| Svelte UI | `principles.md`, `languages/typescript.md`, `frontend/svelte.md` |
| Solid UI | `principles.md`, `languages/typescript.md`, `frontend/solid.md` |
| Architecture / layout decisions | `principles.md` first, then the language file |

Do not load all files at once; each language file is self-contained on top of
`principles.md`. See `templates/CLAUDE.md.example` for how a project should
reference this repo.

**Humans** — read `principles.md` end to end once; treat the language files as
lookup references. Each file covers, in order: project layout, composition/DI,
domain modelling, error handling, testing, and the anti-patterns AI agents most
often produce in that language.

## Philosophy (10 lines)

1. Dependencies point inward: the domain imports nothing from the edges.
2. All wiring happens in one composition root; no DI containers or locators.
3. Consumers own their interfaces (ports); adapters implement them at the edge.
4. Parse, don't validate: boundaries produce typed values or errors, once.
5. Make invalid states unrepresentable before reaching for runtime checks.
6. Expected failures are values in the return path; panics are for bugs.
7. Errors are translated at layer boundaries and handled exactly once.
8. Test through public APIs; fake only at architectural seams.
9. Derive, don't sync: UI state is computed from source data, not mirrored.
10. Abstraction must be paid for by a concrete second use or a genuine seam.

## Layout

```
principles.md            language-agnostic core (read first)
languages/go.md          Go
languages/rust.md        Rust (2024 edition)
languages/typescript.md  TypeScript (strict, ESM)
frontend/react.md        React
frontend/svelte.md       Svelte 5 (runes)
frontend/solid.md        Solid
templates/CLAUDE.md.example  how a project references this repo
```
