#!/usr/bin/env python3
"""The review state kept in the code review PR comment, for review-proof.sh.

review-state.py decide STATE IN OUT SHA COMMIT MINUTES RUN_URL RESULT
    Merges this run's findings ($IN/findings.json), unless RESULT is failure, into the saved state, closes the open findings named in
    $OUT/accepted.txt by a Review-accept trailer on a commit after the one they were found in, and writes $OUT/state-new.json and
    $OUT/suggestions.json (the inline suggested changes, each tagged with its finding id).
review-state.py open STATE OUT
    Writes the confirmed findings still open to $OUT/open.json and the accepted ones to $OUT/accepted.json.
review-state.py render OUT REPO SHA RESULT NOTE [FAILED_ID...]
    Marks the findings whose suggestion couldn't be posted, writes the review comment to $OUT/section.md (this
    review's findings, then every finding the PR has had, closed ones with their text and reason) and prints how many
    confirmed medium or high findings are unresolved.
"""
import json
import os
import re
import subprocess
import sys

OPEN = ('suggested', 'not fixed')
KEEP = 400
LIMIT = 60000
CLOSED = ('id', 'sha', 'file', 'line', 'severity', 'verdict', 'summary', 'status', 'detail', 'commit')


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


def short(f, n):
    g = {k: f[k] for k in CLOSED if k in f}
    for k in ('summary', 'detail'):
        if k in g:
            g[k] = cap(g[k], n) if n else ''
    return g


def unresolved(f):
    return f['status'] in OPEN and f['verdict'] == 'CONFIRMED'


def open_findings(state_p, out):
    findings = load(state_p, {}).get('findings', [])
    acc = acceptances(out)
    taken = [f for f in findings if f['status'] == 'accepted' or f['status'] in OPEN and accepts(f, acc)]
    json.dump([f for f in findings if unresolved(f) and f not in taken], open(os.path.join(out, 'open.json'), 'w'))
    json.dump(taken, open(os.path.join(out, 'accepted.json'), 'w'))


def suggestion(fid, r, hs):
    start = r.get('start_line') or r['line']
    if 'suggestion' not in r or not any(r['file'] == hf and s <= start and r['line'] <= e for hf, s, e in hs):
        return None
    text = r['suggestion'].rstrip('\n')
    fence = '`' * max(3, 1 + max((len(m) for m in re.findall('`+', text)), default=0))
    body = '\n\n'.join(filter(None, [f"**{fid} ({r['severity']}, {r['verdict'].lower()})** {r['summary']}",
                                     r.get('failure_scenario'), f"{fence}suggestion\n{text}\n{fence}"]))
    c = {'id': fid, 'path': r['file'], 'line': r['line'], 'side': 'RIGHT', 'body': body}
    if start != r['line']:
        c.update(start_line=start, start_side='RIGHT')
    return c


def decide(state_p, inp, out, sha, commit, mins, run_url, result):
    state = load(state_p, {})
    fixed = load(os.path.join(out, 'fixed.json'), [])
    done = {f['i'] for f in fixed if 'i' in f}
    done_open = {f['id']: f for f in fixed if 'i' not in f}
    plan = load(os.path.join(inp, 'plan.json'), {})
    res = load(os.path.join(inp, 'findings.json')) if result != 'failure' else None
    findings = state.get('findings', [])
    acc = acceptances(out)
    for f in findings:
        if result != 'failure' and not plan.get('skip'):
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
            if f['status'] not in OPEN or not p:
                continue
            if commit and f['id'] in done_open:
                f['status'], f['commit'], f['new'] = 'fixed', commit, True
                f.update({k: done_open[f['id']][k] for k in ('file', 'line') if k in done_open[f['id']]})
            elif p.get('fixed'):
                f['new'] = True
                c = 'line' in p and suggestion(f['id'], {**f, **p}, hs)
                f.update({k: p[k] for k in ('file', 'line') if p.get(k) is not None})
                if c:
                    f['status'] = 'suggested'
                    comments.append(c)
                else:
                    f['status'], f['detail'] = 'not fixed', "fixed in the review, but the fix wasn't pushed"
            elif p.get('resolved'):
                f['status'], f['new'] = 'resolved', True
                f['detail'] = f"resolved by {sha[:12]}" + (f": {cap(p['note'])}" if p.get('note') else '')
            elif p.get('note'):
                f['detail'] = f"still open at {sha[:12]}: {cap(p['note'])}"
        for f in findings:
            if f['status'] in OPEN and f['verdict'] != 'CONFIRMED' and not f.get('new'):
                f['status'] = 'unconfirmed'
        n = state.get('next', 1)
        for i, r in enumerate(res['findings']):
            fid = f'R{n}'
            n += 1
            f = {'id': fid, 'sha': sha, 'file': r['file'], 'line': r['line'], 'severity': r['severity'],
                 'summary': cap(r['summary'], 300), 'verdict': r['verdict'], 'new': True}
            if commit and i in done:
                f['status'], f['commit'] = 'fixed', commit
            elif c := suggestion(fid, r, hs):
                f['status'] = 'suggested'
                comments.append(c)
            else:
                f['status'] = 'not fixed'
                f['detail'] = cap(r['reason']) if r.get('reason') else (
                    "fixed in the review, but the fix wasn't pushed" if r.get('fixed') else
                    'not on a line this PR changes' if 'suggestion' in r else 'no suggestion given')
            findings.append(f)
        state.update(next=n, sha=sha, mode=plan['mode'], level=plan['level'], model=plan['model'],
                     reason=plan['reason'], minutes=int(mins) if mins else None, run=run_url)
    state['findings'] = [f if f['status'] in OPEN + ('accepted',) or f.get('new') else short(f, 120) for f in findings]
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


def detail(f, repo):
    if f['status'] == 'fixed' and f.get('commit'):
        return f"[{f['commit'][:12]}](https://github.com/{repo}/commit/{f['commit']})"
    if f['status'] == 'suggested':
        return 'suggested change on the PR'
    if f['status'] == 'unconfirmed' and not f.get('detail'):
        return 'never confirmed, so no longer re-checked'
    return cell(cap(f.get('detail', ''), 160))


def row(f, repo):
    where = f"`{f['file']}:{f['line']}` " if f.get('file') else ''
    text = cap(f['summary'], 200) if f.get('summary') else '(its text was not kept)'
    sev = (f.get('severity', '?') + ('' if f.get('verdict', 'CONFIRMED') == 'CONFIRMED' else ' (plausible)'))
    return f"| {f['id']} | {cell(where + text)} | {sev} | {f['status']} | {detail(f, repo)} |"


def table(fs, repo):
    return ['| # | Finding | Severity | Status | Fix commit or reason |', '|---|---|---|---|---|'] + [row(f, repo) for f in fs]


def render(out, repo, sha, result, note, failed):
    state = load(os.path.join(out, 'state-new.json'), {})
    findings = state.get('findings', [])
    for f in findings:
        if f['id'] in failed and f['status'] == 'suggested':
            f['status'], f['detail'] = 'not fixed', "its suggested change couldn't be posted"
    open_ = [f for f in findings if unresolved(f) and f.get('severity') != 'low']
    if result == 'failure':
        status = {'sha': sha, 'state': 'fail', 'text': 'the review did not finish'}
    elif open_:
        status = {'sha': sha, 'state': 'fail', 'text': f'{len(open_)} confirmed medium or high finding(s) unresolved'}
    elif result == 'unreviewed':
        status = {'sha': sha, 'state': 'wait', 'text': "not reviewed yet: CI's own fix, which the next push's review covers"}
    else:
        status = {'sha': sha, 'state': 'pass', 'text': 'no confirmed medium or high findings unresolved'}
    ids = {f['id'] for f in findings if f['status'] in OPEN or f.get('new')}
    rows = len(findings)
    text = body(state, status, ids, open_, repo, note, rows)
    for step in (120, 60, 0, 'ids', 'rows', 'open'):
        if len(text) < LIMIT:
            break
        if step == 'ids':
            state['findings'] = [f if f['id'] in ids else {'id': f['id'], 'status': f['status']} for f in state['findings']]
        elif step == 'rows':
            while rows and len(body(state, status, ids, open_, repo, note, rows)) >= LIMIT:
                rows //= 2
        elif step == 'open':
            state['findings'] = [short(f, 80) | {k: f[k] for k in f if k not in CLOSED} if f['id'] in ids else f
                                 for f in state['findings']]
        else:
            state['findings'] = [f if f['id'] in ids else short(f, step) for f in state['findings']]
        text = body(state, status, ids, open_, repo, note, rows)
    open(os.path.join(out, 'section.md'), 'w').write(text)
    print(len(open_))


def body(state, status, ids, open_, repo, note, rows):
    findings = state.get('findings', [])
    shown = [f for f in findings if f['id'] in ids]
    lines = ['<!-- pr-proof:status ' + json.dumps(status, separators=(',', ':')).replace('>', '\\u003e') + ' -->',
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
    if shown:
        lines += table(shown, repo)
    elif state.get('sha'):
        lines.append('No open findings.')
    else:
        lines.append('Not reviewed yet.')
    lines += ['', f"**{len(open_)} confirmed medium or high finding(s) unresolved.**" if open_ else 'No confirmed medium or high findings unresolved.']
    if findings and len(shown) < len(findings):
        lines += ['', f'#### Every finding on this PR ({len(findings)})', ''] + table(findings[-rows:] if rows else [], repo)
        if rows < len(findings):
            lines += ['', f'The {len(findings) - rows} oldest are left out to fit the comment.']
    return '\n'.join(lines) + '\n'


if __name__ == '__main__':
    cmd, args = sys.argv[1], sys.argv[2:]
    if cmd == 'decide':
        decide(*args)
    elif cmd == 'open':
        open_findings(*args)
    elif cmd == 'render':
        render(args[0], args[1], args[2], args[3], args[4], set(args[5:]))
    else:
        sys.exit(__doc__)
