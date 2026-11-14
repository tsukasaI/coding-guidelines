# Tooling

Specializes `principles.md` for lint/format/pre-commit tooling. Load when
setting up or auditing a project's toolchain, alongside the language file(s)
for the project's stack.

## Pre-commit mechanism (mandatory)

- `lefthook` is the mandated pre-commit orchestrator: a Go binary, no Node
  dependency, parallel job execution, and native glob/path scoping for
  polyglot and monorepo layouts. One `lefthook.yaml` at the repo root defines
  every hook.
- `lefthook` MUST NOT be replaced by `husky`+`lint-staged` (Node-only,
  sequential execution, awkward in polyglot repos) or the Python
  `pre-commit` framework (broad ecosystem, but adds a Python dependency to
  every contributor's machine) without a recorded exception in the
  project's CLAUDE.md.
- `git commit --no-verify` and lefthook's own bypasses (`LEFTHOOK=0`, which
  disables all hooks, and `LEFTHOOK_EXCLUDE`, which skips named ones) MUST
  NOT be used except as a documented emergency, and that exception is
  human-only: AI agents NEVER use it. When a human invokes it, the bypass
  and a follow-up ticket to fix the underlying finding are recorded in the
  commit message.
- Every hook fails the commit on any warning, not only on errors — see
  "Maximal strictness stance" below.

Ref: Lefthook (https://lefthook.dev/), `parallel` configuration
(https://lefthook.dev/configuration/parallel) and `root`
(https://lefthook.dev/configuration/root/); the `LEFTHOOK` environment
variable (https://lefthook.dev/usage/envs/LEFTHOOK/; `LEFTHOOK`,
`LEFTHOOK_EXCLUDE`).

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
  `[[allowlists]]` entry for known non-secrets (test fixtures, documented example
  keys) — NEVER for a real leaked credential (rotate it instead).
- Test paths are scanned like any other path: the template allowlists no
  directories or file globs. A dummy value in a test is allowlisted by that
  specific value (`regexes` / `stopwords`, see the commented example in
  `templates/gitleaks.toml.example`), so a real credential pasted into a test
  file is still caught.
- Footnote, not a reason to switch today: gitleaks has a drop-in successor,
  Betterleaks (see "Tool status"). Revisit periodically; drop-in
  compatibility means switching later costs little.

Ref: gitleaks (https://github.com/gitleaks/gitleaks; CLI subcommands, config
schema).

## Lint and format by language

| Language | Format | Lint | Extra |
|---|---|---|---|
| Go | gofumpt | golangci-lint v2 (explicit `linters.enable` list) + staticcheck | — |
| Rust | rustfmt (Google Rust Style Guide settings) | clippy (default groups → deny, cherry-picked pedantic/nursery via `[lints.clippy]`) | cargo-deny, cargo-audit |
| TypeScript | oxfmt | oxlint (`templates/oxlintrc.json.example`) + tsgolint (type-aware) | Biome — fallback only |
| React | oxfmt | as TypeScript, with native react/react-hooks rules (`templates/oxlintrc.react.json.example`) | |
| Svelte | oxfmt (`.oxfmtrc.json`, `svelte: true` + install `svelte` pkg) | oxlint (script blocks only) + eslint-plugin-svelte (template-syntax gap) | |
| Solid | oxfmt | oxlint + eslint-plugin-solid (no native oxlint plugin yet) | |

Why oxlint/oxfmt over `typescript-eslint`+Prettier or Biome: `tsgolint`
(oxlint's type-aware engine) is a separate Go binary built on
`typescript-go` — TS7's own "Corsa" engine, not the old tsc programmatic
API — so it works natively with a TS7 baseline instead of forcing the 6.x
carve-out `typescript-eslint` would need (see "TypeScript version vs.
TS-API tools" below). Use `strict-type-checked` + `stylistic-type-checked`
as the reference severity bar for "maximal strictness". The oxlint
ESLint-plugin compatibility layer is unproven: treat it as not
load-bearing. Biome has its own type-aware inference and framework
lint domains (see "Tool status"), so it is the fallback if oxlint's
plugin layer proves unstable for a project — not a co-equal default.
Maturity, coverage numbers, and dates are in "Tool status"; re-check them on
version bumps, same as the config-schema caveat in the oxlint template.

## Tool status (as of: per row)

The single home for dated tool-status facts. Other files point here; update
the row and its date when the fact changes.

| Tool | Status | As of |
|---|---|---|
| gitleaks | Core binary is MIT OSS (only the `gitleaks-action` wrapper became source-available in v2.0.0, irrelevant when the binary is invoked directly). gitleaks itself is feature-complete and receives security patches only; its successor is **Betterleaks** (source: gitleaks README, https://github.com/gitleaks/gitleaks). | 2026-11 |
| gitleaks `detect`/`protect` | Deprecated (hidden from `--help`, still functional) in favor of `git`/`dir`/`stdin` | v8.19.0 |
| oxlint JS-plugin layer (ESLint v9+ plugin API) | Alpha; existing plugins "should mostly work"; the `import` plugin (`import/no-cycle`) stays behind it | 2026-03 |
| oxlint type-aware linting (tsgolint) | Stable, announced 2026-07-22 (https://oxc.rs/blog/2026-07-22-type-aware-linting-stable) | 2026-11 |
| oxfmt | Beta since 2026-02-24; still 0.x (`oxfmt_v0.78.0`, 2026-11-09) (https://github.com/oxc-project/oxc/releases) | 2026-11 |
| tsgolint | Covers 59/61 of `typescript-eslint`'s type-aware rules (tsgolint README) | 2026-11 |
| oxc `.svelte` template linting | Not shipped: only `<script>` blocks are linted (https://oxc.rs/compatibility). The oxlint JS-plugins alpha post says limited support for frameworks' custom file formats is "coming later this year" (https://oxc.rs/blog/2026-03-11-oxlint-js-plugins-alpha); no date for template linting. Formatting `.svelte` is separate (oxfmt, "Framework gaps") | 2026-11 |
| pgtyped | Last npm release `@pgtyped/cli` 2.4.3 (2025-03-15; https://registry.npmjs.org/@pgtyped/cli). Check upstream activity before adopting in a new project | 2026-11 |
| rustfmt `hex_literal_case` | Stabilized per upstream changelog, but stable rustfmt 1.10.0 still warns `unstable features are only available in nightly channel`; omit `rustfmt.toml` while it warns | rustfmt 1.10.0 (2026-11-12) |
| gitleaks version pinning | lefthook runs the `gitleaks` binary found on `PATH` and has no option to install or pin tool binaries (https://lefthook.dev/configuration/); pin the version through the install method (a version-pinning tool such as mise or aqua, a pinned release binary, or a pinned Docker image tag) | 2026-11 |
| oxlint Solid plugin | No native plugin (oxc `crates/oxc_linter/src/rules` has no `solid` directory); the upstream request oxc-project/oxc#13894 was closed on 2025-11-21. Keep `eslint-plugin-solid` running through ESLint. | 2026-11 |
| TypeScript 7 | Native compiler, GA July 2026; `latest` is 7.0.2; 7.0 has no stable programmatic API (planned for 7.1, in beta since 2026-10-20); typescript-eslint supports `<6.1.0` | 2026-11 |
| Biome | Own type-aware inference; has react-hooks-equivalent rules (`useExhaustiveDependencies`, `useHookAtTopLevel`: https://biomejs.dev/linter/rules/use-exhaustive-dependencies/) and Solid and Svelte lint domains (https://biomejs.dev/linter/domains/); Svelte language support is labelled experimental | 2026-11 |
| google/wire | Archived, unmaintained | 2025-08 |
| clippy `allow-*-in-tests` keys | Cover in-crate `#[cfg(test)]` code and `#[test]` fns incl. in `tests/`; not non-test helpers in `tests/`, `examples/`, `benches/` (rust-clippy#13981). Re-check after rust-clippy#16786 reaches stable | clippy 0.1.93 |

### TypeScript version vs. TS-API tools

Tools that consume the TypeScript programmatic API (`typescript-eslint`,
`svelte-check`, Svelte/Vue/Astro/MDX integrations, language-service plugins)
need TS 6.x until 7.1 ships a stable API. Svelte and Solid projects depend on
that API through ESLint (`templates/eslint.*.config.example`) and therefore
MUST stay on TS 6.x until then; React and backend TypeScript projects lint
with oxlint + tsgolint and use TS 7.

Type-aware oxlint (`oxlint --type-aware`, via tsgolint) requires TS 7.0+
(https://oxc.rs/docs/guide/usage/linter/type-aware.html), so a TS 6.x project
cannot rely on it. There, type errors come from `tsc --noEmit` or
`svelte-check` (a separate lefthook job, see
`templates/lefthook.yaml.example`), and type-aware lint rules such as
`no-floating-promises` must come from `typescript-eslint` in the project's
ESLint config. The Svelte and Solid ESLint templates do not yet enable such
rules (Svelte extends `ts.configs.recommended` with `projectService`; Solid
sets only the parser), so a TS 6.x project that wants them adds a
`typescript-eslint` type-checked config itself.

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
  `*-layout-ban` jobs in `templates/lefthook.yaml.example`.

## Maximal strictness stance

- Every language's lint/format check is a zero-warnings gate in the
  pre-commit hook: a warning fails the commit exactly like an error. This
  is the mandatory floor.
- If a project also runs CI, CI SHOULD apply the same zero-warnings gate —
  but this repo does not mandate that a project have CI at all (a local
  pre-commit hook is bypassable only by the documented human-only emergency
  exception above, and CI is a separate, not-required, backstop).
- Checks that are "CI only" in these guides (codegen drift check and spec
  lint in `patterns/codegen.md`, `cargo deny` / `cargo audit` in
  `languages/rust.md`) are too slow or tool-heavy for pre-commit, not
  optional. A project without CI MUST run them from a lefthook `pre-push`
  job instead (commented examples in `templates/lefthook.yaml.example`).
- Deliberate exceptions to the zero-warnings gate, both by decision:
  - `gofumpt` auto-fixes (`-w` + `stage_fixed`) instead of failing: its
    rewrite is deterministic and semantics-free, so auto-fixing loses
    nothing and saves a round trip.
  - `cargo-deny` `bans.multiple-versions = "warn"`
    (`templates/deny.toml.example`): duplicate transitive versions are often
    unfixable by the project itself, so they warn instead of blocking.
- Concrete flag lists ("what maximal strictness means") live in each
  language file's own `## Tooling` section — not duplicated here.

## Framework gaps (Svelte / Solid)

- **Lint**: oxlint has no template-syntax linting for `.svelte` files yet
  (only `<script>` blocks are covered), and Solid has no built-in oxlint
  plugin (status: "Tool status"). Keep `eslint-plugin-svelte` /
  `eslint-plugin-solid` running — via oxlint's JS-plugin layer, or as a
  plain ESLint fallback step (`templates/eslint.*.config.example`) — until
  native support ships. That ESLint step ties these projects to TS 6.x (see
  "TypeScript version vs. TS-API tools").
- **Format**: this is NOT a Svelte gap. `oxfmt` bundles
  `prettier-plugin-svelte` and formats `.svelte` files given `svelte: true`
  in `.oxfmtrc.json`; the only setup requirement is installing the
  `svelte` package yourself (oxfmt doesn't auto-install it). Solid is plain
  TSX and was never a gap either.

## Anti-patterns AI agents produce around tooling

1. **Reaching for `--no-verify`/`LEFTHOOK=0`/`LEFTHOOK_EXCLUDE`** the moment a hook fails, instead
   of fixing the finding. The bypass is a human-only emergency exception
   with a recorded follow-up; an agent NEVER uses it, and "the linter is
   being annoying" is not an emergency.
2. **Blanket-enabling `clippy::pedantic`/`clippy::nursery`** (or an
   equivalent "turn everything on" lint group) instead of cherry-picking —
   floods the diff with unrelated warnings and buries the ones that matter.
   Exception, by decision: the TypeScript template enables oxlint's
   `pedantic`, `perf` and `style` categories as a whole
   (`templates/oxlintrc.json.example`). The template keeps the categories at
   `error` and turns off, rule by rule with a reason, those that reject code
   the guides present as Good; a further noisy rule gets the same treatment,
   the category stays. The React template does not enable `react-perf`: its
   rules would demand manual memoization the React Compiler makes unnecessary.
3. **Allowlisting a real leaked secret** in `.gitleaks.toml` instead of
   rotating the credential. An allowlist entry is for known non-secrets,
   NEVER for "this one is fine because it's already committed."
4. **Unpinned lint-tool versions**: CI (or a teammate's machine) resolves a
   newer linter release mid-project and the diff fills with unrelated
   reformatting/rule-drift noise. Pin, and upgrade as a deliberate change —
   the same discipline `patterns/codegen.md` requires for generators.
5. **Linting or formatting generated/vendored files**: they were never
   meant to pass hand-written-code lint rules. Exclude them per
   `patterns/codegen.md`'s "mark generated, exclude from lint" rule instead
   of adding per-file suppressions.

Ref: golangci-lint configuration, v2 configuration model
(https://golangci-lint.run/docs/configuration/); Clippy lints, lint groups
(https://doc.rust-lang.org/clippy/lints.html); RustSec
(https://rustsec.org/); cargo-deny
(https://github.com/EmbarkStudios/cargo-deny); Oxlint
(https://oxc.rs/docs/guide/usage/linter), Oxfmt
(https://oxc.rs/docs/guide/usage/formatter) and compatibility
(https://oxc.rs/compatibility); Biome (https://biomejs.dev/).
