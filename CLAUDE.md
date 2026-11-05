# Thunar (alexhu98 fork)

## Branches and PRs
- Work on a branch named `<issue>-<short-slug>` and open the PR into `main`, the default branch. Put `Closes #<issue>` in the PR description, or `Refs #<issue>` when the PR does only part of the issue.
- Never push to the `upstream` remote. Never touch `master` or `xfce-4.20`: they mirror upstream.
- The owner merges, and only when the build and verify jobs are green and the screenshots are reviewed.

## Building
- Build from git with `--enable-maintainer-mode`, as `debian/rules` does: `sudo add-apt-repository -y ppa:zorinos/stable` (Xfce 4.20 libraries), `sudo apt-get build-dep -y ./`, then `dpkg-buildpackage -b -us -uc`.
- Never build from the release tarball. Its pre-generated gdbus files need GLib 2.84, and Ubuntu 24.04 (noble) has 2.80. A git build regenerates them.
- Never run `apt-get update` limited to one source list (`-o Dir::Etc::sourcelist=…`). It deletes the other sources' package lists, so the next install finds nothing from noble.

## Verify
- Every feature PR adds `verify/<issue>.sh`, and its description says what each screenshot proves.
- CI's `verify` job runs after the build on every PR. It installs the built `thunar`, `thunar-data` and `libthunarx-3-0` debs and starts Xvfb. It runs the smoke test (Thunar is still running 10 s after launch), then each `verify/*.sh`. It commits the screenshots to the orphan `shots` branch under `pr-<n>/` and posts them with the results in the PR comment's verify section. That comment is CI's proof, not the agent's report.
- A `verify/<issue>.sh` runs from the repo root with `bash`, in its own D-Bus session with xfwm4, a fresh `HOME` and its own XDG folders, for at most 300 s. It sources `.github/scripts/verify-lib.sh` (`open_thunar`, `focus`, `wait_title`, `shot`, `fail`). It drives Thunar with `xdotool`, asserts the result (window title, `xdotool` window queries, files on disk) and exits non-zero on failure. It creates its files in `$WORK`, and `shot` saves PNGs to `$SHOTS`. Name a before/after pair `before-<what>` and `after-<what>`. Every `shot` states what it proves.
- `xdotool key` and `type` with `--window` send synthetic events that GTK ignores. Call `focus "$WID"` and send them without `--window`.
- To run the tests in a sandbox, as CI does: build, `mkdir -p dist && mv ../*.deb dist/`, then `.github/scripts/verify-proof.sh install` and `.github/scripts/verify-proof.sh run`. Shots, logs and the manifest `verify.tsv` land in `$OUT`, by default `${TMPDIR:-/tmp}/verify-proof/`. `install` replaces the system's Thunar, so never run it on the owner's machine. If the sandbox can't run Xvfb, write the script anyway: CI runs it.
- The split-view crash regression test only reproduces in the owner's real session, not under Xvfb. It stays a manual check after an update.

## Explainers
- Every issue PR adds `explainers/<issue>-<slug>.html`, named after its `<issue>-<slug>` branch and written with the `explainer` skill (`.claude/skills/explainer/`). Not in `docs/`, which belongs to upstream. CI fails the PR without it and renders it into the PR comment. PRs from forks skip that job, so they aren't checked.

## CI review
- CI reviews every code push to a PR and, by default, pushes its fixes as a `claude[bot]` commit. Run `git pull --rebase` before every push to a PR branch. A head commit with the trailer `Review: suggest` gets suggested changes instead of a fix commit; `Review: auto-fix` or `Review: suggest` on an empty commit forces a re-review. A `Review-accept: R23, R32` trailer on any commit in the PR closes those findings as accepted, so they stop failing the job. Re-running the `review-report` job alone after a successful review isn't supported and has no guards: it can report a pushed fix as not pushed and post suggestions twice.

## Code comments and screenshots
- Don't add new explanatory code comments, in fixes and reviews too; when a change makes a comment stale, update it.
- Audit every screenshot before posting it or presenting it: run `/visual-verify` (`.claude/skills/visual-verify/`) on the captures, and fix the capture until it passes. CI posts its verify screenshots by itself, so after each CI run audit them from the `shots` branch (`/visual-verify pr:<n>`) and say in the PR what the audit found.
