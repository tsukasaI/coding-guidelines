#!/usr/bin/env bash
# Check that every rule/job named in an `(enforced: ...)` tag in
# languages/*.md and frontend/*.md exists in some templates/*.example file.
# Prints the missing ones and exits 1. Needs bash, grep, perl, tr.
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
    [[ $1 == "$l" ]] && grep -qF -- '-D warnings' templates/lefthook.yml.example && return 0
  done
  return 1
}

in_templates() { grep -qE "$1" templates/*.example; }

exists() {
  local tok=$1 rule
  case $tok in
    revive.*)
      rule=${tok#revive.}
      in_templates "name: ${rule}\$|name: ${rule}[[:space:]]" ;;
    clippy::*)
      rule=${tok#clippy::}
      default_group_clippy "$rule" ||
        in_templates "^(${rule}|${rule//_/-})[[:space:]]*=" ;;
    */*)
      in_templates "\"${tok}\"" ;;
    *)
      grep -qFw -- "$tok" templates/*.example ;;
  esac
}

# shellcheck disable=SC2016  # the backticks are literal regex characters
BACKTICKED='`[^`]*`'

missing=0
checked=0
tags=0

for f in languages/*.md frontend/*.md; do
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

if ((tags == 0)); then
  echo "error: no (enforced: ...) tags found; the extraction is broken" >&2
  exit 1
fi

echo "checked ${checked} names in ${tags} tags, ${missing} missing"
((missing == 0))
