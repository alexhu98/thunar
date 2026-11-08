#!/bin/bash
set -euo pipefail

gh api --paginate 'repos/{owner}/{repo}/git/matching-refs/tags/v' --jq '.[] | "\(.ref) \(.object.sha)"' \
  | sed -n 's|^refs/tags/\(.*+local\([0-9][0-9]*\)\) \([0-9a-f]*\)$|\2 \1 \3|p' | sort -n | tail -1 | cut -d' ' -f2-
