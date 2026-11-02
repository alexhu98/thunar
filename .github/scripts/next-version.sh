#!/bin/bash
# Prints the next package version: <upstream>-1~bpo24.04+local<N>.
# N is one above the highest +localN among existing releases and v* tags, and
# at least 2 because the hand-built +local1 is already installed on the machines.
set -euo pipefail

upstream=$(sed -n 's/^XDT_VERSION_INIT(\[\([0-9.]*\)\].*/\1/p' configure.ac)
[[ -n $upstream ]] || { echo "next-version: no XDT_VERSION_INIT in configure.ac" >&2; exit 1; }

last=$({ gh release list --limit 1000 --json tagName --jq '.[].tagName' &&
         gh api --paginate 'repos/{owner}/{repo}/git/matching-refs/tags/v' --jq '.[].ref'; } \
  | sed -n 's/.*+local\([0-9][0-9]*\)$/\1/p' | sort -n | tail -1)
n=$(( ${last:-1} + 1 ))

echo "${upstream}-1~bpo24.04+local${n}"
