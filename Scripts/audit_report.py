#!/usr/bin/env python3
"""The UX audit's report (docs/audit/08-ux-audit.md). Reads report/<config>/<journey>/record.json and its pictures,
writes a contact sheet per journey (sheets/<config>--<journey>.jpg) and SUMMARY.md: the failed checks by severity,
the benchmarks against docs/audit/benchmarks.json, the pictures that changed since the baseline, the accessibility
issues by type, the timings, and which journeys did not finish.
Usage: audit_report.py <dir> <sha> [<baseline dir>] [<benchmarks.json>]"""
import json, os, re, sys
from collections import Counter, defaultdict
from PIL import Image, ImageDraw, ImageFont

root, sha = sys.argv[1], sys.argv[2]
baseline = sys.argv[3] if len(sys.argv) > 3 else ""
bench_file = sys.argv[4] if len(sys.argv) > 4 else "docs/audit/benchmarks.json"
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
    if not os.path.isdir(cdir) or config in ("sheets", "diffs"):
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

# Benchmarks: taps per job and app responses, against their targets.
targets = json.load(open(bench_file)) if os.path.exists(bench_file) else {"jobs": {}, "responses": {"default": 1.5}}
lines += ["## Benchmarks (targets in docs/audit/benchmarks.json)", ""]
rows, over = [], 0
for r in records:
    for s_ in r["steps"]:
        if s_["kind"] == "benchmark":
            t = targets["jobs"].get(s_["name"], {}).get("taps")
            bad = (not s_["ok"]) or (t is not None and s_["taps"] > t)
            over += bad
            rows.append(f"| {r['config']} | job: {s_['name']} | {s_['taps']} taps | {t if t is not None else '-'} | {'**over**' if bad else 'ok'}{'' if s_['ok'] else ', not done'} |")
        elif s_["kind"] == "response":
            t = targets["responses"].get(s_["name"], targets["responses"].get("default", 1.5))
            sec = s_["seconds"]
            bad = sec < 0 or sec > t
            over += bad
            rows.append(f"| {r['config']} | {r['journey']}: {s_['name']} | {'never' if sec < 0 else str(sec) + ' s'} | {t} s | {'**over**' if bad else 'ok'} |")
if rows:
    lines += [f"{over} over target.", "", "| Config | What | Result | Target | |", "|---|---|---|---|---|"] + rows
else:
    lines.append("None recorded.")
lines.append("")

# Pictures that changed since the baseline (the last run marked [baseline]). Matched by config, journey and step
# name, so a new step does not shift the rest. A change is more than 1% of pixels off by more than a small amount.
lines += ["## Pictures changed since the baseline", ""]
def key(path):
    return re.sub(r"^\d+-", "", os.path.basename(path))
if baseline and os.path.isdir(baseline):
    from PIL import ImageChops
    os.makedirs(os.path.join(root, "diffs"), exist_ok=True)
    changed, compared, new = [], 0, 0
    for r in records:
        bdir = os.path.join(baseline, r["config"], r["journey"])
        bfiles = {key(f): os.path.join(bdir, f) for f in (os.listdir(bdir) if os.path.isdir(bdir) else []) if f.endswith(".png")}
        for s_ in r["steps"]:
            if s_["kind"] != "shot":
                continue
            cur = os.path.join(r["_dir"], s_["file"])
            old_ = bfiles.get(key(s_["file"]))
            if not old_ or not os.path.exists(cur):
                new += 1
                continue
            a_, b_ = Image.open(old_).convert("L"), Image.open(cur).convert("L")
            compared += 1
            if a_.size != b_.size:
                changed.append((r["config"], r["journey"], s_["name"], 100.0, None)); continue
            diff = ImageChops.difference(a_, b_).point(lambda v: 255 if v > 32 else 0)
            frac = diff.histogram()[255] / (diff.width * diff.height) * 100
            if frac > 1.0:
                w = 360
                pa = Image.open(old_).convert("RGB").resize((w, int(a_.height * w / a_.width)))
                pb = Image.open(cur).convert("RGB").resize((w, int(b_.height * w / b_.width)))
                pd = diff.convert("RGB").resize((w, int(b_.height * w / b_.width)))
                out = Image.new("RGB", (w * 3 + 32, pa.height + 50), (246, 243, 232))
                for i, im in enumerate([pa, pb, pd]):
                    out.paste(im, (8 + i * (w + 8), 42))
                ImageDraw.Draw(out).text((8, 10), f"{r['config']} / {r['journey']} / {s_['name']}: before, now, what changed", fill=(42, 30, 46), font=F)
                name = f"{r['config']}--{r['journey']}--{key(s_['file'])}".replace(".png", ".jpg")
                out.save(os.path.join(root, "diffs", name), quality=80)
                changed.append((r["config"], r["journey"], s_["name"], round(frac, 1), name))
    lines.append(f"Compared {compared} pictures; {len(changed)} changed; {new} new or with no baseline.")
    lines.append("")
    for cfg, j, n, frac, name in sorted(changed):
        lines.append(f"- {cfg} / {j} / {n}: {frac}% of the picture" + (f" ![](diffs/{name})" if name else " (a different size)"))
else:
    lines.append("No baseline yet. This run's pictures become the baseline.")
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
