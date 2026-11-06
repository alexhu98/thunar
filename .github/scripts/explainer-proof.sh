#!/bin/bash
# Requires, renders and posts a PR's explainer: explainer-proof.sh [check|narration|render [page...]|publish] (no argument: all four).
#   check     a PR from a <n>-<slug> branch must add or change explainers/<n>-*.html; other branches are exempt
#   narration make-video.py status <n> for the branch's issue and for every explainer page or narration the PR adds
#             or changes, or for every narration when the PR changes make-video.py: fails when a narration is
#             missing, stale, or names keys the page no longer has
#   render   each explainers/<issue>-*.html the PR adds or changes (or each page given) -> 1200px full-page dark PNG
#   publish  commits each PNG to the shots branch as pr-$PR/explainer-<issue>.png and puts it in the PR comment's
#            explainer section, with the narration results, through pr-comment.sh. A failed render or upload is
#            marked in the section, and publish then fails.
# Env: PR (number), HEAD_REF (branch, default the current one), HEAD_SHA, BASE (default origin/main), OUT.
# DRY_RUN=1 runs check, narration and render, then prints the comment instead of uploading and posting.
set -euo pipefail

BASE=${BASE:-origin/main}
OUT=${OUT:-${RUNNER_TEMP:-${TMPDIR:-/tmp}}/explainer-proof}
CHROME=${CHROME:-google-chrome}
WIDTH=1200
mkdir -p "$OUT"

check() {
  local branch=${HEAD_REF:-$(git rev-parse --abbrev-ref HEAD)} changed
  changed=$(git diff --name-only --diff-filter=ACMR "$BASE...HEAD" -- 'explainers/*.html')
  grep -E '^explainers/[0-9]+-[A-Za-z0-9._-]+\.html$' <<<"$changed" > "$OUT/list" || true
  if [[ ! $branch =~ ^([0-9]+)-[A-Za-z0-9] ]]; then
    echo "$branch is not an <issue>-<slug> branch; no explainer required"
    return
  fi
  local n=${BASH_REMATCH[1]}
  if ! grep -q "^explainers/${n}-" "$OUT/list"; then
    echo "::error::Branch $branch must add or change explainers/${n}-<slug>.html (see .claude/skills/explainer/SKILL.md)" >&2
    exit 1
  fi
  echo "explainers in this PR:"
  sed 's/^/  /' "$OUT/list"
}

narration() {
  local branch=${HEAD_REF:-$(git rev-parse --abbrev-ref HEAD)} nums n out failed=0
  nums=$( {
    git diff --name-only --diff-filter=ACMR "$BASE...HEAD" -- 'explainers/*.html' 'explainers/*.narration.json' \
      | sed -nE 's|^explainers/([0-9]+)-.*|\1|p'
    if [[ $branch =~ ^([0-9]+)-[A-Za-z0-9] ]]; then echo "${BASH_REMATCH[1]}"; fi
    if ! git diff --quiet "$BASE...HEAD" -- .claude/skills/explainer/make-video.py; then
      git ls-files 'explainers/*.narration.json' | sed -nE 's|^explainers/([0-9]+)-.*|\1|p'
    fi
  } | sort -nu)
  : > "$OUT/narration.md"
  for n in $nums; do
    if out=$(CHROME="$CHROME" EXPLAINER_CACHE="$OUT/narration-cache" python3 .claude/skills/explainer/make-video.py status "$n" 2>&1); then
      printf -- '- Narration of #%s: current.\n' "$n" >> "$OUT/narration.md"
      echo "narration of #$n: current"
    else
      printf -- '- Narration of #%s: **fails** `make-video.py status %s`. Write or fix it, then `make-video.py stamp %s` (see `.claude/skills/explainer/SKILL.md`).\n\n  ```text\n%s\n  ```\n' \
        "$n" "$n" "$n" "$(sed 's/^/  /' <<<"$out")" >> "$OUT/narration.md"
      echo "::error::The narration of #$n fails make-video.py status (missing, stale, or the page is not unique); see .claude/skills/explainer/SKILL.md" >&2
      failed=1
    fi
    sed 's/^/  /' <<<"$out"
  done
  return "$failed"
}

chrome() {
  timeout 180 "$CHROME" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=1 --force-dark-mode \
    ${CI:+--no-sandbox} --user-data-dir="$OUT/profile" --virtual-time-budget=3000 "$@" </dev/null
}

measure() {  # page URL -> "height scrollWidth" at $WIDTH and "scrollWidth" at 390px, each laid out in an iframe of that width (headless windows are at least 500px)
  printf '%s' "<!doctype html><body style='margin:0'><iframe id=w src='$1' style='border:0;width:${WIDTH}px;height:100px'></iframe><iframe id=n src='$1' style='border:0;width:390px;height:100px'></iframe>
<script>onload = () => { const e = w.contentDocument.documentElement; document.title = ['size', e.scrollHeight, e.scrollWidth, n.contentDocument.documentElement.scrollWidth].join(' '); }</script>" \
    > "$OUT/probe.html"
  chrome --allow-file-access-from-files --window-size=1300,900 --dump-dom "file://$OUT/probe.html" 2>"$OUT/chrome.log" \
    | sed -n 's|.*<title>size \([0-9]*\) \([0-9]*\) \([0-9]*\)</title>.*|\1 \2 \3|p' | head -1
}

render() {
  if (( $# )); then printf '%s\n' "$@" > "$OUT/list"; else check >/dev/null; fi
  local page url issue height width narrow failed=0
  while read -r page; do
    issue=$(basename "$page" | cut -d- -f1)
    rm -f "$OUT/explainer-$issue.png"
    url="file://$(realpath "$page")"
    height=
    read -r height width narrow < <(measure "$url") || true
    if [[ -z ${height:-} ]]; then
      cat "$OUT/chrome.log" >&2
      echo "::error::Chrome could not measure $page"
      failed=1
      continue
    fi
    if (( ${narrow:-0} > 390 )); then
      echo "::warning file=$page::$page is ${narrow}px wide at a 390px viewport; diagrams and code must scroll inside their own boxes"
    fi
    chrome --window-size="$WIDTH,$height" --screenshot="$OUT/explainer-$issue.png" "$url" 2>>"$OUT/chrome.log" >/dev/null || true
    if [[ ! -s $OUT/explainer-$issue.png ]]; then
      cat "$OUT/chrome.log" >&2
      echo "::error::Chrome made no image of $page"
      failed=1
      continue
    fi
    echo "$page -> $OUT/explainer-$issue.png (${width}x${height})"
  done < "$OUT/list"
  return "$failed"
}

section() {  # the explainer section of the comment, for each image URL in $OUT/urls
  local sha=${HEAD_SHA:-$(git rev-parse HEAD)} page issue url
  echo '<!-- explainer:start -->'
  while read -r page url; do
    issue=$(basename "$page" | cut -d- -f1)
    if [[ $url == - ]]; then
      printf '### Explainer: `%s`\n\nThe upload of its image failed, as of %s. See the run.\n\n' "$page" "${sha::12}"
    elif [[ $url == '!' ]]; then
      printf '### Explainer: `%s`\n\nChrome made no image of it, as of %s. See the run.\n\n' "$page" "${sha::12}"
    else
      printf '### Explainer: `%s`\n\nDark mode, %spx wide, full page, as of %s.\n\n![Explainer for #%s](%s)\n\n' \
        "$page" "$WIDTH" "${sha::12}" "$issue" "$url"
    fi
  done < "$OUT/urls"
  if [[ -s $OUT/narration.md ]]; then
    printf '### Narration\n\n'
    cat "$OUT/narration.md"
    echo
  fi
  echo '<!-- explainer:end -->'
}

publish() {
  [[ -n ${PR:-} || ${DRY_RUN:-0} == 1 ]] || { echo "publish needs PR" >&2; exit 1; }
  : "${GH_REPO:?}"
  [[ -f $OUT/list ]] || render
  if [[ ! -s $OUT/list && ! -s $OUT/narration.md ]]; then
    echo "no explainer in this PR; nothing to post"
    return
  fi
  : > "$OUT/urls"
  local page issue path sha failed=0
  while read -r page; do
    issue=$(basename "$page" | cut -d- -f1)
    path="pr-${PR:-0}/explainer-$issue.png"
    if [[ ! -s $OUT/explainer-$issue.png ]]; then
      echo "::error::no image of $page to upload" >&2
      echo "$page !" >> "$OUT/urls"
      failed=1
    elif sha=$(OUT="$OUT/shots" "$(dirname "$0")/shots.sh" "$OUT/explainer-$issue.png" "$path" "Explainer image for PR #${PR:-0}" </dev/null); then
      echo "$page https://github.com/$GH_REPO/blob/$sha/$path?raw=true" >> "$OUT/urls"
    else
      echo "::error::could not upload $path" >&2
      echo "$page -" >> "$OUT/urls"
      failed=1
    fi
  done < "$OUT/list"
  section > "$OUT/section.md"
  OUT="$OUT/comment" "$(dirname "$0")/pr-comment.sh" put explainer "$OUT/section.md"
  return "$failed"
}

case ${1:-all} in
  check) check ;;
  narration) narration ;;
  render) shift; render "$@" ;;
  publish) publish ;;
  all) check; status=0; narration || status=1; render || status=1; set +e; (set -e; publish); rc=$?; set -e; (( rc == 0 )) || status=1; exit "$status" ;;
  *) echo "usage: $0 [check|narration|render|publish]" >&2; exit 2 ;;
esac
