#!/usr/bin/env python3
"""
ONE-TIME migration: build catalog.json (the new cloud source-of-truth for all
video metadata) from the legacy hardcoded data in index.html.

After this runs, catalog.json is hand-edited going forward and uploaded to R2
(see tools/upload_catalog.sh). The clients fetch it at runtime.

Sources merged:
  * index.html VIDEOS array  -> the canonical set of videos that ship + captions
  * index.html coordinate map -> category (section), lat, lng, noPin
"""
import json, re, sys, os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
HTML = os.path.join(ROOT, "index.html")
OUT  = os.path.join(ROOT, "catalog.json")

html = open(HTML, encoding="utf-8").read()

# --- 1. VIDEOS playlist array (uncommented entries only) ------------------
vids_block = re.search(r"const VIDEOS = \[(.*?)\n\];", html, re.S).group(1)
captions = {}          # id -> caption  (order preserved via list)
order = []
for line in vids_block.splitlines():
    if re.match(r"\s*//", line):        # commented-out = excluded, skip
        continue
    m = re.search(r'file:\s*"video-(\d+)\.mp4"\s*,\s*caption:\s*"([^"]*)"', line)
    if m:
        vid = int(m.group(1))
        captions[vid] = m.group(2)
        order.append(vid)

# --- 2. coordinate / category map -----------------------------------------
meta = {}              # id -> {category, lat, lng, noPin}
for m in re.finditer(
        r'"video-(\d+)\.mp4":\s*\{\s*section:\s*"([^"]*)",\s*'
        r'lat:\s*(-?[\d.]+),\s*lng:\s*(-?[\d.]+)(,\s*noPin:\s*true)?', html):
    vid = int(m.group(1))
    meta[vid] = {
        "category": m.group(2),
        "lat": float(m.group(3)),
        "lng": float(m.group(4)),
        "noPin": bool(m.group(5)),
    }

# --- 3. merge -------------------------------------------------------------
videos = []
missing_meta = []
for vid in order:
    entry = {"id": vid, "caption": captions[vid]}
    md = meta.get(vid)
    if md:
        entry["category"] = md["category"]
        entry["lat"] = md["lat"]
        entry["lng"] = md["lng"]
        if md["noPin"]:
            entry["noPin"] = True
    else:
        missing_meta.append(vid)
        entry["category"] = "uncategorized"
    videos.append(entry)

catalog = {"version": 1, "videos": videos}
with open(OUT, "w", encoding="utf-8") as f:
    json.dump(catalog, f, indent=2, ensure_ascii=False)
    f.write("\n")

print(f"Wrote {OUT} with {len(videos)} videos.")
cats = sorted({v['category'] for v in videos})
print("Categories:", cats)
if missing_meta:
    print("WARNING: no coord/category for ids:", missing_meta, file=sys.stderr)
