#!/usr/bin/env python3
"""Numbered shots, pair images and the verify comment, for verify-proof.sh.

verify-shots.py check DIR
    For a test that passed: fails unless every before-<what> in DIR/shots.tsv has its after-<what> and one row in
    DIR/pairs.tsv (verify-lib.sh's pair), and every row in DIR/pairs.tsv has both of its shots.
verify-shots.py build OUT
    Numbers the shots of the tests in $OUT/results.tsv (the verify scripts in order, then the smoke test; a pair is one
    number), and writes $OUT/numbered.json, the manifest $OUT/verify.tsv and each pair's 1920px image as
    $OUT/pairs/<test>-<what>.png.
verify-shots.py manifest OUT
    Prints the manifest with each file named as on the shots branch; a file whose upload failed ($OUT/urls.tsv) is -.
verify-shots.py comment OUT
    Prints the verify comment's body from $OUT/numbered.json, $OUT/results.tsv, the logs and $OUT/urls.tsv
    ("<local file><tab><url or ->"). Env: HEAD_SHA, HEAD_REF, RUN_URL.
"""
import json
import os
import re
import subprocess
import sys

HALF = 950
GAP = 20
BAR = 44
BG = '#57606a'
COLOURS = {'before': '#0969da', 'after': '#1a7f37'}


def rows(path, n):
    if not os.path.exists(path):
        return []
    out = []
    for ln in open(path, encoding='utf-8'):
        ln = ln.rstrip('\n')
        if ln:
            out.append((ln.split('\t') + [''] * n)[:n])
    return out


def check(d):
    shots = [r[0] for r in rows(os.path.join(d, 'shots.tsv'), 2)]
    pairs = [r[0] for r in rows(os.path.join(d, 'pairs.tsv'), 6)]
    errors = []
    whats = {s.split('-', 1)[1] for s in shots if re.match(r'(before|after)-', s)}
    for w in sorted(whats):
        for side, other in (('before', 'after'), ('after', 'before')):
            if f'{side}-{w}' in shots and f'{other}-{w}' not in shots:
                errors.append(f'{side}-{w} has no {other}-{w}')
        if f'before-{w}' in shots and f'after-{w}' in shots and w not in pairs:
            errors.append(f'the pair before-{w} / after-{w} has no pair call saying its action, what it proves and its states')
    for w in pairs:
        if f'before-{w}' not in shots or f'after-{w}' not in shots:
            errors.append(f'pair {w} is described, but before-{w} and after-{w} were not both saved')
    for e in errors:
        print(f'FAIL: {e}', file=sys.stderr)
    return 1 if errors else 0


def tests(out):
    res = rows(os.path.join(out, 'results.tsv'), 3)
    return [r for r in res if r[0] != 'smoke'] + [r for r in res if r[0] == 'smoke']


def number(out):
    entries = []
    for name, status, _ in tests(out):
        d = os.path.join(out, 'shots', name)
        shots = rows(os.path.join(d, 'shots.tsv'), 2)
        caption = dict((s, p) for s, p in shots)
        pairs = {r[0]: r for r in rows(os.path.join(d, 'pairs.tsv'), 6)}
        done = set()
        for shot, proves in shots:
            if shot in done:
                continue
            m = re.match(r'(before|after)-(.+)', shot)
            partner = m and f"{'after' if m.group(1) == 'before' else 'before'}-{m.group(2)}"
            if m and partner in caption:
                what = m.group(2)
                p = pairs.get(what, [what, '', '', '', '', ''])
                done.update({f'before-{what}', f'after-{what}'})
                entries.append({'test': name, 'kind': 'pair', 'what': what, 'group': p[5], 'action': p[1],
                                'proves': p[2] or caption[f'after-{what}'],
                                'shots': [{'role': role, 'name': f'{role}-{what}', 'caption': caption[f'{role}-{what}'],
                                           'state': p[3 if role == 'before' else 4],
                                           'file': f'shots/{name}/{role}-{what}.png'} for role in ('before', 'after')],
                                'image': f'pairs/{name}-{what}.png'})
            else:
                done.add(shot)
                group = ''
                if m and m.group(2) in pairs:
                    group = pairs[m.group(2)][5]
                entries.append({'test': name, 'kind': 'single', 'what': shot, 'group': group, 'action': '',
                                'proves': proves, 'shots': [{'role': 'single', 'name': shot, 'caption': proves,
                                                            'state': '', 'file': f'shots/{name}/{shot}.png'}],
                                'image': f'shots/{name}/{shot}.png'})
    for i, e in enumerate(entries, 1):
        e['num'] = i
    return entries


def bar_text(num, role, state):
    text = f'#{num} {role.upper()}' + (f' · {state}' if state else '')
    return text.replace('\\', '\\\\').replace('%', '%%')


def pointsize(text):
    width = subprocess.run(['convert', '-font', 'DejaVu-Sans-Bold', '-pointsize', '22', f'label:{text}', '-format', '%w', 'info:'],
                           capture_output=True, text=True).stdout.strip()
    return 22 if not width.isdigit() or int(width) <= HALF - 28 else max(12, 22 * (HALF - 28) // int(width))


def pair_image(out, e):
    tmp = os.path.join(out, 'pairs', 'tmp')
    os.makedirs(tmp, exist_ok=True)
    halves = []
    for s in e['shots']:
        half = os.path.join(tmp, f"{e['test']}-{s['name']}.png")
        text = bar_text(e['num'], s['role'], s['state'])
        subprocess.run(['convert', '(', '-size', f'{HALF}x{BAR}', f"xc:{COLOURS[s['role']]}", '-font', 'DejaVu-Sans-Bold',
                        '-pointsize', str(pointsize(text)), '-fill', 'white', '-gravity', 'west', '-annotate', '+14+0',
                        text, ')',
                        '(', os.path.join(out, s['file']), '-resize', f'{HALF}x>', ')',
                        '-background', BG, '-gravity', 'center', '-append', '+repage', half], check=True)
        halves.append(half)
    dest = os.path.join(out, e['image'])
    subprocess.run(['convert', halves[0], '(', '-size', f'{GAP}x1', f'xc:{BG}', ')', halves[1],
                    '-background', BG, '-gravity', 'north', '+append', '+repage', '-depth', '8', dest], check=True)
    for h in halves:
        os.remove(h)
    os.rmdir(tmp)


def manifest(out, entries, where, lost=()):
    sha = os.environ.get('HEAD_SHA') or subprocess.run(['git', 'rev-parse', 'HEAD'], capture_output=True, text=True).stdout.strip() or 'unknown'
    lines = ['sha\tnum\ttest\tresult\tshot\tfile\tproves']
    by_test = {}
    for e in entries:
        for s in e['shots']:
            by_test.setdefault(e['test'], []).append((e['num'], s))
    for name, status, _ in tests(out):
        if name not in by_test:
            lines.append(f'{sha}\t-\t{name}\t{status}\t-\t-\t-')
            continue
        for num, s in sorted(by_test[name], key=lambda x: x[0]):
            f = s['file'] if where == 'local' else f"verify-{name}-{s['name']}.png"
            if s['file'] in lost:
                f = '-'
            lines.append(f"{sha}\t{num}\t{name}\t{status}\t{s['name']}\t{f}\t{s['caption']}")
    return '\n'.join(lines) + '\n'


def build(out):
    entries = number(out)
    os.makedirs(os.path.join(out, 'pairs'), exist_ok=True)
    failed = 0
    for e in entries:
        if e['kind'] == 'pair':
            try:
                pair_image(out, e)
            except (subprocess.CalledProcessError, OSError) as err:
                print(f"could not make the image of pair #{e['num']} ({e['test']}/{e['what']}): {err}", file=sys.stderr)
                e['image'] = None
                failed = 1
    json.dump(entries, open(os.path.join(out, 'numbered.json'), 'w'), indent=1)
    open(os.path.join(out, 'verify.tsv'), 'w').write(manifest(out, entries, 'local'))
    return failed


def urls(out):
    return {k: v for k, v in rows(os.path.join(out, 'urls.tsv'), 2)}


def cell(s):
    return ' '.join(str(s).split()).replace('|', '\\|')


def label(name):
    if name == 'smoke':
        return 'Smoke test'
    return f'`verify/{name}.sh`' if re.fullmatch(r'[0-9]+', name) else f'`verify/{name}`'


def names(e):
    return ' / '.join(s['name'] for s in e['shots'])


def block(e, u, anchor):
    n = e['num']
    lines = [f'<a name="shot-{n}"></a>', ''] if anchor else []
    lines += [f'| [Shot #{n}](#shot-{n}) | {cell(names(e))} |', '|---|---|']
    if e['kind'] == 'pair':
        lines += [f"| **Action** | {cell(e['action'])} |", f"| **Proves** | {cell(e['proves'])} |",
                  f"| **Before** | {cell(e['shots'][0]['caption'])} |", f"| **After** | {cell(e['shots'][1]['caption'])} |"]
    else:
        lines.append(f"| **Proves** | {cell(e['proves'])} |")
    url = u.get(e['image'] or '', '-')
    lines.append('')
    if url == '-':
        what = 'image of this pair' if e['kind'] == 'pair' else 'screenshot'
        lines.append(f"The {what} could not be made or uploaded; the originals are in the run's `verify` artifact.")
    else:
        lines.append(f'![#{n} {names(e)}]({url})')
    return '\n'.join(lines)


def key_entry(entries):
    m = re.match(r'([0-9]+)-', os.environ.get('HEAD_REF', ''))
    pairs = [e for e in entries if e['kind'] == 'pair' and e['test'] != 'smoke']
    own = [e for e in pairs if m and e['test'] == m.group(1)]
    return (own or pairs or [None])[0]


def comment(out):
    sha = os.environ.get('HEAD_SHA') or subprocess.run(['git', 'rev-parse', 'HEAD'], capture_output=True, text=True).stdout.strip()
    run_url = os.environ.get('RUN_URL', '')
    res = tests(out)
    entries = json.load(open(os.path.join(out, 'numbered.json'))) if os.path.exists(os.path.join(out, 'numbered.json')) else []
    u = urls(out)
    lost = [k for k, v in u.items() if v == '-'] + [e['num'] for e in entries if not e['image']]
    lines = []
    if not res:
        status = {'sha': sha, 'state': 'fail', 'text': 'did not run'}
        lines += ['### Verify: did not run', '', f'The job stopped before the tests, as of `{sha[:12]}`. See [the run]({run_url}).']
        data = {'key': '', 'shots': ''}
        return status, data, lines
    total = len(res)
    passed = sum(1 for r in res if r[1] == 'pass')
    complete = os.path.exists(os.path.join(out, 'complete'))
    head = f'{passed} of {total} passed' if complete else f'cut short, {passed} of {total} passed'
    ok = complete and passed == total and not lost
    text = head + (f'; {len(lost)} image(s) missing' if lost else '')
    status = {'sha': sha, 'state': 'pass' if ok else 'fail', 'text': text}
    theme = open(os.path.join(out, 'theme')).read().strip() if os.path.exists(os.path.join(out, 'theme')) else 'default'
    lines += [f'### Verify: {head}', '']
    if not complete:
        lines += ['The run step stopped before it finished, so later tests are missing.', '']
    if lost:
        lines += [f"{len(lost)} image(s) could not be made or uploaded to the `shots` branch; see the run's `verify` artifact.", '']
    lines += [f'Xvfb, xfwm4 and the {theme} GTK theme, as of `{sha[:12]}`. [Logs]({run_url})', '',
              '| Test | Result | Time |', '|---|---|---|']
    for name, st, secs in res:
        lines.append(f"| {label(name)} | {'✅ pass' if st == 'pass' else '❌ ' + cell(st)} | {secs} s |")
    key = key_entry(entries)
    for name, st, _ in res:
        lines += ['', f'#### {label(name)}']
        if st != 'pass':
            log = os.path.join(out, 'logs', f'{name}.log')
            tail = open(log, errors='replace').read().splitlines()[-30:] if os.path.exists(log) else []
            body = '\n'.join(tail).replace('```', "'''")
            lines += ['', 'Last lines of the log:', '', '```text', body, '```']
        mine = [e for e in entries if e['test'] == name]
        if not mine:
            lines += ['', 'No screenshots.']
        group = ''
        for e in mine:
            if e['group'] and e['group'] != group:
                lines += ['', f"##### {e['group']}"]
            group = e['group'] or group
            lines.append('')
            if e is key or (key and e['num'] == key['num']):
                lines.append(f"[Shot #{e['num']}](#shot-{e['num']}) ({cell(names(e))}) is the key result, shown in the summary.")
            else:
                lines.append(block(e, u, True))
    table = ['| # | Shots | Proves |', '|---|---|---|']
    for e in entries:
        what = names(e) + (' (smoke test)' if e['test'] == 'smoke' else '')
        table.append(f"| [{e['num']}](#shot-{e['num']}) | {cell(what)} | {cell(e['proves'])} |")
    data = {'key': block(key, u, True) if key else '', 'shots': '\n'.join(table) if entries else ''}
    return status, data, lines


def hidden(kind, obj):
    return f'<!-- pr-proof:{kind} ' + json.dumps(obj, ensure_ascii=False, separators=(',', ':')).replace('>', '\\u003e') + ' -->'


if __name__ == '__main__':
    cmd, args = (sys.argv[1], sys.argv[2:]) if len(sys.argv) > 2 else ('', [])
    if cmd == 'check':
        sys.exit(check(args[0]))
    elif cmd == 'build':
        sys.exit(build(args[0]))
    elif cmd == 'manifest':
        out = args[0]
        entries = json.load(open(os.path.join(out, 'numbered.json')))
        sys.stdout.write(manifest(out, entries, 'shots', {k for k, v in urls(out).items() if v == '-'}))
    elif cmd == 'comment':
        status, data, lines = comment(args[0])
        print('\n'.join([hidden('status', status), hidden('data', data), *lines]))
    else:
        sys.exit(__doc__)
