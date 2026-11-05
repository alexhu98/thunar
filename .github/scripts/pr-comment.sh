#!/bin/bash
# Reads and writes one section of the PR comment marked <!-- pr-proof -->: pr-comment.sh get | put <name> <file>
#   get           prints the comment's body (nothing if there is no such comment yet)
#   put NAME FILE puts FILE between <!-- NAME:start --> and <!-- NAME:end -->, appending it if the comment has no such
#                 section and creating the comment if there is none. The other sections are kept. After writing it
#                 re-reads the comment and writes again until its own section is there.
# Env: PR (number), GH_REPO, OUT. DRY_RUN=1 prints the new comment instead of writing it.
set -euo pipefail

OUT=${OUT:-${RUNNER_TEMP:-${TMPDIR:-/tmp}}/pr-comment}
MARK='<!-- pr-proof -->'
mkdir -p "$OUT"

comment_id() {
  [[ -n ${PR:-} ]] || return 0
  gh api --paginate "repos/{owner}/{repo}/issues/$PR/comments" \
    --jq ".[] | select(.user.login == \"github-actions[bot]\" and (.body | startswith(\"$MARK\"))) | .id" | sed -n 1p
}

get() {
  local id
  id=$(comment_id)
  [[ -z $id ]] || gh api "repos/{owner}/{repo}/issues/comments/$id" --jq .body
}

merged() {  # old body file, name, section file -> new body
  python3 - "$@" <<'EOF'
import re, sys
old, name, new, mark = open(sys.argv[1]).read().strip('\n'), sys.argv[2], open(sys.argv[3]).read().strip('\n'), sys.argv[4]
start, end = f'<!-- {name}:start -->', f'<!-- {name}:end -->'
if not new.startswith(start) or not new.endswith(end):
    sys.exit(f'section must start with {start} and end with {end}')
if not old:
    old = mark
pat = re.compile('^' + re.escape(start) + '.*?^' + re.escape(end), re.S | re.M)
print(pat.sub(lambda _: new, old, count=1) if pat.search(old) else old + '\n\n' + new)
EOF
}

put() {
  local name=${1:?name} file=${2:?file} id attempt created=
  [[ -n ${PR:-} || ${DRY_RUN:-0} == 1 ]] || { echo "put needs PR" >&2; exit 1; }
  for attempt in 1 2 3 4; do
    id=$(comment_id)
    if [[ -n $id ]]; then gh api "repos/{owner}/{repo}/issues/comments/$id" --jq .body > "$OUT/old.md"; else : > "$OUT/old.md"; fi
    merged "$OUT/old.md" "$name" "$file" "$MARK" > "$OUT/comment.md"
    if [[ ${DRY_RUN:-0} == 1 ]]; then
      if [[ -n $id ]]; then echo "would update comment $id:"; else echo "would create a comment on PR #${PR:-?}:"; fi
      sed 's/^/  | /' "$OUT/comment.md"
      return
    elif [[ -n $id ]]; then
      gh api -X PATCH "repos/{owner}/{repo}/issues/comments/$id" -F body=@"$OUT/comment.md" --jq '"updated \(.html_url)"'
    else
      created=$(gh api "repos/{owner}/{repo}/issues/$PR/comments" -F body=@"$OUT/comment.md" --jq .id)
      echo "created comment $created"
    fi
    sleep $((attempt * 5))
    if [[ -n $created ]] && id=$(comment_id) && [[ -n $id && $id != "$created" ]]; then
      gh api -X DELETE "repos/{owner}/{repo}/issues/comments/$created" \
        || echo "::warning::could not delete the duplicate comment $created" >&2
    fi
    created=
    get > "$OUT/now.md"
    if python3 - "$OUT/now.md" "$file" <<'EOF'
import sys
now, new = (open(p).read().strip('\n') for p in sys.argv[1:])
sys.exit(0 if new in now else 1)
EOF
    then
      return
    fi
    echo "the $name section was overwritten by another job; writing it again (attempt $attempt)" >&2
  done
  echo "::error::could not keep the $name section in the PR comment" >&2
  exit 1
}

case ${1:-} in
  get) get ;;
  put) shift; put "$@" ;;
  *) echo "usage: $0 get | put <name> <file>" >&2; exit 2 ;;
esac
