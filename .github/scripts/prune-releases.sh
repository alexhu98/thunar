#!/bin/bash
# Deletes all but the newest $KEEP releases, and their tags.
# DRY_RUN=1 only prints what would be deleted.
set -euo pipefail

KEEP=${KEEP:-10}
gh release list --limit 1000 --json tagName,createdAt \
  --jq 'sort_by(.createdAt) | reverse | .[].tagName' \
  | tail -n +$((KEEP + 1)) \
  | while read -r tag; do
      if [[ ${DRY_RUN:-0} == 1 ]]; then
        echo "would delete $tag"
      else
        echo "deleting $tag"
        gh release delete "$tag" --cleanup-tag --yes
      fi
    done
