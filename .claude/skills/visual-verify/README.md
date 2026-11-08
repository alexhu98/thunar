# /visual-verify: usage

A visual acceptance gate. It audits Thunar screenshots for **content correctness** against each shot's stated intent, and returns a machine-checkable verdict.

- **What it answers:** "do the screenshots show what they claim?"
- **What it doesn't answer:** whether the feature's assertions passed. CI's `verify` job answers that (see the repo `CLAUDE.md`). A green job proves the script's checks, not the pictures: a frame captured before Thunar drew its view passes every title check and still shows nothing.

## Where the shots and intents come from

`.github/scripts/verify-proof.sh run` writes a manifest, `verify.tsv`, next to the shots. CI's `verify` job commits the same manifest to the `shots` branch as `pr-<n>/verify.tsv`, beside `pr-<n>/verify-<test>-<shot>.png` and each pair's side-by-side image for the PR comments, `pr-<n>/pair-<test>-<what>.png`. The audit reads the originals. The manifest has one row per shot, and `num` is the shot's number in the PR comments, shared by both shots of a pair (the smoke test comes last):

```
sha    num  test   result  shot           file                         proves
4f0c…  1    3      pass    before-parent  verify-3-before-parent.png   The child folder is open, with the Up button enabled
4f0c…  1    3      pass    after-parent   verify-3-after-parent.png    A double-click on empty space opened the parent folder
4f0c…  2    smoke  pass    window         verify-smoke-window.png      Thunar is still running 10 s after launch, with its window open on a folder of 2 folders and a file
```

`proves` is the sentence the script passed to `shot`. A shot whose upload failed has `-` as its file. It is the intent the auditor checks, so write it as the state to confirm ("the parent folder is open"), not as the action ("double-clicked"). A test that saved no shot has `-` in num, shot, file and proves.

## Usage

Audit CI's shots for a PR (needs git, plus a `pr-digest` digest of the PR's checks):

```
/visual-verify pr:42
```

Audit a local run, or run it first (sandbox only, with the built debs installed):

```
/visual-verify /tmp/verify-proof
/visual-verify run:
```

Add the issue's acceptance as extra intents, or diff against an older run (report-only):

```
/visual-verify pr:42 "after-parent must also show the parent folder selected in the side pane"
/visual-verify pr:42 baseline:pr:42@<older shots commit>
```

The output is the table, the mandatory `Visible changes, before to after` section and a sentinel:

```
# | shot            | intent                              | verdict | observed
1 | 3/before-parent | child folder open, Up enabled       | OK      | path bar …/parent/child/, Up arrow active
1 | 3/after-parent  | parent folder opened                | OK      | path bar …/parent/, child folder icon shown
2 | smoke/window    | Thunar running 10 s after launch    | OK      | window on work/: Documents, Pictures, notes.txt; status bar "2 folders | 1 file"
Visible changes, before to after
#1 parent | before: child folder's contents | after: parent folder with child | intended
VERDICT: PASS
```

On a PR, post that output as a comment whose first line is `<!-- visual-verify <the manifest's sha> -->`. CI's summary comment picks up the latest verdict posted for the PR's head.

## Verdict contract

| Verdict | Meaning | Caller action |
|---|---|---|
| `PASS` | every shot is present and OK, every test passed | the shots may be posted or presented as proof |
| `FAIL` | a shot is BLANK, MISMATCH or MISSING | fix the capture or the code, run again |
| `FAIL (test: …)` | the shots are OK but a test's assertions failed | fix the code or the test |
| `NOT NEEDED (…)` | `pr:<n>` only: build and verify ran `No code changed`, so CI took no shots | post nothing; `CLAUDE.md`'s merge rule needs no verdict for that head |
| `NOT YET (…)` | `pr:<n>` only: build or verify hasn't finished for the head | post nothing; run again after CI's next event |
| `INCONCLUSIVE (cause)` | no trustworthy audit was possible (no manifest, stale shots, capture errored) | surface the cause, hand to the owner; never present the shots as proof |

- **BLANK** means one colour, a view still loading, or the target out of frame. **MISMATCH** means the wrong state, or an after shot identical to its before shot. **MISSING** means no file.
- The final line is always `VERDICT: PASS|FAIL|INCONCLUSIVE|NOT NEEDED|NOT YET[ (cause)]`.

## Writing `verify/<issue>.sh` so audits pass

The helpers are in `.github/scripts/verify-lib.sh`. A minimal script:

```bash
#!/bin/bash
set -euo pipefail
. .github/scripts/verify-lib.sh

mkdir -p "$WORK/parent/child"
open_thunar "$WORK/parent/child"
wait_title "$WID" child
shot "$WID" before-parent "The child folder is open"

focus "$WID"
xdotool mousemove --window "$WID" 400 300 click --repeat 2 1
wait_title "$WID" parent
shot "$WID" after-parent "A double-click on empty space opened the parent folder"
pair parent "Double-clicked empty space in the view" "A double-click on empty space opens the parent folder" \
  "child folder open" "parent folder open" "Going up"
```

- **Assert before you shoot.** Wait for the state (`wait_title`, a file on disk, `xdotool search` for a dialog) before calling `shot`. `shot` waits 1 s more for the view to draw.
- **Send input to a focused window.** `xdotool key`, `type` and `click` with `--window` send synthetic events that GTK ignores. Call `focus "$WID"` first and send them without `--window`. `mousemove --window` is fine, because it only positions the pointer.
- **Capture popups from the root window.** Menus, tooltips and some dialogs are separate X windows. `shot "$WID"` misses them, so use `shot root <name> "<proves>"`.
- **Describe every pair.** `pair <what> ACTION PROVES BEFORE-STATE AFTER-STATE [GROUP]` gives the pair's Action (what the test did between the two shots), what the pair proves, the short states (at most 48 characters) on its image's BEFORE and AFTER bars, and the heading it's grouped under in the verify comment. A test that passes with a pair that has no `pair` call fails.
- **Keep pairs comparable.** Shoot `before-<what>` and `after-<what>` of the same window at the same size, so the only difference is the one the intent names.
- **Stay in `$WORK`.** Create every file the test needs there. Each script gets its own Xvfb, `HOME` and XDG folders, and nothing from the owner's desktop exists. `open_thunar` again in the same script opens another window of the same Thunar, as a second `thunar` call does.
- **Exit non-zero on failure.** `fail "<what was wrong>"` prints the reason, which CI shows in the verify comment under the test.
