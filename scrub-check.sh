#!/bin/sh
# scrub-check: a content check for this repository.
#
# It fails if any file contains a term from a denylist. The list is not kept in the
# repository: it is read from the environment variable SCRUB_TERMS, one term per line.
# Each line is an extended regular expression (grep -E), matched case-insensitively;
# use \b for word boundaries so a short term does not match inside a longer word.
# Blank lines and lines starting with # are ignored.
#
#   SCRUB_TERMS="$(cat my-terms.txt)" ./scrub-check.sh          # scan the working tree
#   SCRUB_TERMS="$(cat my-terms.txt)" ./scrub-check.sh <dir>    # scan a specific path
#
# Without SCRUB_TERMS there is nothing to check. On a workstation the check then says
# it is skipped and passes; in CI (CI or GITHUB_ACTIONS set) it fails, so the check
# cannot be switched off without anyone noticing. In GitHub Actions the list comes from
# the repository secret SCRUB_TERMS.
#
# A hit is reported as file:line only. Neither the term nor the matching text is
# printed, so a public CI log does not show the list.
set -eu

root="${1:-.}"

terms="$(printf '%s\n' "${SCRUB_TERMS:-}" | tr -d '\r' | grep -v -e '^[[:space:]]*$' -e '^[[:space:]]*#' || true)"

if [ -z "$terms" ]; then
  if [ -n "${CI:-}" ] || [ -n "${GITHUB_ACTIONS:-}" ]; then
    echo "scrub-check: FAILED -- SCRUB_TERMS is not set, so nothing was checked." >&2
    echo "Set the repository secret SCRUB_TERMS (one term per line). Pull requests from" >&2
    echo "forks do not receive secrets: a maintainer has to run the check for those." >&2
    exit 1
  fi
  echo "scrub-check: SKIPPED -- SCRUB_TERMS is not set (see the header of this script)."
  exit 0
fi

list="$(mktemp)"
trap 'rm -f "$list"' EXIT INT TERM
printf '%s\n' "$terms" > "$list"

count="$(wc -l < "$list" | tr -d ' ')"
echo "scrub-check: scanning '$root' for $count term(s)..."

# -n with cut: keep "file:line", drop the matching text.
set +e
hits="$(grep -rniE --exclude-dir=.git --binary-files=without-match -f "$list" "$root" 2>/dev/null)"
rc=$?
set -e

if [ "$rc" -gt 1 ]; then
  echo "scrub-check: FAILED -- grep could not use the term list (is every line a valid extended regular expression?)." >&2
  exit 2
fi
if [ "$rc" -eq 0 ]; then
  echo
  echo "scrub-check: FAILED -- denylisted term(s) found at:"
  printf '%s\n' "$hits" | cut -d: -f1,2 | sort -u
  echo
  echo "Remove or reword each of these lines."
  exit 1
fi

echo "scrub-check: PASSED -- no denylisted terms."
