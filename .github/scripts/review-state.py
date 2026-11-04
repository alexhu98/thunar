#!/usr/bin/env python3
"""The review state kept in the PR comment, for review-proof.sh.

review-state.py decide STATE IN OUT SHA COMMIT MINUTES RUN_URL
    Merges this run's findings ($IN/findings.json) into the saved state, closes the open findings named in
    $OUT/accepted.txt by a Review-accept trailer on a commit after the one they were found in, and writes $OUT/state-new.json and
    $OUT/suggestions.json (the inline suggested changes, each tagged with its finding id).
review-state.py open STATE OUT
    Writes the confirmed findings still open to $OUT/open.json and the accepted ones to $OUT/accepted.json.
review-state.py render OUT REPO NOTE [FAILED_ID...]
    Marks the findings whose suggestion couldn't be posted, writes the review section to $OUT/section.md and
    prints how many confirmed findings are unresolved.
"""
import json
import os
import subprocess
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


def git(*args):
    return subprocess.run(['git', *args], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0


def acceptances(out):
    acc = {}
    p = os.path.join(out, 'accepted.txt')
    for ln in open(p) if os.path.exists(p) else ():
        fid, c = ln.split()
        acc.setdefault(fid, []).append(c)
    return acc


def accepts(f, acc):
    s = f.get('sha')
    known = bool(s) and git('cat-file', '-e', f'{s}^{{commit}}')
    return any(c != s and (not known or git('merge-base', '--is-ancestor', s, c)) for c in acc.get(f['id'], ()))


def unresolved(f):
    return f['status'] in OPEN and f['verdict'] == 'CONFIRMED'


def open_findings(state_p, out):
    findings = load(state_p, {}).get('findings', [])
    acc = acceptances(out)
    taken = [f for f in findings if f['status'] == 'accepted' or f['status'] in OPEN and accepts(f, acc)]
    json.dump([f for f in findings if unresolved(f) and f not in taken], open(os.path.join(out, 'open.json'), 'w'))
    json.dump(taken, open(os.path.join(out, 'accepted.json'), 'w'))


def decide(state_p, inp, out, sha, commit, mins, run_url):
    state = load(state_p, {})
    fixed = load(os.path.join(out, 'fixed.json'), [])
    done = {f['i'] for f in fixed if 'i' in f}
    done_open = {f['id'] for f in fixed if 'id' in f}
    plan = load(os.path.join(inp, 'plan.json'), {})
    res = load(os.path.join(inp, 'findings.json'))
    findings = state.get('findings', [])
    acc = acceptances(out)
    for f in findings:
        f.pop('new', None)
        if f['status'] in OPEN and accepts(f, acc):
            f['status'], f['new'] = 'accepted', True
            f['detail'] = 'accepted by a Review-accept trailer'
    hs = list(hunks(out))
    comments = []
    if res is not None and not plan.get('skip') and state.get('sha') != sha:
        prev = {p['id']: p for p in res.get('previous', [])}
        for f in findings:
            p = prev.get(f['id'])
            if f['status'] in OPEN and commit and f['id'] in done_open:
                f['status'], f['commit'], f['new'] = 'fixed', commit, True
            elif f['status'] in OPEN and p and p.get('resolved'):
                f['status'], f['new'] = 'resolved', True
                f['detail'] = f"resolved by {sha[:12]}" + (f": {cap(p['note'])}" if p.get('note') else '')
        for f in findings:
            if f['status'] in OPEN and f['verdict'] != 'CONFIRMED' and not f.get('new'):
                f['status'] = 'unconfirmed'
        n = state.get('next', 1)
        for i, r in enumerate(res['findings']):
            fid = f'R{n}'
            n += 1
            start = r.get('start_line') or r['line']
            f = {'id': fid, 'sha': sha, 'file': r['file'], 'line': r['line'], 'severity': r['severity'],
                 'summary': cap(r['summary']), 'verdict': r['verdict'], 'new': True}
            if commit and i in done:
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
                    "fixed in the review, but the fix wasn't pushed" if r.get('fixed') else
                    'not on a line this PR changes' if 'suggestion' in r else 'no suggestion given')
            findings.append(f)
        state.update(next=n, sha=sha, mode=plan['mode'], level=plan['level'], model=plan['model'],
                     reason=plan['reason'], minutes=int(mins) if mins else None, run=run_url)
    state['findings'] = [f if f['status'] in OPEN + ('accepted',) or f.get('new') else {'id': f['id'], 'status': f['status']}
                         for f in findings]
    json.dump(state, open(os.path.join(out, 'state-new.json'), 'w'))
    json.dump({'commit_id': sha, 'event': 'COMMENT',
               'body': f'CI code review of {sha[:12]}: {len(comments)} suggested change(s).', 'comments': comments},
              open(os.path.join(out, 'suggestions.json'), 'w'))


def cell(s):
    parts = ' '.join(str(s).split()).split('`')
    if len(parts) % 2 == 0:
        parts[-2:] = [parts[-2] + "'" + parts[-1]]
    parts = [p if i % 2 else p.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;') for i, p in enumerate(parts)]
    return '`'.join(parts).replace('|', '\\|')


def render(out, repo, note, failed):
    state = load(os.path.join(out, 'state-new.json'), {})
    findings = state.get('findings', [])
    for f in findings:
        if f['id'] in failed and f['status'] == 'suggested':
            f['status'], f['detail'] = 'not fixed', "its suggested change couldn't be posted"
    open_ = [f for f in findings if unresolved(f)]
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
                detail = cell(cap(f.get('detail', ''), 160))
            lines.append(f"| {f['id']} | {cell(chr(96) + f['file'] + ':' + str(f['line']) + chr(96))} {cell(cap(f['summary'], 200))} | {f['severity']}"
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
    elif cmd == 'open':
        open_findings(*args)
    elif cmd == 'render':
        render(args[0], args[1], args[2], set(args[3:]))
    else:
        sys.exit(__doc__)
