---
name: upstream-merge
description: The weekly upstream watcher (#30). Checks gitlab.xfce.org for a Thunar release tag newer than main's; when there is one, opens an issue for it and a PR that merges the tag into main, with its explainer. Run by the weekly scheduled task, or by hand as "/upstream-merge", or "/upstream-merge --test" for a test run against a fake next release.
---

# Upstream merge

Thunar's upstream tags each release as `thunar-<major>.<minor>.<n>` at `https://gitlab.xfce.org/xfce/thunar.git`. `main` is upstream's tree plus the fork's commits, so a new release comes in as one merge of its tag. CI then builds it, runs every `verify/*.sh` as a regression suite and reviews it, and the owner merges as usual.

One run handles at most one tag: the newest in `main`'s own series. A run that finds nothing new says so in one line and ends.

Below, `<upstream>` is `https://gitlab.xfce.org/xfce/thunar.git` (in a test run, the fake repo), `<base>` is `origin/main`, `<tag>` is the new tag (`thunar-4.20.11`), `<old>` is the base's release (`thunar-4.20.10`), `<n>` is the release's issue, and `<title>` is `Merge upstream <tag>`, or `[test] Merge upstream <tag>` in a test run. Write them out literally in every command: shell variables don't survive between commands.

## Rules

- Merge the git tag, never a release tarball.
- Never push to the `upstream` remote, `master` or `xfce-4.20`, and never push tags. Push only the release's branch.
- Never edit `debian/changelog` or the version: CI stamps `<new>-1~bpo24.04+local<N>` from `configure.ac`.
- Keep the merge's message `Merge upstream <tag>`: CI's review finds the release merge by it, suggests changes instead of committing them, and reviews only the fork's side (the conflict resolutions and the commits after the merge).
- Before every push after the first, `git pull --rebase=merges`, never a plain `--rebase`, which would flatten the merge.
- The PR goes into `main`. The owner merges it.

## Arguments

- none: the weekly run.
- `--test`: a test run, the same steps against a fake upstream. After step 1's `git fetch` and unshallow lines, `.claude/skills/upstream-merge/fake-upstream.sh <fake>` makes a local bare repo holding `main`'s release tag and a fake next tag, such as `thunar-4.20.11`: that release plus one commit that only raises `XDT_VERSION_INIT` and adds a `NEWS` entry. `<fake>` is `fake-upstream.git` in the session's scratch directory, or `/tmp` if it has none. That repo is `<upstream>`, and every step runs with `UPSTREAM=<upstream>` for `check.sh`. The PR then shows only that commit and the explainer, and CI builds and checks it. The issue and PR are titled with the `[test]` prefix, the PR is a draft so it can't be merged by mistake, and step 8 closes both.

## 1. Check

```sh
git fetch origin main
[[ $(git rev-parse --is-shallow-repository) == true ]] && git fetch --unshallow origin
UPSTREAM=<upstream> .claude/skills/upstream-merge/check.sh <base>
```

`check.sh` prints one line:
- `none (main has 4.20.10, newest upstream thunar-4.20.10)`: report that line and stop.
- `new thunar-4.20.11 (main has 4.20.10)`: go on, with `<tag>` = `thunar-4.20.11` and `<old>` = `thunar-4.20.10`.
- a non-zero exit: report the error and stop. `CONNECT tunnel failed, response 403` means `gitlab.xfce.org` is missing from the environment's allowed domains; say so.

A `; upstream also has thunar-4.22.0, a newer stable series` note is reported, never acted on: a new series needs new Xfce libraries from the PPA, which is the owner's decision.

Then fetch both releases, outside `refs/tags`:

```sh
git fetch --no-tags <upstream> "+refs/tags/<old>:refs/upstream-tags/<old>" "+refs/tags/<tag>:refs/upstream-tags/<tag>"
```

## 2. Already in hand?

```sh
gh api --paginate -X GET search/issues -f per_page=100 -f q='repo:alexhu98/thunar is:issue in:title "Merge upstream"' \
  --jq '.items[] | select(.title | test("^(\\[test\\] )?Merge upstream thunar-")) | "#\(.number) \(.state) \(.state_reason) \(.title)"'
gh api --paginate -X GET search/issues -f per_page=100 -f q='repo:alexhu98/thunar is:pull-request is:open in:title "Merge upstream"' \
  --jq '.items[] | select(.title | test("^(\\[test\\] )?Merge upstream thunar-")) | "#\(.number) \(.title)"'
```

Look only at titles of this run's kind, with `[test] ` in a test run and without it otherwise. A test run looks only at open ones:
- An open PR: report `waiting: PR #<pr> for <its tag> is in review` and stop.
- An open issue and no open PR: report `stuck: #<n> has no PR`, name its branch if `git ls-remote --heads origin '<n>-*'` shows one, and stop. A failed run left it; ask the owner under "What I need from you" to clear it, as "For the owner" below says. A run never takes over another run's issue or branch, so one release is in flight at a time.
- An issue titled `<title>` closed as not planned (weekly runs only): report `skipped: #<n> was closed as not planned` and stop.
- Otherwise go on: a new issue and branch for the release.

## 3. Open the issue

With the GitHub MCP `issue_write` tool, in `alexhu98/thunar`:
- Title: `<title>`.
- Body: the tag and its link, `https://gitlab.xfce.org/xfce/thunar/-/tags/<tag>` (in a test run, "a fake release from `fake-upstream.sh`" instead); the tag's section of upstream's `NEWS`, from `git show refs/upstream-tags/<tag>:NEWS`; `Refs #30`; and a Done-when list: merged with green checks, screenshots reviewed.

## 4. Merge

```sh
git checkout --no-track -b <n>-<tag> <base>          # e.g. 57-thunar-4.20.11 from origin/main
git merge --no-ff -m "Merge upstream <tag>" refs/upstream-tags/<tag>
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

Write `explainers/<n>-<tag>.html` and its stamped narration with the `explainer` skill, and commit them. Part 1 is what the release changes for the owner, from `NEWS` and `git log --oneline refs/upstream-tags/<old>..refs/upstream-tags/<tag>`, and what the merge did with each conflict. Part 2 is the checks run here: `check.sh`, the merge, the file-list diff, a build if there was one. CI's build, verify and review go under "Checked only after the merge" until they run. Part 3 is the next release, found by next week's run; in a test run, the rest of the test (step 8).

## 6. Push and open the PR

```sh
git push -u origin <n>-<tag>
```

With the GitHub MCP `create_pull_request` tool, from `<n>-<tag>` into `main`, as a draft in a test run:
- Title: `<title>`.
- Body: `Closes #<n>` and `Refs #30`; upstream's `NEWS` section; the conflicts and their resolutions, or "merged cleanly"; that no `verify/<n>.sh` is added because the existing `verify/*.sh` run as the regression suite, with the `# | Shot | Proves` table filled from CI's verify comment once it runs; and any word in the narration Kokoro may mispronounce.

## 7. Follow CI

Subscribe to the PR's activity with `subscribe_pr_activity` and follow the rules in its first event. After each verify run, run `/visual-verify pr:<pr>` and post its comment, as `CLAUDE.md` says. Fix only failures the merge caused, following the Rules above. A failure that was already on `main` goes in the report, not in this PR.

## 8. Close a test run

In a test run only, once CI has finished on the PR and step 7 is done: close the PR, close its issue as completed, delete its branch with `git push origin --delete <n>-<tag>`, and remove `<fake>` and `refs/upstream-tags/<tag>` (`git update-ref -d refs/upstream-tags/<tag>`), which names a release that doesn't exist yet.

## For the owner

- **Skip a release:** close its PR, then close its issue as *not planned*. Every later run reports it as skipped.
- **Clear a failed run:** close its issue as *completed*, the default, and delete its branch if the report named one. The next run starts the release again under a new issue.
- **Un-skip a release:** reopen its issue, then close it as *completed*.

## Report

End with one line: `none (…)`, `waiting: PR #<pr> …`, `stuck: #<n> has no PR`, `skipped: #<n> was closed as not planned`, `opened #<n> and PR #<pr> for <tag>`, or for a test run `test: PR #<pr> <its check results>, closed`, then anything the owner must do in a "**What I need from you**" section.
