#!/bin/bash
# Commits one file to the orphan shots branch: shots.sh <local file> <path on shots> <commit message>
# Prints the commit's sha, which pins the file's URL: https://github.com/$GH_REPO/blob/<sha>/<path>?raw=true
# Env: GH_TOKEN, GH_REPO, OUT, SHOTS_BRANCH (default shots). DRY_RUN=1 prints DRY-RUN instead of committing.
set -euo pipefail

file=${1:?local file} path=${2:?path on shots} message=${3:?commit message}
OUT=${OUT:-${RUNNER_TEMP:-${TMPDIR:-/tmp}}/shots}
mkdir -p "$OUT"
body="$OUT/upload.json" err="$OUT/upload.err"
branch=${SHOTS_BRANCH:-shots}
[[ -s $file ]] || { echo "::error::$file is missing or empty" >&2; exit 1; }
if [[ ${DRY_RUN:-0} == 1 ]]; then
  echo "would upload $file to $branch:$path" >&2
  echo DRY-RUN
  exit 0
fi
delays=(2 4 8 16 30)
attempts=6
outage="$OUT/outage"
if [[ -e $outage ]]; then
  attempts=1
  echo "an earlier upload in this run gave up on GitHub errors, so $path gets 1 attempt" >&2
fi
local_blob=$(git hash-object --no-filters "$file")
transient=0
landed() {
  local blob sha
  blob=$(gh api "repos/{owner}/{repo}/contents/$path?ref=$branch" -H 'Accept: application/vnd.github.object' --jq .sha 2>/dev/null) &&
    [[ $blob == "$local_blob" ]] &&
    sha=$(gh api "repos/{owner}/{repo}/commits?sha=$branch&path=$path&per_page=1" --jq '.[0].sha' 2>/dev/null) &&
    [[ $sha =~ ^[0-9a-f]{40}$ ]] &&
    blob=$(gh api "repos/{owner}/{repo}/contents/$path?ref=$sha" -H 'Accept: application/vnd.github.object' --jq .sha 2>/dev/null) &&
    [[ $blob == "$local_blob" ]] || return 1
  echo "$branch:$path already holds this file, in ${sha::12}; the failed upload landed" >&2
  echo "$sha"
}
for (( attempt = 1; attempt <= attempts; attempt++ )); do
  if (( transient )) && landed; then
    exit 0
  fi
  blob=$(gh api "repos/{owner}/{repo}/contents/$path?ref=$branch" -H 'Accept: application/vnd.github.object' --jq .sha 2>/dev/null) || blob=
  jq -n --arg m "$message" --arg b "$branch" --arg s "$blob" --rawfile c <(base64 -w0 "$file") \
    '{message: $m, branch: $b, content: $c} + (if $s == "" then {} else {sha: $s} end)' > "$body"
  if sha=$(gh api -X PUT "repos/{owner}/{repo}/contents/$path" --input "$body" --jq .commit.sha 2>"$err") && [[ $sha =~ ^[0-9a-f]{40}$ ]]; then
    echo "uploaded $branch:$path in ${sha::12}" >&2
    echo "$sha"
    exit 0
  fi
  cat "$err" >&2
  if grep -qE 'HTTP (409|422)' "$err"; then
    echo "upload of $path hit a conflict (attempt $attempt)" >&2
  elif grep -qE 'HTTP 4[0-9]{2}' "$err" && ! grep -qiE 'HTTP 429|rate limit' "$err"; then
    echo "upload of $path failed (attempt $attempt) with $(grep -oE 'HTTP 4[0-9]{2}' "$err" | head -n 1), so not retried" >&2
    exit 1
  else
    transient=1
    echo "upload of $path failed (attempt $attempt) with a transient error" >&2
  fi
  if (( attempt < attempts )); then
    delay=${delays[attempt-1]}
    sleep $(( delay + RANDOM % (delay / 2 + 1) ))
  fi
done
if (( transient )); then
  landed && exit 0
  touch "$outage"
fi
echo "upload of $path failed after $attempts attempt(s)" >&2
exit 1
