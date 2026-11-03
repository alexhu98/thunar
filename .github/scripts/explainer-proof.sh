#!/bin/bash
# Requires, renders and posts a PR's explainer: explainer-proof.sh [check|render [page...]|publish] (no argument: all three).
#   check    a PR from a <n>-<slug> branch must add or change explainers/<n>-*.html; other branches are exempt
#   render   each explainers/<issue>-*.html the PR adds or changes (or each page given) -> 1200px full-page dark PNG
#   publish  commits each PNG to the shots branch as pr-$PR/explainer-<issue>.png and puts it in the
#            PR comment marked <!-- pr-proof -->, between <!-- explainer:start --> and <!-- explainer:end -->
# Env: PR (number), HEAD_REF (branch, default the current one), HEAD_SHA, BASE (default origin/main), OUT.
# DRY_RUN=1 runs check and render, then prints the comment instead of uploading and posting.
set -euo pipefail

BASE=${BASE:-origin/main}
OUT=${OUT:-${RUNNER_TEMP:-${TMPDIR:-/tmp}}/explainer-proof}
CHROME=${CHROME:-google-chrome}
WIDTH=1200
mkdir -p "$OUT"

check() {
  local branch=${HEAD_REF:-$(git rev-parse --abbrev-ref HEAD)}
  git diff --name-only --diff-filter=ACMR "$BASE...HEAD" -- 'explainers/*.html' \
    | grep -E '^explainers/[0-9]+-[^/]+\.html$' > "$OUT/list" || true
  if [[ ! $branch =~ ^([0-9]+)-[A-Za-z0-9] ]]; then
    echo "$branch is not an <issue>-<slug> branch; no explainer required"
    return
  fi
  local n=${BASH_REMATCH[1]}
  if ! grep -q "^explainers/${n}-" "$OUT/list"; then
    echo "::error::Branch $branch must add or change explainers/${n}-<slug>.html (see .claude/skills/explainer/SKILL.md)"
    exit 1
  fi
  echo "explainers in this PR:"
  sed 's/^/  /' "$OUT/list"
}

chrome() {
  "$CHROME" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=1 --force-dark-mode \
    ${CI:+--no-sandbox} --user-data-dir="$OUT/profile" --virtual-time-budget=3000 "$@"
}

measure() {  # page width -> "height scrollWidth", laid out in an iframe of that width (headless windows are at least 500px)
  printf '%s' "<!doctype html><body style='margin:0'><iframe id=f src='file://$PWD/$1' style='border:0;width:$2px;height:100px'></iframe>
<script>f.onload = () => { const e = f.contentDocument.documentElement; document.title = 'size ' + e.scrollHeight + ' ' + e.scrollWidth; }</script>" \
    > "$OUT/probe.html"
  chrome --allow-file-access-from-files --window-size=1300,900 --dump-dom "file://$OUT/probe.html" 2>"$OUT/chrome.log" \
    | sed -n 's|.*<title>size \([0-9]*\) \([0-9]*\)</title>.*|\1 \2|p' | head -1
}

render() {
  if (( $# )); then printf '%s\n' "$@" > "$OUT/list"; else check >/dev/null; fi
  local page issue height width narrow
  while read -r page; do
    issue=$(basename "$page" | cut -d- -f1)
    read -r height width < <(measure "$page" "$WIDTH") || true
    if [[ -z ${height:-} ]]; then
      cat "$OUT/chrome.log" >&2
      echo "::error::Chrome could not measure $page"
      exit 1
    fi
    read -r _ narrow < <(measure "$page" 390) || true
    if (( ${narrow:-0} > 390 )); then
      echo "::warning file=$page::$page is ${narrow}px wide at a 390px viewport; diagrams and code must scroll inside their own boxes"
    fi
    chrome --window-size="$WIDTH,$height" --screenshot="$OUT/explainer-$issue.png" "file://$PWD/$page" 2>>"$OUT/chrome.log" >/dev/null
    [[ -s $OUT/explainer-$issue.png ]] || { cat "$OUT/chrome.log" >&2; echo "::error::Chrome made no image of $page"; exit 1; }
    echo "$page -> $OUT/explainer-$issue.png (${width}x${height})"
  done < "$OUT/list"
}

section() {  # the explainer section of the comment, for each image URL in $OUT/urls
  local sha=${HEAD_SHA:-$(git rev-parse HEAD)} page issue url
  echo '<!-- explainer:start -->'
  while read -r page url; do
    issue=$(basename "$page" | cut -d- -f1)
    printf '### Explainer: `%s`\n\nDark mode, %spx wide, full page, as of %s.\n\n![Explainer for #%s](%s)\n\n' \
      "$page" "$WIDTH" "${sha::12}" "$issue" "$url"
  done < "$OUT/urls"
  echo '<!-- explainer:end -->'
}

upload() {  # local png, path on shots -> commit sha
  local body="$OUT/upload.json" blob attempt sha
  [[ -s $1 ]] || { echo "::error::$1 is missing; run render first" >&2; return 1; }
  for attempt in 1 2; do
    blob=$(gh api "repos/{owner}/{repo}/contents/$2?ref=shots" -H 'Accept: application/vnd.github.object' --jq .sha 2>/dev/null) || blob=
    jq -n --arg m "Explainer image for PR #$PR" --arg b shots --arg s "$blob" --rawfile c <(base64 -w0 "$1") \
      '{message: $m, branch: $b, content: $c} + (if $s == "" then {} else {sha: $s} end)' > "$body"
    if sha=$(gh api -X PUT "repos/{owner}/{repo}/contents/$2" --input "$body" --jq .commit.sha) && [[ $sha =~ ^[0-9a-f]{40}$ ]]; then
      echo "$sha"
      return
    fi
    echo "upload of $2 failed (attempt $attempt)" >&2
  done
  return 1
}

publish() {
  [[ -n ${PR:-} || ${DRY_RUN:-0} == 1 ]] || { echo "publish needs PR" >&2; exit 1; }
  : "${GH_REPO:?}"
  [[ -f $OUT/list ]] || render
  if [[ ! -s $OUT/list ]]; then
    echo "no explainer in this PR; nothing to post"
    return
  fi
  : > "$OUT/urls"
  local page issue path sha
  while read -r page; do
    issue=$(basename "$page" | cut -d- -f1)
    path="pr-${PR:-0}/explainer-$issue.png"
    if [[ ${DRY_RUN:-0} == 1 ]]; then
      echo "would upload $OUT/explainer-$issue.png to shots:$path"
      sha=DRY-RUN
    else
      sha=$(upload "$OUT/explainer-$issue.png" "$path")
      echo "uploaded shots:$path in ${sha::12}"
    fi
    echo "$page https://github.com/$GH_REPO/blob/$sha/$path?raw=true" >> "$OUT/urls"
  done < "$OUT/list"
  section > "$OUT/section.md"

  local id=
  if [[ -n ${PR:-} ]]; then
    id=$(gh api --paginate "repos/{owner}/{repo}/issues/$PR/comments" \
      --jq '.[] | select(.body | contains("<!-- pr-proof -->")) | .id' | head -1)
  fi
  if [[ -n $id ]]; then
    gh api "repos/{owner}/{repo}/issues/comments/$id" --jq .body > "$OUT/old.md"
    python3 - "$OUT/old.md" "$OUT/section.md" > "$OUT/comment.md" <<'EOF'
import re, sys
old, new = (open(p).read().strip('\n') for p in sys.argv[1:])
pat = re.compile(r'<!-- explainer:start -->.*?<!-- explainer:end -->', re.S)
print(pat.sub(lambda _: new, old, count=1) if pat.search(old) else old + '\n\n' + new)
EOF
  else
    { echo '<!-- pr-proof -->'; cat "$OUT/section.md"; } > "$OUT/comment.md"
  fi

  if [[ ${DRY_RUN:-0} == 1 ]]; then
    if [[ -n $id ]]; then echo "would update comment $id:"; else echo "would create a comment on PR #${PR:-?}:"; fi
    sed 's/^/  | /' "$OUT/comment.md"
  elif [[ -n $id ]]; then
    gh api -X PATCH "repos/{owner}/{repo}/issues/comments/$id" -F body=@"$OUT/comment.md" --jq '"updated \(.html_url)"'
  else
    gh api "repos/{owner}/{repo}/issues/$PR/comments" -F body=@"$OUT/comment.md" --jq '"created \(.html_url)"'
  fi
}

case ${1:-all} in
  check) check ;;
  render) shift; render "$@" ;;
  publish) publish ;;
  all) check; render; publish ;;
  *) echo "usage: $0 [check|render|publish]" >&2; exit 2 ;;
esac
