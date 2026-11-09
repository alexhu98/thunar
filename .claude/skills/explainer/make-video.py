#!/usr/bin/env python3
"""Narrated video of an explainer page: explainers/<n>-<slug>.html + .narration.json -> .mp4

  make-video.py status <n>          lines whose page text changed since the last stamp, and video mode problems
  make-video.py stamp <n>           record the page's current text in the narration file
  make-video.py phonemes <n> [--all] Kokoro phonemes for lines not voiced yet (or all)
  make-video.py render <n>          voice, screenshot and join into explainers/<n>-<slug>.mp4

status and stamp need only Chrome ($CHROME, default google-chrome), so they also run in the cloud and in CI.
phonemes and render are local only. Voice: Kokoro af_heart in $TTS_DIR (default ~/.claude/usage-data/rebuild/tts).
Work files and the voice cache live in $EXPLAINER_CACHE (default ~/.cache/explainer-video).
The committed page is never modified: video mode is added to a copy in the work dir.
"""
import glob, hashlib, html, json, os, pathlib, re, shlex, shutil, subprocess, sys, wave

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..', '..', '..'))
TTS = os.path.expanduser(os.environ.get('TTS_DIR', '~/.claude/usage-data/rebuild/tts'))
CACHE = os.path.expanduser(os.environ.get('EXPLAINER_CACHE', '~/.cache/explainer-video'))
CHROME = os.environ.get('CHROME', 'google-chrome')
NO_SANDBOX = ['--no-sandbox'] if os.geteuid() == 0 or os.environ.get('CI') else []
ESPEAK = dict(lib_path='/usr/lib/x86_64-linux-gnu/libespeak-ng.so.1',
              data_path='/usr/lib/x86_64-linux-gnu/espeak-ng-data')
RATE = 24000
FPS = 30
MAX_CAPTION_LINES = 2


def die(msg):
    sys.exit(f'make-video: {msg}')


def short(s):
    return hashlib.sha1(s.encode()).hexdigest()[:12]


def need_kokoro():
    try:
        import kokoro_onnx  # noqa: F401
    except ImportError:
        py = os.path.join(TTS, 'venv', 'bin', 'python')
        if os.environ.get('MAKE_VIDEO_IN_VENV') or not os.path.exists(py):
            die(f'kokoro_onnx is not importable, here or in {py}')
        os.environ['MAKE_VIDEO_IN_VENV'] = '1'
        os.execv(py, [py] + sys.argv)


def kokoro():
    from kokoro_onnx import Kokoro
    from kokoro_onnx.config import EspeakConfig
    return Kokoro(os.path.join(TTS, 'kokoro-v1.0.int8.onnx'), os.path.join(TTS, 'voices-v1.0.bin'),
                  espeak_config=EspeakConfig(**ESPEAK))


# ---------------------------------------------------------------- files

def paths(n):
    pages = glob.glob(os.path.join(ROOT, 'explainers', f'{n}-*.html'))
    if len(pages) != 1:
        die(f'expected one explainers/{n}-*.html, found {len(pages)}')
    page = pages[0]
    stem = os.path.basename(page)[:-5]
    work = os.path.join(CACHE, stem)
    os.makedirs(work, exist_ok=True)
    return page, page[:-5] + '.narration.json', page[:-5] + '.mp4', work


def load_narration(path):
    if not os.path.exists(path):
        die(f'no narration file {os.path.relpath(path, ROOT)}: write it first (see SKILL.md)')
    with open(path, encoding='utf-8') as f:
        nar = json.load(f)
    for i, ln in enumerate(nar['lines']):
        for k in ('screen', 'caption'):
            if k not in ln:
                die(f'line {i}: missing "{k}"')
        ln.setdefault('keys', [])
    return nar


def save_narration(path, nar):
    out = ['{']
    head = {k: v for k, v in nar.items() if k not in ('lines', 'page_text')}
    for k, v in head.items():
        out.append(f'  {json.dumps(k)}: {json.dumps(v, ensure_ascii=False)},')
    out.append('  "lines": [')
    out.append(',\n'.join('    ' + json.dumps(ln, ensure_ascii=False) for ln in nar['lines']))
    out.append('  ],')
    out.append('  "page_text": {')
    pt = nar.get('page_text', {})
    out.append(',\n'.join(f'    {json.dumps(k)}: {json.dumps(v)}' for k, v in pt.items()))
    out.append('  }')
    out.append('}')
    with open(path, 'w', encoding='utf-8') as f:
        f.write('\n'.join(out) + '\n')


def page_sha(page):
    with open(page, 'rb') as f:
        return hashlib.sha256(f.read()).hexdigest()


SAY_TABLE = re.compile(r'^\|\s*`([^`]+)`\s*\|\s*`([^`]*)`\s*\|')


def say_subs():
    subs, on = [], False
    with open(os.path.join(HERE, 'SKILL.md'), encoding='utf-8') as f:
        for line in f:
            if '<!-- say:start -->' in line:
                on = True
            elif '<!-- say:end -->' in line:
                on = False
            elif on and (m := SAY_TABLE.match(line)):
                subs.append((m.group(1), m.group(2)))
    return subs


def spoken(ln, subs):
    s = ln.get('say') or ln['caption']
    for a, b in subs:
        s = re.sub(a, b, s)
    return s


# ---------------------------------------------------------------- video mode

VM_CSS = r'''
html.vm, html.vm body { width: 1920px; height: 1080px; overflow: hidden; margin: 0; background: var(--bg); }
html.vm main { display: none; }
.vm-top { position: absolute; left: 80px; right: 80px; top: 28px; display: flex; justify-content: space-between;
  font: 22px/1.3 system-ui, -apple-system, "Segoe UI", Ubuntu, sans-serif; color: var(--muted); }
.vm-top b { color: var(--text); font-weight: 650; }
.vm-stage { position: absolute; left: 80px; right: 80px; top: 80px; bottom: 180px; overflow: hidden; }
.vm-move { position: absolute; left: 0; right: 0; top: 0; }
.vm-zoom { width: 1060px; margin: 0 auto; padding: 0 16px; }
.vm-zoom.vm-card { width: 880px; text-align: center; padding-top: 10px; }
.vm-card h1 { font-size: 34px; margin: 0 0 12px; line-height: 1.2; }
.vm-card h2 { font-size: 34px; margin: 6px 0 12px; line-height: 1.2; }
.vm-card p.lead, .vm-card p.intro { font-size: 17px; margin: 0 auto 22px; max-width: 760px; }
.vm-card nav.parts { text-align: left; }
.vm-zoom section.sub > h3.sec:first-child, .vm-zoom section.sub > h2:first-child { margin-top: 0; }
.vm-focus [data-k] { opacity: .3; transition: none; }
.vm-focus [data-k].vm-hl, .vm-focus .vm-hl [data-k] { opacity: 1; }
.vm-focus .card.vm-hl, .vm-focus .note.vm-hl, .vm-focus pre.vm-hl, .vm-focus nav.parts a.vm-hl,
.vm-focus dl.gloss > div.vm-hl, .vm-focus p.vm-hl { outline: 2px solid var(--accent); outline-offset: 3px; border-radius: 8px; }
.vm-focus tr.vm-hl td, .vm-focus li.vm-hl { background: var(--accent-soft); }
.vm-focus g.vm-hl rect { stroke-width: 3.5; filter: drop-shadow(0 0 5px var(--accent)); }
.vm-cap { position: absolute; left: 50%; transform: translateX(-50%); bottom: 62px; width: max-content; max-width: 1720px;
  background: rgba(0, 0, 0, .8); color: #fff; font: 36px/1.35 system-ui, -apple-system, "Segoe UI", Ubuntu, sans-serif;
  padding: 10px 26px; border-radius: 10px; text-align: center; }
.vm-cap:empty { display: none; }
.vm-bar { position: absolute; left: 40px; right: 40px; bottom: 26px; display: flex; gap: 6px; height: 8px; }
.vm-seg { position: relative; background: rgba(255, 255, 255, .22); border-radius: 3px; overflow: hidden; }
.vm-seg i { position: absolute; left: 0; top: 0; bottom: 0; background: #ff3d3d; }
'''

VM_JS = r'''
(() => {
const D = window.VM;
const root = document.documentElement;
root.classList.add('vm');
root.dataset.theme = 'dark';
const main = document.querySelector('main');
const pristine = main.cloneNode(true);
main.remove();
const norm = s => (s || '').replace(/\s+/g, ' ').trim();

function screens() {
  const out = {};
  const title = pristine.querySelector('header#title');
  if (title) out.title = {kind: 'title', el: title, name: 'Intro'};
  pristine.querySelectorAll('section.part').forEach((p, i) => {
    const h = p.querySelector(':scope > h2');
    out[p.id] = {kind: 'part', el: p, part: i + 1, name: `Part ${i + 1} · ${norm(h && h.textContent)}`};
    p.querySelectorAll('section.sub').forEach(s => { out[s.id] = {kind: 'sub', el: s, part: i + 1, name: out[p.id].name}; });
  });
  pristine.querySelectorAll('section.sub').forEach(s => {
    if (!out[s.id]) { const h = s.querySelector('h2, h3'); out[s.id] = {kind: 'sub', el: s, part: 0, name: norm(h && h.textContent)}; }
  });
  return out;
}
const S = screens();

function keyed(sc, twice = []) {
  const sel = sc.kind === 'part' ? ':scope > [data-k]' : '[data-k]';
  const m = Object.create(null);
  sc.el.querySelectorAll(sel).forEach(e => { if (e.dataset.k in m) twice.push(e.dataset.k); else m[e.dataset.k] = e; });
  return m;
}
function defaultText(sc) {
  if (sc.kind === 'sub') { const h = sc.el.querySelector('h2, h3'); return norm(h ? h.textContent : sc.el.textContent); }
  const k = keyed(sc);
  return Object.values(k).map(e => norm(e.textContent)).join(' | ');
}

function build(f) {
  document.body.querySelectorAll('.vm-top, .vm-stage, .vm-cap, .vm-bar').forEach(e => e.remove());
  const sc = S[f.screen];
  const top = document.createElement('div'); top.className = 'vm-top';
  top.innerHTML = `<span><b></b></span><span class="vm-chap"></span>`;
  top.querySelector('b').textContent = D.title;
  top.querySelector('.vm-chap').textContent = f.chapter || '';
  const stage = document.createElement('div'); stage.className = 'vm-stage';
  const move = document.createElement('div'); move.className = 'vm-move';
  const zoom = document.createElement('div'); zoom.className = 'vm-zoom';
  stage.appendChild(move); move.appendChild(zoom);
  const cap = document.createElement('div'); cap.className = 'vm-cap'; cap.textContent = f.caption;
  const bar = document.createElement('div'); bar.className = 'vm-bar';
  (D.chapters || []).forEach(c => {
    const g = document.createElement('div'); g.className = 'vm-seg'; g.style.flex = String(Math.max(c.b - c.a, 1e-6));
    const i = document.createElement('i'); i.style.width = (Math.max(0, Math.min(1, (f.t - c.a) / (c.b - c.a))) * 100) + '%';
    g.appendChild(i); bar.appendChild(g);
  });
  document.body.append(top, stage, cap, bar);
  if (!sc) return {problems: [`screen "${f.screen}" not found`]};
  let content;
  if (sc.kind !== 'part') {
    content = sc.el.cloneNode(true);
    if (sc.kind === 'title') zoom.classList.add('vm-card');
  } else {
    zoom.classList.add('vm-card');
    content = document.createElement('div');
    Object.values(keyed(sc)).forEach(e => content.appendChild(e.cloneNode(true)));
  }
  zoom.appendChild(content);
  const problems = [];
  const hl = [];
  if (f.keys.length) {
    zoom.classList.add('vm-focus');
    const m = Object.create(null);
    zoom.querySelectorAll('[data-k]').forEach(e => { if (!(e.dataset.k in m)) m[e.dataset.k] = e; });
    f.keys.forEach(k => { if (m[k]) { m[k].classList.add('vm-hl'); hl.push(m[k]); } else problems.push(`key "${k}" not in screen "${f.screen}"`); });
  }
  const st = stage.getBoundingClientRect();
  const wide = [...zoom.querySelectorAll('*')].filter(e => !hl.length || hl.some(h => e.contains(h) || h.contains(e)));
  const overflow = () => Math.max(0, ...wide.map(e => e.scrollWidth - e.clientWidth));
  let over = overflow();
  while (over > 1) {
    const base = zoom.style.width;
    zoom.style.width = (zoom.getBoundingClientRect().width + over) + 'px';
    const left = overflow();
    if (left > over / 2) { zoom.style.width = base; break; }
    over = left;
  }
  if (over > 1) problems.push(`content of "${f.screen}" overflows by ${Math.ceil(over)} px`);
  const nat = zoom.getBoundingClientRect();
  const fitWidth = st.width / nat.width;
  let z = Math.min(fitWidth, st.height / nat.height, sc.kind === 'sub' ? 1.9 : 2.0);
  if (z < 1.45) z = Math.min(fitWidth, 1.55);
  if (hl.length) {
    const rs = hl.map(e => e.getBoundingClientRect());
    const hlH = Math.max(...rs.map(r => r.bottom)) - Math.min(...rs.map(r => r.top)) + 16;
    z = Math.min(z, st.height / hlH);
  }
  if (z < 1) problems.push(`zoom ${Math.floor(z * 100) / 100} of "${f.screen}" is too small to read`);
  zoom.style.zoom = z;
  const zr = zoom.getBoundingClientRect();
  let y;
  if (zr.height <= st.height) y = (st.height - zr.height) / 2;
  else if (hl.length) {
    const rs = hl.map(e => e.getBoundingClientRect());
    const a = Math.min(...rs.map(r => r.top)) - zr.top, b = Math.max(...rs.map(r => r.bottom)) - zr.top;
    y = Math.min(0, Math.max(st.height - zr.height, st.height / 2 - (a + b) / 2));
  } else y = 0;
  move.style.top = y + 'px';
  hl.forEach(e => {
    const r = e.getBoundingClientRect();
    if (r.top < st.top - 1 || r.bottom > st.bottom + 1 || r.left < st.left - 1 || r.right > st.right + 1)
      problems.push(`key "${e.dataset.k}" of "${f.screen}" is not fully on screen`);
  });
  const lh = parseFloat(getComputedStyle(cap).lineHeight);
  const lines = cap.textContent ? Math.round((cap.clientHeight - 20) / lh) : 0;
  if (lines > D.maxLines) problems.push(`caption wraps to ${lines} lines`);
  return {problems, zoom: Math.round(z * 100) / 100, lines};
}

const q = new URLSearchParams(location.search);
if (q.has('probe')) {
  const texts = {}, info = {}, dups = [];
  for (const [id, sc] of Object.entries(S)) {
    const twice = [];
    texts[id] = {'': defaultText(sc)};
    for (const [k, e] of Object.entries(keyed(sc, twice))) texts[id][k] = norm(e.textContent);
    dups.push(...twice.map(k => `${id}/${k}`));
    info[id] = {kind: sc.kind, part: sc.part || 0, name: sc.name};
  }
  const frames = D.frames.map(build);
  const pre = document.createElement('pre'); pre.id = 'vm-probe';
  pre.textContent = JSON.stringify({texts, screens: info, frames, dups});
  document.body.appendChild(pre);
} else {
  build(D.frames[+q.get('i')]);
}
})();
'''


def write_video_page(page, work, data):
    with open(page, encoding='utf-8') as f:
        src = f.read()
    if '</body>' not in src:
        die('page has no </body>')
    vm = json.dumps(data, ensure_ascii=False).replace('<', '\\u003c')
    inject = f'<style>{VM_CSS}</style>\n<script>window.VM = {vm};</script>\n<script>{VM_JS}</script>\n</body>'
    out = os.path.join(work, 'video.html')
    at = src.rindex('</body>')
    with open(out, 'w', encoding='utf-8') as f:
        f.write(src[:at] + inject + src[at + len('</body>'):])
    return out


def chrome(args, prof):
    try:
        return subprocess.run([CHROME] + NO_SANDBOX + ['--headless=new', '--disable-gpu', '--hide-scrollbars', '--force-device-scale-factor=1',
                               f'--user-data-dir={prof}', '--window-size=1920,1080', '--virtual-time-budget=2000'] + args,
                              capture_output=True, text=True, timeout=180)
    except subprocess.TimeoutExpired:
        die(f'{CHROME} did not finish within 180 s (see SKILL.md for the Chrome to use in the cloud container)')


def probe(page, work, nar, subs):
    frames = [{'screen': ln['screen'], 'keys': ln['keys'], 'caption': ln['caption'], 't': 0, 'chapter': ''}
              for ln in nar['lines']]
    vp = write_video_page(page, work, {'title': nar.get('title', ''), 'frames': frames, 'chapters': [],
                                       'maxLines': MAX_CAPTION_LINES})
    r = chrome(['--dump-dom', pathlib.Path(vp).as_uri() + '?probe'], os.path.join(work, 'prof-probe'))
    m = re.search(r'<pre id="vm-probe">(.*?)</pre>', r.stdout, re.S)
    if not m:
        die('probe failed:\n' + r.stderr[-2000:])
    res = json.loads(html.unescape(m.group(1)))
    if res['dups']:
        die('keys used twice in one screen (each data-k must be unique within its section.sub): ' + ', '.join(res['dups']))
    return res


def fingerprint(ln, texts):
    sc = texts.get(ln['screen'])
    if sc is None:
        return None
    keys = ln.get('from', ln['keys'])
    if not keys:
        return short(sc[''])
    if any(k not in sc for k in keys):
        return None
    return short('\n'.join(sc[k] for k in keys))


def page_text(texts):
    return {f'{s}/{k}': short(v) for s, d in texts.items() for k, v in d.items() if k}


# ---------------------------------------------------------------- status / stamp

def video_problems(pr, missing=()):
    return [f'line {i}: {p}' for i, fr in enumerate(pr['frames']) for p in fr['problems']
            if i not in missing or not p.startswith(('key ', 'screen '))]


def status(n, quiet=False):
    page, narp, _, work = paths(n)
    nar = load_narration(narp)
    pr = probe(page, work, nar, say_subs())
    stale = []
    for i, ln in enumerate(nar['lines']):
        fp = fingerprint(ln, pr['texts'])
        if fp is None or fp != ln.get('src'):
            stale.append((i, ln, 'missing' if fp is None else 'changed'))
    now = page_text(pr['texts'])
    old = nar.get('page_text', {})
    narrated = set()
    for ln in nar['lines']:
        keys = ln.get('from', ln['keys'])
        if not keys and pr['screens'].get(ln['screen'], {}).get('kind') in ('title', 'part'):
            keys = [k for k in pr['texts'][ln['screen']] if k]
        narrated |= {f"{ln['screen']}/{k}" for k in keys}
    loose = [k for k in now if old and k not in narrated and old.get(k) != now[k]]
    gone = [k for k in old if k not in now]
    same_page = nar.get('page_sha256') == page_sha(page)
    problems = video_problems(pr, {i for i, _, why in stale if why == 'missing'})
    if not quiet:
        print(f'page {"unchanged" if same_page else "changed"} since the last stamp')
        for i, ln, why in stale:
            print(f'  stale line {i} ({why}): [{ln["screen"]} {",".join(ln.get("from", ln["keys"]))}] {ln["caption"]}')
        for k in loose:
            print(f'  {"new" if k not in old else "changed"} page text no line narrates: {k} = {pr["texts"][k.split("/")[0]][k.split("/", 1)[1]][:90]}')
        for k in gone:
            print(f'  removed from the page: {k}')
        for p in problems:
            print(f'  video mode problem: {p}')
        if not stale and not loose and not gone and not same_page:
            print('no narrated text changed; run stamp' + (' once the video mode problems are fixed' if problems else ''))
        elif not stale and not loose and not gone and not problems:
            print('narration matches the page')
    return page, narp, nar, pr, stale, loose, same_page, problems


def stamp(n):
    page, narp, nar, pr, stale, loose, _, problems = status(n, quiet=True)
    for i, ln, why in stale:
        if why == 'missing':
            die(f'line {i} names a screen or key the page doesn\'t have: {ln["screen"]} {ln.get("from", ln["keys"])}')
    for ln in nar['lines']:
        ln['src'] = fingerprint(ln, pr['texts'])
    nar['page_sha256'] = page_sha(page)
    nar['page_text'] = page_text(pr['texts'])
    save_narration(narp, nar)
    print(f'stamped {len(nar["lines"])} lines ({len(stale)} were stale) against {os.path.basename(page)}')
    for p in problems:
        print(f'  video mode problem: {p}')
    for k in loose:
        print(f'  note: {k} changed and no line narrates it')


# ---------------------------------------------------------------- voice

def clip_path(text, voice):
    d = os.path.join(CACHE, 'clips')
    os.makedirs(d, exist_ok=True)
    return os.path.join(d, hashlib.sha1(f'{voice}|{text}'.encode()).hexdigest() + '.npy')


def phonemes(n, everything):
    need_kokoro()
    _, narp, _, _ = paths(n)
    nar = load_narration(narp)
    subs, voice = say_subs(), nar.get('voice', 'af_heart')
    k = kokoro()
    for i, ln in enumerate(nar['lines']):
        text = spoken(ln, subs)
        if everything or not os.path.exists(clip_path(text, voice)):
            print(f'{i:3d} {text}\n    {k.tokenizer.phonemize(text, "en-us")}')


def synth(lines_text, voice):
    import numpy as np
    k, made, clips = None, 0, []
    for text in lines_text:
        p = clip_path(text, voice)
        if not os.path.exists(p):
            if k is None:
                k = kokoro()
            samples, rate = k.create(text, voice=voice, speed=1.0, lang='en-us')
            assert rate == RATE, rate
            np.save(p, (np.clip(samples, -1, 1) * 32767).astype(np.int16))
            made += 1
            print(f'  voiced: {text}', flush=True)
        clips.append(np.load(p))
    return clips, made


# ---------------------------------------------------------------- render

def timeline(nar, clips, info):
    import numpy as np
    lead, tail = int(RATE * 0.6), int(RATE * 2.0)
    parts, frames, pos = [np.zeros(lead, np.int16)], [], lead
    prev = None
    seen_part = False
    for i, (ln, clip) in enumerate(zip(nar['lines'], clips)):
        sc = info[ln['screen']]
        if sc['kind'] == 'title':
            chapter = 'Wrap-up' if seen_part else 'Intro'
        else:
            chapter = sc['name']
            seen_part = seen_part or sc['part'] > 0
        if i == 0:
            gap = 0
        elif prev and chapter != prev['chapter']:
            gap = int(RATE * 1.0)
        elif prev and ln['screen'] != prev['screen']:
            gap = int(RATE * 0.6)
        else:
            gap = int(RATE * 0.3)
        parts.append(np.zeros(gap, np.int16))
        pos += gap
        fr = {'start': 0 if i == 0 else pos - gap, 'speech': pos, 'screen': ln['screen'], 'keys': ln['keys'],
              'caption': ln['caption'], 'chapter': chapter}
        frames.append(fr)
        parts.append(clip)
        pos += len(clip)
        prev = fr
    parts.append(np.zeros(tail, np.int16))
    pos += tail
    for i, fr in enumerate(frames):
        fr['end'] = frames[i + 1]['start'] if i + 1 < len(frames) else pos
    return np.concatenate(parts), frames, pos


def chapters_of(frames, total):
    out = []
    for fr in frames:
        if not out or out[-1]['name'] != fr['chapter']:
            out.append({'name': fr['chapter'], 'start': fr['start']})
    for i, c in enumerate(out):
        c['end'] = out[i + 1]['start'] if i + 1 < len(out) else total
    return out


def render(n, force):
    need_kokoro()
    page, narp, nar, pr, stale, loose, same_page, _ = status(n, quiet=True)
    if (stale or not same_page) and not force:
        status(n)
        die('the narration is older than the page: rewrite the stale lines, run stamp, then render')
    problems = video_problems(pr)
    if problems:
        die('video mode problems:\n  ' + '\n  '.join(problems))
    _, _, out, work = paths(n)
    subs, voice = say_subs(), nar.get('voice', 'af_heart')
    texts = [spoken(ln, subs) for ln in nar['lines']]
    clips, made = synth(texts, voice)
    print(f'voice: {made} new clip(s), {len(clips) - made} from cache')
    audio, frames, total = timeline(nar, clips, pr['screens'])
    chaps = chapters_of(frames, total)
    data = {'title': nar.get('title', ''), 'maxLines': MAX_CAPTION_LINES,
            'chapters': [{'name': c['name'], 'a': c['start'] / total, 'b': c['end'] / total} for c in chaps],
            'frames': [{'screen': f['screen'], 'keys': f['keys'], 'caption': f['caption'], 'chapter': f['chapter'],
                        't': f['start'] / total} for f in frames]}
    vp = write_video_page(page, work, data)
    fdir = os.path.join(work, 'frames')
    shutil.rmtree(fdir, ignore_errors=True)
    os.makedirs(fdir)
    q = shlex.quote
    cmd = (f'i=$0; {q(CHROME)} {" ".join(NO_SANDBOX)} --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=1 '
           f'--user-data-dir={q(work)}/prof/$i --window-size=1920,1080 --virtual-time-budget=2000 '
           f'--screenshot={q(fdir)}/f$(printf %03d $i).png {q(pathlib.Path(vp).as_uri())}"?i=$i" >/dev/null 2>&1')
    subprocess.run(['xargs', '-P', '12', '-I{}', 'bash', '-c', cmd, '{}'],
                   input='\n'.join(str(i) for i in range(len(frames))), text=True, check=True)
    shutil.rmtree(os.path.join(work, 'prof'), ignore_errors=True)
    missing = [i for i in range(len(frames)) if not os.path.exists(f'{fdir}/f{i:03d}.png')]
    if missing:
        die(f'no screenshot for lines {missing}')

    wav = os.path.join(work, 'audio.wav')
    with wave.open(wav, 'wb') as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(RATE); w.writeframes(audio.tobytes())
    def listed(i):
        return "file '" + f'{fdir}/f{i:03d}.png'.replace("'", "'\\''") + "'"
    lst = [f"{listed(i)}\nduration {(f['end'] - f['start']) / RATE:.6f}" for i, f in enumerate(frames)]
    lst.append(listed(len(frames) - 1))
    with open(os.path.join(work, 'frames.txt'), 'w', encoding='utf-8') as f:
        f.write('\n'.join(lst) + '\n')
    def esc(v):
        return re.sub(r'([=;#\\\n])', r'\\\1', v)
    meta = [';FFMETADATA1', f'title={esc(nar.get("title", ""))}']
    for c in chaps:
        meta += ['[CHAPTER]', 'TIMEBASE=1/1000', f'START={c["start"] * 1000 // RATE}', f'END={c["end"] * 1000 // RATE}',
                 f'title={esc(c["name"])}']
    with open(os.path.join(work, 'chapters.txt'), 'w', encoding='utf-8') as f:
        f.write('\n'.join(meta) + '\n')
    subprocess.run(['ffmpeg', '-nostdin', '-y', '-loglevel', 'error',
                    '-f', 'concat', '-safe', '0', '-i', os.path.join(work, 'frames.txt'), '-i', wav,
                    '-i', os.path.join(work, 'chapters.txt'),
                    '-map', '0:v', '-map', '1:a', '-map_metadata', '2', '-map_chapters', '2',
                    '-vf', f'fps={FPS},format=yuv420p', '-c:v', 'libx264', '-tune', 'stillimage', '-crf', '20',
                    '-preset', 'medium', '-af', 'loudnorm=I=-16:TP=-1.5', '-ar', '48000', '-c:a', 'aac', '-b:a', '160k',
                    '-t', f'{total / RATE:.3f}', '-movflags', '+faststart', out], check=True)
    with open(os.path.join(work, 'timeline.json'), 'w', encoding='utf-8') as f:
        json.dump({'rate': RATE, 'total': total, 'chapters': chaps,
                   'lines': [{k: fr[k] for k in ('start', 'speech', 'end', 'screen', 'caption')} for fr in frames]},
                  f, indent=1, ensure_ascii=False)

    def dur(stream):
        r = subprocess.run(['ffprobe', '-v', 'error', '-select_streams', stream, '-show_entries', 'stream=duration',
                            '-of', 'csv=p=0', out], capture_output=True, text=True, check=True)
        return float(r.stdout.strip())
    v, a = dur('v:0'), dur('a:0')
    print(f'{os.path.relpath(out, ROOT)}: {total / RATE:.2f}s, picture {v:.3f}s, sound {a:.3f}s, '
          f'difference {abs(v - a) * 1000:.0f} ms ({"within" if abs(v - a) <= 1 / FPS else "MORE than"} one frame)')
    for c in chaps:
        s = c['start'] // RATE
        print(f'  {s // 60}:{s % 60:02d} {c["name"]}')
    print(f'work files: {work}')


if __name__ == '__main__':
    a = sys.argv[1:]
    if len(a) < 2 or a[0] not in ('status', 'stamp', 'phonemes', 'render'):
        sys.exit(__doc__)
    cmd, n = a[0], a[1]
    if cmd == 'status':
        _, _, _, _, stale, loose, same, problems = status(n)
        sys.exit(1 if stale or loose or not same or problems else 0)
    elif cmd == 'stamp':
        stamp(n)
    elif cmd == 'phonemes':
        phonemes(n, '--all' in a)
    else:
        render(n, '--force' in a)
