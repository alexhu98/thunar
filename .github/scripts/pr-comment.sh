#!/bin/bash
# The four PR comments CI keeps, each starting with its marker <!-- pr-proof:NAME -->: pr-comment.sh ids | get NAME | put NAME FILE
#   ids           prints "NAME ID" for each of the four that exists
#   get NAME      prints that comment's body (nothing if it doesn't exist yet)
#   put NAME FILE makes sure all four exist, creating the missing ones as placeholders in the order summary, review,
#                 verify, explainer, then replaces NAME's body with its marker and FILE.
# A name's comment is its oldest comment by github-actions[bot] with that marker. When two jobs create the comments at
# once, every comment of a name is created after a comment of the name before it exists, so the oldest of each name are
# still in order; the newer duplicates are deleted.
# Env: PR (number), GH_REPO, OUT. DRY_RUN=1 prints the new comment instead of writing it.
set -euo pipefail

OUT=${OUT:-${RUNNER_TEMP:-${TMPDIR:-/tmp}}/pr-comment}
NAMES=(summary review verify explainer)
mkdir -p "$OUT"

list() {  # -> "ID NAME" for every marked comment by the bot, oldest first
  [[ -n ${PR:-} ]] || return 0
  gh api --paginate "repos/{owner}/{repo}/issues/$PR/comments" --jq '.[]
    | select(.user.login == "github-actions[bot]" and (.body | test("^<!-- pr-proof:[a-z]+ -->")))
    | "\(.id) \(.body | capture("^<!-- pr-proof:(?<n>[a-z]+) -->").n)"' | sort -n
}

ids() {
  list | awk '!seen[$2]++ {print $2, $1}'
}

id_of() {
  list | awk -v n="$1" '$2 == n {print $1; exit}'
}

get() {
  local id
  id=$(id_of "${1:?name}")
  [[ -z $id ]] || gh api "repos/{owner}/{repo}/issues/comments/$id" --jq .body
}

placeholder() {
  local title
  case $1 in
    summary) title='PR proof: ⏳ running' ;;
    review) title='Code review' ;;
    verify) title='Verify' ;;
    explainer) title='Explainer' ;;
  esac
  printf '<!-- pr-proof:%s -->\n### %s\n\nNot run yet for this PR.\n' "$1" "$title"
}

ensure() {
  local name created=0 id
  list > "$OUT/list"
  for name in "${NAMES[@]}"; do
    awk -v n="$name" '$2 == n {f = 1} END {exit !f}' "$OUT/list" && continue
    placeholder "$name" > "$OUT/placeholder.md"
    gh api "repos/{owner}/{repo}/issues/$PR/comments" -F body=@"$OUT/placeholder.md" --jq '"created the \(.body | capture("pr-proof:(?<n>[a-z]+)").n) comment \(.id)"'
    created=1
  done
  (( created )) && { sleep 3; list > "$OUT/list"; }
  for id in $(awk 'seen[$2]++ {print $1}' "$OUT/list"); do
    gh api -X DELETE "repos/{owner}/{repo}/issues/comments/$id" && echo "deleted the duplicate comment $id" \
      || echo "::warning::could not delete the duplicate comment $id" >&2
  done
}

put() {
  local name=${1:?name} file=${2:?file} id
  [[ " ${NAMES[*]} " == *" $name "* ]] || { echo "unknown comment $name; one of ${NAMES[*]}" >&2; exit 2; }
  { printf '<!-- pr-proof:%s -->\n' "$name"; cat "$file"; } > "$OUT/comment.md"
  if [[ ${DRY_RUN:-0} == 1 ]]; then
    echo "would write the $name comment on PR #${PR:-?}:"
    sed 's/^/  | /' "$OUT/comment.md"
    return
  fi
  [[ -n ${PR:-} ]] || { echo "put needs PR" >&2; exit 1; }
  ensure
  id=$(id_of "$name")
  [[ -n $id ]] || { echo "::error::the $name comment is missing after creating it" >&2; exit 1; }
  gh api -X PATCH "repos/{owner}/{repo}/issues/comments/$id" -F body=@"$OUT/comment.md" --jq '"updated \(.html_url)"'
}

case ${1:-} in
  ids) ids ;;
  get) shift; get "$@" ;;
  put) shift; put "$@" ;;
  *) echo "usage: $0 ids | get <name> | put <name> <file>" >&2; exit 2 ;;
esac
