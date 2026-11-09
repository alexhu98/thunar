---
name: explainer
description: Write the explainer page and its stamped narration that every issue PR in this repo carries (explainers/<issue>-<slug>.html and .narration.json), and render the narrated video locally. Use when opening or finishing an issue PR, when asked for "an explainer", "explainer with video" (page, then narration, then video), or "/explainer video <n>" (re-render the video, first re-narrating whatever changed on the page).
---

# Explainer

Every PR for issue `<n>`, from branch `<n>-<slug>`, adds `explainers/<n>-<slug>.html` and its narration `explainers/<n>-<slug>.narration.json`, stamped from the final page. The page is one self-contained page that tells the owner what the PR adds, how it was built and verified, and what comes later. CI fails the PR without either, or when the narration is stale, renders the page as a 1200px dark full-page PNG, and posts that image in the explainer PR comment, because GitHub shows HTML in a private repo as source. Write for the owner reading that image on a phone: plain words, no assumed context.

## Inputs to gather first

1. **The issue**: `gh issue view <n>`, including its comments. Its decisions are the "why"; its rollout list is what Part 2 must answer.
2. **The diff**: `git diff --stat origin/main...HEAD` and the diff itself. Every file in it appears in "Files in the PR".
3. **What was actually run**: commands, outputs, CI runs and review findings from this session. Part 2 is built only from these. If the session that built the PR is gone, use the PR's CI logs (`gh run view <id> --log`) and its description. Label each result with its source, e.g. "CI run 41529610568" or "the building session, per the PR description, not re-run here".
4. **What builds on it**: open issues whose body says "Depends on #<n>". `gh issue list --state open --search "<n>"` finds candidates, but the search drops the `#`, so read each body before including it. These issues become Part 3, in dependency order, as many as there are.

## The page

Start from `template.html` in this folder: copy it to `explainers/<n>-<slug>.html` and replace every `[placeholder]`. Keep its `<style>` block whole, adding rules only when a new element needs them. It already has the light and dark colour tokens, diagram and table styles, and `td.ok` / `td.open` / `td.no` result colours.

**Header** (`<header id="title">`): `<title>` "PR #<pr> <two-word name>", then `h1` "PR #<pr>: <what it does>", a one-line lead (branch → `main`, closes #<n>, what changes for the owner), and the three part links.

**Part 1: What this PR adds** (`section.part#adds`)
- A diagram of the flow or behaviour (inline SVG). Number the boxes with badges. The step-by-step list below it uses the same numbers and the same titles, so the reader can go back and forth. The template has two lanes: delete the second if there's one, or copy its pattern for a third. Each later lane's `ol.steps` carries `start` and `counter-reset: s <steps before it>`, so its numbers continue.
- "The big picture": why this exists, for someone new to the repo, plus a `.note` with the one fact that makes the rest make sense.
- "Step by step (numbers match the diagram)": one `li` per numbered box. Say what triggers it, what it does, and what it produces. Name the real file, job or command.
- Close-ups that help: cards (`.grid` fits 3 a row at 1200px, so use 2, 3 or 6), a short `pre` with `<span class="add">` around added lines for a key diff, or a table of cases.
- "Files in the PR": a `pre` tree of every changed file with a `#` note on each. Put a folder of copied or generated files on one line, e.g. `debian/  # 22 files from Zorin's packaging`, and list only the files that were edited by hand.
- Anything the owner must know to undo or recover, such as rollback, as a `.note`.

**Part 2: How it was built and verified** (`section.part#verified`)
- The reference it was checked against: the known-good thing(s) the work was compared with or derived from (cards).
- "What was checked": a table with Check | How | Result. "How" names the exact command or method and what it ran against. "Result" is what was measured (`1 of 1 pass`, `same`, `+local2`), not "OK".
- "Code review": the local fresh-agent review: after the last code change, a `general-purpose` agent given only the diff (`git diff origin/main...HEAD`) and the issue. Give its level, how many findings, how many were fixed, and the findings grouped in plain words. Then link the code review PR comment for CI's own review (see "CI review" below).
- "Checked only after the merge": what can't run before the merge, why, and when it first runs (`td.open`).
- "See it yourself": links to the PR, the CI runs and any outputs.

**Part 3: What comes later** (`section.part#later`)
- A diagram of the open issues that build on this one, in dependency order. Boxes built by this PR are green (`box-merge`), the owner's steps are `box-you`, and anything not built yet is dashed (`box-future`, `arrow-future`). Box colours can mean different things in different diagrams, so every diagram gets a legend saying what its colours mean.
- One `section.sub` per issue, with numbered steps saying what it adds and how it uses this PR. Mark which is next.

**Glossary** (`section.sub#glossary`, after Part 3): every term a newcomer would stumble on, one line each, as `<div data-k="…"><dt>…</dt><dd>…</dd></div>`.

## Page rules

- **Claim only what was run.** Every result in Part 2 comes from a command or check run in this session or by CI, and says which. Anything not run gets a row with `td.no` "not run" and the reason, or goes in "Checked only after the merge". Never write "verified", "tested" or "works" for something that wasn't run. If a check ran before later fixes, say so.
- Colours only through the `:root` tokens, and they must work in dark mode. CI renders the page with `--force-dark-mode`.
- No horizontal page scroll at a 390px viewport. Diagrams (`.diagram`), tables (`.table-wrap`) and `pre` scroll inside their own boxes. CI warns when the page is wider than 390px at that viewport.
- No external assets: no fonts, scripts, images or stylesheets from the network. Everything is inline.
- SVG text lines fit their box in CI's image, whose font (DejaVu Sans) is wider than the desktop's. In a 210px box, write at most about 22 characters per line, and at most 17 for a title beside a badge. Each box gets 3–4 lines. A local render can look fine and still overflow on GitHub, so read the CI image after the first push.
- Each SVG defines its own arrow markers with ids unique to the page (`ah-flow`, `ahf-next`, …). A marker defined in another diagram breaks when that diagram is hidden, which video mode does.

## Ids and keys (what the narration needs)

The template already follows these rules. Keep them when adding content:
- Each part is a `section.part` with an id (`adds`, `verified`, `later`) and keyed `label`, `heading` and `intro` children.
- Each subsection is a `section.sub` with a page-unique id.
- Every element a sentence would point at carries a `data-k` key that is unique within its `section.sub`: diagram boxes (`<g data-k="1">` wrapping the rect, its text and its badge), steps (`li`), cards, table rows (`tr`), notes, paragraphs, `pre` blocks, glossary entries. Matching things share keys across subsections, e.g. box `1` and step `1`.

## Check the page before committing

Render it the way CI does and look at the image: framing, dark mode, nothing cut off, every diagram readable, badges matching the steps.

```sh
OUT=/tmp/explainer .github/scripts/explainer-proof.sh render explainers/<n>-<slug>.html   # -> /tmp/explainer/explainer-<n>.png; works before it's committed
convert /tmp/explainer/explainer-<n>.png -crop 1200x1600 +repage /tmp/explainer/slice-%d.png   # the full image is too tall to read in one view
```

`DRY_RUN=1 GH_REPO=alexhu98/thunar PR=<pr> .github/scripts/explainer-proof.sh` also prints the explainer comment that CI would post.

## Narration (every PR)

Written and stamped in the session that builds the PR, from the final page. `status` and `stamp` need only Chrome, so they run in the cloud container and in CI. Only `phonemes` and `render` need Kokoro, which is on the owner's machine.

1. Write `explainers/<n>-<slug>.narration.json` from the page (format and rules below).
2. `make-video.py stamp <n>` records which page text each line was written from, and the page's SHA-256.
3. `make-video.py status <n>` must print "narration matches the page" and exit 0.
4. After any later page edit, including a review fix: run `status`, rewrite the stale lines and add lines for new text, then `stamp` again. Leave unchanged lines byte-for-byte as they are, so their cached voice clips are reused.
5. In the PR description, list any word you're unsure how Kokoro will say (names, abbreviations, numbers), so the owner checks it with `phonemes`.

CI's explainer job runs `make-video.py status` for the branch's issue and for every explainer page or narration the PR adds or changes, and for every narration when the PR changes `make-video.py`. It fails when a narration is missing, stale (page text changed after the stamp), names keys the page no longer has, or has a video mode problem that `render` would refuse (a highlighted element that can't be fully on screen, a zoom below 1, a caption over 2 lines), and reports each result in the explainer PR comment.

All commands are `.claude/skills/explainer/make-video.py <cmd> <n>`. Chrome comes from `$CHROME`, default `google-chrome`. In the cloud container, full Chromium hangs on `--dump-dom`; use the Playwright headless shell:

```sh
export CHROME=$(ls /opt/pw-browsers/chromium_headless_shell-*/chrome-headless-shell-linux64/chrome-headless-shell | head -1)
```

### Narration file

```json
{
  "title": "PR #10 · Explainer per PR",
  "voice": "af_heart",
  "lines": [
    {"screen": "title", "keys": [], "caption": "This is a tour of pull request 10, ..."},
    {"screen": "title", "keys": ["p1", "p2", "p3"], "caption": "It has three parts: ..."},
    {"screen": "adds", "keys": [], "caption": "Part 1. What this PR adds."},
    {"screen": "flow", "keys": ["2"], "caption": "The job renders the page at 1200 pixels.", "say": "The job renders the page at twelve hundred pixels."},
    {"screen": "steps", "keys": [], "from": ["3"], "caption": "..."}
  ]
}
```

- `screen` is what is shown: `title` (the header as a title card), a part id (a card with the part's label, heading and intro), or a `section.sub` id (that subsection, zoomed to fill the frame).
- `keys` are highlighted. Everything else keyed on that screen is dimmed, and a tall screen scrolls to the highlight. The zoom shrinks, below its usual 1.55 floor if needed, until the highlighted elements fit the frame and content wider than its column (a wide table) fits across. Use no keys only on short screens or card screens.
- `from` names the keys whose text the line narrates, if different from `keys`. With neither, the line is tied to the screen's heading. This is what `status` uses to find stale lines, so tie each line to what it actually says.
- `caption` is the on-screen text, exact as on the page (`v4.20.10+local2`, `explainer-proof.sh`). At most 2 lines at 1920×1080, about 140 characters. `render` refuses longer ones.
- `say` (optional) is the spoken text, respelled for the ear. Use it for numbers, versions and paths: "plus local two", "twelve hundred", "in the explainers folder". The pronunciation table below is applied after it.
- `src`, `page_sha256` and `page_text` are written by `stamp`. Don't edit them.

How to write the lines:
- Open on `title` ("This is a tour of pull request N, which …") and a line on the three parts. Each part opens with its card ("Part 1. What this PR adds."). End on `title` with a one-sentence wrap-up (that chapter is named Wrap-up).
- Follow the page in order. Give one line per numbered box or step, and make the diagram lines highlight the box they talk about.
- One sentence a line, under about 20 words, as spoken English rather than page text. Don't read paths, hashes or code aloud. Say what they are.
- Narrate Part 2 as plainly as the page: say what was run, and say what wasn't.
- The glossary isn't narrated.

## CI review

CI's `review` job reviews every push that changes more than `explainers/` and reports in the code review PR comment, the second of CI's four comments. The head commit's `Review:` trailer picks the mode:
- No trailer: auto-fix. Confirmed fixes come back as one `claude[bot]` commit, so `git pull --rebase` before pushing again.
- `Review: suggest`: suggested changes on the PR instead of a commit.
- `Review: auto-fix` or `Review: suggest` on an empty commit forces a re-review: `git commit --allow-empty -m "Re-review" --trailer "Review: auto-fix"`.
- `Review-accept: R23, R32` on any commit in the PR closes those findings as accepted, for findings kept on purpose.

A push that changes nothing but `explainers/` since the last reviewed commit, CI's own fix commit and a head that a newer push replaced skip the review; the next code push's review covers them. The job fails while confirmed medium or high findings stay unresolved; low ones are reported without failing it.

## Video (local only, never in CI)

Output `explainers/<n>-<slug>.mp4` (ignored by git). Needs Kokoro, so it runs on the owner's machine.

### "explainer with video"
1. Write the page, the narration and stamp it, as above.
2. `make-video.py phonemes <n>`: read the phonemes of every new line and fix the respellings (in `say`, or in the table below) until each word sounds right.
3. `make-video.py render <n>`, then audit the frames (below). The next `videos-all.sh` run replaces this video with the gallery's unless it runs with `--no-copy`.

### "/explainer video <n>"
1. `make-video.py status <n>` lists the stale lines (their page text changed), any changed page text that no line narrates, keys that no longer exist, and video mode problems.
2. Rewrite only those lines and add lines for new text that should be narrated. Leave every other line byte-for-byte unchanged, so its cached voice clip is reused.
3. Run `stamp`, `phonemes` and `render` as above. `render` refuses to run while the narration is older than the page, and it reports how many clips were newly voiced. That count should equal the number of lines you changed.

The script re-runs itself under the Kokoro venv. Voice clips are cached by spoken text in `~/.cache/explainer-video/clips/`, and work files go in `~/.cache/explainer-video/<n>-<slug>/`, including `frames/` and `timeline.json` with each line's start and speech time in samples.

### Every video at once: `videos-all.sh`

`.claude/skills/explainer/videos-all.sh` renders the video of every narrated explainer on `main` and on every `<digits>-<slug>` branch into one gallery folder, by default `~/thunar-explainers`. Run it on the owner's machine, never in CI:

```sh
.claude/skills/explainer/videos-all.sh                 # every page
.claude/skills/explainer/videos-all.sh --only 25       # one explainer
.claude/skills/explainer/videos-all.sh --branch 25-narration-videos
.claude/skills/explainer/videos-all.sh --open-prs      # only branches with an open PR (needs gh)
.claude/skills/explainer/videos-all.sh --dry-run       # report what it would render, render nothing, copy nothing
.claude/skills/explainer/videos-all.sh --no-copy       # leave the checkout's explainers/ alone
```

1. `git fetch origin --prune`.
2. Keeps the gallery as a git worktree detached at `origin/main`, so `make-video.py` and the pronunciation table are current. The script never resets or checks out the owner's own checkout (step 5 only copies videos into its `explainers/`): it only resets a worktree it created itself (it leaves a marker in that worktree's git dir), and it refuses a new gallery inside the checkout. `--gallery <dir>` picks another folder, relative to where you run it.
3. Copies `explainers/*.html` and `*.narration.json` from `origin/main` and each branch with `git show`, without a checkout. A branch provides the explainer files it changed since it left `main`, in a version `main` has never had (so a branch merged by squash and never deleted provides nothing); each issue's page and narration come from one ref. The issue's own `<n>-<slug>` branch wins over other branches. Two `<n>-<slug>` branches for one issue, or two other branches and no own one, are reported as a conflict, and that issue is not rendered. Use `--open-prs` so merged branches that were never deleted are left out. `SOURCES.tsv` lists each page with its branch and commit.
4. Decides per page by content hash, never timestamps: no narration → "needs narration"; `<stem>.mp4` exists and the page and narration hashes, and the hash of `make-video.py` with the pronunciation table, equal those in `<stem>.mp4.sha` from the last render → "skipped", without running `status`; `make-video.py status` fails → "needs re-narration"; otherwise `make-video.py render`, then the new hashes are written. With `$CHROME` unset, `status` uses the newest Playwright headless shell in `${PLAYWRIGHT_BROWSERS_PATH:-~/.cache/ms-playwright}`, else `google-chrome`, and retries with `google-chrome` when `make-video.py` stops with an error on the shell; when that retry passes, `google-chrome` checks the rest of the run; `render` always uses `google-chrome`.
5. Copies each skipped or rendered `<stem>.mp4` into the checkout's `explainers/` when it differs from the copy there, unless `--no-copy` or `--dry-run`. The gallery's video replaces any other one there, including one rendered directly in the checkout. The copy is the gallery's version of the page, so it doesn't reflect an uncommitted or unpushed page edit in the checkout.
6. Prints a table of page, branch, commit, result (rendered, skipped, needs narration, needs re-narration, conflict, failed; "would render" under `--dry-run`; "a narration but no page"; and with `--branch`, one row with page `-` when that branch provides nothing to decide) and copied (`yes`, `-` or `failed`), also saved as `REPORT.tsv`, and the folder the videos were copied to when any were. Exits non-zero if any render or copy failed.

### Pronunciation

Applied to every spoken line, in order, as regular expressions. Add a row whenever the owner corrects a word. Before adding one, check the word with `make-video.py phonemes` on the owner's machine; in the cloud container, which has no Kokoro, list the word in the PR description instead.

<!-- say:start -->
| Pattern | Say |
|---|---|
| `\bThunar\b` | `Thoonar` |
| `\bCI\b` | `C I` |
| `\bPRs\b` | `pull requests` |
| `\bPPA\b` | `P P A` |
| `\.debs\b` | `debs` |
| `\.deb\b` | `deb` |
| `\bSHA\b` | `S H A` |
| `\bCLAUDE\.md\b` | `Claude dot M D` |
| `\b1200px\b` | `twelve hundred pixel` |
| `\b1200\b` | `twelve hundred` |
| `\b1920×1080\b` | `nineteen twenty by ten eighty` |
<!-- say:end -->

Version numbers go in words in `say`: "Ubuntu twenty-four oh four", "four point twenty point ten".

### Audit the video

Before handing a video over, look at frames from it:
- the title card
- each part card
- a diagram line, checking that the highlight lands on the right box
- a table row
- the last frame

In each one, check that the right screen is showing, the highlight is right, the caption fits in at most 2 lines and doesn't cover the content, and the page is in dark mode. Also check these:
- `render`'s report shows picture and sound lengths within one frame (33 ms), and the chapter list
- `ffprobe -show_chapters` lists the chapters
- at one line boundary from `timeline.json`, the caption changes in the silence before that line's speech starts
- `git diff --exit-code explainers/<n>-<slug>.html`: the committed page is unchanged
