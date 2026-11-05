---
name: shot-audit
description: Audits captured Thunar screenshots in an independent read-only subagent. Reads every PNG and returns a per-shot OK/BLANK/MISMATCH/MISSING table. Invoked by /visual-verify Step 3; not usually run by hand.
context: fork
agent: shot-auditor
background: false
effort: high
allowed-tools: Read Grep Glob
---

## Audit request

$ARGUMENTS

The caller passes the shots directory, the required-shots list and optionally a `baseline:` directory. Each entry in the list has a filename relative to the shots directory, an intent, and the element and state to confirm. The intent is the `proves` sentence from the manifest. A before/after pair is listed with both files.

## Task

**First, confirm you are the `shot-auditor` agent.** Your system prompt should open with "You
are an independent screenshot auditor". If it does not, the `agent:` binding did not take effect.
The usual cause is that `.claude/agents/shot-auditor.md` was added or changed after this session
started: agent definitions load at session start and are **not** reloaded, unlike skills.
In that case:

1. `Read` `.claude/agents/shot-auditor.md` and apply its method and output format as written.
2. Say so in one line above the table: `NOTE: agent binding inert, ran the audit from file;
   restart Claude Code to bind the agent.`
3. Treat the read-only rule as binding **by instruction**, since the tool restriction in the
   agent definition is not in force.

Then audit the shots and return the table.

Constraints:

- **Read every required PNG.** The Read tool renders images. A verdict inferred from a filename,
  a byte size, or the mere existence of a file is not an audit. That is the failure mode this
  skill exists to prevent.
- Read-only. Do not edit any file, do not re-run the capture, do not adjust the intents.
- Return the table and nothing else. No preamble, no fix suggestions, no verdict line: the
  caller reduces the table and owns the `VERDICT:` sentinel.
- A shot you could not read is `MISSING`, not `OK`. Never let an unreadable file pass silently.
