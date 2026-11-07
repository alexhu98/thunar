---
name: upstream-merge
description: The weekly upstream watcher (#30). Checks gitlab.xfce.org for a Thunar release tag newer than main's; when there is one, opens an issue for it and a PR that merges the tag into main, with its explainer. Run by the weekly scheduled task, or by hand as "/upstream-merge", or "/upstream-merge --base <ref> --issue <n>" for a test run from an older base.
---

# Upstream merge

Thunar's upstream tags each release as `thunar-<major>.<minor>.<n>` at `https://gitlab.xfce.org/xfce/thunar.git`. `main` is upstream's tree plus the fork's commits, so a new release comes in as one merge of its tag. CI then builds it, runs every `verify/*.sh` as a regression suite and reviews it, and the owner merges as usual.

One run handles at most one tag: the newest in `main`'s own series. A run that finds nothing new says so in one line and ends.

## Rules

- Merge the git tag, never a release tarball.
- Never push to the `upstream` remote, `master` or `xfce-4.20`, and never push tags. Push only the new branch.
- Never edit `debian/changelog` or the version: CI stamps `<new>-1~bpo24.04+local<N>` from `configure.ac`.
- The PR goes into `main`. The owner merges it.

## Arguments

- none: the weekly run.
- `--base <ref> --issue <n>`: a test run. Start from `<ref>` instead of `origin/main`, use the existing issue `<n>` instead of opening one, and title the PR `[test] Merge upstream <tag>`. The test PR is closed after its checks, never merged.

## 1. Check

```sh
git fetch origin main
[[ $(git rev-parse --is-shallow-repository) == true ]] && git fetch --unshallow origin main
.claude/skills/upstream-merge/check.sh [<base>]
```

`check.sh` prints one line:
- `none (main has 4.20.10, newest upstream thunar-4.20.10)`: report that line and stop.
- `new thunar-4.20.11 (main has 4.20.10)`: go on with that tag.
- a non-zero exit: report the error and stop. `CONNECT tunnel failed, response 403` means `gitlab.xfce.org` is missing from the environment's allowed domains; say so.

A `; upstream also has thunar-4.22.0, a newer stable series` note is reported, never acted on: a new series needs new Xfce libraries from the PPA, which is the owner's decision.

## 2. Already in hand?

```sh
gh api -X GET search/issues -f q='repo:alexhu98/thunar in:title "Merge upstream <tag>"' --jq '.items[] | "\(.number) \(.state) \(.pull_request != null) \(.title)"'
```

If an issue or PR for the tag exists, open or closed, report its number and stop. Closing the issue without a PR is how the owner skips a release.

## 3. Open the issue

```sh
git fetch --no-tags https://gitlab.xfce.org/xfce/thunar.git "refs/tags/<tag>:refs/upstream-tags/<tag>"
```

With the GitHub MCP `issue_write` tool, in `alexhu98/thunar`:
- Title: `Merge upstream <tag>`.
- Body: the tag and its link, `https://gitlab.xfce.org/xfce/thunar/-/tags/<tag>`; the tag's section of upstream's `NEWS`, from `git show refs/upstream-tags/<tag>:NEWS`; `Refs #30`; and a Done-when list: merged with green checks, screenshots reviewed, the split-view crash check done by hand after installing (`CLAUDE.md`).

## 4. Merge

```sh
git checkout -b <n>-<tag> <base>          # e.g. 57-thunar-4.20.11 from origin/main
git merge --no-ff -m "Merge upstream <tag>" "refs/upstream-tags/<tag>"
```

On conflicts, resolve each file by hand, never with `-X ours` or `-X theirs` for the whole merge:
- Files only the fork has (`.github/`, `.claude/`, `debian/`, `explainers/`, `verify/`, `CLAUDE.md`): keep the fork's.
- Thunar's source: keep both upstream's change and the fork's feature. If they can't both stay, keep upstream's code and re-apply the fork's change on top.
- Record every conflict and its resolution for the PR description and the explainer.
- If a conflict touched C code, build before pushing, as `CLAUDE.md` (Building) says.

Then check that the merge kept the fork's changes and nothing else moved. The two file lists must match, apart from files upstream also changed:

```sh
old=thunar-$(git show <base>:configure.ac | sed -n 's/^XDT_VERSION_INIT(\[\([0-9.]*\)\].*/\1/p')
git fetch --no-tags https://gitlab.xfce.org/xfce/thunar.git "refs/tags/$old:refs/upstream-tags/$old"
diff <(git diff --name-only "refs/upstream-tags/$old" <base>) <(git diff --name-only "refs/upstream-tags/<tag>" HEAD)
```

## 5. Explainer

Write `explainers/<n>-<tag>.html` and its stamped narration with the `explainer` skill. Part 1 is what the release changes for the owner, from `NEWS` and `git log --oneline <old>..<tag>`, and what the merge did with each conflict. Part 2 is the checks run here: `check.sh`, the merge, the file-list diff, a build if there was one. CI's build, verify and review go under "Checked only after the merge" until they run. Part 3 is the next release, found by next week's run.

## 6. Push and open the PR

```sh
git push -u origin <n>-<tag>
```

With the GitHub MCP `create_pull_request` tool, from `<n>-<tag>` into `main`:
- Title: `Merge upstream <tag>`.
- Body: `Closes #<n>` and `Refs #30`; upstream's `NEWS` section; the conflicts and their resolutions, or "merged cleanly"; that no `verify/<n>.sh` is added because the existing `verify/*.sh` run as the regression suite, with the `# | Shot | Proves` table filled from CI's verify comment once it runs; the split-view crash check left to the owner; and any word in the narration Kokoro may mispronounce.

## 7. Follow CI

Subscribe to the PR's activity with `subscribe_pr_activity` and follow the rules in its first event. After each verify run, run `/visual-verify pr:<pr>` and post its comment, as `CLAUDE.md` says. Fix only failures the merge caused. A failure that was already on `main` goes in the report, not in this PR.

## Report

End with one line: `none (…)`, `skipped: #<n> already exists`, or `opened #<n> and PR #<pr> for <tag>`, then anything the owner must do in a "**What I need from you**" section.
