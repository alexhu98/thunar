---
name: batch
description: Orchestrates several issues as grouped PRs, one fresh cloud session per group, from a small orchestrator session that never reads PR noise. Plans the groups for the owner to confirm, tracks them in one issue, starts each group's session with a fixed brief, checks on them cheaply and stops when they're merged. Run as "/batch <issue numbers or range> [stop after <group>]", e.g. "/batch 48 52-60".
---

# Batch

One session that implements several issues fills its context with PR noise: GitHub notifications, CI comments, review rounds. `/batch` keeps that noise out. This session, the orchestrator, plans and tracks; each group of issues gets its own fresh child session, which builds, reviews and merges its PR under `CLAUDE.md` and reports back in one line. The orchestrator keeps only each child's status, the way `/visual-verify` keeps only `shot-audit`'s verdict.

Below, `<parent>` is this session's ID (`get_session` with no `session_id`), `<t>` the tracking issue, and each group has a letter (`A`, `B`, …), its issues `#<a>, #<b>`, its first issue `<a>` and its branch `<a>-<slug>`. Write them out literally in every call.

## Rules

- The orchestrator never subscribes to a PR, never reads CI's PR comments or checks, never runs `pr-digest`, and never commits, pushes, reviews or merges. Each child does all of that for its own PR.
- Events come from the children: each one reports its PR number, a block, a resume and its merge with `send_message`. The orchestrator never infers them. Its own check-ins are a safety net that reads only `get_session` (`status_bucket`) and, for an idle child with a PR, that PR's state from one search with no PR body.
- Groups run one at a time, in the plan's order. Two groups run at once only when the confirmed plan says they touch disjoint files and don't depend on each other.
- A child's question goes to the owner once, with the child's session named, and the owner answers in that child's session. An approval relayed from another session may be refused by the child's permission check (for example a `CLAUDE.md` edit), so the orchestrator doesn't relay answers unless the owner asks it to.
- Never start an issue the plan doesn't list, and never start any group before the owner has confirmed the plan.

## Arguments

- Issue numbers and ranges: `48 52-60`, `#56 #66`. Issues and PRs share numbers, so skip numbers that are PRs (`issue_read` shows `pull_request`) and closed issues, and say which.
- `stop after <group>` (optional): the stop point. The owner can also give it when confirming the plan.
- `check-in #<t>`: a check-in (step 4), not a new batch. Read the tracking issue `#<t>` (`issue_read get`, the body only) to rebuild the state (every row and the `Check-in:` line), then go straight to step 4's check-in.

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

A row: `- [ ] A: #52 #53 | branch 52-review-skip | session - | PR - | waiting on owner: no | notes: <the group's brief notes, or ->`. A ticked row is merged, a row whose status reads `skipped` (in place of `waiting on owner`) is done without a merge, and an unticked row with session `-` hasn't started. `waiting on owner` is `yes` once the owner has been told about that child (step 4), and goes back to `no` at the child's next message. `Check-in:` holds the pending check-in's `trigger_id`, or `-`.

The body is the batch's state. Update it with `issue_write update` whenever a row changes. A check-in that has lost the conversation rebuilds from it.

## 3. Run

For each group in order, start its child with `create_session`, with `source_url` `https://github.com/alexhu98/thunar`, a `title` of `Batch <t> group A: #52 #53`, and this brief as the `prompt`, filled in for the group:

> Implement GitHub issues #<a> and #<b> of alexhu98/thunar together in one PR. Read the issues and CLAUDE.md first, and follow CLAUDE.md fully, including the pr-digest agent and the review-loop rules. Ignore the claude/… branch this session is assigned. Create branch `<a>-<slug>` from `origin/main`, push from it, and open the PR into main with `Closes #<a>` and `Closes #<b>` (or `Refs` for an issue it does only part of). Add `explainers/<a>-<slug>.html` with the explainer skill, and a stamped narration (`make-video.py stamp <a>`, with CHROME set to the Playwright headless shell). Add `verify/<a>.sh` only if the change touches Thunar's code. Before pushing, run a local fresh-agent review of the diff and fix what it finds. After each CI run that took shots, run `/visual-verify pr:<n>` and post its comment, as CLAUDE.md says. If build and verify ran `No code changed`, follow CLAUDE.md's rule for that. Squash-merge your PR yourself when the CLAUDE.md merge rule allows it, and ask the owner in the cases where it says the agent doesn't merge. If the change needs a CLAUDE.md edit, the permission check may refuse an approval relayed from another session: ask the owner directly in this session in CLAUDE.md's "What I need from you" format, and tell your parent session it's blocked. When blocked on the owner for anything else, ask the same way. Post one line on issue #<t> when you open the PR, when you merge it, and when you're blocked (with the question). Report to your parent session `<parent>` with `send_message`, in one line starting with `batch <t> group A:`, when you open the PR (`opened #<n>`), when you're blocked (`blocked: <the question>`), when you go on after a block or a restart (`resumed`), and when the PR is merged (`merged #<n>`). Don't start any other issue. Stop once the PR is merged.

Add the group's notes from its row after "together in one PR" (e.g. "plus #58 only if its version-stamp blocker is solved", or what an earlier group already changed). Record the returned session ID in the row.

Then make sure a check-in is pending (step 4) and end the turn. A group starts only when every group before it in the plan is merged or skipped, or when the plan runs it in parallel with them; a group whose `After` names a skipped group starts only on the owner's word. A group whose child failed or stopped holds up the groups after it until it merges or the owner says to skip it. When the owner skips a group, its row reads `skipped`; then, unless it is the stop point's group, start the groups that may now start, and ask in the same reply whether the groups whose `After` names it should start. Each one the owner declines is skipped too.

## 4. Watch cheaply

The children report their own events; the orchestrator records them and passes on what needs the owner. Check-ins only catch a child that stopped without reporting.

**A child's message** (`batch <t> group A: …`), handled once, since each message arrives once:
- `opened #<n>`: record the PR number in the row.
- `blocked: <question>`: tell the owner in "What I need from you": group A's session title, the question in one line, and that they answer it in that session. Set `waiting on owner: yes`.
- `resumed`: set `waiting on owner: no`.
- `merged #<n>`: record the PR number in the row, tick it and set `waiting on owner: no`. If the stop point's group is merged or skipped, start nothing more; otherwise start the groups that may now start (step 3).

Any message from the child also sets `waiting on owner: no` before it is handled, unless its row reads `skipped`: no handler changes a skipped row, and its child's messages only go to the owner.

**A `<child-session-event>` turn** (the child's turn failed or its worker restarted): read `get_session <child>`. If its `status_bucket` is `failed`, tell the owner once, with the session's title, and set `waiting on owner: yes`; otherwise leave it to the child's messages and the next check-in. Never restart a child yourself.

**A check-in**, the safety net. `send_later` with `delay_minutes: 90` (240 while every started, unticked, unskipped row waits on the owner, below) and the message `/batch check-in #<t>`, its `trigger_id` stored in the `Check-in:` line. A check-in turn first sets that line to `-`, since it has fired; any other value is pending, even past its time, because a check-in waits while another turn runs. Only one is ever pending: to schedule one, `delete_trigger` the stored one if there is one, then store the new one. On a check-in, for each started, unticked row with `waiting on owner: no`, read `get_session <child>`'s `status_bucket`:
- `working`: nothing. A working child is never flagged; the owner sees it in their session list.
- `review_ready` or `completed` with a PR in the row: read that PR's state with one search that returns no body, `gh api -X GET search/issues -f q='repo:alexhu98/thunar is:pr head:<a>-<slug>' --jq '.items[] | select(.number == <n>) | "\(.state) \(.pull_request.merged_at)"'`. Merged is handled as `merged #<n>`; closed unmerged is told to the owner as `PR #<n> closed unmerged`, with `waiting on owner: yes`. Otherwise the child is idle with its PR not merged: CI takes well under 90 minutes and wakes a watching child, so it has likely stopped. Tell the owner as below.
- `failed` or `blocked`, or `review_ready` or `completed` with no PR in the row, or with an unmerged PR as above: the child stopped without reporting (or its message was lost). Tell the owner, with the session's title and that word, and set `waiting on owner: yes`.

On a check-in, a row with `waiting on owner: yes` is read the same way but never told about again: `working` means the child went on and its message was lost, so set `waiting on owner: no`; an idle child whose PR search shows it merged is handled as `merged #<n>`.

After any wake, update the tracking issue's body if a row or the `Check-in:` line changed. Keep a check-in pending while some row is started, unticked and not skipped: 90 minutes out while one of them has `waiting on owner: no`, and 4 hours out while all of them wait on the owner, since the owner answers in the child's session and nothing else may wake the orchestrator. When the owner says a group's PR merged, handle it as `merged #<n>`. When they say a child is handled otherwise, leave `waiting on owner: yes`: the child's next message clears it.

Go to step 5 when every group is merged or skipped, when the stop point's group and every other started group are merged or skipped, or when the owner says to end the batch.

A check-in is one `get_session` per running child, plus one search for an idle child with a PR. If it needs more, such as reading a child's transcript or CI's comments, ask the owner first.

## 5. Stop

At the stop point, when every group is merged or skipped, or when the owner says to end the batch (for example after a failed group):
1. Delete the pending check-in, if there is one (`delete_trigger` with its `trigger_id`), and set `Check-in:` to `-`.
2. Update the tracking issue's body (each row's PR and tick), and close it (`issue_write` with `state: closed`, `state_reason: completed`) when every group merged or was skipped, with a line naming the skipped groups, or otherwise leave it open with a line naming the groups that were skipped or never started.
3. Report.

## Report

Open with one line: `batch #<t>: <m> of <k> groups merged (PRs #…)`, then any group not merged and why. Anything the owner must do goes last, in a "**What I need from you**" section.
