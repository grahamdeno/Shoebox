#!/usr/bin/env python3
"""The UX audit's report (docs/audit/08-ux-audit.md). Reads report/<config>/<journey>/record.json and its pictures,
writes a contact sheet per journey (sheets/<config>--<journey>.jpg) and SUMMARY.md: the failed checks by severity,
the accessibility issues by type, the timings, and which journeys did not finish. Usage: audit_report.py <dir> <sha>"""
import json, os, sys
from collections import Counter, defaultdict
from PIL import Image, ImageDraw, ImageFont

root, sha = sys.argv[1], sys.argv[2]
os.makedirs(os.path.join(root, "sheets"), exist_ok=True)

def font(size):
    for p in ["/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", "/System/Library/Fonts/Helvetica.ttc"]:
        if os.path.exists(p):
            return ImageFont.truetype(p, size)
    return ImageFont.load_default()

F, FB = font(18), font(26)

def sheet(config, journey, folder, shots):
    if not shots:
        return None
    w, cols = 300, 5
    thumbs = []
    for s in shots:
        p = os.path.join(folder, s["file"])
        if not os.path.exists(p):
            continue
        im = Image.open(p).convert("RGB")
        im = im.resize((w, int(im.height * w / im.width)))
        thumbs.append((s, im))
    if not thumbs:
        return None
    h = max(im.height for _, im in thumbs) + 56
    rows = (len(thumbs) + cols - 1) // cols
    out = Image.new("RGB", (cols * (w + 16) + 16, rows * (h + 16) + 70), (246, 243, 232))
    d = ImageDraw.Draw(out)
    d.text((16, 18), f"{config} / {journey}", fill=(42, 30, 46), font=FB)
    for i, (s, im) in enumerate(thumbs):
        x, y = 16 + (i % cols) * (w + 16), 70 + (i // cols) * (h + 16)
        out.paste(im, (x, y))
        d.text((x, y + im.height + 6), f"{s['n']:02d} {s['name']}"[:34], fill=(42, 30, 46), font=F)
        d.text((x, y + im.height + 28), f"+{s.get('dt', 0)}s", fill=(106, 96, 112), font=F)
    name = f"{config}--{journey}.jpg"
    out.save(os.path.join(root, "sheets", name), quality=82)
    return name

records = []
for config in sorted(os.listdir(root)):
    cdir = os.path.join(root, config)
    if not os.path.isdir(cdir) or config == "sheets":
        continue
    for journey in sorted(os.listdir(cdir)):
        jdir = os.path.join(cdir, journey)
        rec = os.path.join(jdir, "record.json")
        if os.path.isfile(rec):
            r = json.load(open(rec))
            r["_dir"] = jdir
            records.append(r)

lines = [f"# UX audit for {sha}", ""]
configs = sorted({r["config"] for r in records})
lines.append(f"Configs: {', '.join(configs) or 'none'}. Journeys recorded: {len(records)}.")
lines.append("")

fails = []
a11y = defaultdict(list)
for r in records:
    for s in r["steps"]:
        if s["kind"] == "check" and not s["ok"]:
            fails.append((s["severity"], r["config"], r["journey"], s["name"], s.get("detail", "")))
    for i in r["accessibility"]:
        a11y[(i["type"], i["summary"], i.get("element", ""), i["screen"])].append(r["config"])

fails.sort(key=lambda f: (-f[0], f[2], f[3], f[1]))
lines += ["## Failed checks (severity 4 blocks the task, 1 is cosmetic)", ""]
if not fails:
    lines.append("None.")
grouped = defaultdict(list)
for sev, cfg, j, name, det in fails:
    grouped[(sev, j, name)].append((cfg, det))
for (sev, j, name), where in sorted(grouped.items(), key=lambda kv: (-kv[0][0], kv[0][1])):
    cfgs = ", ".join(sorted({c for c, _ in where}))
    det = where[0][1].replace("\n", " ")[:160]
    lines.append(f"- **{sev}** {j}: {name} ({cfgs}){' — ' + det if det else ''}".replace(" — ", ": "))
lines.append("")

lines += ["## Accessibility audit (Apple's), by issue", ""]
if not a11y:
    lines.append("None.")
counts = Counter(k[0] for k in a11y)
lines.append("By type: " + ", ".join(f"{t} {n}" for t, n in counts.most_common()))
lines.append("")
for (t, summary, el, screen), cfgs in sorted(a11y.items()):
    lines.append(f"- {t} on {screen}: {summary} [{el or 'no label'}] ({', '.join(sorted(set(cfgs)))})")
lines.append("")

lines += ["## Timings", ""]
for r in records:
    for s in r["steps"]:
        if s["kind"] == "timing":
            lines.append(f"- {r['config']} {r['journey']}: {s['name']} {s['seconds']} s")
lines.append("")

lines += ["## Journeys", ""]
for r in records:
    shots = [s for s in r["steps"] if s["kind"] == "shot"]
    name = sheet(r["config"], r["journey"], r["_dir"], shots)
    ok = sum(1 for s in r["steps"] if s["kind"] == "check" and s["ok"])
    bad = sum(1 for s in r["steps"] if s["kind"] == "check" and not s["ok"])
    lines.append(f"### {r['config']} / {r['journey']} ({r['seconds']} s, {ok} checks held, {bad} did not)")
    if name:
        lines.append(f"![]({'sheets/' + name})")
    for s in r["steps"]:
        if s["kind"] == "labels":
            lines.append(f"- on screen at {s['name']}: buttons {s['buttons'][:14]}; words {[t[:40] for t in s['texts'][:14]]}")
    lines.append("")

expected = {"pro-light", "pro-dark", "stone-dark", "big-text", "small-phone"}
missing = expected - set(configs)
if missing:
    lines.insert(3, f"**Configs with no records (failed to build or run): {', '.join(sorted(missing))}.**\n")

open(os.path.join(root, "SUMMARY.md"), "w").write("\n".join(lines) + "\n")
print("\n".join(lines[:60]))
