#!/bin/bash
# Build writeup.pdf from index.html + assets in this directory.
# Adapted from hw1-bha-writeup/build-pdf.sh.
# Requires: pandoc, typst, Inter TTFs (auto-fetched to /tmp/fonts).
set -e
cd "$(dirname "$0")"

# 1. fonts
mkdir -p /tmp/fonts
python3 - <<'PYEOF'
import os, re, urllib.request
D = "/tmp/fonts"
os.makedirs(D, exist_ok=True)
CSS_URL = "https://fonts.googleapis.com/css?family=Inter:400,700italic,400italic,700"
css = urllib.request.urlopen(CSS_URL).read().decode()
faces = re.findall(r"font-style:\s*(\w+);\s*\n\s*font-weight:\s*(\d+);\s*\n\s*src:\s*url\((https://[^)]+)\)", css)
names = {('italic', '400'): 'Inter-Italic.ttf', ('italic', '700'): 'Inter-BoldItalic.ttf',
         ('normal', '400'): 'Inter-Regular.ttf', ('normal', '700'): 'Inter-Bold.ttf'}
for style, weight, url in faces:
    fn = os.path.join(D, names[(style, weight)])
    if not os.path.exists(fn):
        urllib.request.urlretrieve(url, fn)
        print('fetched', fn)
PYEOF

# 2. clean html (drop layout divs, keep centering)
python3 - <<'PYEOF'
import re
s = open('index.html').read()
s = re.sub(r'<div style="text-align: center;">(.*?)</div>', r'<p align="center">\1</p>', s, flags=re.S)
s = re.sub(r'<div[^>]*>', '', s).replace('</div>', '')
open('/tmp/page_clean.html', 'w').write(s)
PYEOF

# 3. html -> typst
pandoc /tmp/page_clean.html -t typst --standalone --embed-resources \
  --resource-path=. -V mainfont="Inter" -V fontsize=12pt -o /tmp/pandoc.typ

# 4. post-process: standalone figures at 80% with manual captions only
#    (no auto numbering), fixed table image widths, per-section pages,
#    disc bullets
python3 - <<'PYEOF'
import re
s = open('/tmp/pandoc.typ').read()
pat = re.compile(r'#figure\(image\("([^"]+)"[^)]*\),\s*caption:\s*\[(.*?)\]\s*\)', re.S)
s, n = pat.subn(r'#figure(image("\1", width: 80%), caption: [\2], supplement: none)', s)
print('figures sized:', n)
# center table cell content like the site's td{text-align:center}
s = re.sub(r'align: \(auto(,auto)*,\)', lambda m: 'align: ' + '(' + ','.join(['center'] * m.group(0).count('auto')) + ',)', s)
print('cell align centered')
def fix(m):
    name = m.group(1)
    return f'image("{name}", width: 2.2in)'
s, n = re.subn(r'image\("([^"]+)", width: 100\.0%\)', fix, s)
print('table images resized:', n)
# captions onto their own line below each table image
s, n = re.subn(r'\)\)\n(\s*)Figure (\d)', r'))\n\1#parbreak()\n\1Figure \2', s)
print('captions broken:', n)
lines = s.split('\n')
out, first = [], True
in_overview = False
prev_is_h2 = False
for line in lines:
    if line.startswith('== ') and not line.startswith('==='):
        in_overview = line.startswith('== Overview')
        if not first:
            out.append('#pagebreak()')
        first = False
        prev_is_h2 = True
    elif line.startswith('=== ') and not in_overview and not prev_is_h2:
        out.append('#pagebreak()')
        prev_is_h2 = False
    elif line.strip() and not line.startswith('<'):
        prev_is_h2 = False
    out.append(line)
s = '#set list(marker: [\u2022])\n#show figure.where(kind: image): it => {\n  set align(center)\n  it.body\n  it.caption\n}\n' + '\n'.join(out)
open('/tmp/pandoc.typ', 'w').write(s)
PYEOF

cp /tmp/pandoc.typ ./pandoc.typ
typst compile --font-path /tmp/fonts ./pandoc.typ ./writeup.pdf
echo "built writeup.pdf ($(stat -c%s writeup.pdf) bytes)"
