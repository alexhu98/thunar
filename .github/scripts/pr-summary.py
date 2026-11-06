#!/usr/bin/env python3
"""Writes the summary comment, the first of the four PR comments, from the other three: pr-summary.py

Reads the status each of the review, verify and explainer comments carries (<!-- pr-proof:status {...} -->), the
build job of this run, and the latest /visual-verify verdict posted for the PR's head (a comment or the PR description
holding <!-- visual-verify <sha> --> and a VERDICT: line). Writes the heading (ready for review, or the first failing,
running or awaited check), the checks table, the key result and the shots table from the verify comment's data, through
pr-comment.sh. Does nothing when HEAD_SHA is no longer the PR's head, so an older run can't overwrite a newer summary.
Every job that writes a comment calls it, and the summary job calls it last.
Env: PR, GH_REPO, HEAD_SHA, RUN_ID, RUN_URL, OUT. DRY_RUN=1 prints the comment instead of writing it.
"""
import json
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ICON = {'pass': '✅', 'fail': '❌', 'running': '⏳', 'wait': '⏳', 'skip': '⏭️'}
JOBS = {'verify': ('verify',), 'review': ('review', 'review-report'), 'explainer': ('explainer',)}


def gh(*args):
    return subprocess.run(['gh', 'api', *args], check=True, capture_output=True, text=True).stdout


def lines_json(*args):
    return [json.loads(ln) for ln in gh(*args).splitlines() if ln.strip()]


def hidden(body, kind):
    m = re.search(r'^<!-- pr-proof:' + kind + r' (\{.*?\}) -->$', body or '', re.M)
    return json.loads(m.group(1)) if m else None


def cell(s):
    return ' '.join(str(s).split()).replace('|', '\\|')


def job_states(run_id):
    if not run_id:
        return None
    jobs = {}
    for j in lines_json(f'repos/{{owner}}/{{repo}}/actions/runs/{run_id}/jobs', '--paginate', '--jq', '.jobs[] | tojson'):
        if j['status'] != 'completed':
            state = 'running'
        else:
            state = {'success': 'pass', 'skipped': 'skip', 'cancelled': 'cancelled'}.get(j['conclusion'], 'fail')
        jobs[j['name']] = (state, j.get('html_url', ''))
    return jobs


def audit(comments, pr_body, head):
    found = []
    for src, body, when, url in [('description', pr_body, '', '')] + comments:
        m = re.search(r'<!-- visual-verify ([0-9a-f]{7,40}) -->', body or '')
        v = re.findall(r'^\s*`*VERDICT: ([^`\n]*)', body or '', re.M)
        if m and v:
            found.append((m.group(1), v[-1].strip(), when, src, url))
    mine = sorted([f for f in found if head.startswith(f[0])], key=lambda f: f[2])
    where = lambda f: f"[{'PR description' if f[3] == 'description' else 'audit comment'}]({f[4] or '#'})"
    if mine:
        sha, verdict, _, src, url = mine[-1]
        state = 'pass' if verdict.startswith('PASS') else 'fail'
        return state, f'{verdict} for `{head[:12]}`', where(mine[-1])
    if found:
        last = sorted(found, key=lambda f: f[2])[-1]
        return 'wait', f'not run for `{head[:12]}` yet (last: {last[1]} for `{last[0][:12]}`)', where(last)
    pr = os.environ.get('PR', '<n>')
    return 'wait', 'not run yet', f'`/visual-verify pr:{pr}`'


def section_state(name, st, head, jobs):
    if st and st.get('sha') == head:
        return st['state'], st['text']
    names = JOBS[name]
    if jobs is None or any(jobs.get(n, ('running',))[0] == 'running' for n in names):
        return 'running', 'running'
    if name == 'verify' and jobs.get('build', ('',))[0] != 'pass':
        return 'skip', 'not run: the build did not pass'
    if st:
        return 'fail', f"not run for `{head[:12]}` (last: {st['text']} for `{st['sha'][:12]}`)"
    return 'fail', 'not run'


def summary():
    pr = os.environ['PR']
    head_env = os.environ.get('HEAD_SHA', '')
    pull = json.loads(gh(f'repos/{{owner}}/{{repo}}/pulls/{pr}', '--jq', '{head: .head.sha, body: .body} | tojson'))
    head = pull['head']
    if head_env and head_env != head:
        print(f'skipping the summary: {head_env[:12]} is no longer the head of PR #{pr} ({head[:12]})')
        return None
    comments, mine = [], {}
    for c in lines_json(f'repos/{{owner}}/{{repo}}/issues/{pr}/comments', '--paginate', '--jq',
                        '.[] | {id, user: .user.login, body, updated_at, html_url} | tojson'):
        m = re.match(r'<!-- pr-proof:([a-z]+) -->', c['body'] or '')
        if c['user'] == 'github-actions[bot]' and m:
            mine.setdefault(m.group(1), c)
        else:
            comments.append(('comment', c['body'], c['updated_at'], c['html_url']))
    jobs = job_states(os.environ.get('RUN_ID'))
    link = lambda n, t: f"[{t}](#issuecomment-{mine[n]['id']})" if n in mine else t
    checks = []
    if jobs is None:
        build = ('running', 'unknown', '')
    else:
        b = jobs.get('build', ('running', ''))
        build = (b[0], {'pass': 'passed', 'fail': 'failed', 'running': 'running', 'skip': 'skipped'}.get(b[0], b[0]),
                 f'[build job]({b[1]})' if b[1] else '')
    checks.append(('Build', build[0], build[1], build[2]))
    status = {n: hidden(mine.get(n, {}).get('body'), 'status') for n in JOBS}
    v = section_state('verify', status['verify'], head, jobs)
    checks.append(('Verify', v[0], v[1], link('verify', 'Verify comment')))
    a = audit(comments, pull['body'], head)
    checks.append(('Screenshot audit', a[0], a[1], a[2]))
    r = section_state('review', status['review'], head, jobs)
    checks.append(('Code review', r[0], r[1], link('review', 'Code review comment')))
    e = section_state('explainer', status['explainer'], head, jobs)
    checks.append(('Explainer', e[0], e[1], link('explainer', 'Explainer comment')))
    failing = [c for c in checks if c[1] == 'fail']
    running = [c for c in checks if c[1] == 'running']
    if failing:
        title = f'❌ {failing[0][0]}: {failing[0][2]}'
    elif running:
        title = f'⏳ {running[0][0]} running'
    elif a[0] == 'wait':
        title = '⏳ waiting for the screenshot audit'
    else:
        title = '✅ ready for review'
    run_url = os.environ.get('RUN_URL', '')
    out = [f'## PR proof: {title}', '', f"Head `{head[:12]}`" + (f' · [workflow run]({run_url})' if run_url else ''), '',
           '| Check | Result | Where |', '|---|---|---|']
    out += [f'| {n} | {ICON.get(s, "⚠️")} {cell(t)} | {w} |' for n, s, t, w in checks]
    data = hidden(mine.get('verify', {}).get('body'), 'data') or {}
    vsha = (status['verify'] or {}).get('sha', '')
    stale = f' (as of `{vsha[:12]}`, not the head)' if data and vsha and vsha != head else ''
    out += ['', '### The key result' + stale, '']
    out.append(data.get('key') or 'No before/after pair in the verify scripts yet.')
    out += ['', '### Shots' + stale, '']
    out.append(data.get('shots') or 'No screenshots yet.')
    return '\n'.join(out) + '\n'


def main():
    body = summary()
    if body is None:
        return
    d = os.environ.get('OUT') or os.path.join(os.environ.get('RUNNER_TEMP') or os.environ.get('TMPDIR') or '/tmp', 'pr-summary')
    os.makedirs(d, exist_ok=True)
    path = os.path.join(d, 'summary.md')
    open(path, 'w').write(body)
    env = dict(os.environ, OUT=os.path.join(d, 'comment'))
    subprocess.run([os.path.join(HERE, 'pr-comment.sh'), 'put', 'summary', path], check=True, env=env)


if __name__ == '__main__':
    try:
        main()
    except subprocess.CalledProcessError as err:
        sys.exit(f'{err.cmd[:3]} failed: {err.stderr or err}')
