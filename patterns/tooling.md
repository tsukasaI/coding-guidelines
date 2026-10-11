# Tooling

Specializes `principles.md` for lint/format/pre-commit tooling. Load when
setting up or auditing a project's toolchain, alongside the language file(s)
for the project's stack.

## Pre-commit mechanism (mandatory)

- `lefthook` is the mandated pre-commit orchestrator: a Go binary, no Node
  dependency, parallel job execution, and native glob/path scoping for
  polyglot and monorepo layouts. One `lefthook.yml` at the repo root defines
  every hook.
- `lefthook` MUST NOT be replaced by `husky`+`lint-staged` (Node-only,
  sequential execution, awkward in polyglot repos) or the Python
  `pre-commit` framework (broad ecosystem, but adds a Python dependency to
  every contributor's machine) without a recorded exception in the
  project's CLAUDE.md.
- `git commit --no-verify` and hook-level `SKIP=` bypasses are banned except
  as a documented emergency: the bypass and a follow-up ticket to fix the
  underlying finding are recorded in the commit message.
- Every hook fails the commit on any warning, not only on errors — see
  "Maximal strictness stance" below.

Ref: lefthook.dev (parallel execution, monorepo configuration).

## Secret scanning (mandatory)

- `gitleaks` is mandatory in the pre-commit hook, invoked as `gitleaks git
  --staged --redact` — the `--staged`-diff-only mode, documented upstream
  as "good for pre-commit." Do NOT use `gitleaks detect`/`gitleaks protect`:
  both were deprecated in v8.19.0 (hidden from `--help`, still functional,
  but not the interface new setups should standardize on) in favor of the
  `git`/`dir`/`stdin` subcommands. A full-tree audit (e.g. onboarding an
  existing repo) uses `gitleaks dir . -c .gitleaks.toml`.
- Config lives in `.gitleaks.toml`: `[extend] useDefault = true` to keep
  the built-in rule set, plus project-specific custom `[[rules]]` and an
  `[allowlist]` for known non-secrets (test fixtures, documented example
  keys) — NEVER for a real leaked credential (rotate it instead).
- Footnote, not a reason to switch today: gitleaks's core binary is
  MIT-licensed OSS (only the separate `gitleaks-action` GitHub Action
  wrapper changed to a source-available license in v2.0.0 — irrelevant
  here since the binary is invoked directly, not the Action). In March
  2026 its original creator announced he no longer has full control of
  the gitleaks repo/brand and launched **Betterleaks** as a successor
  (Aikido Security-sponsored, MIT-licensed, a verified drop-in
  replacement — existing `.gitleaks.toml`, `.gitleaksignore`, and CLI
  flags carry over unmodified). gitleaks itself is now described as
  "stable, security-patches only." Revisit this footnote periodically;
  the drop-in compatibility means switching later costs little.

Ref: github.com/gitleaks/gitleaks (CLI subcommands, config schema).

## Lint and format by language

| Language | Format | Lint | Extra |
|---|---|---|---|
| Go | gofumpt | golangci-lint v2 (explicit `linters.enable` list) + staticcheck | — |
| Rust | rustfmt (defaults) | clippy (default groups → deny, cherry-picked pedantic/nursery via `[lints.clippy]`) | cargo-deny, cargo-audit |
| TypeScript / React | oxfmt | oxlint (native react/react-hooks) + tsgolint (type-aware) | Biome — fallback only |
| Svelte | oxfmt (`.oxfmtrc.json`, `svelte: true` + install `svelte` pkg) | oxlint (script blocks only) + eslint-plugin-svelte (template-syntax gap) | |
| Solid | oxfmt | oxlint + eslint-plugin-solid (no native oxlint plugin yet) | |

Why oxlint/oxfmt over `typescript-eslint`+Prettier or Biome: `tsgolint`
(oxlint's type-aware engine) is a separate Go binary built on
`typescript-go` — TS7's own "Corsa" engine, not the old tsc programmatic
API — so it works natively with a TS7 baseline instead of forcing the 6.x
carve-out `typescript-eslint` would need (see `languages/typescript.md`).
It covers 59/61 of `typescript-eslint`'s type-aware rules; use
`strict-type-checked` + `stylistic-type-checked` as the reference severity
bar. oxlint's ESLint-plugin compatibility layer (v9+ plugin API) is alpha
(March 2026) — existing plugins "should mostly work" through it, but treat
that as unproven. `oxfmt` and the type-aware lint path are themselves still
maturing through 2026 (Q3 2026 is oxc's target for full stabilization, with
some reports of memory pressure on very large monorepos) — re-check status
on version bumps, same as the config-schema caveat below. Biome has its own
type-aware inference but the same framework-coverage gaps (Svelte beta, no
Solid, no react-hooks-equivalent rules), so it is positioned as the
fallback if oxlint's plugin layer proves unstable for a project — not a
co-equal default.

## The `(enforced: ...)` convention

- When a MUST/NEVER rule in a language file has an off-the-shelf
  linter/formatter/compiler-flag equivalent, the rule keeps its prose (WHY,
  Bad/Good examples) and gets a trailing `(enforced: tool/rule-name)`
  pointer to the config that makes it mechanical. This lets an AI agent
  reading a language file also know which violations a hook will actually
  catch versus which still rely on code review.
- Some rules are architectural judgment calls with no tool (dependency
  direction, "consumer owns the port", DI-container bans). Those stay
  prose-only; don't invent a fake enforcement tag for them.
- A directory-naming ban (Go's `pkg/`, TypeScript's `src/utils/`-by-kind)
  has no linter equivalent, existing linters check import paths and
  identifiers, not directory names. Enforce these with a plain glob-scoped
  lefthook job that always fails when a matching path is staged, see the
  `*-layout-ban` jobs in `templates/lefthook.yml.example`.

## Maximal strictness stance

- Every language's lint/format check is a zero-warnings gate in the
  pre-commit hook: a warning fails the commit exactly like an error. This
  is the mandatory floor.
- If a project also runs CI, CI SHOULD apply the same zero-warnings gate —
  but this repo does not mandate that a project have CI at all (a local
  pre-commit hook is bypassable only by the documented emergency exception
  above, and CI is a separate, not-required, backstop).
- Concrete flag lists ("what maximal strictness means") live in each
  language file's own `## Tooling` section — not duplicated here.

## Framework gaps (Svelte / Solid)

- **Lint**: oxlint has no template-syntax linting for `.svelte` files yet
  (only `<script>` blocks are covered); full framework file-format support
  is on oxc's 2026 roadmap but unshipped. Solid has no built-in oxlint
  plugin (open, unresolved upstream discussion). Keep
  `eslint-plugin-svelte` / `eslint-plugin-solid` running — via oxlint's
  alpha JS-plugin layer, or as a plain ESLint fallback step — until native
  support ships.
- **Format**: this is NOT a Svelte gap. `oxfmt` bundles
  `prettier-plugin-svelte` and formats `.svelte` files given `svelte: true`
  in `.oxfmtrc.json`; the only setup requirement is installing the
  `svelte` package yourself (oxfmt doesn't auto-install it). Solid is plain
  TSX and was never a gap either.

## Anti-patterns AI agents produce around tooling

1. **Reaching for `--no-verify`/`SKIP=`** the moment a hook fails, instead
   of fixing the finding. The bypass exists for genuine emergencies with a
   recorded follow-up, not for "the linter is being annoying."
2. **Blanket-enabling `clippy::pedantic`/`clippy::nursery`** (or an
   equivalent "turn everything on" lint group) instead of cherry-picking —
   floods the diff with unrelated warnings and buries the ones that matter.
3. **Allowlisting a real leaked secret** in `.gitleaks.toml` instead of
   rotating the credential. An allowlist entry is for known non-secrets,
   never for "this one is fine because it's already committed."
4. **Unpinned lint-tool versions**: CI (or a teammate's machine) resolves a
   newer linter release mid-project and the diff fills with unrelated
   reformatting/rule-drift noise. Pin, and upgrade as a deliberate change —
   the same discipline `patterns/codegen.md` requires for generators.
5. **Linting or formatting generated/vendored files**: they were never
   meant to pass hand-written-code lint rules. Exclude them per
   `patterns/codegen.md`'s "mark generated, exclude from lint" rule instead
   of adding per-file suppressions.

Ref: golangci-lint.run (v2 configuration model); doc.rust-lang.org/clippy
(lint groups); rustsec.org; github.com/EmbarkStudios/cargo-deny; oxc.rs
(oxlint/oxfmt docs, compatibility, config reference); biomejs.dev.
