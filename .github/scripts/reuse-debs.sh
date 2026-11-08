#!/bin/bash
# On a push to main, reuses the debs the merged PR's CI built and verified instead of building again: reuse-debs.sh find | check VERSION
#   find          prints run=<id> and pr=<PR #n> for the newest build run of the merged PR's head whose build and verify
#                 passed (verify having run its tests, not "No code changed") and whose debs artifact hasn't expired.
#                 Prints nothing when there is none, or when the GitHub API fails, so the push builds as before.
#   check VERSION succeeds when dist/ holds that run's debs, built from this commit's tree (dist/built-tree) and
#                 stamped VERSION, the version this push releases. Otherwise says why, and the push builds.
# Env: GITHUB_SHA, GH_REPO, GH_TOKEN.
set -euo pipefail

find_run() {
  local pr head run ok
  read -r pr head < <(gh api "repos/{owner}/{repo}/commits/$GITHUB_SHA/pulls" \
    --jq '[.[] | select(.merged_at != null and .base.ref == "main")][0] // empty | "\(.number) \(.head.sha)"') || return 0
  [[ -n ${head:-} ]] || { echo "no merged PR for ${GITHUB_SHA::12}; building" >&2; return 0; }
  for run in $(gh api "repos/{owner}/{repo}/actions/workflows/build.yml/runs?head_sha=$head&event=pull_request&per_page=20" \
    --jq '.workflow_runs[].id'); do
    ok=$(gh api "repos/{owner}/{repo}/actions/runs/$run/jobs" --jq '[.jobs[] | select(.name == "build" or .name == "verify")
      | select(.conclusion == "success" and all(.steps[]?; .name != "No code changed" or .conclusion == "skipped")) | .name] | length') || continue
    [[ $ok == 2 ]] || continue
    gh api "repos/{owner}/{repo}/actions/runs/$run/artifacts" --jq '.artifacts[] | select(.name == "debs" and (.expired | not)) | .id' \
      | grep -q . || continue
    echo "run=$run"
    echo "pr=PR #$pr"
    echo "reusing the debs of PR #$pr's run $run for ${head::12}" >&2
    return 0
  done
  echo "PR #$pr has no build run of ${head::12} with verified debs that haven't expired; building" >&2
}

check() {
  local version=${1:?version} deb got tree
  for deb in dist/thunar_*.deb dist/thunar-data_*.deb dist/libthunarx-3-0_*.deb; do
    [[ -f $deb ]] || { echo "no reusable debs; building" >&2; return 1; }
  done
  tree=$(git rev-parse 'HEAD^{tree}')
  [[ -f dist/built-tree && $(cat dist/built-tree) == "$tree" ]] \
    || { echo "the PR's debs were built from another tree than ${GITHUB_SHA::12}'s; building" >&2; return 1; }
  got=$(dpkg-deb -f dist/thunar_*.deb Version)
  [[ $got == "$version" ]] || { echo "the PR's debs are $got, not $version; building" >&2; return 1; }
}

case ${1:-} in
  find) find_run ;;
  check) shift; check "$@" ;;
  *) echo "usage: $0 find | check <version>" >&2; exit 2 ;;
esac
