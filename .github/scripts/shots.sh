#!/bin/bash
# Commits one file to the orphan shots branch: shots.sh <local file> <path on shots> <commit message>
# Prints the commit's sha, which pins the file's URL: https://github.com/$GH_REPO/blob/<sha>/<path>?raw=true
# Env: GH_TOKEN, GH_REPO, OUT. DRY_RUN=1 prints DRY-RUN instead of committing.
set -euo pipefail

file=${1:?local file} path=${2:?path on shots} message=${3:?commit message}
OUT=${OUT:-${RUNNER_TEMP:-${TMPDIR:-/tmp}}/shots}
mkdir -p "$OUT"
body="$OUT/upload.json"
[[ -s $file ]] || { echo "::error::$file is missing or empty" >&2; exit 1; }
if [[ ${DRY_RUN:-0} == 1 ]]; then
  echo "would upload $file to shots:$path" >&2
  echo DRY-RUN
  exit 0
fi
for attempt in 1 2 3; do
  blob=$(gh api "repos/{owner}/{repo}/contents/$path?ref=shots" -H 'Accept: application/vnd.github.object' --jq .sha 2>/dev/null) || blob=
  jq -n --arg m "$message" --arg b shots --arg s "$blob" --rawfile c <(base64 -w0 "$file") \
    '{message: $m, branch: $b, content: $c} + (if $s == "" then {} else {sha: $s} end)' > "$body"
  if sha=$(gh api -X PUT "repos/{owner}/{repo}/contents/$path" --input "$body" --jq .commit.sha) && [[ $sha =~ ^[0-9a-f]{40}$ ]]; then
    echo "uploaded shots:$path in ${sha::12}" >&2
    echo "$sha"
    exit 0
  fi
  echo "upload of $path failed (attempt $attempt)" >&2
  (( attempt == 3 )) || sleep $((attempt * 2))
done
exit 1
