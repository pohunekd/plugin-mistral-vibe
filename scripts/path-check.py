"""Fail on operator path material in the corpus screens.

Usage: python3 -I -B scripts/path-check.py [--generic-only | --tokens FILE] [corpus-dir]

Token sources (one is required, there is no silent fallback):
  --tokens FILE     generic tokens plus the tokens of FILE (one per line, `#` comments and blank
                    lines ignored; a file with no token is an error)
  --generic-only    the generic tokens only (what the CI runs)
  neither           the local token file `scripts/path-tokens.local` next to this script; when it
                    does not exist the check exits 2 and names the file and the flag
The local token file is gitignored and never ships: it holds the host-specific path fragments
that must not appear in the public package.

Generic tokens: `/mnt/`, `/tmp/`, `captures/r-`, `zajca` outside `github.com/zajca/pohunek`
and a `/home/<user>` prefix.

Each screen is searched in three views, each collapsed by removing box-drawing characters, block
characters, `…` and all whitespace (a path a narrow terminal wrapped across box rows, or a footer
cut with a leading `…`, is found like an unbroken one):
  - the rendered frame at the case width (50 rows) at the end of the stream and the frame
    standing before every full-screen erase (ED 2/3, RIS), plus every row that scrolled off;
  - the raw bytes with every escape sequence removed (CSI, OSC/DCS/APC/PM/SOS strings and the
    nF/Fp/Fe/Fs two-byte forms).
Not detected: a cut that leaves no whole token (a path whose cut-off start removes the
beginning of every token that it holds).

Exit code: 0 clean, 1 at least one token found (each file and token is listed), 2 usage or input
error. python3 standard library only.
"""
import re
import sys
import tomllib
from pathlib import Path

GENERIC_TOKENS = ('/mnt/', '/tmp/', 'captures/r-', 'zajca')
HOME_USER = re.compile(r'/home/[A-Za-z0-9_]')
ALLOWED = ('github.com/zajca/pohunek',)
STRIP = re.compile('[\\s─-╿▁-▏…]+')
ESCAPES = re.compile(r'\x1b(?:\[[0-?]*[ -/]*[@-~]|[\]P_^X].*?(?:\x07|\x1b\\)|[ -/]*[0-~])', re.S)
CSI = re.compile(r'\x1b\[([?>=!]?)([0-9;:]*)([ -/]*)([@-~])')
LOCAL_TOKENS = Path(__file__).resolve().parent / 'path-tokens.local'
ROWS = 50


def render(data, cols, rows=ROWS):
    """Minimal VT renderer: cursor moves, erases, CR/LF/BS and autowrap; SGR and modes ignored.

    Returns the text blocks to search: every frame standing before a full-screen erase, the
    rows that scrolled off the top, and the final frame."""
    blocks = []
    scrolled = []

    def blank():
        return [' '] * cols

    def text(grid):
        return '\n'.join(''.join(x).rstrip(' ') for x in grid)

    def scroll(grid):
        scrolled.append(''.join(grid.pop(0)).rstrip(' '))
        grid.append(blank())

    scr = [blank() for _ in range(rows)]
    r = c = 0
    i = 0
    n = len(data)
    pending_wrap = False
    while i < n:
        ch = data[i]
        if ch == '\x1b':
            if i + 1 < n and data[i + 1] == '[':
                m = CSI.match(data, i)
                if not m:
                    i += 1
                    continue
                priv, params, _inter, fin = m.groups()
                ps = [int(x) if x else 0 for x in re.split('[;:]', params)] if params else []
                i = m.end()
                if priv:
                    continue
                p1 = ps[0] if ps else 0
                if fin in 'Hf':
                    r = max(1, ps[0] if len(ps) > 0 and ps[0] else 1) - 1
                    c = max(1, ps[1] if len(ps) > 1 and ps[1] else 1) - 1
                    r, c = min(r, rows - 1), min(c, cols - 1)
                    pending_wrap = False
                elif fin == 'A':
                    r = max(0, r - max(1, p1))
                elif fin == 'B':
                    r = min(rows - 1, r + max(1, p1))
                elif fin == 'C':
                    c = min(cols - 1, c + max(1, p1))
                elif fin == 'D':
                    c = max(0, c - max(1, p1))
                elif fin == 'G':
                    c = min(cols - 1, max(1, p1) - 1)
                elif fin == 'd':
                    r = min(rows - 1, max(1, p1) - 1)
                elif fin == 'J':
                    if p1 in (2, 3):
                        blocks.append(text(scr))
                        scr = [blank() for _ in range(rows)]
                    elif p1 == 0:
                        scr[r][c:] = [' '] * (cols - c)
                        for k in range(r + 1, rows):
                            scr[k] = blank()
                elif fin == 'K':
                    if p1 == 0:
                        scr[r][c:] = [' '] * (cols - c)
                    elif p1 == 1:
                        scr[r][:c + 1] = [' '] * (c + 1)
                    else:
                        scr[r] = blank()
                continue
            if i + 1 < n and data[i + 1] in ']P_^X':
                j = i + 2
                while j < n:
                    if data[j] == '\x07':
                        j += 1
                        break
                    if data[j] == '\x1b' and j + 1 < n and data[j + 1] == '\\':
                        j += 2
                        break
                    j += 1
                i = j
                continue
            # nF: ESC, intermediates (0x20-0x2f), one final byte (0x30-0x7e); RIS is ESC c.
            j = i + 1
            while j < n and ' ' <= data[j] <= '/':
                j += 1
            if j < n and '0' <= data[j] <= '~':
                if j == i + 1 and data[j] == 'c':
                    blocks.append(text(scr))
                    scr = [blank() for _ in range(rows)]
                    r = c = 0
                    pending_wrap = False
                j += 1
            i = j
            continue
        if ch == '\r':
            c = 0
            pending_wrap = False
        elif ch == '\n':
            if r == rows - 1:
                scroll(scr)
            else:
                r += 1
            pending_wrap = False
        elif ch == '\b':
            c = max(0, c - 1)
        elif ord(ch) < 32:
            pass
        else:
            if pending_wrap:
                c = 0
                if r == rows - 1:
                    scroll(scr)
                else:
                    r += 1
                pending_wrap = False
            scr[r][c] = ch
            if c == cols - 1:
                pending_wrap = True
            else:
                c += 1
        i += 1
    blocks.append('\n'.join(scrolled + [text(scr)]))
    return blocks


def tokens_in(collapsed, tokens):
    for allowed in ALLOWED:
        collapsed = collapsed.replace(allowed, '')
    found = [t for t in tokens if t in collapsed]
    if HOME_USER.search(collapsed):
        found.append('/home/<user>')
    return found


def read_tokens(path):
    try:
        lines = path.read_text(encoding='utf-8').splitlines()
    except OSError as exc:
        raise ValueError(f'cannot read token file {path}: {exc}') from exc
    tokens = [x.strip() for x in lines if x.strip() and not x.lstrip().startswith('#')]
    if not tokens:
        raise ValueError(f'token file {path} holds no token')
    return tokens


def parse(argv):
    generic_only = False
    token_file = None
    positional = []
    it = iter(argv[1:])
    for arg in it:
        if arg == '--generic-only':
            generic_only = True
        elif arg == '--tokens':
            token_file = next(it, None)
            if token_file is None:
                raise ValueError('--tokens needs a file')
        elif arg.startswith('-'):
            raise ValueError(f'unknown option {arg}')
        else:
            positional.append(arg)
    if len(positional) > 1 or (generic_only and token_file):
        raise ValueError('usage error')
    return generic_only, token_file, positional


def main(argv):
    try:
        generic_only, token_file, positional = parse(argv)
        if generic_only:
            local = []
            mode = 'generic tokens only'
        else:
            tpath = Path(token_file) if token_file else LOCAL_TOKENS
            if not tpath.exists():
                raise ValueError(
                    f'no local token file {tpath}: create it (one token per line) or pass --generic-only')
            local = read_tokens(tpath)
            mode = f'generic tokens + {len(local)} local'
    except ValueError as exc:
        print(f'path-check: {exc}', file=sys.stderr)
        print(__doc__, file=sys.stderr)
        return 2
    tokens = GENERIC_TOKENS + tuple(local)
    corpus = Path(positional[0]) if positional else Path(__file__).resolve().parent.parent / 'corpus'
    try:
        cases = tomllib.loads((corpus / 'cases.toml').read_text(encoding='utf-8'))['case']
    except (OSError, KeyError, tomllib.TOMLDecodeError) as exc:
        print(f'path-check: cannot read {corpus}/cases.toml: {exc}', file=sys.stderr)
        return 2
    widths = {c['screen']: c['width'] for c in cases}
    hits = {}
    files = sorted(p for p in (corpus / 'screens').iterdir() if p.is_file())
    if not files:
        print(f'path-check: no screens under {corpus}/screens', file=sys.stderr)
        return 2
    for path in files:
        raw = path.read_text(encoding='utf-8', errors='replace')
        found = set(tokens_in(STRIP.sub('', ESCAPES.sub('', raw)), tokens))
        if path.name in widths:
            for block in render(raw, widths[path.name]):
                found.update(tokens_in(STRIP.sub('', block), tokens))
        if found:
            hits[path.name] = sorted(found)
    for name, found in sorted(hits.items()):
        print(f'{name}: {", ".join(found)}')
    print(f'path-check: {len(files)} screens, {len(hits)} with operator tokens ({mode})')
    return 1 if hits else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
