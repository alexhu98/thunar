---
name: upstream-merge
description: The weekly upstream watcher (#30). Checks gitlab.xfce.org for a Thunar release tag newer than main's; when there is one, opens an issue for it and a PR that merges the tag into main, with its explainer. Run by the weekly scheduled task, or by hand as "/upstream-merge", or "/upstream-merge --base <branch>" for a test run from an older base.
---

# Upstream merge

Thunar's upstream tags each release as `thunar-<major>.<minor>.<n>` at `https://gitlab.xfce.org/xfce/thunar.git`. `main` is upstream's tree plus the fork's commits, so a new release comes in as one merge of its tag. CI then builds it, runs every `verify/*.sh` as a regression suite and reviews it, and the owner merges as usual.

One run handles at most one tag: the newest in `main`'s own series. A run that finds nothing new says so in one line and ends.

Below, `<base>` is `origin/main` (or `origin/<branch>` in a test run), `<tag>` is the new tag (`thunar-4.20.11`), `<old>` is the base's release (`thunar-4.20.10`), `<n>` is the release's issue, and `<title>` is `Merge upstream <tag>`, or `[test] Merge upstream <tag>` in a test run. Write them out literally in every command: shell variables don't survive between commands.

## Rules

- Merge the git tag, never a release tarball.
- Never push to the `upstream` remote, `master` or `xfce-4.20`, and never push tags. Push only the release's branch.
- Never edit `debian/changelog` or the version: CI stamps `<new>-1~bpo24.04+local<N>` from `configure.ac`.
- The last commit of every push carries the trailer `Review: suggest`, so CI's review suggests changes instead of committing edits to upstream's code.
- Before every push after the first, `git pull --rebase=merges`, never a plain `--rebase`, which would flatten the merge.
- CI's findings in upstream's own code aren't fixed in the fork. Close each one with a `Review-accept: R<n>` trailer on the next commit (an empty commit with `--allow-empty` if nothing else changes), and list them in the PR description.
- The PR goes into `main`. The owner merges it.

## Arguments

- none: the weekly run.
- `--base <branch>`: a test run from a pushed branch of this repo that is `main` rebuilt on an older release, never a plain upstream tag (an upstream tag has none of the fork's files, so CI and the explainer scripts would be missing). Its issue and PR are titled with the `[test]` prefix, and both are closed after the checks, never merged.

## 1. Check

A test run first fetches its branch: `git fetch origin <branch>`.

```sh
git fetch origin main
[[ $(git rev-parse --is-shallow-repository) == true ]] && git fetch --unshallow origin
.claude/skills/upstream-merge/check.sh <base>
```

`check.sh` prints one line:
- `none (main has 4.20.10, newest upstream thunar-4.20.10)`: report that line and stop.
- `new thunar-4.20.11 (main has 4.20.10)`: go on, with `<tag>` = `thunar-4.20.11` and `<old>` = `thunar-4.20.10`.
- a non-zero exit: report the error and stop. `CONNECT tunnel failed, response 403` means `gitlab.xfce.org` is missing from the environment's allowed domains; say so.

A `; upstream also has thunar-4.22.0, a newer stable series` note is reported, never acted on: a new series needs new Xfce libraries from the PPA, which is the owner's decision.

Then fetch both releases, outside `refs/tags`:

```sh
git fetch --no-tags https://gitlab.xfce.org/xfce/thunar.git "refs/tags/<old>:refs/upstream-tags/<old>" "refs/tags/<tag>:refs/upstream-tags/<tag>"
```

## 2. Already in hand?

```sh
gh api --paginate -X GET search/issues -f per_page=100 -f q='repo:alexhu98/thunar is:issue in:title "Merge upstream"' \
  --jq '.items[] | select(.title | test("^(\\[test\\] )?Merge upstream thunar-")) | "#\(.number) \(.state) \(.state_reason) \(.title)"'
gh api --paginate -X GET search/issues -f per_page=100 -f q='repo:alexhu98/thunar is:pull-request is:open in:title "Merge upstream"' \
  --jq '.items[] | select(.title | test("^(\\[test\\] )?Merge upstream thunar-")) | "#\(.number) \(.title)"'
```

Look only at titles of this run's kind, with `[test] ` in a test run and without it otherwise:
- Any open issue or PR, for any tag: report `waiting: #<n> is open` and stop. One release is in flight at a time, and a run never takes over another run's issue or branch. The owner merges it, or closes it.
- An issue titled `<title>` closed as not planned (weekly runs only): report `skipped: #<n> was closed as not planned` and stop. That is how the owner skips a release.
- Otherwise go on. An issue closed any other way without a merged PR, such as one a failed run left behind, doesn't block: the release gets a new issue and branch.

## 3. Open the issue

With the GitHub MCP `issue_write` tool, in `alexhu98/thunar`:
- Title: `<title>`.
- Body: the tag and its link, `https://gitlab.xfce.org/xfce/thunar/-/tags/<tag>`; the tag's section of upstream's `NEWS`, from `git show refs/upstream-tags/<tag>:NEWS`; `Refs #30`; and a Done-when list: merged with green checks, screenshots reviewed, the split-view crash check done by hand after installing (`CLAUDE.md`).

## 4. Merge

```sh
git checkout --no-track -b <n>-<tag> <base>          # e.g. 57-thunar-4.20.11 from origin/main
git merge --no-ff -m "Merge upstream <tag>" -m "Review: suggest" refs/upstream-tags/<tag>
```

On conflicts, resolve each file by hand, never with `-X ours` or `-X theirs` for the whole merge, then `git commit --no-edit --cleanup=strip`:
- Files only the fork has (`.github/`, `.claude/`, `debian/`, `explainers/`, `verify/`, `CLAUDE.md`): keep the fork's.
- Thunar's source: keep both upstream's change and the fork's feature. If they can't both stay, keep upstream's code and re-apply the fork's change on top.
- Record every conflict and its resolution for the PR description and the explainer.
- If a conflict touched C code, build before pushing, as `CLAUDE.md` (Building) says.

Then check that the merge kept the fork's changes and nothing else moved: list the files the fork changes before and after the merge.

```sh
diff <(git diff --name-only refs/upstream-tags/<old> <base>) <(git diff --name-only refs/upstream-tags/<tag> HEAD)
```

No output means every fork change survived and nothing else moved. A file only on the left is a fork change upstream adopted, or one the merge lost: compare it with `git diff refs/upstream-tags/<tag> HEAD -- <file>` and say which in the PR. A file only on the right is a change the merge made outside the fork's work, which is a mistake to fix.

## 5. Explainer

Write `explainers/<n>-<tag>.html` and its stamped narration with the `explainer` skill, and commit them with the trailer `Review: suggest`, as the Rules say for the last commit of a push. Part 1 is what the release changes for the owner, from `NEWS` and `git log --oneline refs/upstream-tags/<old>..refs/upstream-tags/<tag>`, and what the merge did with each conflict. Part 2 is the checks run here: `check.sh`, the merge, the file-list diff, a build if there was one. CI's build, verify and review go under "Checked only after the merge" until they run. Part 3 is the next release, found by next week's run.

## 6. Push and open the PR

```sh
git push -u origin <n>-<tag>
```

With the GitHub MCP `create_pull_request` tool, from `<n>-<tag>` into `main`:
- Title: `<title>`.
- Body: `Closes #<n>` and `Refs #30`; upstream's `NEWS` section; the conflicts and their resolutions, or "merged cleanly"; that no `verify/<n>.sh` is added because the existing `verify/*.sh` run as the regression suite, with the `# | Shot | Proves` table filled from CI's verify comment once it runs; the split-view crash check left to the owner; and any word in the narration Kokoro may mispronounce.

## 7. Follow CI

Subscribe to the PR's activity with `subscribe_pr_activity` and follow the rules in its first event. After each verify run, run `/visual-verify pr:<pr>` and post its comment, as `CLAUDE.md` says. Fix only failures the merge caused, following the Rules above. A failure that was already on `main` goes in the report, not in this PR.

## Report

End with one line: `none (…)`, `waiting: #<n> is open`, `skipped: #<n> was closed as not planned`, or `opened #<n> and PR #<pr> for <tag>`, then anything the owner must do in a "**What I need from you**" section.
