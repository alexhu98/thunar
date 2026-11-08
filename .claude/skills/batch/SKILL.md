---
name: batch
description: Orchestrates several issues as grouped PRs, one fresh cloud session per group, from a small orchestrator session that never reads PR noise. Plans the groups for the owner to confirm, tracks them in one issue, starts each group's session with a fixed brief, checks on them cheaply and stops when they're merged. Run as "/batch <issue numbers or range> [stop after <group>]", e.g. "/batch 48 52-60".
---

# Batch

One session that implements several issues fills its context with PR noise: GitHub notifications, CI comments, review rounds. `/batch` keeps that noise out. This session, the orchestrator, plans and tracks; each group of issues gets its own fresh child session, which builds, reviews and merges its PR under `CLAUDE.md` and reports back in one line. The orchestrator keeps only each child's status, the way `/visual-verify` keeps only `shot-audit`'s verdict.

Below, `<parent>` is this session's ID (`get_session` with no `session_id`), `<t>` the tracking issue, and each group has a letter (`A`, `B`, …), its issues `#<a>, #<b>`, its first issue `<a>` and its branch `<a>-<slug>`. Write them out literally in every call.

## Rules

- The orchestrator never subscribes to a PR, never reads CI's PR comments or checks, never runs `pr-digest`, and never commits, pushes, reviews or merges. Each child does all of that for its own PR.
- It checks a child only with `get_session` (`status_bucket`) and its PR's merged state (`pull_request_read get`, reading only `state`, `merged` and `updated_at`).
- Groups run one at a time, in the plan's order. Two groups run at once only when the confirmed plan says they touch disjoint files and don't depend on each other.
- A child's question goes to the owner once, with the child's session named, and the owner answers in that child's session. An approval relayed from another session may be refused by the child's permission check (for example a `CLAUDE.md` edit), so the orchestrator doesn't relay answers unless the owner asks it to.
- Never start an issue the plan doesn't list, and never start the next group before the owner has confirmed the plan.

## Arguments

- Issue numbers and ranges: `48 52-60`, `#56 #66`. Issues and PRs share numbers, so skip numbers that are PRs (`issue_read` shows `pull_request`) and closed issues, and say which.
- `stop after <group>` (optional): the stop point. The owner can also give it when confirming the plan.
- `check-in #<t>`: a check-in (step 4), not a new batch. Read the tracking issue `#<t>` (`issue_read get`, the body only) to rebuild the groups, sessions, PRs and the pending check-in's `trigger_id`, then go straight to step 4.

## 1. Plan

Read each open issue (`issue_read get`) and its comments where the body points to them. For each, note the files it would touch, the issues it says it depends on (`after #52`, `Depends on #`), and whether it changes Thunar's code (a `verify/<n>.sh` and screenshots) or only CI, skills and docs.

Group them: issues that touch the same files or depend on each other go in one group, or in consecutive groups in dependency order. Keep a group to one PR a reviewer can follow, usually one to three issues. Print one table:

```
Group | Issues   | Branch          | Touches                         | After | Code?
A     | #52 #53  | 52-review-skip  | .github/workflows/review.yml    | -     | no
B     | #56 #66  | 56-fewer-jobs   | .github/workflows/*, scripts/   | A     | no
```

Under it: how many PRs that is (each runs CI's build, verify, review and explainer jobs, so it costs CI minutes), which groups could run in parallel, and any issue left out and why. Then end the turn with one "**What I need from you**" question, in `CLAUDE.md`'s format, such as: `1. A. Run the plan as shown (recommended) B. Stop after group A C. Change the groups (say how)`. Don't go on until the owner answers.

## 2. Track

Open the tracking issue with `issue_write` in `alexhu98/thunar`:
- Title: `Batch: #<a>, #<b>, …` (every issue in the plan).
- Body: the confirmed table, then one checklist row per group, `- [ ] A: #52 #53, branch 52-review-skip, session -, PR -, waiting`, the stop point if there is one, and `Orchestrator: <parent>`.

The body is the batch's state. Update it with `issue_write update` whenever a row changes (session started, PR opened, blocked, merged), and tick a row at merge. A check-in that has lost the conversation rebuilds from it.

## 3. Run

For each group in order, start its child with `create_session`, with `source_url` `https://github.com/alexhu98/thunar`, a `title` of `Batch <t> group A: #52 #53`, and this brief as the `prompt`, filled in for the group:

> Implement GitHub issues #<a> and #<b> of alexhu98/thunar together in one PR. Read the issues and CLAUDE.md first, and follow CLAUDE.md fully, including the pr-digest agent and the review-loop rules. Ignore the claude/… branch this session is assigned. Create branch `<a>-<slug>` from `origin/main`, push from it, and open the PR into main with `Closes #<a>` and `Closes #<b>` (or `Refs` for an issue it does only part of). Add `explainers/<a>-<slug>.html` with the explainer skill, and a stamped narration (`make-video.py stamp <a>`, with CHROME set to the Playwright headless shell). Add `verify/<a>.sh` only if the change touches Thunar's code. Before pushing, run a local fresh-agent review of the diff and fix what it finds. After CI runs, post a `/visual-verify pr:<n>` comment with a PASS verdict when there are shots. If build and verify ran `No code changed`, follow CLAUDE.md's rule for that. Squash-merge your PR yourself when the CLAUDE.md merge rule allows it, and ask the owner in the cases where it says the agent doesn't merge. If the change needs a CLAUDE.md edit, the permission check may refuse an approval relayed from another session: ask the owner directly in this session in CLAUDE.md's "What I need from you" format, and tell your parent session it's blocked. When blocked on the owner for anything else, ask the same way. Post one line on issue #<t> when you open the PR, when you merge it, and when you're blocked (with the question). Report to your parent session `<parent>` with `send_message` when you're blocked and when the PR is merged, in one line. Don't start any other issue. Stop once the PR is merged.

Add the group's own notes from the plan after "together in one PR" (e.g. "plus #58 only if its version-stamp blocker is solved", or what an earlier group already changed). Record the returned session ID in the tracking issue's row.

Then schedule a check-in (step 4) unless one is already pending, and end the turn. Start the next group only when the previous group's PR is merged, unless the plan runs them in parallel.

## 4. Watch cheaply

Three things wake the orchestrator:
- **A check-in.** `send_later` with `delay_minutes: 90` and the message `/batch check-in #<t>`. Keep its `trigger_id` in the tracking issue's body. Only one is ever pending: before scheduling a new one, `delete_trigger` the stored one (a check-in that has already fired is gone, and deleting it again is harmless).
- **A child's `send_message`** (blocked or merged).
- **A `<child-session-event>` turn**: the child's turn failed or its worker restarted.

On each, for every running child:
1. `get_session <child>`: `status_bucket`.
2. If the tracking row has a PR: `pull_request_read get` for its `state`, `merged` and `updated_at` only. If the row has none yet, find it with `list_pull_requests` (`owner: alexhu98`, `repo: thunar`, `state: all`, `head: alexhu98:<a>-<slug>`), since a child can open and merge its PR between check-ins, and record it in the row.
3. Act on what they say:
   - **Merged:** update the row and tick it, then start the next group (step 3), or stop (step 5) at the stop point or after the last group.
   - **`blocked`, or the child reported a question:** tell the owner once, in "What I need from you", that the child for group A is waiting, with its question in one line if the child sent one, and the session's title, and that they answer it in that session. Mark the row `blocked` so the next check-in doesn't ask again.
   - **`failed`:** tell the owner once, with the session's title; don't restart it yourself.
   - **`working`:** nothing. If a child has been `working` with no PR for more than about 3 hours, or `review_ready` or `completed` with its PR open and its `updated_at` unchanged since the last check-in (CI and review keep updating a live PR), it may have stalled silently (a clean finish doesn't report back): tell the owner once and suggest they look at that session.
4. While a child is running, replace the pending check-in with a new one, as above, and store its `trigger_id`.

A check-in is a few tool calls. If one needs more, such as reading a child's transcript, ask the owner first.

## 5. Stop

At the stop point, or when every group's PR is merged:
1. Delete the pending check-in (`delete_trigger` with its `trigger_id`).
2. Update the tracking issue's body (each row's PR and state), and close it (`issue_write` with `state: closed`, `state_reason: completed`) when every group merged, or leave it open with the remaining groups marked `not started` at a stop point.
3. Report.

## Report

Open with one line: `batch #<t>: <m> of <k> groups merged (PRs #…)`, then any group not merged and why. Anything the owner must do goes last, in a "**What I need from you**" section.
