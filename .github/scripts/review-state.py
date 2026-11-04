#!/usr/bin/env python3
"""The review state kept in the PR comment, for review-proof.sh.

review-state.py decide STATE IN OUT SHA COMMIT PUSHED MINUTES RUN_URL
    Merges this run's findings ($IN/findings.json) into the saved state and writes $OUT/state-new.json and
    $OUT/suggestions.json (the inline suggested changes, each tagged with its finding id).
review-state.py render OUT REPO NOTE [FAILED_ID...]
    Marks the findings whose suggestion couldn't be posted, writes the review section to $OUT/section.md and
    prints how many confirmed findings are unresolved.
"""
import json
import os
import sys

OPEN = ('suggested', 'not fixed')
KEEP = 400


def cap(s, n=KEEP):
    s = ' '.join(str(s).split())
    return s if len(s) <= n else s[:n - 1].rstrip() + '…'


def load(p, default=None):
    return json.load(open(p)) if os.path.exists(p) and os.path.getsize(p) else default


def hunks(out):
    for ln in open(os.path.join(out, 'hunks.txt')):
        f, s, e = ln.rstrip('\n').split('\t')
        yield f, int(s), int(e)


def decide(state_p, inp, out, sha, commit, pushed, mins, run_url):
    state = load(state_p, {})
    plan = load(os.path.join(inp, 'plan.json'), {})
    res = load(os.path.join(inp, 'findings.json'))
    findings = state.get('findings', [])
    for f in findings:
        f.pop('new', None)
    hs = list(hunks(out))
    comments = []
    if res is not None and not plan.get('skip'):
        prev = {p['id']: p for p in res.get('previous', [])}
        for f in findings:
            p = prev.get(f['id'])
            if f['status'] in OPEN and p and p.get('resolved'):
                f['status'], f['new'] = 'resolved', True
                f['detail'] = f"resolved by {sha[:12]}" + (f": {cap(p['note'])}" if p.get('note') else '')
        n = state.get('next', 1)
        for r in res['findings']:
            fid = f'R{n}'
            n += 1
            start = r.get('start_line') or r['line']
            f = {'id': fid, 'sha': sha, 'file': r['file'], 'line': r['line'], 'severity': r['severity'],
                 'summary': cap(r['summary']), 'verdict': r['verdict'], 'new': True}
            if r.get('fixed') and commit and pushed == '1':
                f['status'], f['commit'] = 'fixed', commit
            elif 'suggestion' in r and any(r['file'] == hf and s <= start and r['line'] <= e for hf, s, e in hs):
                f['status'] = 'suggested'
                body = (f"**{fid} ({r['severity']}, {r['verdict'].lower()})** {r['summary']}\n\n{r['failure_scenario']}\n\n"
                        f"```suggestion\n{r['suggestion'].rstrip(chr(10))}\n```")
                c = {'id': fid, 'path': r['file'], 'line': r['line'], 'side': 'RIGHT', 'body': body}
                if start != r['line']:
                    c.update(start_line=start, start_side='RIGHT')
                comments.append(c)
            else:
                f['status'] = 'not fixed'
                f['detail'] = cap(r['reason']) if r.get('reason') else (
                    'not on a line this PR changes' if 'suggestion' in r else 'no suggestion given')
            findings.append(f)
        state.update(next=n, sha=sha, mode=plan['mode'], level=plan['level'], model=plan['model'],
                     reason=plan['reason'], minutes=int(mins) if mins else None, run=run_url)
    for f in findings:
        if f['status'] not in OPEN and not f.get('new'):
            f.pop('summary', None)
            f.pop('detail', None)
    state['findings'] = findings
    json.dump(state, open(os.path.join(out, 'state-new.json'), 'w'))
    json.dump({'commit_id': sha, 'event': 'COMMENT',
               'body': f'CI code review of {sha[:12]}: {len(comments)} suggested change(s).', 'comments': comments},
              open(os.path.join(out, 'suggestions.json'), 'w'))


def cell(s):
    s = ' '.join(str(s).split()).replace('`', "'").replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;')
    return s.replace('|', '\\|')


def short(s, n=160):
    return s if len(s) <= n else s[:n - 1].rstrip() + '…'


def render(out, repo, note, failed):
    state = load(os.path.join(out, 'state-new.json'), {})
    findings = state.get('findings', [])
    for f in findings:
        if f['id'] in failed and f['status'] == 'suggested':
            f['status'], f['detail'] = 'not fixed', "its suggested change couldn't be posted"
    open_ = [f for f in findings if f['status'] in OPEN and f['verdict'] == 'CONFIRMED']
    state['open'] = len(open_)
    lines = ['<!-- review:start -->',
             '<!-- review:state ' + json.dumps(state, separators=(',', ':')).replace('>', '\\u003e') + ' -->',
             '### Code review', '']
    if state.get('sha'):
        model = {'claude-opus-5-5': 'Opus 5.5'}.get(state['model'], state['model'])
        lines.append(f"Last reviewed `{state['sha'][:12]}`: {cell(state['reason'])}. Mode: {state['mode']}. "
                     f"{model} at `{state['level']}`."
                     + (f" Review job: {state['minutes']} min." if state.get('minutes') else '')
                     + (f" [Run]({state['run']})" if state.get('run') else ''))
    if note:
        lines += ['', note]
    lines.append('')
    shown = [f for f in findings if f['status'] in OPEN or f.get('new')]
    closed = [f for f in findings if f not in shown]
    if shown:
        lines += ['| # | Finding | Severity | Status | Fix commit or reason |', '|---|---|---|---|---|']
        for f in shown:
            if f['status'] == 'fixed':
                detail = f"[{f['commit'][:12]}](https://github.com/{repo}/commit/{f['commit']})"
            elif f['status'] == 'suggested':
                detail = 'suggested change on the PR'
            else:
                detail = cell(short(f.get('detail', '')))
            lines.append(f"| {f['id']} | `{cell(f['file'])}:{f['line']}` {cell(short(f['summary'], 200))} | {f['severity']}"
                         f"{'' if f['verdict'] == 'CONFIRMED' else ' (plausible)'} | {f['status']} | {detail} |")
    elif state.get('sha'):
        lines.append('No open findings.')
    else:
        lines.append('Not reviewed yet.')
    if closed:
        by = {}
        for f in closed:
            by.setdefault(f['status'], []).append(f['id'])
        lines += ['', 'Earlier, closed: ' + '; '.join(f"{k} {', '.join(v)}" for k, v in sorted(by.items())) + '.']
    lines += ['', f"**{len(open_)} confirmed finding(s) unresolved.**" if open_ else 'No confirmed findings unresolved.',
              '<!-- review:end -->']
    open(os.path.join(out, 'section.md'), 'w').write('\n'.join(lines) + '\n')
    print(len(open_))


if __name__ == '__main__':
    cmd, args = sys.argv[1], sys.argv[2:]
    if cmd == 'decide':
        decide(*args)
    elif cmd == 'render':
        render(args[0], args[1], args[2], set(args[3:]))
    else:
        sys.exit(__doc__)
