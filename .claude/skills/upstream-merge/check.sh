#!/bin/bash
# Prints the newest upstream Thunar release tag that REF (default origin/main) doesn't have yet:
#   new thunar-4.20.11 (main has 4.20.10)
#   none (main has 4.20.10, newest upstream thunar-4.20.10)
# Only tags in REF's own series (thunar-<major>.<minor>.*) count. A newer stable (even minor) series is
# reported, never merged; odd-minor development tags are ignored.
# Exits 0 for "new" and "none", non-zero when upstream or REF can't be read.
set -euo pipefail

UPSTREAM=${UPSTREAM:-https://gitlab.xfce.org/xfce/thunar.git}
ref=${1:-origin/main}

have=$(git show "$ref:configure.ac" | sed -n 's/^XDT_VERSION_INIT(\[\([0-9.]*\)\].*/\1/p')
[[ $have =~ ^([0-9]+\.[0-9]+)\.[0-9]+$ ]] || { echo "check: no XDT_VERSION_INIT in $ref:configure.ac" >&2; exit 1; }
series=${BASH_REMATCH[1]}

tags=$(git ls-remote --tags --refs "$UPSTREAM" 'thunar-*' | sed -n 's|.*refs/tags/\(thunar-[0-9][0-9.]*\)$|\1|p' | sort -V)
[[ -n $tags ]] || { echo "check: no thunar-* tags at $UPSTREAM" >&2; exit 1; }

newest=$(grep -E "^thunar-${series//./\\.}\.[0-9]+$" <<<"$tags" | tail -1 || true)
other=$(grep -E '^thunar-[0-9]+\.[0-9]*[02468]\.[0-9]+$' <<<"$tags" | tail -1 || true)
note=""
[[ -n $other && $other != "$newest" && $(printf '%s\n' "thunar-$have" "$other" | sort -V | tail -1) == "$other" ]] &&
  note="; upstream also has $other, a newer stable series, not merged automatically"

if [[ -n $newest && $(printf '%s\n' "thunar-$have" "$newest" | sort -V | tail -1) != "thunar-$have" ]]; then
  echo "new $newest (${ref#origin/} has $have$note)"
else
  echo "none (${ref#origin/} has $have, newest upstream ${newest:-none in $series}$note)"
fi
