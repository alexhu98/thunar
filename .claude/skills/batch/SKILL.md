---
name: batch
description: Orchestrates several issues as grouped PRs, one fresh cloud session per group, from a small orchestrator session that never reads PR noise. Plans the groups for the owner to confirm, tracks them in one issue, starts each group's session with a fixed brief, checks on them cheaply and stops when they're merged. Run as "/batch <issue numbers or range> [stop after <group>]", e.g. "/batch 48 52-60".
---

# Batch

One session that implements several issues fills its context with PR noise: GitHub notifications, CI comments, review rounds. `/batch` keeps that noise out. This session, the orchestrator, plans and tracks; each group of issues gets its own fresh child session, which builds, reviews and merges its PR under `CLAUDE.md` and reports back in one line. The orchestrator keeps only each child's status, the way `/visual-verify` keeps only `shot-audit`'s verdict.

Below, `<parent>` is this session's ID (`get_session` with no `session_id`), `<t>` the tracking issue, and each group has a letter (`A`, `B`, …), its issues `#<a>, #<b>`, its first issue `<a>` and its branch `<a>-<slug>`. Write them out literally in every call.

## Rules

- The orchestrator never subscribes to a PR, never reads CI's PR comments or checks, never runs `pr-digest`, and never commits, pushes, reviews or merges. Each child does all of that for its own PR.
- It checks a child only with `get_session` (`status_bucket`) and one search for its PR's state (step 4), which returns four fields and no PR body.
- Groups run one at a time, in the plan's order. Two groups run at once only when the confirmed plan says they touch disjoint files and don't depend on each other.
- A child's question goes to the owner once, with the child's session named, and the owner answers in that child's session. An approval relayed from another session may be refused by the child's permission check (for example a `CLAUDE.md` edit), so the orchestrator doesn't relay answers unless the owner asks it to.
- Never start an issue the plan doesn't list, and never start any group before the owner has confirmed the plan.

## Arguments

- Issue numbers and ranges: `48 52-60`, `#56 #66`. Issues and PRs share numbers, so skip numbers that are PRs (`issue_read` shows `pull_request`) and closed issues, and say which.
- `stop after <group>` (optional): the stop point. The owner can also give it when confirming the plan.
- `check-in #<t>`: a check-in (step 4), not a new batch. Read the tracking issue `#<t>` (`issue_read get`, the body only) to rebuild the whole state (every row and the `Check-in:` line), then go straight to step 4.

## 1. Plan

Read each open issue (`issue_read get`) and its comments where the body points to them. For each, note the files it would touch, the issues it says it depends on (`after #52`, `Depends on #`), and whether it changes Thunar's code (a `verify/<n>.sh` and screenshots) or only CI, skills and docs.

Group them: issues that touch the same files or depend on each other go in one group, or in consecutive groups in dependency order. Keep a group to one PR a reviewer can follow, usually one to three issues. Print one table:

```
Group | Issues   | Branch          | Touches                         | After | Code?
A     | #52 #53  | 52-review-skip  | .github/workflows/review.yml    | -     | no
B     | #56 #66  | 56-fewer-jobs   | .github/workflows/*, scripts/   | A     | no
```

Under it: how many PRs that is (each runs CI's build, verify, review and explainer jobs, so it costs CI minutes), which groups could run in parallel, and any issue left out and why. Then end the turn with one "**What I need from you**" question, in `CLAUDE.md`'s format, such as: `1. Run the plan as shown (recommended) 2. Stop after group A 3. Change the groups (say how)`. Don't go on until the owner answers.

## 2. Track

Open the tracking issue with `issue_write` in `alexhu98/thunar`:
- Title: `Batch: #<a>, #<b>, …` (every issue in the plan).
- Body: the confirmed table, then one checklist row per group, the stop point if there is one, `Orchestrator: <parent>` and `Check-in: -`.

A row holds everything a check-in needs: `- [ ] A: #52 #53 | branch 52-review-skip | session - | started - | PR - | seen - | told - | notes: <the group's brief notes, or ->`. `started` is when its session was created (for the report), `seen` the PR's `updated_at` at the last check-in, and `told` the last condition the owner was told about (step 4). A ticked row is merged; an unticked row with session `-` hasn't started. `Check-in:` holds the pending check-in's `trigger_id`, or `-`.

The body is the batch's state. Update it with `issue_write update` whenever a row changes. A check-in that has lost the conversation rebuilds from it.

## 3. Run

For each group in order, start its child with `create_session`, with `source_url` `https://github.com/alexhu98/thunar`, a `title` of `Batch <t> group A: #52 #53`, and this brief as the `prompt`, filled in for the group:

> Implement GitHub issues #<a> and #<b> of alexhu98/thunar together in one PR. Read the issues and CLAUDE.md first, and follow CLAUDE.md fully, including the pr-digest agent and the review-loop rules. Ignore the claude/… branch this session is assigned. Create branch `<a>-<slug>` from `origin/main`, push from it, and open the PR into main with `Closes #<a>` and `Closes #<b>` (or `Refs` for an issue it does only part of). Add `explainers/<a>-<slug>.html` with the explainer skill, and a stamped narration (`make-video.py stamp <a>`, with CHROME set to the Playwright headless shell). Add `verify/<a>.sh` only if the change touches Thunar's code. Before pushing, run a local fresh-agent review of the diff and fix what it finds. After each CI run that took shots, run `/visual-verify pr:<n>` and post its comment, as CLAUDE.md says. If build and verify ran `No code changed`, follow CLAUDE.md's rule for that. Squash-merge your PR yourself when the CLAUDE.md merge rule allows it, and ask the owner in the cases where it says the agent doesn't merge. If the change needs a CLAUDE.md edit, the permission check may refuse an approval relayed from another session: ask the owner directly in this session in CLAUDE.md's "What I need from you" format, and tell your parent session it's blocked. When blocked on the owner for anything else, ask the same way. Post one line on issue #<t> when you open the PR, when you merge it, and when you're blocked (with the question). Report to your parent session `<parent>` with `send_message`, in one line, when you open the PR (with its number), when you're blocked, when you resume after a block, and when the PR is merged. Don't start any other issue. Stop once the PR is merged.

Add the group's notes from its row after "together in one PR" (e.g. "plus #58 only if its version-stamp blocker is solved", or what an earlier group already changed). Record the returned session ID and the time in the row.

Then make sure a check-in is pending (step 4) and end the turn. A group starts only when every group before it in the plan is merged, or when the plan runs it in parallel with them. A group after one that is failed or closed unmerged waits for the owner's word.

## 4. Watch cheaply

Three things wake the orchestrator:
- **A check-in.** `send_later` with `delay_minutes: 90` and the message `/batch check-in #<t>`, its `trigger_id` stored in the `Check-in:` line. A check-in turn first sets that line to `-`, since it has fired; any other line than `-` is pending, even past its time, because a check-in waits while another turn runs. Only one is ever pending: to schedule a new one, `delete_trigger` the stored one if there is one, then store the new one.
- **A child's `send_message`**: PR opened (record its number), blocked, resumed or merged.
- **A `<child-session-event>` turn**: the child's turn failed or its worker restarted.

On each, for every row with a session that isn't ticked:
1. `get_session <child>`: `status_bucket`.
2. The PR, by one search, which returns no body: `gh api -X GET search/issues -f q='repo:alexhu98/thunar is:pr head:<a>-<slug>' --jq '[(.items[] | select(.state == "open")), (.items[] | select(.pull_request.merged_at != null)), (.items | sort_by(.updated_at) | reverse | .[])] | .[0] // empty | "\(.number) \(.state) \(.pull_request.merged_at) \(.updated_at)"'` (the open PR, else a merged one, else the newest). `head:` also matches longer branch names that start with the same text, so once the row has a PR number take only that item (`select(.number == <pr>)`), and before that take a result only when it is the only one, else wait for the child's message with the number. Record its number in the row. Search lags GitHub by a few minutes: when the child says it merged but the search doesn't show it yet, or a new PR is missing, schedule the check-in 10 minutes out instead of 90.
3. Work out the child's condition, the first that holds:
   - `merged`: the PR has a `merged_at`.
   - `closed`: the PR is closed unmerged.
   - `failed`: `status_bucket` is `failed`.
   - `stalled` (long): on a check-in wake, the row has no PR and `started` is more than about 4 hours ago, even if the child is working.
   - `blocked`: `status_bucket` is `blocked`, or the child's message on this wake says it is blocked.
   - `ok`: `status_bucket` is `working`, or the PR's `updated_at` differs from `seen` (CI and review keep updating a live PR).
   - `stalled`: on a check-in wake only, the child is idle (`review_ready` or `completed`) with no PR, or with a PR whose `updated_at` equals `seen`. A clean finish doesn't report back, so a quiet child may have stopped. On any other wake, this case doesn't apply: count it as `ok` without clearing `told`.
   - otherwise `ok`.
4. Act on it:
   - `merged`: tick the row; if it is the stop point's group, start nothing more, otherwise start the groups that may now start (step 3).
   - `ok`: if `status_bucket` is `working`, or the child's message on this wake says it resumed, set `told` to `-`, so the next problem is reported. An idle child waiting on the owner stays idle while CI updates its PR, so a PR update alone doesn't clear `told`.
   - `blocked` from a child's message on this wake: tell the owner its question, even when `told` is already `blocked`, since each message is a new question. Set `told` to `blocked`.
   - `stalled` when `told` is `blocked`: nothing. A child waiting on the owner looks quiet.
   - any other condition that differs from `told`: tell the owner once, in "What I need from you", with the session's title and, for `blocked`, the child's question in one line if it sent one and that they answer it in that session. Set `told` to the condition. Never restart a child yourself.
5. On a check-in wake, set each row's `seen` to its PR's `updated_at`.
6. Update the tracking issue's body if a row changed. While any started row is unticked and its `told` isn't `failed` or `closed`, make sure a check-in is pending (step 2's 10-minute one counts). When every unticked started row is `failed` or `closed` and no group can start, the batch waits on the owner: say so once and schedule nothing; their message, or a child's, wakes it again.
7. When every group is merged, or the stop point's group and every other started group are merged, or the owner says to end the batch, go to step 5.

A check-in is a few tool calls. If one needs more, such as reading a child's transcript, ask the owner first.

## 5. Stop

At the stop point, when every group's PR is merged, or when the owner says to end the batch (for example after a failed group):
1. Delete the pending check-in, if there is one (`delete_trigger` with its `trigger_id`), and set `Check-in:` to `-`.
2. Update the tracking issue's body (each row's PR, tick and `told`), and close it (`issue_write` with `state: closed`, `state_reason: completed`) when every group merged, or otherwise leave it open with a line naming the groups that never started.
3. Report.

## Report

Open with one line: `batch #<t>: <m> of <k> groups merged (PRs #…)`, then any group not merged and why. Anything the owner must do goes last, in a "**What I need from you**" section.
