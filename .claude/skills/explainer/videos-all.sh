#!/bin/bash
# Renders the video of every narrated explainer on main and on every <digits>-<slug> branch into one gallery folder.
# Local only, never in CI: make-video.py render needs Kokoro.
#   videos-all.sh [--only <n>] [--branch <name>] [--open-prs] [--dry-run] [--gallery <dir>]
#   --only <n>       decide and render only explainer <n>
#   --branch <name>  take pages only from main and that branch, and render only that branch's
#   --open-prs       take pages only from main and the branches of open PRs into main (needs gh)
#   --dry-run        report what would be rendered, render nothing
#   --gallery <dir>  the gallery worktree, default $GALLERY or ~/thunar-explainers
# Env: MAKE_VIDEO replaces the gallery's make-video.py (same arguments: status|render <n>).
# The gallery is a git worktree detached at origin/main; pages and narrations are copied into its explainers/ with
# git show. A branch provides the explainer files it changed since it left main, and for each issue it provides, its
# page and narration both come from that branch. Two branches providing the same issue are a conflict: reported,
# not rendered. A page is rendered only when its page and narration hashes differ from <stem>.mp4.sha.
# Writes SOURCES.tsv (page, branch, commit) and REPORT.tsv (page, branch, commit, result) in the gallery's explainers/.
set -euo pipefail

table() {
  awk -F'\t' '{ for (i = 1; i <= NF; i++) { c[NR, i] = $i; if (length($i) > w[i]) w[i] = length($i) } n[NR] = NF }
    END { for (r = 1; r <= NR; r++) { l = ""; for (i = 1; i <= n[r]; i++) l = l sprintf(i < n[r] ? "%-" w[i] "s  " : "%s", c[r, i]); print l } }' "$1"
}

main() {
  local only='' branch='' open_prs=0 dry=0 gallery=${GALLERY:-$HOME/thunar-explainers}
  while (( $# )); do
    case $1 in
      --only) only=${2:?--only needs an issue number}; shift ;;
      --branch) branch=${2:?--branch needs a branch name}; shift ;;
      --open-prs) open_prs=1 ;;
      --dry-run) dry=1 ;;
      --gallery) gallery=${2:?--gallery needs a folder}; shift ;;
      -h|--help) sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; return 0 ;;
      *) echo "videos-all: unknown option $1 (see --help)" >&2; return 2 ;;
    esac
    shift
  done
  [[ -z $only || $only =~ ^[0-9]+$ ]] || { echo "videos-all: --only takes an issue number" >&2; return 2; }

  local repo
  repo=$(git -C "$(dirname "$(realpath "$0")")" rev-parse --show-toplevel)
  cd "$repo"

  echo "== fetch"
  git fetch origin --prune

  echo "== gallery $gallery"
  if [[ -e $gallery ]]; then
    if [[ $(git -C "$gallery" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) != "$(git rev-parse --path-format=absolute --git-common-dir)" ]]; then
      echo "videos-all: $gallery exists and is not a worktree of $repo" >&2
      return 1
    fi
    git -C "$gallery" clean -fq -- 'explainers/*.html' 'explainers/*.narration.json'
    git -C "$gallery" checkout -fq --detach origin/main
  else
    git worktree prune
    git worktree add --detach "$gallery" origin/main
  fi
  local dir=$gallery/explainers
  mkdir -p "$dir"

  echo "== collect"
  local -a branches=()
  local b
  while read -r b; do
    [[ $b =~ ^[0-9]+-[A-Za-z0-9] ]] && branches+=("$b")
  done < <(git for-each-ref --format='%(refname:lstrip=3)' refs/remotes/origin)
  if [[ -n $branch ]]; then
    git rev-parse -q --verify "refs/remotes/origin/$branch" >/dev/null || { echo "videos-all: no branch origin/$branch" >&2; return 1; }
    branches=("$branch")
  elif (( open_prs )); then
    command -v gh >/dev/null || { echo "videos-all: --open-prs needs gh" >&2; return 1; }
    local open
    open=$(gh pr list --state open --base main --limit 200 --json headRefName --jq '.[].headRefName')
    local -a kept=()
    for b in "${branches[@]}"; do grep -qxF "$b" <<<"$open" && kept+=("$b"); done
    branches=("${kept[@]}")
  fi

  local -A claim=()
  local base f n
  for b in "${branches[@]}"; do
    base=$(git merge-base origin/main "origin/$b") || { echo "  $b: no common history with main, skipped"; continue; }
    while read -r f; do
      n=${f#explainers/}; n=${n%%-*}
      [[ $n =~ ^[0-9]+$ ]] || continue
      [[ " ${claim[$n]:-} " == *" $b "* ]] || claim[$n]="${claim[$n]:-}${claim[$n]:+ }$b"
    done < <(git diff --name-only --diff-filter=ACMR "$base" "origin/$b" -- 'explainers/*.html' 'explainers/*.narration.json')
  done

  local -A conflict=() source=()
  for n in "${!claim[@]}"; do
    if [[ ${claim[$n]} == *' '* ]]; then conflict[$n]=${claim[$n]}; else source[$n]=${claim[$n]}; fi
  done

  local main_sha
  main_sha=$(git rev-parse --short=12 origin/main)
  printf 'page\tbranch\tcommit\n' > "$dir/SOURCES.tsv"
  local -A page_ref=() page_sha=()
  copy() {  # ref label n
    local ref=$1 label=$2 n=$3 sha p
    sha=$(git rev-parse --short=12 "$ref")
    rm -f "$dir/$n"-*.html "$dir/$n"-*.narration.json
    while read -r p; do
      git show "$ref:$p" > "$gallery/$p"
      if [[ $p == *.html ]]; then
        printf '%s\t%s\t%s\n' "$p" "$label" "$sha" >> "$dir/SOURCES.tsv"
        page_ref[$p]=$label; page_sha[$p]=$sha
      fi
    done < <(git ls-tree --name-only "$ref" explainers/ | grep -E "^explainers/$n-[^/]*\.(html|narration\.json)$" || true)
  }
  local -a issues
  mapfile -t issues < <({ git ls-tree --name-only origin/main explainers/ | sed -nE 's|^explainers/([0-9]+)-.*\.html$|\1|p'
                          printf '%s\n' "${!claim[@]}"; } | sort -nu)
  for n in "${issues[@]}"; do
    if [[ -n ${source[$n]:-} ]]; then copy "origin/${source[$n]}" "${source[$n]}" "$n"; else copy origin/main main "$n"; fi
  done
  table "$dir/SOURCES.tsv" | sed 's/^/  /'

  echo "== decide"
  local mv=${MAKE_VIDEO:-$gallery/.claude/skills/explainer/make-video.py}
  local -a rows=()
  local failed=0 page stem want have result log
  for n in "${issues[@]}"; do
    [[ -z $only || $n == "$only" ]] || continue
    if [[ -n $branch && ${source[$n]:-} != "$branch" ]]; then continue; fi
    if [[ -n ${conflict[$n]:-} ]]; then
      rows+=("explainers/$n-*"$'\t'"${conflict[$n]// /, }"$'\t'"-"$'\t'"conflict: more than one branch changes it, not rendered")
      continue
    fi
    for page in "$dir/$n"-*.html; do
      [[ -e $page ]] || continue
      stem=${page%.html}
      page=explainers/$(basename "$page")
      log=$stem.log
      if [[ ! -e $stem.narration.json ]]; then
        result='needs narration'
      elif ! "$mv" status "$n" > "$log" 2>&1; then
        result="needs re-narration (status: $({ grep -m1 -E 'stale|changed|removed|make-video:' "$log" || true; } | sed 's/^ *//' | cut -c1-80))"
      else
        want="$(sha256sum < "$stem.html" | cut -d' ' -f1) $(sha256sum < "$stem.narration.json" | cut -d' ' -f1)"
        have=$(cat "$stem.mp4.sha" 2>/dev/null || true)
        if [[ -e $stem.mp4 && $have == "$want" ]]; then
          result=skipped
        elif (( dry )); then
          result='would render'
        elif echo "== $(date -Is) render $n" >> "$log" && "$mv" render "$n" >> "$log" 2>&1 && [[ -s $stem.mp4 ]]; then
          echo "$want" > "$stem.mp4.sha"
          result=rendered
        else
          result="failed (log: $log)"
          failed=1
        fi
      fi
      echo "  $page: $result"
      rows+=("$page"$'\t'"${page_ref[$page]:-main}"$'\t'"${page_sha[$page]:-$main_sha}"$'\t'"$result")
    done
  done

  echo "== report"
  { printf 'page\tbranch\tcommit\tresult\n'; (( ${#rows[@]} == 0 )) || printf '%s\n' "${rows[@]}"; } > "$dir/REPORT.tsv"
  table "$dir/REPORT.tsv"
  echo "videos and reports: $dir"
  return "$failed"
}

main "$@"
exit
