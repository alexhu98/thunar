#!/usr/bin/env python3
"""Writes the summary comment, the first of the four PR comments, from the other three: pr-summary.py

Reads the status each of the review, verify and explainer comments carries (<!-- pr-proof:status {...} -->), the
build job of this run (or BUILD_RESULT, when the build job calls it), and the latest /visual-verify verdict posted
for the PR's head by the owner, a collaborator or claude[bot] (a comment holding <!-- visual-verify <sha> --> and a
VERDICT: line; the latest posted wins). Without RUN_ID it uses the latest build run of the head. Writes the heading
(ready for review, or the first failing, running or awaited check), the checks table, the key result and the shots
table from the verify comment's data, through pr-comment.sh. Does nothing when HEAD_SHA is no longer the PR's head, so
an older run can't overwrite a newer summary. Every job that writes a comment calls it and the summary job calls it
last; the pr-summary workflow re-runs that summary job when an audit comment is posted or edited. After writing it
reads everything again and writes again, up to twice, if anything changed meanwhile.
Env: PR, GH_REPO, HEAD_SHA, RUN_ID, RUN_URL, BUILD_RESULT, OUT. DRY_RUN=1 prints the comment instead of writing it.
"""
import json
import os
import re
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ICON = {'pass': '✅', 'fail': '❌', 'running': '⏳', 'wait': '⏳', 'skip': '⏭️'}
TRUSTED = ('OWNER', 'MEMBER', 'COLLABORATOR')
JOBS = {'verify': ('verify',), 'review': ('review', 'review-report'), 'explainer': ('explainer',)}
HEAVY_STEP = {'build': 'Build', 'verify': 'Smoke test and verify/*.sh'}
NO_CODE = 'skipped: the PR changes only explainers/, .claude/, *.md or narration files'


def gh(*args):
    for attempt in range(3):
        r = subprocess.run(['gh', 'api', *args], capture_output=True, text=True)
        if r.returncode == 0 or attempt == 2:
            break
        print(f'gh api {args[0]} failed (attempt {attempt + 1}): {r.stderr.strip()}', file=sys.stderr)
        time.sleep(5 * (attempt + 1))
    r.check_returncode()
    return r.stdout


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
        if j['name'] == 'build' and os.environ.get('BUILD_RESULT'):
            state = {'success': 'pass', 'cancelled': 'cancelled'}.get(os.environ['BUILD_RESULT'], 'fail')
        elif j['status'] != 'completed':
            state = 'running'
        elif j['conclusion'] == 'success' and any(st['name'] == HEAVY_STEP.get(j['name']) and st['conclusion'] == 'skipped'
                                                  for st in j.get('steps') or []):
            state = 'nocode'
        else:
            state = {'success': 'pass', 'skipped': 'skip', 'cancelled': 'cancelled', 'timed_out': 'cancelled'}.get(j['conclusion'], 'fail')
        jobs[j['name']] = (state, j.get('html_url', ''))
    return jobs


def audit(comments, head):
    found = []
    for body, url in comments:
        m = re.search(r'<!-- visual-verify ([0-9a-f]{7,40}) -->', body or '')
        v = re.findall(r'^\s*`*VERDICT: ([^`\n]*)', body or '', re.M)
        if m and v:
            found.append((m.group(1), v[-1].strip(), url))
    mine = [f for f in found if head.startswith(f[0])]
    where = lambda f: f"[audit comment]({f[2]})"
    if mine:
        verdict = mine[-1][1]
        state = 'pass' if verdict.startswith('PASS') else 'wait' if verdict.startswith('INCONCLUSIVE') else 'fail'
        return state, f'{verdict} for `{head[:12]}`', where(mine[-1])
    if found:
        last = found[-1]
        return 'wait', f'not run for `{head[:12]}` yet (last: {last[1]} for `{last[0][:12]}`)', where(last)
    pr = os.environ.get('PR', '<n>')
    return 'wait', 'not run yet', f'`/visual-verify pr:{pr}`'


def section_state(name, st, head, jobs):
    if st and st.get('sha') == head:
        return st['state'], st['text']
    names = JOBS[name]
    if jobs is None or any(jobs.get(n, ('running',))[0] == 'running' for n in names):
        return 'running', 'running'
    if name == 'verify' and 'nocode' in (jobs.get('build', ('',))[0], jobs.get('verify', ('',))[0]):
        return 'skip', NO_CODE
    if name == 'verify' and jobs.get('build', ('',))[0] != 'pass':
        return 'skip', 'not run: the build did not pass'
    if name == 'review' and jobs.get('review', ('',))[0] == 'cancelled':
        return 'fail', 'stopped: the review job was cancelled or ran past its time limit'
    if st:
        return 'fail', f"not run for `{head[:12]}` (last: {st['text']} for `{st['sha'][:12]}`)"
    return 'fail', 'not run'


def build_run(head):
    if os.environ.get('RUN_ID'):
        return os.environ['RUN_ID']
    return gh(f'repos/{{owner}}/{{repo}}/actions/workflows/build.yml/runs?head_sha={head}&event=pull_request',
              '--jq', '.workflow_runs[0].id // empty').strip()


def summary(runs):
    pr = os.environ['PR']
    head_env = os.environ.get('HEAD_SHA', '')
    head = gh(f'repos/{{owner}}/{{repo}}/pulls/{pr}', '--jq', '.head.sha').strip()
    if head_env and head_env != head:
        print(f'skipping the summary: {head_env[:12]} is no longer the head of PR #{pr} ({head[:12]})')
        return None
    comments, mine = [], {}
    for c in lines_json(f'repos/{{owner}}/{{repo}}/issues/{pr}/comments', '--paginate', '--jq',
                        '.[] | {id, user: .user.login, body, html_url, author_association} | tojson'):
        m = re.match(r'<!-- pr-proof:([a-z]+) -->', c['body'] or '')
        if c['user'] == 'github-actions[bot]' and m:
            mine.setdefault(m.group(1), c)
        elif c['author_association'] in TRUSTED or c['user'] == 'claude[bot]':
            comments.append((c['body'], c['html_url']))
    run_id = runs.get(head) or build_run(head)
    runs[head] = run_id
    jobs = job_states(run_id)
    link = lambda n, t: f"[{t}](#issuecomment-{mine[n]['id']})" if n in mine else t
    checks = []
    if jobs is None:
        build = ('running', 'unknown', '')
    else:
        b = jobs.get('build', ('running', ''))
        build = ('fail' if b[0] == 'cancelled' else 'skip' if b[0] == 'nocode' else b[0],
                 {'pass': 'passed', 'fail': 'failed', 'running': 'running', 'skip': 'skipped', 'nocode': NO_CODE}.get(b[0], b[0]),
                 f'[build job]({b[1]})' if b[1] else '')
    checks.append(('Build', build[0], build[1], build[2]))
    status = {n: hidden(mine.get(n, {}).get('body'), 'status') for n in JOBS}
    v = section_state('verify', status['verify'], head, jobs)
    checks.append(('Verify', v[0], v[1], link('verify', 'Verify comment')))
    a = audit(comments, head)
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
    elif a[0] == 'wait' and a[1].startswith('INCONCLUSIVE'):
        title = '⚠️ Screenshot audit inconclusive: the owner decides'
    elif a[0] == 'wait':
        title = '⏳ waiting for the screenshot audit'
    else:
        title = '✅ ready for review'
    run_url = os.environ.get('RUN_URL') or (f"https://github.com/{os.environ['GH_REPO']}/actions/runs/{run_id}"
                                            if run_id and os.environ.get('GH_REPO') else '')
    out = [f'## PR proof: {title}', '', f"Head `{head[:12]}`" + (f' · [workflow run]({run_url})' if run_url else ''), '',
           '| Check | Result | Where |', '|---|---|---|']
    out += [f'| {n} | {ICON.get(s, "⚠️")} {cell(t)} | {w} |' for n, s, t, w in checks]
    data = hidden(mine.get('verify', {}).get('body'), 'data') or {}
    vsha = (status['verify'] or {}).get('sha', '')
    stale = f' (as of `{vsha[:12]}`, not the head)' if data and vsha and vsha != head else ''
    out += ['', '### The key result' + stale, '']
    if data.get('key'):
        out.append(data['key'])
    elif data and vsha == head:
        out.append("No key result: the PR's issue has no verify script with a before/after pair.")
    elif v[1] == NO_CODE:
        out.append('No key result: verify did not run, because the PR changes no code, packaging or CI scripts.')
    else:
        out.append('No key result yet: verify has not published shots for this head.')
    out += ['', '### Shots' + stale, '']
    out.append(data.get('shots') or 'No screenshots yet.')
    return '\n'.join(out) + '\n'


def main():
    d = os.environ.get('OUT') or os.path.join(os.environ.get('RUNNER_TEMP') or os.environ.get('TMPDIR') or '/tmp', 'pr-summary')
    os.makedirs(d, exist_ok=True)
    path = os.path.join(d, 'summary.md')
    env = dict(os.environ, OUT=os.path.join(d, 'comment'))
    written = None
    runs = {}
    for _ in range(3):
        body = summary(runs)
        if body is None or body == written:
            return
        open(path, 'w').write(body)
        subprocess.run([os.path.join(HERE, 'pr-comment.sh'), 'put', 'summary', path], check=True, env=env)
        if os.environ.get('DRY_RUN') == '1':
            return
        written = body


if __name__ == '__main__':
    try:
        main()
    except subprocess.CalledProcessError as err:
        sys.exit(f'{err.cmd[:3]} failed: {err.stderr or err}')
