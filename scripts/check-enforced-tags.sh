#!/usr/bin/env bash
# Check that every rule/job named in an `(enforced: ...)` tag in
# languages/*.md, frontend/*.md, patterns/*.md and principles.md exists in
# some templates/*.example file. Prints the missing ones and exits 1.
# Needs bash, grep, perl, tr.
#
# Names are matched literally (names are identifier-shaped, so `.` is the only
# regex metacharacter, and it is escaped). templates/CLAUDE.md.example is prose
# and is not searched. Comments in the templates are stripped before
# matching, so a name
# that only appears in a comment does not count: whole-line `#` / `//`
# comments, and trailing ` # ...` / ` // ...` comments (the marker must follow
# whitespace). Known limitation: `/* ... */` block comments are not stripped,
# and a ` #` or ` //` inside a quoted string is treated as a comment start.
#
# Tag formats handled (tags may span lines and contain nested parentheses):
#   (enforced: `typescript/no-explicit-any` in `templates/...`)
#   (enforced, partial: `errname` covers ...; `errorlint` ...)
# Only backticked tokens inside a tag are considered. Lookup by token shape:
#   revive.X          -> `name: X` in a template
#   clippy::X         -> `X = ` or clippy.toml's `x-y = ` in a template, or a
#                        default-group lint (DEFAULT_GROUP_CLIPPY)
#   plugin/rule       -> the quoted string "plugin/rule" in a template
#   anything else     -> the word (golangci linter, lefthook job name)
set -euo pipefail

cd "$(dirname "$0")/.."

# Tokens that appear inside tags but are prose, not enforceable names.
# Each entry needs a reason. Tokens that are not identifier-shaped (paths with
# `*`, regexes, expressions, anything containing spaces) are skipped
# automatically by the shape check below.
SKIP_TOKENS=(
  'as'              # the TS keyword, named in prose ("comment-on-`as`")
  'never'           # the TS type, named in prose (exhaustiveness check)
  'files:'          # YAML key of the depguard rule, not a rule name
  'internal/'       # directory convention for no-restricted-imports
  'import/no-cycle' # deliberately absent: needs the import plugin, which
                    # stays on oxlint's JS-plugin layer (tooling.md)
)

# Skip template paths named inside a tag (`templates/...`, `*.example`).
is_path() { [[ $1 == templates/* || $1 == *.example ]]; }

skipped() {
  local t
  for t in "${SKIP_TOKENS[@]}"; do [[ $1 == "$t" ]] && return 0; done
  return 1
}

# clippy default-group lints have no per-lint template entry: they are denied
# wholesale by `-D warnings` in the lefthook template's clippy job.
DEFAULT_GROUP_CLIPPY=(
  ptr_arg borrowed_box wrong_self_convention len_without_is_empty
  unnecessary_unwrap missing_safety_doc
)

default_group_clippy() {
  local l
  for l in "${DEFAULT_GROUP_CLIPPY[@]}"; do
    [[ $1 == "$l" ]] && grep -qF -- '-D warnings' <<<"$TEMPLATES" && return 0
  done
  return 1
}

# Template contents with comments removed (see the header for the limits).
TEMPLATE_FILES=()
for t in templates/*.example; do
  [[ $t == templates/CLAUDE.md.example ]] || TEMPLATE_FILES+=("$t")
done
TEMPLATES=$(perl -pe '$_ .= "\n" if eof && !/\n\z/; s{^\s*(?:\#|//).*$}{}; s{(?<=\s)(?:\#|//).*$}{}' "${TEMPLATE_FILES[@]}")

in_templates() { grep -qE -- "$1" <<<"$TEMPLATES"; }

# Names are identifier-shaped (see the shape check below): `.` is the only
# ERE metacharacter they can contain.
re_escape() { printf '%s' "${1//./[.]}"; }

exists() {
  local tok=$1 rule
  case $tok in
    revive.*)
      rule=$(re_escape "${tok#revive.}")
      in_templates "name: ${rule}([[:space:]]|\$)" ;;
    clippy::*)
      rule=${tok#clippy::}
      default_group_clippy "$rule" ||
        in_templates "^($(re_escape "$rule")|$(re_escape "${rule//_/-}"))[[:space:]]*=" ;;
    */*)
      grep -qF -- "\"${tok}\"" <<<"$TEMPLATES" ;;
    *)
      grep -qFw -- "$tok" <<<"$TEMPLATES" ;;
  esac
}

# shellcheck disable=SC2016  # the backticks are literal regex characters
BACKTICKED='`[^`]*`'

missing=0
checked=0
tags=0

for f in languages/*.md frontend/*.md patterns/*.md principles.md; do
  # Join lines so multi-line tags match, then pull out balanced (enforced...).
  while IFS= read -r tag; do
    [[ -z $tag ]] && continue
    tags=$((tags + 1))
    while IFS= read -r raw; do
      tok=${raw//\`/}
      [[ -z $tok ]] && continue
      is_path "$tok" && continue
      skipped "$tok" && continue
      [[ $tok =~ ^[A-Za-z][A-Za-z0-9_:./-]*$ ]] || continue
      checked=$((checked + 1))
      if ! exists "$tok"; then
        echo "missing: $tok (tag in $f)"
        missing=$((missing + 1))
      fi
    done < <(printf '%s\n' "$tag" | grep -o "$BACKTICKED" || true)
  # Not `grep -oP`: macOS's BSD grep has no -P, and the recursive (?1) needs PCRE.
  done < <(tr '\n' ' ' <"$f" |
    perl -ne 'print "$&\n" while /\(enforced(?:[^()]|(\((?:[^()]|(?1))*\)))*\)/g')
done

if ((tags == 0 || checked == 0)); then
  echo "error: found ${tags} (enforced: ...) tags and ${checked} names; the extraction is broken" >&2
  exit 1
fi

echo "checked ${checked} names in ${tags} tags, ${missing} missing"
((missing == 0))
