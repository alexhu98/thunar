# /visual-verify: usage

A visual acceptance gate. It audits Thunar screenshots for **content correctness** against each shot's stated intent, and returns a machine-checkable verdict.

- **What it answers:** "do the screenshots show what they claim?"
- **What it doesn't answer:** whether the feature's assertions passed. CI's `verify` job answers that (see the repo `CLAUDE.md`). A green job proves the script's checks, not the pictures: a frame captured before Thunar drew its view passes every title check and still shows nothing.

## Where the shots and intents come from

`.github/scripts/verify-proof.sh run` writes a manifest, `verify.tsv`, next to the shots. CI's `verify` job commits the same manifest to the `shots` branch as `pr-<n>/verify.tsv`, beside `pr-<n>/verify-<test>-<shot>.png`. It has one row per shot:

```
sha            test   result  shot           file                         proves
4f0c…          smoke  pass    window         verify-smoke-window.png      Thunar is still running 10 s after launch, with its window open on a folder of 2 folders and a file
4f0c…          3      pass    before-parent  verify-3-before-parent.png   The child folder is open, with the Up button enabled
4f0c…          3      pass    after-parent   verify-3-after-parent.png    A double-click on empty space opened the parent folder
```

`proves` is the sentence the script passed to `shot`. It is the intent the auditor checks, so write it as the state to confirm ("the parent folder is open"), not as the action ("double-clicked"). A test that saved no shot has `-` in shot, file and proves.

## Usage

Audit CI's shots for a PR (needs only git):

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
shot           | intent                              | verdict | observed
smoke/window   | Thunar running 10 s after launch    | OK      | window on work/: Documents, Pictures, notes.txt; status bar "2 folders | 1 file"
3/before-parent| child folder open, Up enabled       | OK      | path bar …/parent/child/, Up arrow active
3/after-parent | parent folder opened                | OK      | path bar …/parent/, child folder icon shown
Visible changes, before to after
parent | before: child folder's contents | after: parent folder with child | intended
VERDICT: PASS
```

## Verdict contract

| Verdict | Meaning | Caller action |
|---|---|---|
| `PASS` | every shot is present and OK, every test passed | the shots may be posted or presented as proof |
| `FAIL` | a shot is BLANK, MISMATCH or MISSING | fix the capture or the code, run again |
| `FAIL (test: …)` | the shots are OK but a test's assertions failed | fix the code or the test |
| `INCONCLUSIVE (cause)` | no trustworthy audit was possible (no manifest, stale shots, capture errored) | surface the cause, hand to the owner; never present the shots as proof |

- **BLANK** means one colour, a view still loading, or the target out of frame. **MISMATCH** means the wrong state, or an after shot identical to its before shot. **MISSING** means no file.
- The final line is always `VERDICT: PASS|FAIL|INCONCLUSIVE[ (cause)]`.

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
```

- **Assert before you shoot.** Wait for the state (`wait_title`, a file on disk, `xdotool search` for a dialog) before calling `shot`. `shot` waits 1 s more for the view to draw.
- **Send input to a focused window.** `xdotool key`, `type` and `click` with `--window` send synthetic events that GTK ignores. Call `focus "$WID"` first and send them without `--window`. `mousemove --window` is fine, because it only positions the pointer.
- **Capture popups from the root window.** Menus, tooltips and some dialogs are separate X windows. `shot "$WID"` misses them, so use `shot root <name> "<proves>"`.
- **Keep pairs comparable.** Shoot `before-<what>` and `after-<what>` of the same window at the same size, so the only difference is the one the intent names.
- **Stay in `$WORK`.** Create every file the test needs there. `HOME` and the XDG folders are fresh for each script, and nothing from the owner's desktop exists. `open_thunar` again in the same script opens another window of the same Thunar, as a second `thunar` call does.
- **Exit non-zero on failure.** `fail "<what was wrong>"` prints the reason, which CI shows in the PR comment under the test.
