---
name: visual-verify
description: Visual acceptance gate for Thunar screenshots. Audits the shots from verify/<issue>.sh and the smoke test, locally or CI's from the shots branch, against each shot's stated intent and returns a machine-checkable verdict (PASS / FAIL / INCONCLUSIVE, or for `pr:<n>` the unposted NOT NEEDED / NOT YET). Can run the capture first. Use before posting or presenting any screenshot, and after each CI verify run on a PR that took shots (not one whose build and verify ran `No code changed`). See README.md in this folder for usage and for writing verify scripts that pass.
---

## /visual-verify

Independently audits Thunar screenshots for **content correctness** against each shot's declared intent, and returns a verdict other automation can branch on. It answers **"do the screenshots show what they claim"**. CI's `verify` job answers "did the scripts' assertions pass"; a green job doesn't prove the pictures are right.

The audit MUST run in the **independent `shot-audit` skill** (Step 3). That skill is a forked, read-only subagent bound to the `shot-auditor` agent. Independence is the enforcement: an inline self-check only re-confirms what the author already assumed was on screen, and an outside reader catches blanks and wrong-state frames it can't. Never hand-roll the audit inline, and never spawn a generic subagent for it: a generic agent carries Edit/Write and has no auditing prompt.

### Arguments (`$ARGUMENTS`)

Free-form tokens. Resolve what is present, and ask only if a required input is missing and can't be inferred.

- **Shots**, one of these (required):
  - `pr:<n>`: CI's original shots for PR `<n>` (not the side-by-side `pair-*.png` images made for the PR comments), from the `shots` branch: `git fetch origin +refs/heads/shots:refs/remotes/origin/shots` (a plain `git fetch origin shots` updates only `FETCH_HEAD` in a single-branch clone), then `git show origin/shots:pr-<n>/verify.tsv` and each listed `pr-<n>/<file>`, written into a new scratch directory. Needs git, plus Step 0's `pr-digest` digest of the PR's checks; it works where `gh` and Xvfb don't.
  - a local directory holding `verify.tsv`, as `.github/scripts/verify-proof.sh run` writes it (`$OUT`, by default `${TMPDIR:-/tmp}/verify-proof/`).
- **Intents**: the manifest's `proves` column, written by each `shot` call. Its `num` column is the shot's number in CI's PR comments: both shots of a pair share one. The caller may add intents inline, for example from the issue's acceptance criteria. Inline intents are added to the manifest's, never replace them.
- **`run:`** *(optional)*: run `.github/scripts/verify-proof.sh run` first, then audit its `$OUT`. Only in a sandbox where the built debs are installed (see the repo `CLAUDE.md`).
- **`baseline:<dir or pr:<n>@<sha>>`** *(optional)*: older shots for an old-vs-new diff (report-only). `pr:<n>@<sha>` reads `pr-<n>/` from the `shots` commit `<sha>`.

### Step 0: no shots to audit (`pr:<n>` only)

Before the preflight, check whether the PR's head ran `No code changed` in both build and verify. Read it from the `checks:` line of a `pr-digest` digest whose `head` is the PR's current head (`git ls-remote origin refs/pull/<n>/head`): the caller's if it has one, otherwise a new one (`Agent(pr-digest, "<n>")`). `CLAUDE.md` routes every read of the PR's checks through `pr-digest`, so the skill doesn't list the jobs itself.

- Both build and verify show `No code changed`: stop with `VERDICT: NOT NEEDED (build and verify ran No code changed)`.
- Build or verify is `running` (queued or in progress): stop with `VERDICT: NOT YET (build or verify hasn't finished)`. The caller runs the skill again when CI's next event for the head arrives. Don't go on to Step 1, where a missing or older manifest would read as INCONCLUSIVE.
- Anything else, `missing` included: go on to Step 1. Key this check on the `No code changed` step only, never on a missing or stale manifest, so a verify run that skipped its steps by mistake still ends INCONCLUSIVE there.

`NOT NEEDED` and `NOT YET` are never posted as a PR comment.

### Step 1: preflight (guards the INCONCLUSIVE outcome)

Before reading any image, check that the run can produce a trustworthy verdict. **Any failure here is INCONCLUSIVE with the cause named; stop. Never FAIL for a runtime problem, and never pass silently.**

- `run:`: `Xvfb`, `xdotool`, `import` and `xfwm4` exist, and `dpkg -s thunar` shows the version built from this branch. If not, the verdict is INCONCLUSIVE("sandbox can't run the capture"); rely on CI's shots instead (`pr:<n>`).
- The manifest exists and has at least one row. If none, the verdict is INCONCLUSIVE("no verify.tsv").
- Every row has a `proves` sentence, except rows with shot `-`, which are tests that saved no shot. A row with a shot but file `-` lost its upload: list it as a required shot, so the auditor reports it MISSING.
- `pr:<n>`: the manifest's `sha` is the PR's head commit (`git ls-remote origin refs/pull/<n>/head`, or the branch head). If not, the verdict is INCONCLUSIVE("shots are for <sha>, the PR head is <sha>"), because CI may still be running.
- If the capture itself errored (Xvfb didn't start, a script timed out before its first shot), the verdict is INCONCLUSIVE.

### Step 2: optional capture

With `run:`, run the capture through the `build-verify` agent (`.claude/agents/build-verify.md`) with `only run`. It runs `.github/scripts/verify-proof.sh run > <log> 2>&1; echo "exit=$?"` and returns its exit code and the log's `grep -n -E ' in [0-9]+ s$|: (not run|misnamed)|^  \||passed$'` lines: each test's result line, and each failing test's last 30 log lines. A session started before that agent existed runs a `general-purpose` agent told to read that file and follow it. Never read the whole log, and **never pipe the command into `tail`**, because that masks the exit code. If a script fails its own assertions, that is a test failure, not a runtime problem: keep going and let Step 4 report it.

### Step 3: independent audit skill

Invoke `Skill(shot-audit, "<the audit request>")`. The request carries the shots directory, the required-shots list (each entry: its `num`, file relative to the directory, its intent, the element and state to confirm, and its pair partner if it is `before-*` or `after-*`), and the `baseline:` directory if given. The skill forks into the read-only `shot-auditor` agent, which Reads every PNG and returns a table:

```
# | shot | intent | verdict (OK / BLANK / MISMATCH / MISSING) | observed (1 line)
```

The skill returns the table only; this command reduces it in Step 4. **A missing, empty or unparseable table is INCONCLUSIVE, never PASS.** If `shot-audit` returns nothing, name that as the cause and stop. Don't fall back to auditing the PNGs inline, which is exactly the self-check this step exists to replace.

### Step 4: verdict and output

Reduce the table to one verdict and print it, ending with a parseable sentinel line:

- **PASS**: every required shot is OK, and every test in the manifest has `result` `pass`. Sentinel: `VERDICT: PASS`.
- **FAIL**: any required shot is BLANK, MISMATCH or MISSING. Sentinel: `VERDICT: FAIL`.
- **FAIL (test)**: every shot is OK, but a test's `result` is not `pass`. A failed assertion is never a visual pass. Sentinel: `VERDICT: FAIL (test: <test> <result>[, …])`.
- **INCONCLUSIVE**: preflight or capture couldn't yield a trustworthy audit. Sentinel: `VERDICT: INCONCLUSIVE (<cause>)`.

Always print the full table above the sentinel, so a human can see why.

**Visible changes, before to after (mandatory).** Between the table and the sentinel, always print a `Visible changes, before to after` heading. A pair whose shots match their intents can still contain a change nobody wanted, because the intent can be wrong. Print one line per `before-<what>` / `after-<what>` pair: `#<num> <what> | before: <what it showed> | after: <what it shows> | intended / not in the intent`. Build each line from the auditor's two `observed` cells, never from the intents alone. List intended changes too. If a pair shows no change, say `none`. If there are no pairs, print `no before/after pairs`. This section never changes the verdict and is printed for PASS and FAIL alike.

Advisory output, such as a `baseline:` diff or extra states, is reported but never changes the verdict.

### Contract for callers

- The final line is `VERDICT: PASS|FAIL|INCONCLUSIVE|NOT NEEDED|NOT YET[ (cause)]`, which callers parse. `NOT NEEDED` and `NOT YET` come only from Step 0 and are never posted; `CLAUDE.md`'s merge rule needs no verdict for a head whose build and verify ran `No code changed`.
- On a PR, post the table, the visible-changes section and the verdict as a PR comment whose first line is `<!-- visual-verify <the manifest's sha> -->`, for the owner to review before merging. CI's summary comment shows the latest verdict posted for the PR's head as its Screenshot audit row, and "not run yet" until there is one.
- **PASS**: the screenshots may be posted or presented as proof. **FAIL**: fix the capture or the code and run again. **INCONCLUSIVE**: surface the cause and hand to the owner. Never present a shot as proof on anything but PASS.
