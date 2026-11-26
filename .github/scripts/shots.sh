#!/bin/bash
# Commits files to the orphan shots branch in one commit: shots.sh <list> <commit message>
# <list> holds one "<local file><tab><path on shots>" line per file. Prints "<local file><tab><commit sha>" for each
# file in the commit; the sha pins its URL: https://github.com/$GH_REPO/blob/<sha>/<path>?raw=true. A file whose blob
# could not be made is left out of the commit and printed with -. Fails when the commit could not be made.
# The commit goes on top of the branch's tip through the Git Data API, and is made again on a newer tip when another
# run moved the branch first.
# Env: GH_TOKEN, GH_REPO, OUT, SHOTS_BRANCH (default shots), SHOTS_DEADLINE (epoch seconds after which GitHub errors
# other than conflicts are no longer retried), SHOTS_JOBS (blobs made at a time, default 8). DRY_RUN=1 prints DRY-RUN
# for each file instead of committing.
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
OUT=${OUT:-${RUNNER_TEMP:-${TMPDIR:-/tmp}}/shots}
branch=${SHOTS_BRANCH:-shots}
mkdir -p "$OUT"

api() {  # out file, gh api args... -> 0 done, 1 failed, 2 conflict (HTTP 409 or 422)
  local out=$1 err=$1.err attempt delay delays=(2 4 8 16 30)
  shift
  for attempt in 1 2 3 4 5 6; do
    gh api "$@" > "$out" 2> "$err" && return 0
    cat "$err" >&2
    if grep -qE 'HTTP (409|422)' "$err"; then
      return 2
    elif grep -qE 'HTTP 4[0-9]{2}' "$err" && ! grep -qiE 'HTTP 429|rate limit' "$err"; then
      echo "$2 failed with $(grep -oE 'HTTP 4[0-9]{2}' "$err" | head -n 1), so not retried" >&2
      return 1
    elif [[ -n ${SHOTS_DEADLINE:-} ]] && (( $(date +%s) >= SHOTS_DEADLINE )); then
      echo "this run's time for retrying GitHub errors is used up, so $2 is not retried" >&2
      return 1
    fi
    if (( attempt < 6 )); then
      delay=${delays[attempt-1]}
      sleep $(( delay + RANDOM % (delay / 2 + 1) ))
    fi
  done
  return 1
}

blob() {  # local file, work file -> prints the blob's sha
  local file=$1 work=$2 sha
  [[ -s $file ]] || { echo "::error::$file is missing or empty" >&2; return 1; }
  jq -n --rawfile c <(base64 -w0 "$file") '{content: $c, encoding: "base64"}' > "$work.json"
  api "$work.out" "repos/{owner}/{repo}/git/blobs" -X POST --input "$work.json" --jq .sha || return 1
  sha=$(<"$work.out")
  [[ $sha == "$(git hash-object --no-filters "$file")" ]] || { echo "::error::the blob of $file came back as '$sha'" >&2; return 1; }
  echo "$sha"
}

if [[ ${1:-} == --blob ]]; then
  IFS=$'\t' read -r i file <<< "$2"
  if sha=$(blob "$file" "$OUT/blob-$i"); then printf '%s\t%s\n' "$i" "$sha"; else printf '%s\t-\n' "$i"; fi
  exit 0
fi

list=${1:?list of files} message=${2:?commit message}
if [[ ${DRY_RUN:-0} == 1 ]]; then
  while IFS=$'\t' read -r file path; do
    echo "would upload $file to $branch:$path" >&2
    printf '%s\tDRY-RUN\n' "$file"
  done < "$list"
  exit 0
fi

rm -f "$OUT"/blob-*
awk -F'\t' '{ printf "%d\t%s\n", NR, $1 }' "$list" \
  | OUT=$OUT xargs -d '\n' -P "${SHOTS_JOBS:-8}" -n 1 "$HERE/shots.sh" --blob \
  | sort -n > "$OUT/blobs.tsv"
awk -F'\t' 'NR == FNR { sha[$1] = $2; next } { print $1 "\t" $2 "\t" (FNR in sha ? sha[FNR] : "-") }' "$OUT/blobs.tsv" "$list" > "$OUT/files.tsv"
jq -R -s 'split("\n") | map(select(length > 0) | split("\t") | select(.[2] != "-") | {path: .[1], mode: "100644", type: "blob", sha: .[2]})' \
  "$OUT/files.tsv" > "$OUT/entries.json"
lost=$(awk -F'\t' '$3 == "-"' "$OUT/files.tsv" | wc -l)
(( lost == 0 )) || echo "::error::$lost of $(wc -l < "$list") file(s) could not be uploaded, so they are left out" >&2
if [[ $(jq length "$OUT/entries.json") == 0 ]]; then
  echo "::error::no file could be uploaded, so no commit was made" >&2
  exit 1
fi

for attempt in 1 2 3 4 5 6 7 8; do
  api "$OUT/tip" "repos/{owner}/{repo}/git/ref/heads/$branch" --jq .object.sha || exit 1
  tip=$(<"$OUT/tip")
  api "$OUT/base" "repos/{owner}/{repo}/git/commits/$tip" --jq .tree.sha || exit 1
  jq -n --arg b "$(<"$OUT/base")" --slurpfile t "$OUT/entries.json" '{base_tree: $b, tree: $t[0]}' > "$OUT/tree.json"
  api "$OUT/tree" "repos/{owner}/{repo}/git/trees" -X POST --input "$OUT/tree.json" --jq .sha || exit 1
  jq -n --arg m "$message" --arg t "$(<"$OUT/tree")" --arg p "$tip" '{message: $m, tree: $t, parents: [$p]}' > "$OUT/commit.json"
  api "$OUT/commit" "repos/{owner}/{repo}/git/commits" -X POST --input "$OUT/commit.json" --jq .sha || exit 1
  sha=$(<"$OUT/commit")
  [[ $sha =~ ^[0-9a-f]{40}$ ]] || { echo "::error::the commit came back as '$sha'" >&2; exit 1; }
  jq -n --arg s "$sha" '{sha: $s, force: false}' > "$OUT/ref.json"
  if api "$OUT/ref" "repos/{owner}/{repo}/git/refs/heads/$branch" -X PATCH --input "$OUT/ref.json" --jq .object.sha; then
    status=0
  else
    status=$?
  fi
  if (( status != 0 )) && api "$OUT/now" "repos/{owner}/{repo}/git/ref/heads/$branch" --jq .object.sha && [[ $(<"$OUT/now") == "$sha" ]]; then
    echo "$branch already points at ${sha::12}; the failed update landed" >&2
    status=0
  fi
  if (( status == 0 )); then
    echo "committed $(jq length "$OUT/entries.json") file(s) to $branch in ${sha::12}" >&2
    awk -F'\t' -v s="$sha" '{ print $1 "\t" ($3 == "-" ? "-" : s) }' "$OUT/files.tsv"
    exit "$(( lost > 0 ))"
  fi
  (( status == 2 )) || exit 1
  echo "$branch moved while committing (attempt $attempt), so the commit is made again on its new tip" >&2
  sleep $(( 1 + RANDOM % 4 ))
done
echo "::error::$branch kept moving; the commit was not made after $attempt attempts" >&2
exit 1
