#!/bin/bash
# Prints "new <tag> (…)" or "none (…)": the newest upstream release in REF's series (default origin/main) that REF lacks.
set -euo pipefail

UPSTREAM=${UPSTREAM:-https://gitlab.xfce.org/xfce/thunar.git}
ref=${1:-origin/main}

newer() { [[ $(printf '%s\n' "$1" "$2" | sort -V | tail -1) == "$1" && $1 != "$2" ]]; }

have=$(git show "$ref:configure.ac" | sed -n 's/^XDT_VERSION_INIT(\[\([0-9.]*\)\].*/\1/p')
[[ $have =~ ^([0-9]+\.[0-9]+)\.[0-9]+$ ]] || { echo "check: no XDT_VERSION_INIT in $ref:configure.ac" >&2; exit 1; }
series=${BASH_REMATCH[1]}

tags=$(git ls-remote --tags --refs "$UPSTREAM" 'thunar-*' | sed -n 's|.*refs/tags/\(thunar-[0-9][0-9.]*\)$|\1|p' | sort -V)
[[ -n $tags ]] || { echo "check: no thunar-* tags at $UPSTREAM" >&2; exit 1; }

newest=$(grep -E "^thunar-${series//./\\.}\.[0-9]+$" <<<"$tags" | tail -1 || true)
stable=$(grep -E '^thunar-[0-9]+\.[0-9]*[02468]\.[0-9]+$' <<<"$tags" | tail -1 || true)
note=""
[[ -n $stable && $stable != "$newest" ]] && newer "$stable" "thunar-$have" &&
  note="; upstream also has $stable, a newer stable series, not merged automatically"

if [[ -n $newest ]] && newer "$newest" "thunar-$have"; then
  echo "new $newest (${ref#origin/} has $have$note)"
else
  echo "none (${ref#origin/} has $have, newest upstream ${newest:-none in $series}$note)"
fi
