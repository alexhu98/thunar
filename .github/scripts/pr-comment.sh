#!/bin/bash
# The four PR comments CI keeps, each starting with its marker <!-- pr-proof:NAME -->: pr-comment.sh legacy get|delete | get NAME | put NAME FILE
#   legacy get    prints the body of the single comment CI wrote before there were four (<!-- pr-proof -->)
#   legacy delete deletes it
#   get NAME      prints that comment's body (nothing if it doesn't exist yet)
#   put NAME FILE makes sure all four exist, creating the missing ones as placeholders in the order summary, review,
#                 verify, explainer, then replaces NAME's body with its marker and FILE, unless it already is that, so
#                 an unchanged comment isn't edited and doesn't notify anyone.
# A name's comment is its oldest comment by github-actions[bot] with that marker; the newer duplicates are deleted.
# Env: PR (number), GH_REPO, OUT. DRY_RUN=1 prints the new comment instead of writing it.
set -euo pipefail

OUT=${OUT:-${RUNNER_TEMP:-${TMPDIR:-/tmp}}/pr-comment}
NAMES=(summary review verify explainer)
mkdir -p "$OUT"

api() {
  local out attempt
  for attempt in 1 2 3; do
    if out=$(gh api "$@"); then
      [[ -z $out ]] || printf '%s\n' "$out"
      return 0
    fi
    (( attempt == 3 )) || { echo "gh api ${1:-} failed (attempt $attempt)" >&2; sleep $((attempt * 5)); }
  done
  return 1
}

list() {  # -> "ID NAME BODY" (BODY in base64) for every marked comment by the bot, oldest first
  [[ -n ${PR:-} ]] || return 0
  api --paginate "repos/{owner}/{repo}/issues/$PR/comments" --jq '.[]
    | select(.user.login == "github-actions[bot]" and (.body | test("^<!-- pr-proof:[a-z]+ -->")))
    | "\(.id) \(.body | capture("^<!-- pr-proof:(?<n>[a-z]+) -->").n) \(.body | @base64)"' | sort -n
}

legacy() {
  local id
  [[ -n ${PR:-} ]] || return 0
  id=$(api --paginate "repos/{owner}/{repo}/issues/$PR/comments" \
    --jq '.[] | select(.user.login == "github-actions[bot]" and (.body | startswith("<!-- pr-proof -->"))) | .id' | sed -n 1p)
  [[ -n $id ]] || return 0
  case $1 in
    get) api "repos/{owner}/{repo}/issues/comments/$id" --jq .body ;;
    delete) [[ ${DRY_RUN:-0} == 1 ]] && echo "would delete the old comment $id" || api -X DELETE "repos/{owner}/{repo}/issues/comments/$id" ;;
  esac
}

get() {
  local body
  body=$(list | awk -v n="${1:?name}" '$2 == n {print $3; exit}')
  [[ -z $body ]] || { printf '%s' "$body" | base64 -d; echo; }
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
    api "repos/{owner}/{repo}/issues/$PR/comments" -F body=@"$OUT/placeholder.md" --jq '"created the \(.body | capture("pr-proof:(?<n>[a-z]+)").n) comment \(.id)"'
    created=1
  done
  (( created )) && { sleep 3; list > "$OUT/list"; }
  for id in $(awk 'seen[$2]++ {print $1}' "$OUT/list"); do
    api -X DELETE "repos/{owner}/{repo}/issues/comments/$id" && echo "deleted the duplicate comment $id" \
      || echo "::warning::could not delete the duplicate comment $id" >&2
  done
}

put() {
  local name=${1:?name} file=${2:?file} id body
  [[ " ${NAMES[*]} " == *" $name "* ]] || { echo "unknown comment $name; one of ${NAMES[*]}" >&2; exit 2; }
  { printf '<!-- pr-proof:%s -->\n' "$name"; cat "$file"; } > "$OUT/comment.md"
  if [[ ${DRY_RUN:-0} == 1 ]]; then
    echo "would write the $name comment on PR #${PR:-?}:"
    sed 's/^/  | /' "$OUT/comment.md"
    return
  fi
  [[ -n ${PR:-} ]] || { echo "put needs PR" >&2; exit 1; }
  ensure
  read -r id _ body < <(awk -v n="$name" '$2 == n {print; exit}' "$OUT/list") || true
  [[ -n ${id:-} ]] || { echo "::error::the $name comment is missing after creating it" >&2; exit 1; }
  if [[ $(printf '%s' "${body:-}" | base64 -d) == "$(cat "$OUT/comment.md")" ]]; then
    echo "the $name comment is unchanged"
    return
  fi
  api -X PATCH "repos/{owner}/{repo}/issues/comments/$id" -F body=@"$OUT/comment.md" --jq '"updated \(.html_url)"'
}

case ${1:-} in
  legacy) shift; legacy "${1:?get or delete}" ;;
  get) shift; get "$@" ;;
  put) shift; put "$@" ;;
  *) echo "usage: $0 legacy get|delete | get <name> | put <name> <file>" >&2; exit 2 ;;
esac
