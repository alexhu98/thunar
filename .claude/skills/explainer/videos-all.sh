#!/bin/bash
# Renders the video of every narrated explainer on main and on every <digits>-<slug> branch into one gallery folder.
# Local only, never in CI: make-video.py render needs Kokoro.
#   videos-all.sh [--only <n>] [--branch <name>] [--open-prs] [--dry-run] [--no-copy] [--gallery <dir>]
#   --only <n>       decide and render only explainer <n>
#   --branch <name>  take pages only from main and that branch, and render only that branch's
#   --open-prs       take pages only from main and the branches of open PRs into main (needs gh)
#   --dry-run        report what would be rendered, render nothing, copy nothing
#   --no-copy        don't copy the current videos into the checkout's explainers/
#   --gallery <dir>  the gallery worktree, default $GALLERY or ~/thunar-explainers
# Env: MAKE_VIDEO replaces the gallery's make-video.py (same arguments: status|render <n>); it must act on the
#      gallery's explainers/, e.g. by calling the gallery's make-video.py.
#      CHROME is passed to make-video.py; when unset, status uses the newest Playwright headless shell, if any, and
#      render uses google-chrome.
# The gallery is a linked git worktree detached at origin/main that this script created and marked, never the checkout
# the script runs from. Pages and narrations are copied into its explainers/ with git show. A branch provides the
# explainer files it changed since it left main, in a version main has never had; for each issue it provides, its page
# and narration both come from that branch. The issue's own <n>-<slug> branch wins over other branches; two <n>-<slug>
# branches, or two other branches and no own one, are a conflict: reported, not rendered. A page whose <stem>.mp4 exists
# and whose page and narration hashes equal those in <stem>.mp4.sha, which also holds a hash of make-video.py and the
# pronunciation table, is skipped without running status. Any other page runs status, then render.
# Writes SOURCES.tsv (page, branch, commit) and REPORT.tsv (page, branch, commit, result, copied) in the gallery's
# explainers/, and copies each skipped or rendered video that differs into the checkout's explainers/.
set -euo pipefail

table() {
  awk -F'\t' '{ for (i = 1; i <= NF; i++) { c[NR, i] = $i; if (length($i) > w[i]) w[i] = length($i) } n[NR] = NF }
    END { for (r = 1; r <= NR; r++) { l = ""; for (i = 1; i <= n[r]; i++) l = l sprintf(i < n[r] ? "%-" w[i] "s  " : "%s", c[r, i]); print l } }' "$1"
}

main() {
  local only='' branch='' open_prs=0 dry=0 copy=1 gallery=${GALLERY:-$HOME/thunar-explainers}
  while (( $# )); do
    case $1 in
      --only) only=${2:?--only needs an issue number}; shift ;;
      --branch) branch=${2:?--branch needs a branch name}; shift ;;
      --open-prs) open_prs=1 ;;
      --dry-run) dry=1 ;;
      --no-copy) copy=0 ;;
      --gallery) gallery=${2:?--gallery needs a folder}; shift ;;
      -h|--help) awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"; return 0 ;;
      *) echo "videos-all: unknown option $1 (see --help)" >&2; return 2 ;;
    esac
    shift
  done
  [[ -z $only || $only =~ ^[0-9]+$ ]] || { echo "videos-all: --only takes an issue number" >&2; return 2; }
  gallery=$(realpath -m "$gallery")

  local repo
  repo=$(git -C "$(dirname "$(realpath "$0")")" rev-parse --show-toplevel)
  cd "$repo"

  echo "== fetch"
  git fetch origin --prune

  echo "== gallery $gallery"
  if [[ -e $gallery ]]; then
    local top gitdir common
    top=$(git -C "$gallery" rev-parse --show-toplevel 2>/dev/null || true)
    gitdir=$(git -C "$gallery" rev-parse --path-format=absolute --git-dir 2>/dev/null || true)
    common=$(git -C "$gallery" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)
    if [[ $gallery == "$repo" || $top != "$gallery" || $common != "$(git rev-parse --path-format=absolute --git-common-dir)" \
          || ! -e $gitdir/videos-all-gallery ]] || git -C "$gallery" symbolic-ref -q HEAD >/dev/null; then
      echo "videos-all: $gallery is not a gallery worktree this script made for $repo; refusing to reset it." >&2
      if [[ $gallery != "$repo" && $top == "$gallery" && $gitdir != "$common" \
            && $common == "$(git rev-parse --path-format=absolute --git-common-dir)" ]] && ! git -C "$gallery" symbolic-ref -q HEAD >/dev/null; then
        echo "  If it is an old gallery, remove it (git worktree remove --force \"$gallery\") and run again, or pick another --gallery." >&2
      fi
      return 1
    fi
    git -C "$gallery" clean -fq -- 'explainers/*.html' 'explainers/*.narration.json'
    git -C "$gallery" checkout -fq --detach origin/main
  else
    if [[ $gallery == "$repo" || $gallery == "$repo"/* ]]; then
      echo "videos-all: the gallery $gallery would be inside the checkout $repo; pick a folder outside it" >&2
      return 1
    fi
    local admin='' d
    for d in "$(git rev-parse --path-format=absolute --git-common-dir)"/worktrees/*/; do
      [[ -f $d/gitdir && $(cat "$d/gitdir") == "$gallery/.git" ]] && admin=$d
    done
    if [[ -z $admin ]]; then
      git worktree add --detach "$gallery" origin/main
    elif [[ -e $admin/videos-all-gallery ]]; then
      git worktree add --force --detach "$gallery" origin/main
    else
      echo "videos-all: git still has a worktree registered at $gallery that this script did not make; refusing to replace it." >&2
      return 1
    fi
    touch "$(git -C "$gallery" rev-parse --path-format=absolute --git-dir)/videos-all-gallery"
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
    local slug
    slug=$(git remote get-url origin | sed -E 's#/+$##; s#^(https://|git@)github\.com[:/]##; s#\.git$##')
    open=$(gh pr list --repo "$slug" --state open --base main --limit 200 --json headRefName --jq '.[].headRefName')
    local -a kept=()
    for b in "${branches[@]}"; do grep -qxF "$b" <<<"$open" && kept+=("$b"); done
    branches=("${kept[@]}")
  fi

  local -A claim=()
  local base f n blob path history
  local -A on_main=()
  if (( ${#branches[@]} )); then
    history=$(git log --format= --raw --no-abbrev --diff-merges=separate --full-history origin/main -- explainers/)
    while read -r blob path; do
      on_main["$path $blob"]=1
    done < <(awk 'NF { print $4, $NF }' <<<"$history")
  fi
  for b in "${branches[@]}"; do
    base=$(git merge-base origin/main "origin/$b") || { echo "  $b: no common history with main, skipped"; continue; }
    while read -r f; do
      n=${f#explainers/}; n=${n%%-*}
      [[ $n =~ ^[0-9]+$ ]] || continue
      [[ -z ${on_main["$f $(git rev-parse "origin/$b:$f")"]:-} ]] || continue
      [[ " ${claim[$n]:-} " == *" $b "* ]] || claim[$n]="${claim[$n]:-}${claim[$n]:+ }$b"
    done < <(git diff --name-only --diff-filter=ACMR "$base" "origin/$b" -- 'explainers/*.html' 'explainers/*.narration.json')
  done

  local -A conflict=() source=()
  local -a own
  for n in "${!claim[@]}"; do
    own=()
    for b in ${claim[$n]}; do [[ $b == "$n"-* ]] && own+=("$b"); done
    if (( ${#own[@]} == 1 )); then source[$n]=${own[0]}
    elif (( ${#own[@]} > 1 )); then conflict[$n]=${own[*]}
    elif [[ ${claim[$n]} == *' '* ]]; then conflict[$n]=${claim[$n]}
    else source[$n]=${claim[$n]}; fi
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
                          (( ${#claim[@]} == 0 )) || printf '%s\n' "${!claim[@]}"; } | sort -nu)
  for n in "${issues[@]}"; do
    if [[ -n ${source[$n]:-} ]]; then copy "origin/${source[$n]}" "${source[$n]}" "$n"; else copy origin/main main "$n"; fi
  done
  table "$dir/SOURCES.tsv" | sed 's/^/  /'

  echo "== decide"
  local mv=${MAKE_VIDEO:-$gallery/.claude/skills/explainer/make-video.py}
  local -a rows=()
  local failed=0 page stem want have result log tool copied probe=${CHROME:-}
  if [[ -z $probe ]]; then
    probe=$(printf '%s\n' "${PLAYWRIGHT_BROWSERS_PATH:-$HOME/.cache/ms-playwright}"/chromium_headless_shell-*/chrome-headless-shell-linux64/chrome-headless-shell \
              | sort -V | tail -1)
    [[ -x $probe ]] || probe=google-chrome
  fi
  (( dry )) && copy=0
  tool=$(cat "$gallery/.claude/skills/explainer/make-video.py" <(sed -n '/<!-- say:start -->/,/<!-- say:end -->/p' "$gallery/.claude/skills/explainer/SKILL.md") \
           | sha256sum | cut -d' ' -f1)
  for n in "${issues[@]}"; do
    [[ -z $only || $n == "$only" ]] || continue
    if [[ -n $branch && ${source[$n]:-} != "$branch" ]]; then continue; fi
    if [[ -n ${conflict[$n]:-} ]]; then
      rows+=("explainers/$n-*"$'\t'"${conflict[$n]// /, }"$'\t'"-"$'\t'"conflict: more than one branch changes it, not rendered"$'\t'"-")
      continue
    fi
    if ! compgen -G "$dir/$n-*.html" >/dev/null; then
      if compgen -G "$dir/$n-*.narration.json" >/dev/null; then
        rows+=("explainers/$n-*"$'\t'"${source[$n]:-main}"$'\t'"-"$'\t'"a narration but no page, not rendered"$'\t'"-")
      fi
      continue
    fi
    for page in "$dir/$n"-*.html; do
      stem=${page%.html}
      page=explainers/$(basename "$page")
      log=$stem.log
      copied=-
      if [[ ! -e $stem.narration.json ]]; then
        result='needs narration'
      else
        want="$(sha256sum < "$stem.html" | cut -d' ' -f1) $(sha256sum < "$stem.narration.json" | cut -d' ' -f1) $tool"
        have=$(cat "$stem.mp4.sha" 2>/dev/null || true)
        if [[ -e $stem.mp4 && $have == "$want" ]]; then
          result=skipped
        elif ! CHROME=$probe "$mv" status "$n" > "$log" 2>&1; then
          result="needs re-narration (status: $({ grep -m1 -E '^  |make-video:' "$log" || head -1 "$log"; } | sed 's/^ *//' | cut -c1-80))"
        elif (( dry )); then
          result='would render'
        elif echo "== $(date -Is) render $n" >> "$log" && "$mv" render "$n" >> "$log" 2>&1 && [[ -s $stem.mp4 ]]; then
          echo "$want" > "$stem.mp4.sha"
          result=rendered
        else
          result="failed (log: $log)"
          failed=1
        fi
        if (( copy )) && [[ $result == skipped || $result == rendered ]] && ! cmp -s "$stem.mp4" "$repo/${page%.html}.mp4"; then
          cp -p "$stem.mp4" "$repo/${page%.html}.mp4"
          copied=yes
        fi
      fi
      echo "  $page: $result"
      rows+=("$page"$'\t'"${page_ref[$page]:-main}"$'\t'"${page_sha[$page]:-$main_sha}"$'\t'"$result"$'\t'"$copied")
    done
  done

  if [[ -n $branch ]] && (( ${#rows[@]} == 0 )); then
    if (( ${#claim[@]} == 0 )); then
      result="no explainer version on this branch that main hasn't had"
    else
      result="provides #$(printf '%s\n' "${!claim[@]}" | sort -n | paste -sd' ' | sed 's/ /, #/g'), not #$only"
    fi
    rows+=("-"$'\t'"$branch"$'\t'"$(git rev-parse --short=12 "origin/$branch")"$'\t'"$result"$'\t'"-")
  fi
  echo "== report"
  { printf 'page\tbranch\tcommit\tresult\tcopied\n'; (( ${#rows[@]} == 0 )) || printf '%s\n' "${rows[@]}"; } > "$dir/REPORT.tsv"
  table "$dir/REPORT.tsv"
  echo "videos and reports: $dir"
  (( ! copy )) || echo "videos copied to: $repo/explainers"
  return "$failed"
}

main "$@"
exit
