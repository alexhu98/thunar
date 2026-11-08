#!/bin/bash
# CI code review of a PR: review-proof.sh plan | collect | report
#   plan     before the review: picks the mode from the head commit's Review: trailer (default auto-fix, or suggest
#            for an upstream release merge), and skips at once, writing only plan.json, when a newer run of this repo's
#            branch replaced the head. Otherwise waits (up to 20 min) until earlier runs on the branch have written their
#            review state, skips when the head was already reviewed, is CI's own fix commit (recorded in the state) on
#            top of the last reviewed one, or only explainers/ changed since the last reviewed commit, and writes the diff (for a release merge, only the fork's side), the issue, the open
#            findings with the commits since each was found, the accepted findings and the prompt to $OUT. Prints its decisions as key=value lines for $GITHUB_OUTPUT.
#   collect  after the review: saves the findings ($FINDINGS, the action's structured_output) and the working-tree
#            fix as a patch, for the report job.
#   report   as the review job's last step, without the push token, when the review left no fix to push. Otherwise, or when
#            that step didn't write the review comment, in the separate review-report job holding the push token, which
#            commits and pushes the fix (if any) as claude[bot]. Either way posts the other
#            findings as suggested changes, writes the review comment through pr-comment.sh and then the summary
#            through pr-summary.py, and fails while confirmed medium or high findings stay unresolved.
# Env: PR, HEAD_SHA, HEAD_REF, BASE (default origin/main), OUT, IN (report: the collected files), REVIEW_RESULT
# (report: the result of the review job's steps before the report), SUGGESTIONS_POSTED (report: 1 when the review job's own report already posted the suggestions), RUN_ID, RUN_NUMBER (plan), RUN_URL, REVIEW_LEVEL, REVIEW_MODEL. DRY_RUN=1 makes report print the
# commit, the suggestions and the section instead of pushing and posting them.
set -euo pipefail

BASE=${BASE:-origin/main}
OUT=${OUT:-${RUNNER_TEMP:-${TMPDIR:-/tmp}}/review}
IN=${IN:-$OUT}
LEVEL=${REVIEW_LEVEL:-high}
MODEL=${REVIEW_MODEL:-claude-opus-5-5}
HERE=$(cd "$(dirname "$0")" && pwd)
BOT_NAME='claude[bot]'
BOT_EMAIL='209825114+claude[bot]@users.noreply.github.com'
NOT_IN_FIX=(':!explainers/' ':!.claude' ':!CLAUDE.md' ':!CLAUDE.local.md' ':!.mcp.json' ':!.claude.json' ':!.gitmodules' ':!.ripgreprc' ':!.husky' ':!.github/workflows/' ':!.github/scripts/')
mkdir -p "$OUT"

state() {  # the review state saved in the review comment, or in the single comment from before -> stdout (JSON; {} when there is none)
  { "$HERE/pr-comment.sh" get review; echo; "$HERE/pr-comment.sh" legacy get; } | python3 -c '
import json, re, sys
m = re.search(r"^<!-- review:state (.*?) -->", sys.stdin.read(), re.M)
print(m.group(1) if m else "{}")'
}

schema() {
  cat <<'EOF'
{"type":"object","required":["findings","previous"],"properties":{"findings":{"type":"array","items":{"type":"object","required":["file","line","severity","summary","failure_scenario","verdict","fixed"],"properties":{"file":{"type":"string","description":"repo-relative path"},"line":{"type":"integer","description":"line in the file at HEAD; the last line of the range when start_line is set"},"start_line":{"type":"integer","description":"first line of a multi-line range, if any"},"files":{"type":"array","items":{"type":"string"},"description":"every repo-relative file the fix changed, when it changed more than file"},"severity":{"type":"string","enum":["high","medium","low"]},"summary":{"type":"string","description":"one sentence"},"failure_scenario":{"type":"string","description":"concrete inputs or state -> wrong output or crash"},"verdict":{"type":"string","enum":["CONFIRMED","PLAUSIBLE"],"description":"CONFIRMED only if a verify pass confirmed it"},"fixed":{"type":"boolean","description":"true only if the fix is in the working tree now"},"suggestion":{"type":"string","description":"the exact replacement text for lines start_line..line (or line), without code fences; omit when the fix is not confined to those lines"},"reason":{"type":"string","description":"why it was not fixed, when fixed is false"}}}},"previous":{"type":"array","items":{"type":"object","required":["id","resolved"],"properties":{"id":{"type":"string"},"resolved":{"type":"boolean"},"fixed":{"type":"boolean","description":"auto-fix only: true if you fixed it in the working tree in this review"},"file":{"type":"string","description":"its file, when fixed"},"files":{"type":"array","items":{"type":"string"},"description":"every file its fix changed, when more than file"},"line":{"type":"integer","description":"when fixed, its line at HEAD; the last line of the range when start_line is set"},"start_line":{"type":"integer","description":"first line of a multi-line range, if any"},"suggestion":{"type":"string","description":"when fixed, the exact replacement text for lines start_line..line (or line), without code fences; omit when the fix is not confined to those lines"},"note":{"type":"string"}}}}}}
EOF
}

wait_for_earlier_runs() {
  [[ -n ${RUN_ID:-} && -n ${RUN_NUMBER:-} && -n ${HEAD_REF:-} ]] || return 0
  local waited=0 start=$SECONDS busy errors=0 failed seen run runs jobs
  while :; do
    busy=0 failed=0 seen=0
    if ! runs=$(gh api -X GET "repos/{owner}/{repo}/actions/runs" -f branch="$HEAD_REF" -f event=pull_request -F per_page=30 --jq \
      ".workflow_runs[] | select(.path == \".github/workflows/build.yml\" and .head_repository.full_name == .repository.full_name and .status != \"completed\" and .run_number < $RUN_NUMBER) | .id"); then
      busy=1 failed=1 runs=
    fi
    for run in $runs; do
      if ! jobs=$(gh api "repos/{owner}/{repo}/actions/runs/$run/jobs" --jq \
        '[.jobs[] | select(.name == "review" or .name == "review-report") | {(.name): .status}] | add // {}
         | .review == "completed" and .["review-report"] != "completed"'); then
        busy=1 failed=1
      elif [[ $jobs == true ]]; then
        busy=1 seen=1
      fi
    done
    (( busy )) || return 0
    (( failed && ! seen )) && errors=$((errors + 1)) || errors=0
    if (( errors >= 3 )); then
      echo "::warning::the GitHub API failed 3 times in a row while checking earlier runs; reviewing anyway" >&2
      return 0
    fi
    if (( SECONDS - start >= 1200 )); then
      echo "::warning::an earlier run's review still hasn't finished after 20 min; reviewing anyway" >&2
      return 0
    fi
    (( waited == 0 )) && echo "waiting for an earlier run's review to finish" >&2
    sleep 20
    waited=$((waited + 20))
  done
}

superseded() {
  [[ -n ${RUN_NUMBER:-} && -n ${HEAD_REF:-} ]] || return 1
  gh api -X GET "repos/{owner}/{repo}/actions/runs" -f branch="$HEAD_REF" -f event=pull_request -F per_page=30 --jq \
    "[.workflow_runs[] | select(.path == \".github/workflows/build.yml\" and .head_repository.full_name == .repository.full_name and .run_number > $RUN_NUMBER and .head_sha != \"$HEAD_SHA\")]
     | max_by(.run_number) | .head_sha // empty" 2>/dev/null
}

write_plan() {
  jq -n --arg sha "$HEAD_SHA" --arg mode "$mode" --arg from "$from" --arg reason "$reason" --arg level "$LEVEL" \
    --arg model "$MODEL" --arg release "$release" --argjson skip "$skip" --argjson full "$full" --argjson forced "$forced" \
    --argjson ownfix "$ownfix" \
    '{sha: $sha, mode: $mode, from: $from, full: ($full == 1), forced: ($forced == 1), skip: ($skip == 1), own_fix: ($ownfix == 1),
      reason: $reason, level: $level, model: $model,
      release: (if $release == "" then null else $release end)}' \
    > "$OUT/plan.json"
  echo "review of ${HEAD_SHA::12}: $([[ $skip == 1 ]] && echo skipped || echo "$mode"), $reason" >&2
  echo "skip=$skip"
  echo "superseded=$1"
  echo "mode=$mode"
}

own_fix() {
  [[ -n $1 && $(git rev-parse -q --verify "$HEAD_SHA^" 2>/dev/null) == "$1" ]] &&
    jq -e --arg c "$HEAD_SHA" 'any(.findings[]?; .commit == $c)' "$OUT/state.json" > /dev/null
}

accepted() {
  git log --format='%H %(trailers:key=Review-accept,valueonly,separator=%x2C)' "$(git merge-base "$BASE" "$HEAD_SHA")..$HEAD_SHA" \
    | awk -F '[^A-Za-z0-9]+' '{ for (i = 2; i <= NF; i++) if (toupper($i) ~ /^R[0-9]+$/) print toupper($i), $1 }' | sort -u
}

release_merge() {  # merge base -> the newest "Merge upstream thunar-<version>" merge on the PR's first-parent line whose second parent isn't on BASE
  local sha subject
  while IFS=$'\t' read -r sha subject; do
    if [[ $subject =~ ^Merge\ upstream\ thunar-[0-9]+(\.[0-9]+)+$ ]] && ! git merge-base --is-ancestor "$sha^2" "$BASE"; then
      echo "$sha"
      return 0
    fi
  done < <(git log --first-parent --merges --format=$'%H\t%s' "$1..$HEAD_SHA")
}

auto_merge() {  # merge base, release merge -> the tree git's own merge of the release into the merge base makes
  local tree
  tree=$(git merge-tree --write-tree --no-messages "$1" "$2^2") || (( $? == 1 )) || return 1
  echo "${tree%%$'\n'*}"
}

fork_side() {  # merge base, release merge -> the fork's side of the PR: the merge's conflict resolutions and its commits after it
  if [[ $(git rev-parse "$2^1") == "$1" ]]; then
    git show --remerge-diff --format= "$2" -- . ':!explainers/'
    git diff "$2" "$HEAD_SHA" -- . ':!explainers/'
  else
    git diff "$(auto_merge "$1" "$2")" "$HEAD_SHA" -- . ':!explainers/'
  fi
}

open_findings() {
  accepted > "$OUT/accepted.txt"
  python3 "$HERE/review-state.py" open "$OUT/state.json" "$OUT"
}

plan() {
  : "${HEAD_SHA:?}"
  local trailer mode default=auto-fix forced=0 last skip=0 reason= from full=1 mb release issue= trusted newer ownfix=0
  trailer=$(git log -1 --format='%(trailers:key=Review,valueonly,separator=%x2C)' "$HEAD_SHA" | tr -d ' \n' | tr '[:upper:]' '[:lower:]')
  mb=$(git merge-base "$BASE" "$HEAD_SHA")
  release=$(release_merge "$mb")
  [[ -z $release ]] || default=suggest
  case $trailer in
    suggest|auto-fix) mode=$trailer; forced=1 ;;
    '') mode=$default ;;
    *) echo "::warning::unknown Review: trailer \"$trailer\"; using $default" >&2; mode=$default ;;
  esac
  newer=$(superseded) || newer=
  [[ -n $newer ]] || wait_for_earlier_runs
  [[ -n $newer ]] || newer=$(superseded) || newer=
  if [[ -n $newer ]]; then
    from= skip=1 reason="a newer run for ${newer::12} replaced it and reviews the changes"
    : > "$OUT/prompt.md"
    schema | jq -c . > "$OUT/schema.json"
    write_plan 1
    return 0
  fi
  state > "$OUT/state.json"
  last=$(jq -r '.sha // empty' "$OUT/state.json")
  from=${release:-$mb}
  if [[ $last == "$HEAD_SHA" ]]; then
    skip=1 reason="${last::12} was already reviewed"
  elif [[ -n $last ]] && git merge-base --is-ancestor "$HEAD_SHA" "$last" 2>/dev/null; then
    skip=1 reason="${HEAD_SHA::12} is already part of the reviewed ${last::12}"
  elif own_fix "$last"; then
    skip=1 ownfix=1 reason="it is CI's own fix from the review of ${last::12}, which the next push's review covers"
  elif [[ -n $last ]] && git cat-file -e "$last^{commit}" 2>/dev/null && git merge-base --is-ancestor "$last" "$HEAD_SHA" \
    && git merge-base --is-ancestor "$mb" "$last" && { [[ -z $release ]] || git merge-base --is-ancestor "$release" "$last"; }; then
    if git diff --quiet "$last" "$HEAD_SHA" -- . ':!explainers/'; then
      if (( forced )) && [[ -z $release ]]; then
        reason="forced by the head commit's Review: $mode trailer; nothing changed since ${last::12}, so the whole PR"
      else
        skip=1 reason="nothing but explainers/ changed since ${last::12}"
      fi
    else
      from=$last full=0 reason="the commits since ${last::12}"
    fi
  fi
  if [[ -n $release ]]; then
    fork_side "$mb" "$release" > "$OUT/fork.patch"
    if (( ! skip )) && [[ ! -s $OUT/fork.patch ]]; then
      open_findings
      if [[ $(jq length "$OUT/open.json") == 0 ]]; then
        skip=1 reason="the fork's side of the release merge ${release::12} changes nothing but explainers/"
      else
        from=$release full=1 reason="the fork's side of the release merge ${release::12} is empty, so only its open findings"
      fi
    fi
    [[ -n $reason ]] || reason="the fork's side of the release merge ${release::12}"
    if (( full )); then
      mv "$OUT/fork.patch" "$OUT/diff.patch"
    else
      git diff "$from" "$HEAD_SHA" -- . ':!explainers/' > "$OUT/diff.patch"
      mv "$OUT/fork.patch" "$OUT/pr.patch"
    fi
  else
    if (( ! skip )) && git diff --quiet "$mb" "$HEAD_SHA" -- . ':!explainers/'; then
      skip=1 reason="the PR changes nothing but explainers/"
    fi
    [[ -n $reason ]] || reason="the whole PR"
    git diff "$from" "$HEAD_SHA" -- . ':!explainers/' > "$OUT/diff.patch"
    (( full )) || git diff "$mb" "$HEAD_SHA" -- . ':!explainers/' > "$OUT/pr.patch"
  fi
  open_findings
  local s
  local -a since=() not=(^"$mb")
  [[ -z $release ]] || not+=(^"$release^2")
  while read -r s; do
    if [[ -n $s ]] && git cat-file -e "$s^{commit}" 2>/dev/null && git merge-base --is-ancestor "$s" "$HEAD_SHA"; then
      since+=("$(git log --no-merges --format=%h "$s..$HEAD_SHA" "${not[@]}" | paste -sd' ')")
    else
      since+=(-)
    fi
  done < <(jq -r '.[] | .sha // ""' "$OUT/open.json")
  printf '%s\n' "${since[@]}" | jq -R 'if . == "-" then null else split(" ") - [""] end' > "$OUT/since.json"
  jq --slurpfile c "$OUT/since.json" '[to_entries[] | .value + {commits_since: $c[.key]}]' "$OUT/open.json" > "$OUT/open.tmp"
  mv "$OUT/open.tmp" "$OUT/open.json"
  if (( skip )); then
    : > "$OUT/issue.md"
  elif [[ ${HEAD_REF:-} =~ ^([0-9]+)- ]]; then
    issue=${BASH_REMATCH[1]}
    trusted='.author_association | IN("OWNER", "MEMBER", "COLLABORATOR")'
    if ! gh api "repos/{owner}/{repo}/issues/$issue" > "$OUT/issue.json"; then
      echo "::warning::issue #$issue could not be read" >&2
      echo "Issue #$issue could not be read." > "$OUT/issue.md"
    elif jq -e .pull_request "$OUT/issue.json" > /dev/null; then
      echo "#$issue is a pull request, not an issue." > "$OUT/issue.md"
    else
      jq -r 'if '"$trusted"' then "# #\(.number): \(.title)\n\n\(.body // "")"
        else "Issue #\(.number) was written outside the repo, so it is left out." end' "$OUT/issue.json" > "$OUT/issue.md"
      if gh api --paginate "repos/{owner}/{repo}/issues/$issue/comments" --jq '.[] | select('"$trusted"')
        | "\n## Comment by \(.user.login)\n\n\(.body)"' > "$OUT/comments.md"; then
        cat "$OUT/comments.md" >> "$OUT/issue.md"
      else
        echo "::warning::the comments on issue #$issue could not be read" >&2
        printf '\nIts comments could not be read.\n' >> "$OUT/issue.md"
      fi
    fi
    rm -f "$OUT/issue.json"
  else
    echo "This branch is not named after an issue." > "$OUT/issue.md"
  fi
  schema | jq -c . > "$OUT/schema.json"
  prompt "$mode" "$from" "$full" "$release" > "$OUT/prompt.md"
  write_plan 0
}

prompt() {  # mode, from sha, full (1|0), release merge (or empty)
  local scope skip target="$2..$HEAD_SHA"
  printf -v skip '%s, ' "${NOT_IN_FIX[@]#:!}"
  if [[ -n $4 && $3 == 1 ]]; then
    target="the unified diff in $OUT/diff.patch: review the changes it shows, reporting each at its file and line at HEAD, not at lines of the patch file"
    scope="only the fork's side of the upstream release merge ${4::12}, saved in $OUT/diff.patch: the merge's conflict resolutions (\`git show --remerge-diff $4\`) and the PR's commits after it (\`git diff $4 $HEAD_SHA\`); when the branch has other commits around the merge, the diff from git's own merge of the release (\`git merge-tree\`) to HEAD instead. The commits of upstream's release are not under review: report nothing in code the release brought in unchanged"
  elif [[ -n $4 ]]; then
    scope="only the commits since the last review, \`git diff $2 $HEAD_SHA\`, saved in $OUT/diff.patch. The fork's whole side of the upstream release merge ${4::12}, $OUT/pr.patch, is context, not the target; upstream's release is neither"
  elif [[ $3 == 1 ]]; then
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

1. Use the Skill tool to run the code-review skill with args "$LEVEL $target".
2. Verify every finding it reports: give each, with its file, line, claim and failure scenario, to a fresh
   general-purpose Agent (all at once, in parallel) that tries to disprove it against the code at HEAD, read with
   \`git show HEAD:<path>\` because the working tree's CLAUDE.md and .claude/ are the base branch's, and that changes
   no files. The verdict is CONFIRMED only if that agent confirms the failure scenario; otherwise PLAUSIBLE.
EOF
  if [[ $1 == auto-fix ]]; then
    cat <<EOF
3. Fix each CONFIRMED finding in the working tree, and each finding in $OUT/open.json that its step 4 agent, run
   before this step, finds still there at HEAD. Change no code for a PLAUSIBLE one or one in $OUT/accepted.json. Don't stage,
   commit, push or switch branches. The fix leaves out every change under ${skip%, },
   so check that before making any edit for a finding. Set fixed to false for one whose fix needs it, make none of its
   edits and create no file for it, and undo any of its edits already made. Set fixed to true only if
   the finding's fix is in the working tree now; otherwise give the reason. When a fix changes more files than the
   finding's own, list every file it changed in files. Also give the exact replacement text as suggestion for each
   finding whose fix fits in its own lines, in case the fix can't be pushed.
EOF
  else
    cat <<EOF
3. Change no files. For each finding whose fix fits in its own lines, give the exact replacement text as suggestion.
   Set fixed to false for every finding.
EOF
  fi
  cat <<EOF
4. $OUT/open.json lists findings from earlier reviews that are still open, each with commits_since: the branch's own
   commits since it was found, without merges, or null when its commit is no longer in the history. This step is not
   limited to the diff under review: give each open finding to one fresh general-purpose Agent (all at once, in
   parallel), as in step 2, that reads with \`git show HEAD:<path>\` the finding's file and the code its claim
   depends on, looks at the commits in commits_since, which may have fixed it in another file, and decides from the
   code at HEAD alone whether it is resolved. "Not changed in this diff" is never a reason to keep a finding open.
   Report in previous whether each is resolved, by its id, with a note naming the code at HEAD that resolves it or
   still shows it. If you fixed it in step 3, set fixed to true, resolved to false, and give its file, files if the
   fix changed more, and its line, start_line and suggestion as in step 3.
5. Return the findings and previous in the output schema. Report every finding the skill reported, except one
   already listed in open.json: report that one only in previous. Leave out any finding that matches one in
   $OUT/accepted.json: the PR's author kept those on purpose.
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

right_hunks() {  # from, to -> "file<TAB>start<TAB>end" for each hunk on the right side of their diff
  git -c core.quotePath=false diff --no-ext-diff --no-color --no-relative --src-prefix=a/ --dst-prefix=b/ "$1" "$2" | awk '
    /^diff --git / { h = 1 }
    h && /^\+\+\+ / {
      h = 0; f = substr($0, 5); sub(/\t$/, "", f)
      if (f ~ /^"/) { f = substr(f, 2, length(f) - 2); gsub(/\\\\/, "\001", f); gsub(/\\"/, "\"", f); gsub(/\001/, "\\", f) }
      f = substr(f, 3)
    }
    /^@@/ { split($3, r, ","); s = substr(r[1], 2); n = (r[2] == "" ? 1 : r[2]); if (n > 0) print f "\t" s "\t" s + n - 1 }'
}

hunks() {  # the lines at HEAD_SHA where inline comments can go: the PR's diff, or for a release merge only the fork's side of it
  local mb release tree
  mb=$(git merge-base "$BASE" "$HEAD_SHA")
  release=$(release_merge "$mb")
  if [[ -z $release ]]; then
    right_hunks "$mb" "$HEAD_SHA"
    return 0
  fi
  tree=$(auto_merge "$mb" "$release")
  python3 -c '
import sys
def ranges(path):
    out = {}
    for ln in open(path):
        f, s, e = ln.rstrip("\n").split("\t")
        out.setdefault(f, []).append((int(s), int(e)))
    return out
pr, fork = ranges(sys.argv[1]), ranges(sys.argv[2])
for f, rs in fork.items():
    for s, e in rs:
        for a, b in pr.get(f, []):
            if max(s, a) <= min(e, b):
                print(f"{f}\t{max(s, a)}\t{min(e, b)}")' <(right_hunks "$mb" "$HEAD_SHA") <(right_hunks "$tree" "$HEAD_SHA")
}

report() {
  : "${HEAD_SHA:?}" "${HEAD_REF:?}"
  local result=${REVIEW_RESULT:-success} commit= note= mins= failed=() ids i unresolved
  rm -f "$OUT/reported"
  state > "$OUT/state.json"
  rm -f "$OUT/fixed-files.txt" "$OUT/fixed.json"
  if [[ ! -s $IN/plan.json ]]; then
    if [[ $result == success ]]; then
      note="The review of \`${HEAD_SHA::12}\` ran, but its results couldn't be downloaded, so its findings are not recorded."
    else
      note="The review of \`${HEAD_SHA::12}\` didn't run ($result)."
    fi
    result=failure
  elif [[ $(jq -r .skip "$IN/plan.json") == true ]]; then
    note="Skipped \`${HEAD_SHA::12}\`: $(jq -r .reason "$IN/plan.json")."
    if [[ $result != success ]]; then
      note+=" The review job still ended with $result."
    elif [[ $(jq -r '.own_fix // false' "$IN/plan.json") == true ]]; then
      result=unreviewed
    fi
  elif [[ $result != success ]]; then
    note="The review job for \`${HEAD_SHA::12}\` did not finish ($result); its findings are not recorded."
    result=failure
  elif [[ ! -s $IN/findings.json ]]; then
    note="The review of \`${HEAD_SHA::12}\` returned no findings object, so its findings are not recorded."
    result=failure
  fi
  open_findings
  if [[ -z $note && $(jq -r .mode "$IN/plan.json") == auto-fix && -s $IN/fix.patch ]]; then
    local fixed partial remote unverified stray stats
    git apply --numstat -z "$IN/fix.patch" | cut -z -f3- | tr '\0' '\n' | sort -u > "$OUT/fixed-files.txt"
    jq --slurpfile st "$OUT/state.json" --slurpfile open "$OUT/open.json" '($st[0].next // 1) as $n
      | ($open[0] | map({(.id): .}) | add // {}) as $o
      | [.findings | to_entries[] | .value + {i: .key, id: "R\($n + .key)"}]
        + [.previous // [] | map(select(.fixed)) | unique_by(.id)[]
          | ($o[.id] // {id, verdict: "PLAUSIBLE"}) + ({file, line} | with_entries(select(.value != null))) + {files, fixed: true}]' \
      "$IN/findings.json" > "$OUT/all.json"
    stats=$(jq -r --rawfile files "$OUT/fixed-files.txt" \
      'def cover: (.files | select(length > 0)) // [.file] | unique; def covered($f): all(cover[]; IN($f[]));
      ($files | split("\n") - [""]) as $f | [.[] | select(.fixed)] as $x | [$x[] | select(covered($f))] as $ok
      | ($ok | tojson), ([($ok | length), ([$x[] | select(any(cover[]; IN($f[])) and (covered($f) | not))] | length),
        ([$x[] | select(.verdict != "CONFIRMED")] | length), ($f - [$ok[] | cover[]] | length)] | @tsv)' "$OUT/all.json")
    printf '%s\n' "${stats%%$'\n'*}" > "$OUT/fixed.json"
    read -r fixed partial unverified stray <<< "${stats#*$'\n'}"
    if (( fixed == 0 )); then
      note="The review left changes in the working tree, but no finding marked fixed had all of its fix in them, so they weren't pushed."
    elif (( unverified > 0 )); then
      note="The fix also changed code for $unverified unconfirmed finding(s), so it wasn't pushed; its findings are suggestions instead."
    elif (( partial > 0 )); then
      note="The fix for $partial finding(s) was only partly kept, so it wasn't pushed; its findings are suggestions instead."
    elif (( stray > 0 )); then
      note="The fix also changed $stray file(s) with no fully fixed finding, so it wasn't pushed; its findings are suggestions instead."
    elif ! remote=$(git ls-remote origin "refs/heads/$HEAD_REF" | cut -f1); then
      note="Reading the branch \`$HEAD_REF\` failed, so the fix wasn't pushed; its findings are suggestions instead."
    elif [[ -z $remote ]]; then
      note="The branch \`$HEAD_REF\` was deleted during the review, so the fix wasn't pushed; its findings are suggestions instead."
    elif [[ $remote != "$HEAD_SHA" ]]; then
      note="The branch moved to \`${remote::12}\` during the review, so the fix wasn't pushed; its findings are suggestions instead."
    elif ! git apply --index "$IN/fix.patch"; then
      note="The fix didn't apply to \`${HEAD_SHA::12}\`, so it wasn't pushed; its findings are suggestions instead."
    else
      git -c user.name="$BOT_NAME" -c user.email="$BOT_EMAIL" commit -q -F - <<EOF
Fix $fixed finding(s) from the CI code review of ${HEAD_SHA::12}

$(jq -r '.[] | "- \(.id): \(.file):\(.line): \(.summary)"' "$OUT/fixed.json")

Review: suggest
EOF
      commit=$(git rev-parse HEAD)
      if [[ ${DRY_RUN:-0} == 1 ]]; then
        echo "would push ${commit::12} to $HEAD_REF:"; git show --stat HEAD | sed 's/^/  | /'
      elif ! git push origin "HEAD:refs/heads/$HEAD_REF" && [[ $(git ls-remote origin "refs/heads/$HEAD_REF" | cut -f1) != "$commit" ]]; then
        note="Pushing the fix failed, so its findings are suggestions instead."
        commit=
      fi
    fi
  fi
  if [[ -n ${RUN_ID:-} ]]; then
    mins=$(gh api "repos/{owner}/{repo}/actions/runs/$RUN_ID/jobs" --jq \
      '[.jobs[] | select(.name == "review" and .started_at != null) | ((if .completed_at then .completed_at | fromdate else now end) - (.started_at | fromdate))] | add // empty | . / 60 | ceil' 2>/dev/null) || mins=
  fi
  hunks > "$OUT/hunks.txt"
  python3 "$HERE/review-state.py" decide "$OUT/state.json" "$IN" "$OUT" "$HEAD_SHA" "$commit" "$mins" "${RUN_URL:-}" "$result"
  mapfile -t ids < <(jq -r '.comments[].id' "$OUT/suggestions.json")
  if (( ${#ids[@]} > 0 )) && [[ ${SUGGESTIONS_POSTED:-} != 1 ]]; then
    if [[ ${DRY_RUN:-0} == 1 ]]; then
      echo "would post a review with these suggestions:"; jq . "$OUT/suggestions.json" | sed 's/^/  | /'
    elif ! jq 'del(.comments[].id)' "$OUT/suggestions.json" | gh api "repos/{owner}/{repo}/pulls/$PR/reviews" --input - --jq '"posted \(.html_url)"'; then
      for i in "${!ids[@]}"; do
        jq ".comments = [.comments[$i] | del(.id)] | .body |= sub(\"[0-9]+ suggested\"; \"1 suggested\")" "$OUT/suggestions.json" \
          | gh api "repos/{owner}/{repo}/pulls/$PR/reviews" --input - --jq '"posted \(.html_url)"' || failed+=("${ids[$i]}")
      done
      (( ${#failed[@]} == 0 )) || echo "::warning::suggestions ${failed[*]} could not be posted" >&2
    fi
    if [[ -n ${GITHUB_OUTPUT:-} && ${DRY_RUN:-0} != 1 ]] && (( ${#failed[@]} == 0 )); then
      echo suggested=1 >> "$GITHUB_OUTPUT"
    fi
  fi
  unresolved=$(python3 "$HERE/review-state.py" render "$OUT" "$GH_REPO" "$HEAD_SHA" "$result" "$note" "${failed[@]}")
  OUT="$OUT/comment" "$HERE/pr-comment.sh" put review "$OUT/section.md"
  if [[ -n ${GITHUB_OUTPUT:-} && ${DRY_RUN:-0} != 1 ]]; then
    echo reported=1 >> "$GITHUB_OUTPUT"
    touch "$OUT/reported"
  fi
  "$HERE/pr-comment.sh" legacy delete || echo "::warning::could not delete the old single PR comment" >&2
  OUT="$OUT/summary" python3 "$HERE/pr-summary.py" || echo "::warning::could not update the summary comment" >&2
  if (( unresolved > 0 )) || [[ $result == failure ]]; then
    echo "::error::$unresolved confirmed medium or high finding(s) unresolved${note:+; ${note%.}}. Don't re-run this job alone; push a fix or a Review-accept trailer." >&2
    exit 1
  fi
}

case ${1:-} in
  plan) plan ;;
  collect) collect ;;
  report) report ;;
  *) echo "usage: $0 plan | collect | report" >&2; exit 2 ;;
esac
