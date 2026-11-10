#!/bin/sh
# scrub-check: the safety gate for this repository.
#
# It fails if any file carries a term that would tie this generic image back to the
# private project it was extracted from, or to the purpose that project was built for.
# Run it from the repository root; it scans every tracked file. Zero hits is a pass and
# is a precondition for ever making this repository or its image public.
#
#   ./scrub-check.sh            # scan the whole working tree
#   ./scrub-check.sh <dir>      # scan a specific path
#
# Each pattern brackets its first letter, e.g. [c]orvo, so this script never contains
# the literal words it forbids (otherwise it would flag itself); the regex still matches
# the real words in any other file. Word boundaries (\b) keep short terms from matching
# inside unrelated words -- for instance the [n]orma pattern must not fire on a package
# named "charset-normalizer".
set -eu

root="${1:-.}"

pattern='\b[c]orvo\b|\b[c]orvid\b|\b[a]rtex\b|\b[n]orma\b|\b[p]entest\b|\b[a]ssessment\b|\b[c]tem\b|\b[e]gress\b|\b[j]ail\b|[a]pi-recon|0xmanhnv/[c]orvo'

echo "scrub-check: scanning '$root' for forbidden terms..."
if matches="$(grep -rniE --exclude-dir=.git --binary-files=without-match "$pattern" "$root")"; then
  echo
  echo "SCRUB GATE FAILED -- forbidden term(s) found:"
  echo "$matches"
  echo
  echo "Neutralize every line above before this repository may be published."
  exit 1
fi

echo "SCRUB GATE PASSED -- 0 forbidden terms."
