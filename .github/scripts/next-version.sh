#!/bin/bash
# Prints the next package version: <upstream>-1~bpo24.04+local<N>.
# N is one above the highest +localN among existing releases, and at least 2
# because the hand-built +local1 is already installed on the machines.
set -euo pipefail

upstream=$(sed -n 's/^XDT_VERSION_INIT(\[\([0-9.]*\)\].*/\1/p' configure.ac)
[[ -n $upstream ]] || { echo "next-version: no XDT_VERSION_INIT in configure.ac" >&2; exit 1; }

last=$(gh release list --repo "$REPO" --limit 1000 --json tagName --jq '.[].tagName' \
  | sed -n 's/.*+local\([0-9][0-9]*\)$/\1/p' | sort -n | tail -1)
n=$(( ${last:-1} + 1 ))

echo "${upstream}-1~bpo24.04+local${n}"
