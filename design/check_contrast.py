"""Check every text role in design/tokens.json against the grounds it sits on, in every theme.

Run: python3 design/check_contrast.py   (exits 1 if any pair misses its floor)
"""
import json, re, sys, pathlib

tokens = json.loads((pathlib.Path(__file__).parent / "tokens.json").read_text())
themes = [t["id"] for t in tokens["color"]["themes"]]
colors = {t["name"]: t["value"] for t in tokens["color"]["tokens"]}

def value(name, theme):
    v = colors[name]
    v = v if isinstance(v, str) else v.get(theme, v[themes[0]])
    alias = re.fullmatch(r"\{(.+)\}", v)
    return value(alias.group(1), theme) if alias else v

def rgba(v):
    if v.startswith("#"):
        return [int(v[i:i + 2], 16) / 255 for i in (1, 3, 5)], 1.0
    n = [float(x) for x in re.findall(r"[\d.]+", v)]
    return [x / 255 for x in n[:3]], (n[3] if len(n) > 3 else 1.0)

def over(fg, bg):
    (f, a), (b, _) = rgba(fg), rgba(bg)
    return [x * a + y * (1 - a) for x, y in zip(f, b)]

def lum(c):
    c = [x / 12.92 if x <= 0.03928 else ((x + 0.055) / 1.055) ** 2.4 for x in c]
    return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]

def ratio(fg, bg):
    a, b = sorted([lum(over(fg, bg)), lum(rgba(bg)[0])], reverse=True)
    return (a + 0.05) / (b + 0.05)

# (foreground, ground, floor): text 4.5, control outlines and focus 3.0
PAIRS = [(fg, g, 4.5) for fg in ("text", "quiet", "done", "act-text") for g in ("surface", "surface-raised")]
PAIRS += [("on-act", "act", 4.5), ("control-line", "surface", 3.0), ("focus", "surface", 3.0), ("act-edge", "surface", 3.0)]

failed = 0
for theme in themes:
    for fg, g, floor in PAIRS:
        r = ratio(value(fg, theme), value(g, theme))
        mark = "ok " if r >= floor else "LOW"
        failed += r < floor
        print(f"{mark} {theme:11} {fg:13} on {g:15} {r:5.2f} (needs {floor})")
sys.exit(1 if failed else 0)
