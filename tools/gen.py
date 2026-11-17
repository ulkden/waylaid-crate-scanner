"""Generate WaylaidCrateScanner/Data.lua from Wowhead's WoW: Forever database.

For every crate type in crates.py it looks the crate up on Wowhead Forever by name to get its
item ID, required level and the fill options listed on its tooltip (the tooltip is the source
of truth; crates.py only supplies the crate names and a name->itemID hint for materials).
It then walks the recipes ("created by") of every material recursively.

Usage: python3 -I tools/gen.py <cache_dir> WaylaidCrateScanner/Data.lua
"""
import html
import json
import os
import re
import subprocess
import sys
import time
import urllib.parse
import xml.etree.ElementTree as ET

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from crates import CRATES  # noqa: E402

CACHE = sys.argv[1]
OUT = sys.argv[2]
UA = "Mozilla/5.0"
BASE = "https://www.wowhead.com/forever"
NETHER = "https://nether.wowhead.com/forever"
os.makedirs(CACHE, exist_ok=True)

MAX_DEPTH = 6

# Only unlimited-stock trade-supply reagents get a vendor price. Many herbs/leathers are
# flagged "sold by vendor" on Wowhead, but those are limited-supply and would skew results.
VENDOR_WHITELIST = {2880, 3857, 4289, 8150}  # Weak Flux, Coal, Salt, Deeprock Salt

problems = []


def fetch(url, fname):
    path = os.path.join(CACHE, fname)
    if os.path.exists(path):
        with open(path, "rb") as f:
            return f.read().decode("utf-8", "replace")
    data = subprocess.run(["curl", "-sfL", "--max-time", "30", "-A", UA, url],
                          check=True, capture_output=True).stdout
    with open(path, "wb") as f:
        f.write(data)
    time.sleep(0.4)
    return data.decode("utf-8", "replace")


def parse_item_xml(txt):
    root = ET.fromstring(txt)
    it = root.find("item")
    if it is None:
        return None
    js = it.findtext("json") or ""
    eq = it.findtext("jsonEquip") or ""
    src = re.search(r'"source":\[([0-9,]*)\]', js)
    sources = [int(x) for x in src.group(1).split(",") if x] if src else []
    buy = re.search(r'"buyprice":(\d+)', eq)
    req = re.search(r'"reqlevel":(\d+)', js)
    qual = it.find("quality")
    spells = []
    cb = it.find("createdBy")
    if cb is not None:
        for sp in cb.findall("spell"):
            reagents = [(int(r.get("id")), r.get("name"), int(r.get("count"))) for r in sp.findall("reagent")]
            spells.append({"id": int(sp.get("id")), "name": sp.get("name"),
                           "min": int(sp.get("minCount") or 0), "reagents": reagents})
    return {
        "id": int(it.get("id")),
        "name": it.findtext("name"),
        "tooltip": it.findtext("htmlTooltip") or "",
        "reqlevel": int(req.group(1)) if req else None,
        "quality": int(qual.get("id")) if qual is not None else None,
        "vendor": int(buy.group(1)) if (buy and 5 in sources) else None,
        "spells": spells,
    }


def item_by_id(item_id):
    info = parse_item_xml(fetch(f"{BASE}/item={item_id}&xml", f"item_{item_id}.xml"))
    if not info:
        raise RuntimeError(f"item {item_id} not found on Wowhead Forever")
    return info


def item_by_name(name):
    q = urllib.parse.quote(name)
    safe = re.sub(r"[^A-Za-z0-9]+", "_", name)
    return parse_item_xml(fetch(f"{BASE}/item={q}&xml", f"name_{safe}.xml"))


def spell_yield(spell, item_id):
    if spell["min"] > 0:
        return spell["min"]
    txt = fetch(f"{NETHER}/tooltip/spell/{spell['id']}", f"spell_{spell['id']}.json")
    tip = json.loads(txt).get("tooltip", "")
    m = re.search(r'/item=%d/[^"]*">[^<]*</a></span> \((\d+)\)' % item_id, tip)
    return int(m.group(1)) if m else 1


def tooltip_options(tooltip):
    """'- 20 Copper Ore<br />- 20 Tin Ore' -> [(20, 'Copper Ore'), (20, 'Tin Ore')]"""
    opts = []
    for qty, name in re.findall(r"-\s*(\d+)\s+([^<]+?)\s*(?=<br|</span)", tooltip):
        opts.append((int(qty), html.unescape(name).strip()))
    return opts


# ---------------------------------------------------------------------------
# Crates
# ---------------------------------------------------------------------------
name_to_id = {name: iid for opts in CRATES.values() for _, name, iid in opts}
items = {}
crates_out = {}

for key, hint_opts in CRATES.items():
    crate_name = "Waylaid Crate: " + key
    info = item_by_name(crate_name)
    if not info or info["name"] != crate_name:
        problems.append(f"crate '{crate_name}' not found on Wowhead Forever; using crates.py data, no item ID")
        crates_out[key] = {"itemID": None, "level": None, "quality": None, "options": [(iid, qty) for qty, _, iid in hint_opts]}
        continue
    opts = tooltip_options(info["tooltip"])
    if not opts:
        problems.append(f"{crate_name}: could not parse options from tooltip; using crates.py")
        opts = [(qty, name) for qty, name, _ in hint_opts]
    resolved = []
    for qty, mat_name in opts:
        iid = name_to_id.get(mat_name)
        if iid is None:
            m = item_by_name(mat_name)
            if not m:
                problems.append(f"{crate_name}: material '{mat_name}' not found")
                continue
            iid = m["id"]
        resolved.append((iid, qty))
    hint = sorted((iid, qty) for qty, _, iid in hint_opts)
    if sorted(resolved) != hint:
        problems.append(f"{crate_name}: Wowhead options {opts} differ from crates.py {[(q, n) for q, n, _ in hint_opts]} (using Wowhead)")
    crates_out[key] = {"itemID": info["id"], "level": info["reqlevel"], "quality": info["quality"], "options": resolved}

# ---------------------------------------------------------------------------
# Recipes
# ---------------------------------------------------------------------------
recipes = {}


def visit(item_id, path, depth):
    if item_id not in items:
        items[item_id] = item_by_id(item_id)
    info = items[item_id]
    if depth >= MAX_DEPTH or item_id in recipes:
        return
    for sp in info["spells"]:
        if not sp["reagents"]:
            continue  # e.g. "Melt Key" style spells with no reagents
        if any(r[0] in path or r[0] == item_id for r in sp["reagents"]):
            continue  # would create a cycle (e.g. lesser <-> greater essence)
        recipes[item_id] = {
            "spell": sp["id"],
            "yield": spell_yield(sp, item_id),
            "reagents": [(r[0], r[2]) for r in sp["reagents"]],
        }
        for rid, _, _ in sp["reagents"]:
            visit(rid, path | {item_id}, depth + 1)
        break


for key, c in crates_out.items():
    for iid, _ in c["options"]:
        visit(iid, set(), 0)


def has_cycle(start):
    stack = [(start, frozenset([start]))]
    while stack:
        cur, seen = stack.pop()
        r = recipes.get(cur)
        if not r:
            continue
        for rid, _ in r["reagents"]:
            if rid == start:
                return True
            if rid not in seen:
                stack.append((rid, seen | {rid}))
    return False


option_items = {iid for c in crates_out.values() for iid, _ in c["options"]}
for iid in list(recipes):
    if iid not in option_items and has_cycle(iid):
        del recipes[iid]
for iid in list(recipes):
    if has_cycle(iid):
        problems.append(f"cycle remains at {iid}")

# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------
def lua_str(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


order = ["Ore", "Ingots", "Herbs", "Parts", "Textiles", "Fabrics", "Curiosities"]
tiers = ["Apprentice", "Journeyman", "Expert", "Artisan"]


def sort_key(k):
    tier = next(i for i, t in enumerate(tiers) if t in k)
    cat = next(i for i, c in enumerate(order) if k.endswith(c))
    return (cat, tier, k)


lines = [
    "-- AUTO-GENERATED by tools/gen.py from Wowhead's WoW: Forever database. Do not edit by hand.",
    "local _, ns = ...",
    "",
    "-- Crate definitions: key = crate name after \"Waylaid Crate: \"",
    "-- itemID = the crate item; quality = 1 common / 2 uncommon (sets the Merchant's Favor reward, see Favor.lua)",
    "-- options = { {itemID, quantity}, ... } (any ONE option fills the crate)",
    "ns.Crates = {",
]
for key in sorted(crates_out, key=sort_key):
    c = crates_out[key]
    opts = ", ".join("{%d, %d}" % (iid, qty) for iid, qty in c["options"])
    lines.append("  [%s] = { itemID = %s, level = %s, quality = %s, options = { %s } },"
                 % (lua_str(key), c["itemID"] or "nil", c["level"] or "nil", c["quality"] or "nil", opts))
lines += ["}", "",
          "-- Recipes: [createdItemID] = { spell = spellID, yield = itemsPerCraft, reagents = { {itemID, count}, ... } }",
          "ns.Recipes = {"]
for iid in sorted(recipes):
    r = recipes[iid]
    rg = ", ".join("{%d, %d}" % (a, b) for a, b in r["reagents"])
    lines.append("  [%d] = { spell = %d, yield = %d, reagents = { %s } }, -- %s"
                 % (iid, r["spell"], r["yield"], rg, items[iid]["name"]))
lines += ["}", "",
          "-- Vendor prices (copper) for unlimited-stock reagents; used when cheaper than / absent from the AH.",
          "ns.VendorPrices = {"]
for iid in sorted(items):
    if items[iid]["vendor"] and iid in VENDOR_WHITELIST:
        lines.append("  [%d] = %d, -- %s" % (iid, items[iid]["vendor"], items[iid]["name"]))
lines += ["}", "",
          "-- English names, used only as a fallback until the client has item data cached.",
          "ns.FallbackNames = {"]
names = {iid: items[iid]["name"] for iid in items}
for key, c in crates_out.items():
    if c["itemID"]:
        names[c["itemID"]] = "Waylaid Crate: " + key
for iid in sorted(names):
    lines.append("  [%d] = %s," % (iid, lua_str(names[iid])))
lines += ["}", ""]

with open(OUT, "w") as f:
    f.write("\n".join(lines))

print(f"crates={len(crates_out)} (with IDs: {sum(1 for c in crates_out.values() if c['itemID'])}) "
      f"items={len(items)} recipes={len(recipes)}")
for key in sorted(crates_out, key=sort_key):
    c = crates_out[key]
    print(f"  {c['itemID']}  L{c['level']}  {key}: " + ", ".join(f"{q} {items[i]['name']}" for i, q in c["options"]))
for p in problems:
    print("PROBLEM:", p)
for iid in sorted(recipes):
    r = recipes[iid]
    print(f"  {items[iid]['name']} x{r['yield']} <= " + ", ".join(f"{c} {items[a]['name']}" for a, c in r["reagents"]))
