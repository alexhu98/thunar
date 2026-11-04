#!/bin/bash
# CI code review of a PR: review-proof.sh plan | collect | report
#   plan     before the review: picks the mode from the head commit's Review: trailer, skips when only explainers/
#            changed since the last reviewed commit, and writes the diff, the issue, the open findings and the
#            prompt to $OUT. Prints its decisions as key=value lines for $GITHUB_OUTPUT.
#   collect  after the review: saves the findings ($FINDINGS, the action's structured_output) and the working-tree
#            fix as a patch, for the report job.
#   report   in a separate job holding the push token: commits and pushes the fix as claude[bot], posts the other
#            findings as suggested changes, writes the review section of the PR comment through pr-comment.sh, and
#            fails while confirmed findings stay unresolved.
# Env: PR, HEAD_SHA, HEAD_REF, BASE (default origin/main), OUT, IN (report: the collected files), REVIEW_RESULT
# (report: the review job's result), RUN_URL, REVIEW_LEVEL, REVIEW_MODEL. DRY_RUN=1 makes report print the
# commit, the suggestions and the section instead of pushing and posting them.
set -euo pipefail

BASE=${BASE:-origin/main}
OUT=${OUT:-${RUNNER_TEMP:-${TMPDIR:-/tmp}}/review}
IN=${IN:-$OUT}
LEVEL=${REVIEW_LEVEL:-xhigh}
MODEL=${REVIEW_MODEL:-claude-opus-5-5}
HERE=$(cd "$(dirname "$0")" && pwd)
BOT_NAME='claude[bot]'
BOT_EMAIL='209825114+claude[bot]@users.noreply.github.com'
NOT_IN_FIX=(':!explainers/' ':!.claude' ':!CLAUDE.md' ':!CLAUDE.local.md' ':!.mcp.json' ':!.claude.json' ':!.gitmodules' ':!.ripgreprc' ':!.husky')
mkdir -p "$OUT"

state() {  # the review state saved in the PR comment -> stdout (JSON; {} when there is none)
  "$HERE/pr-comment.sh" get | python3 -c '
import json, re, sys
m = re.search(r"^<!-- review:state (.*?) -->", sys.stdin.read(), re.M)
print(m.group(1) if m else "{}")'
}

schema() {
  cat <<'EOF'
{"type":"object","required":["findings","previous"],"properties":{"findings":{"type":"array","items":{"type":"object","required":["file","line","severity","summary","failure_scenario","verdict","fixed"],"properties":{"file":{"type":"string","description":"repo-relative path"},"line":{"type":"integer","description":"line in the file at HEAD; the last line of the range when start_line is set"},"start_line":{"type":"integer","description":"first line of a multi-line range, if any"},"files":{"type":"array","items":{"type":"string"},"description":"every repo-relative file the fix changed, when it changed more than file"},"severity":{"type":"string","enum":["high","medium","low"]},"summary":{"type":"string","description":"one sentence"},"failure_scenario":{"type":"string","description":"concrete inputs or state -> wrong output or crash"},"verdict":{"type":"string","enum":["CONFIRMED","PLAUSIBLE"],"description":"CONFIRMED only if a verify pass confirmed it"},"fixed":{"type":"boolean","description":"true only if the fix is in the working tree now"},"suggestion":{"type":"string","description":"the exact replacement text for lines start_line..line (or line), without code fences; omit when the fix is not confined to those lines"},"reason":{"type":"string","description":"why it was not fixed, when fixed is false"}}}},"previous":{"type":"array","items":{"type":"object","required":["id","resolved"],"properties":{"id":{"type":"string"},"resolved":{"type":"boolean"},"note":{"type":"string"}}}}}}
EOF
}

wait_for_earlier_runs() {  # until no earlier run of this workflow on the branch has a review job still to finish
  [[ -n ${RUN_ID:-} && -n ${RUN_NUMBER:-} && -n ${HEAD_REF:-} ]] || return 0
  local waited=0 busy run
  while :; do
    busy=0
    for run in $(gh api "repos/{owner}/{repo}/actions/runs?branch=$HEAD_REF&event=pull_request&per_page=30" --jq \
      ".workflow_runs[] | select(.path == \".github/workflows/build.yml\" and .status != \"completed\" and .run_number < $RUN_NUMBER) | .id"); do
      if gh api "repos/{owner}/{repo}/actions/runs/$run/jobs" --jq \
        '[.jobs[] | select((.name == "review" or .name == "review-report") and .status != "completed")] | length > 0' | grep -q true; then
        busy=1
      fi
    done
    (( busy )) || return 0
    if (( waited >= 1800 )); then
      echo "::warning::an earlier run's review still hasn't finished after 30 min; reviewing anyway" >&2
      return 0
    fi
    (( waited == 0 )) && echo "waiting for an earlier run's review to finish" >&2
    sleep 20
    waited=$((waited + 20))
  done
}

plan() {
  : "${HEAD_SHA:?}"
  local trailer mode forced=0 last skip=0 reason= from full=1 mb issue=
  trailer=$(git log -1 --format='%(trailers:key=Review,valueonly,separator=%x2C)' "$HEAD_SHA" | tr -d ' \n' | tr '[:upper:]' '[:lower:]')
  case $trailer in
    suggest|auto-fix) mode=$trailer; forced=1 ;;
    '') mode=auto-fix ;;
    *) echo "::warning::unknown Review: trailer \"$trailer\"; using auto-fix" >&2; mode=auto-fix ;;
  esac
  wait_for_earlier_runs
  state > "$OUT/state.json"
  last=$(jq -r '.sha // empty' "$OUT/state.json")
  mb=$(git merge-base "$BASE" "$HEAD_SHA")
  from=$mb
  if [[ $last == "$HEAD_SHA" ]]; then
    skip=1 reason="${last::12} was already reviewed"
  elif [[ -n $last ]] && git cat-file -e "$last^{commit}" 2>/dev/null && git merge-base --is-ancestor "$last" "$HEAD_SHA" \
    && git merge-base --is-ancestor "$mb" "$last"; then
    if git diff --quiet "$last" "$HEAD_SHA" -- . ':!explainers/'; then
      if (( forced )); then
        reason="forced by the head commit's Review: $mode trailer; nothing changed since ${last::12}, so the whole PR"
      else
        skip=1 reason="nothing but explainers/ changed since ${last::12}"
      fi
    else
      from=$last full=0 reason="the commits since ${last::12}"
    fi
  fi
  if (( ! skip )) && git diff --quiet "$mb" "$HEAD_SHA" -- . ':!explainers/'; then
    skip=1 reason="the PR changes nothing but explainers/"
  fi
  [[ -n $reason ]] || reason="the whole PR"
  git diff "$from" "$HEAD_SHA" -- . ':!explainers/' > "$OUT/diff.patch"
  git diff "$mb" "$HEAD_SHA" -- . ':!explainers/' > "$OUT/pr.patch"
  jq '[.findings // [] | .[] | select((.status == "suggested" or .status == "not fixed") and .verdict == "CONFIRMED")]' "$OUT/state.json" > "$OUT/open.json"
  if [[ ${HEAD_REF:-} =~ ^([0-9]+)- ]]; then
    issue=${BASH_REMATCH[1]}
    gh issue view "$issue" --json number,title,body,comments \
      --jq '"# #\(.number): \(.title)\n\n\(.body)\n\n" + ([.comments[] | select(.authorAssociation | IN("OWNER", "MEMBER", "COLLABORATOR")) | "## Comment by \(.author.login)\n\n\(.body)\n"] | join("\n"))' \
      > "$OUT/issue.md" 2>/dev/null || echo "Issue #$issue could not be read." > "$OUT/issue.md"
  else
    echo "This branch is not named after an issue." > "$OUT/issue.md"
  fi
  schema | jq -c . > "$OUT/schema.json"
  prompt "$mode" "$from" "$full" > "$OUT/prompt.md"
  jq -n --arg sha "$HEAD_SHA" --arg mode "$mode" --arg from "$from" --arg reason "$reason" --arg level "$LEVEL" \
    --arg model "$MODEL" --argjson skip "$skip" --argjson full "$full" --argjson forced "$forced" \
    '{sha: $sha, mode: $mode, from: $from, full: ($full == 1), forced: ($forced == 1), skip: ($skip == 1), reason: $reason, level: $level, model: $model}' \
    > "$OUT/plan.json"
  echo "review of ${HEAD_SHA::12}: $([[ $skip == 1 ]] && echo skipped || echo "$mode"), $reason" >&2
  echo "skip=$skip"
  echo "mode=$mode"
}

prompt() {  # mode, from sha, full (1|0)
  local scope
  if [[ $3 == 1 ]]; then
    scope="the whole PR, \`git diff $2 $HEAD_SHA\`, saved in $OUT/diff.patch"
  else
    scope="only the commits since the last review, \`git diff $2 $HEAD_SHA\`, saved in $OUT/diff.patch. The whole PR's diff, $OUT/pr.patch, is context, not the target"
  fi
  cat <<EOF
You are CI's code reviewer for PR #${PR:-?} on branch ${HEAD_REF:-?}, checked out at $HEAD_SHA. You review with no
history from the session that wrote it.

- The issue it implements: $OUT/issue.md
- The repo rules in CLAUDE.md apply to the review and to every fix. In particular, add no new explanatory comments.
- Review $scope. Leave explainers/ out: those pages are checked by another job.

1. Use the Skill tool to run the code-review skill with args "$LEVEL $2..$HEAD_SHA".
2. Verify every finding it reports: give each, with its file, line, claim and failure scenario, to a fresh
   general-purpose Agent (all at once, in parallel) that tries to disprove it against the code at HEAD, read with
   \`git show HEAD:<path>\` because the working tree's CLAUDE.md and .claude/ are the base branch's, and that changes
   no files. The verdict is CONFIRMED only if that agent confirms the failure scenario; otherwise PLAUSIBLE.
EOF
  if [[ $1 == auto-fix ]]; then
    cat <<EOF
3. Fix each CONFIRMED finding in the working tree, and change no code for a PLAUSIBLE one or one already listed in
   $OUT/open.json. Don't stage, commit, push or switch branches. Set fixed to true only if the finding's fix is in the
   working tree now; otherwise give the reason. When a fix changes more files than the finding's own, list every file
   it changed in files. Also give the exact replacement text as suggestion for each finding whose fix fits in its own
   lines, in case the fix can't be pushed.
EOF
  else
    cat <<EOF
3. Change no files. For each finding whose fix fits in its own lines, give the exact replacement text as suggestion.
   Set fixed to false for every finding.
EOF
  fi
  cat <<EOF
4. $OUT/open.json lists findings from earlier reviews that are still open. For each, check the code at HEAD and report
   in previous whether it is resolved, by its id.
5. Return the findings and previous in the output schema. Report every finding the skill reported, except one
   already listed in open.json: report that one only in previous.
EOF
}

collect() {
  printf '%s' "${FINDINGS:-}" | jq -e 'has("findings")' > /dev/null || { echo "::error::the review returned no findings object" >&2; exit 1; }
  printf '%s' "$FINDINGS" | jq . > "$OUT/findings.json"
  git add -A
  git diff --cached --binary HEAD -- . "${NOT_IN_FIX[@]}" > "$OUT/fix.patch"
  git reset -q
  echo "$(jq '.findings | length' "$OUT/findings.json") findings; fix patch: $([[ -s $OUT/fix.patch ]] && git apply --numstat "$OUT/fix.patch" | wc -l || echo 0) files" >&2
}

hunks() {  # the PR's diff at HEAD_SHA -> "file<TAB>start<TAB>end" for each hunk on the right side, where inline comments can go
  git -c core.quotePath=false diff "$(git merge-base "$BASE" "$HEAD_SHA")" "$HEAD_SHA" | awk '
    /^diff --git / { h = 1 }
    h && /^\+\+\+ / {
      h = 0; f = substr($0, 5); sub(/\t$/, "", f)
      if (f ~ /^"/) { f = substr(f, 2, length(f) - 2); gsub(/\\\\/, "\001", f); gsub(/\\"/, "\"", f); gsub(/\001/, "\\", f) }
      f = substr(f, 3)
    }
    /^@@/ { split($3, r, ","); s = substr(r[1], 2); n = (r[2] == "" ? 1 : r[2]); if (n > 0) print f "\t" s "\t" s + n - 1 }'
}

write_report() {  # fix commit (or ""), note -> posts the suggestions not yet in POSTED, writes the section, sets UNRESOLVED
  local failed=() ids i id
  python3 "$HERE/review-state.py" decide "$OUT/state.json" "$IN" "$OUT" "$HEAD_SHA" "$1" "${mins:-}" "${RUN_URL:-}"
  jq --argjson done "$(printf '%s\n' "${POSTED[@]}" | jq -R . | jq -s 'map(select(. != ""))')" \
    '.comments |= map(select(.id | IN($done[]) | not)) | (.comments | length) as $n | .body |= sub("[0-9]+ suggested"; "\($n) suggested")' \
    "$OUT/suggestions.json" > "$OUT/to-post.json"
  mapfile -t ids < <(jq -r '.comments[].id' "$OUT/to-post.json")
  if (( ${#ids[@]} > 0 )); then
    if [[ ${DRY_RUN:-0} == 1 ]]; then
      echo "would post a review with these suggestions:"; jq . "$OUT/to-post.json" | sed 's/^/  | /'
    elif jq 'del(.comments[].id)' "$OUT/to-post.json" | gh api "repos/{owner}/{repo}/pulls/$PR/reviews" --input - --jq '"posted \(.html_url)"'; then
      POSTED+=("${ids[@]}")
    else
      for i in "${!ids[@]}"; do
        id=${ids[$i]}
        if jq ".comments = [.comments[$i] | del(.id)] | .body |= sub(\"[0-9]+ suggested\"; \"1 suggested\")" "$OUT/to-post.json" \
          | gh api "repos/{owner}/{repo}/pulls/$PR/reviews" --input - --jq '"posted \(.html_url)"'; then
          POSTED+=("$id")
        else
          failed+=("$id")
        fi
      done
      (( ${#failed[@]} == 0 )) || echo "::warning::suggestions ${failed[*]} could not be posted" >&2
    fi
  fi
  UNRESOLVED=$(python3 "$HERE/review-state.py" render "$OUT" "$GH_REPO" "$2" "${failed[@]}")
  OUT="$OUT/comment" "$HERE/pr-comment.sh" put review "$OUT/section.md"
}

report() {
  : "${HEAD_SHA:?}" "${HEAD_REF:?}"
  local result=${REVIEW_RESULT:-success} commit= note= mins=
  state > "$OUT/state.json"
  rm -f "$OUT/fixed-files.txt"
  if [[ ! -s $IN/plan.json ]]; then
    note="The review of \`${HEAD_SHA::12}\` didn't run ($result)."
    result=failure
  elif [[ $(jq -r .skip "$IN/plan.json") == true ]]; then
    note="Skipped \`${HEAD_SHA::12}\`: $(jq -r .reason "$IN/plan.json")."
  elif [[ $result != success || ! -s $IN/findings.json ]]; then
    note="The review of \`${HEAD_SHA::12}\` failed ($result); its findings are not recorded."
    result=failure
  fi
  if [[ -z $note && $(jq -r .mode "$IN/plan.json") == auto-fix && -s $IN/fix.patch ]]; then
    local fixed remote unverified stray
    git apply --numstat -z "$IN/fix.patch" | cut -z -f3- | tr '\0' '\n' | sort -u > "$OUT/fixed-files.txt"
    jq --rawfile files "$OUT/fixed-files.txt" '[.findings[] | select(.fixed and any((.files // [.file])[]; IN($files | split("\n")[])))]' \
      "$IN/findings.json" > "$OUT/fixed.json"
    fixed=$(jq length "$OUT/fixed.json")
    remote=$(git ls-remote origin "refs/heads/$HEAD_REF" | cut -f1)
    unverified=$(jq '[.findings[] | select(.fixed and .verdict != "CONFIRMED")] | length' "$IN/findings.json")
    stray=$(comm -23 "$OUT/fixed-files.txt" \
      <(jq -r '.findings[] | select(.fixed and .verdict == "CONFIRMED") | (.files // [] | .[]), .file' "$IN/findings.json" | sort -u) | wc -l)
    if (( fixed == 0 )); then
      note="The review left changes in the working tree but marked no finding in those files fixed, so they weren't pushed."
    elif (( unverified > 0 )); then
      note="The fix also changed code for $unverified unconfirmed finding(s), so it wasn't pushed; its findings are suggestions instead."
    elif (( stray > 0 )); then
      note="The fix also changed $stray file(s) with no confirmed fixed finding, so it wasn't pushed; its findings are suggestions instead."
    elif [[ $remote != "$HEAD_SHA" ]]; then
      note="The branch moved to \`${remote::12}\` during the review, so the fix wasn't pushed; its findings are suggestions instead."
    elif ! git apply --index "$IN/fix.patch"; then
      note="The fix didn't apply to \`${HEAD_SHA::12}\`, so it wasn't pushed; its findings are suggestions instead."
    else
      git -c user.name="$BOT_NAME" -c user.email="$BOT_EMAIL" commit -q -F - <<EOF
Fix $fixed finding(s) from the CI code review of ${HEAD_SHA::12}

$(jq -r '.[] | "- \(.file):\(.line): \(.summary)"' "$OUT/fixed.json")

Review: suggest
EOF
      commit=$(git rev-parse HEAD)
    fi
  fi
  if [[ -n ${RUN_ID:-} ]]; then
    mins=$(gh api "repos/{owner}/{repo}/actions/runs/$RUN_ID/jobs" --jq \
      '[.jobs[] | select(.name == "review" and .completed_at != null) | ((.completed_at | fromdate) - (.started_at | fromdate))] | add // empty | . / 60 | ceil' 2>/dev/null) || mins=
  fi
  hunks > "$OUT/hunks.txt"
  POSTED=() UNRESOLVED=0
  write_report "$commit" "$note"
  if [[ -n $commit ]]; then
    if [[ ${DRY_RUN:-0} == 1 ]]; then
      echo "would push ${commit::12} to $HEAD_REF:"; git show --stat HEAD | sed 's/^/  | /'
    elif ! git push origin "HEAD:refs/heads/$HEAD_REF"; then
      note="Pushing the fix failed (the branch moved, or it touches .github/workflows/), so its findings are suggestions instead."
      write_report "" "$note"
    fi
  fi
  local unresolved=$UNRESOLVED
  if (( unresolved > 0 )) || [[ $result == failure ]]; then
    echo "::error::$unresolved confirmed finding(s) unresolved${note:+; $note}" >&2
    exit 1
  fi
}

case ${1:-} in
  plan) plan ;;
  collect) collect ;;
  report) report ;;
  *) echo "usage: $0 plan | collect | report" >&2; exit 2 ;;
esac
