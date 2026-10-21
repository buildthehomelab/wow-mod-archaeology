#!/usr/bin/env python3
"""Build mod-archaeology's world data SQL from Cataclysm archaeology data.

Inputs (tools/cata-data/, not committed; see README "Rebuilding the data"):
  c_ResearchBranch.csv, c_ResearchSite.csv, c_QuestPOIPoint.csv, c_ResearchProject.csv,
  c_SpellEffect.csv, c_ItemSparse.csv, c_Item.csv   Cataclysm Classic DB2 exports (wago.tools)
  sf_arch.sql                                         SkyFire 5.4.8 research_* tables

Output:
  data/sql/db-world/mod_archaeology_world_data.sql   races, sites, polygons, dig spots, projects,
                                               keystone and artifact item_template rows

Rules:
  - Kalimdor, Eastern Kingdoms, Outland and Northrend only (maps 0, 1, 530, 571).
  - No Tol'vir (branch 7), no test branch (29), no skill-450 sites (Cataclysm zones).
  - Cata item ids collide with 3.3.5, so every item gets a new id from ITEM_BASE.

Usage: python3 tools/build_data.py
"""

import csv
import json
import re
import sys
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "tools" / "cata-data"
OUT = ROOT / "data" / "sql" / "db-world" / "mod_archaeology_world_data.sql"

MAPS = {0, 1, 530, 571}
SKIP_BRANCHES = {7, 29}
MAX_SITE_SKILL = 449
LEVEL_OVERRIDES = json.loads((ROOT / "tools" / "site-level-overrides.json").read_text())
# Known incompatible sites and conservative terrain holds; see docs/wotlk-digsites.md.
DISABLED_SITES = json.loads((ROOT / "tools" / "wotlk-disabled-sites.json").read_text())

KEYSTONE_BASE = 9504010   # one keystone item per race, in race order
ITEM_BASE = 9504020       # artifacts, in project id order
ITEM_LAST = 9504499
DISPLAY_BASE = 950400    # ItemDisplayInfo id = DISPLAY_BASE + (item - 9504000), see build_patch.py

# Race id (= Cata ResearchBranch id), keystone value, find gameobject entry
# Unlock skill follows the race's lowest site skill.
RACE_ORDER = [1, 4, 8, 3, 2, 6, 5, 27]
FIND_GO = {1: 9503510, 4: 9503511, 8: 9503512, 3: 9503513, 2: 9503514, 6: 9503515, 5: 9503516, 27: 9503517}

# Cata item class 15 (misc) subclass 4 (other) for commons; quality from the DB2.
CLASS_MISC, SUBCLASS_OTHER = 15, 4


def read_csv(name):
    path = SRC / name
    if not path.exists():
        sys.exit(f"missing {path}; see README 'Rebuilding the data'")
    with open(path, newline="", encoding="utf-8") as f:
        return list(csv.DictReader(f))


def sql_str(s):
    return "'" + s.replace("\\", "\\\\").replace("'", "''").replace("\r", "").replace("\n", "\\n") + "'"


def item_desc(text, limit=255):
    """Fits item_template.description (VARCHAR(255)): whole sentences while they fit, else a word cut.
    The full lore stays in mod_archaeology_project.description."""
    text = re.sub(r"\s+", " ", text).strip()
    if len(text) <= limit:
        return text
    out = ""
    for sentence in re.split(r"(?<=[.!?])\s+", text):
        if len(out) + len(sentence) + 1 > limit:
            break
        out = f"{out} {sentence}" if out else sentence
    return out or text[:limit - 3].rsplit(" ", 1)[0] + "..."


def sf_rows(text, table):
    """Rows of one REPLACE INTO block from the SkyFire dump, as tuples of strings."""
    start = text.index(f"`{table}`")
    end = text.find(";", start)
    block = text[start:end]
    return [tuple(v.strip() for v in m.group(1).split(",")) for m in re.finditer(r"^\(([^)]*)\)", block, re.M)]


def main():
    sf = (SRC / "sf_arch.sql").read_text(encoding="utf-8")

    branches = {int(r["ID"]): r for r in read_csv("c_ResearchBranch.csv")}
    sites = {int(r["ID"]): r for r in read_csv("c_ResearchSite.csv")}
    points = defaultdict(list)
    for r in read_csv("c_QuestPOIPoint.csv"):
        points[int(r["QuestPOIBlobID"])].append((int(r["ID"]), int(r["X"]), int(r["Y"])))

    site_data = {}
    for digsite, branch, skill, level in sf_rows(sf, "research_digsite_data"):
        site_data[int(digsite)] = (int(branch), int(skill), int(level))

    spawns = defaultdict(list)
    for _guid, digsite, _go, x, y, z in sf_rows(sf, "research_digsite_finds"):
        spawns[int(digsite)].append((float(x), float(y), float(z)))

    proj_req = {}
    for pid, skill, chance in sf_rows(sf, "research_project_requirements"):
        proj_req[int(pid)] = (int(skill), float(chance))

    # Sites
    site_rows, point_rows, spawn_rows = [], [], []
    race_min_skill = {}
    for sid in sorted(site_data):
        branch, skill, level = site_data[sid]
        level = LEVEL_OVERRIDES.get(str(sid), {}).get("min_level", level)
        site = sites.get(sid)
        if not site or branch in SKIP_BRANCHES or skill > MAX_SITE_SKILL:
            continue
        map_id = int(site["MapID"])
        if map_id not in MAPS or not spawns.get(sid):
            continue
        poly = sorted(points.get(int(site["QuestPOIBlobID"]), []))
        if len(poly) < 3:
            continue
        race_min_skill[branch] = min(race_min_skill.get(branch, 999), skill)
        site_rows.append(f"({sid}, {map_id}, {branch}, {sql_str(site['Name_lang'])}, {skill}, {level}, {0 if str(sid) in DISABLED_SITES else 1})")
        for idx, (_pid, x, y) in enumerate(poly):
            point_rows.append(f"({sid}, {idx}, {x}, {y})")
        for idx, (x, y, z) in enumerate(spawns[sid]):
            spawn_rows.append(f"({sid}, {idx}, {x:.2f}, {y:.2f}, {z:.2f})")

    # Projects -> the item each project's spell creates
    effects = {}
    for r in read_csv("c_SpellEffect.csv"):
        if r["Effect"] == "24" and r["EffectItemType"] != "0":   # SPELL_EFFECT_CREATE_ITEM
            effects[int(r["SpellID"])] = int(r["EffectItemType"])
    projects = sorted((int(r["ID"]), r) for r in read_csv("c_ResearchProject.csv")
                      if int(r["ResearchBranchID"]) in RACE_ORDER)
    want_items = {effects.get(int(r["SpellID"])) for _, r in projects}
    want_items |= {int(branches[b]["ItemID"]) for b in RACE_ORDER if int(branches[b]["ItemID"])}

    sparse = {}
    with open(SRC / "c_ItemSparse.csv", newline="", encoding="utf-8") as f:
        for r in csv.DictReader(f):
            if int(r["ID"]) in want_items:
                sparse[int(r["ID"])] = r
    item_base = {}
    with open(SRC / "c_Item.csv", newline="", encoding="utf-8") as f:
        for r in csv.DictReader(f):
            if int(r["ID"]) in want_items:
                item_base[int(r["ID"])] = r

    item_rows, item_map_rows, project_rows, race_rows = [], [], [], []

    def item_row(new_id, cata_id, stackable, max_count, item_class, subclass, quality, desc):
        s = sparse[cata_id]
        name = s["Display_lang"]
        sell = int(s["SellPrice"])
        item_map_rows.append(f"({new_id}, {cata_id}, {sql_str(name)})")
        # Display id matches the ItemDisplayInfo row tools/build_patch.py adds for this item.
        return (f"({new_id}, {item_class}, {subclass}, {sql_str(name)}, {DISPLAY_BASE + new_id - 9504000}, {quality}, {sell * 4}, {sell}, "
                f"0, -1, -1, {max_count}, {stackable}, 1, {sql_str(item_desc(desc))})")

    for i, race in enumerate(RACE_ORDER):
        b = branches[race]
        keystone = 0
        cata_key = int(b["ItemID"])
        if cata_key:
            keystone = KEYSTONE_BASE + i
            s = sparse[cata_key]
            item_rows.append(item_row(keystone, cata_key, 20, 0, CLASS_MISC, SUBCLASS_OTHER,
                                      int(s["OverallQualityID"]), s["Description_lang"]))
        race_rows.append(f"({race}, {sql_str(b['Name_lang'])}, {keystone}, {race_min_skill.get(race, 0)}, {FIND_GO[race]})")

    next_item = ITEM_BASE
    for pid, r in projects:
        cata_item = effects.get(int(r["SpellID"]))
        if not cata_item or cata_item not in sparse:
            print(f"project {pid} {r['Name_lang']}: no item, skipped", file=sys.stderr)
            continue
        if next_item > ITEM_LAST:
            sys.exit("item range 9504020-9504499 is full")
        rare = int(r["Rarity"])
        skill, chance = proj_req.get(pid, (0, 100.0 if not rare else 5.0))
        s = sparse[cata_item]
        base = item_base.get(cata_item, {})
        # Commons stay gray junk. Rares start as misc placeholders; implemented
        # reward overrides are applied at the end from world_z_rewards.sql.
        quality = int(s["OverallQualityID"])
        item_rows.append(item_row(next_item, cata_item, 1, 1 if rare else 0, CLASS_MISC, SUBCLASS_OTHER,
                                  quality, r["Description_lang"] if rare else s["Description_lang"]))
        project_rows.append(
            f"({pid}, {int(r['ResearchBranchID'])}, {sql_str(r['Name_lang'])}, {sql_str(r['Description_lang'])}, "
            f"{rare}, {next_item}, {int(r['RequiredWeight'])}, {int(r['NumSockets'])}, {skill}, {chance}, "
            f"{int(base.get('ClassID', CLASS_MISC))}, {int(base.get('SubclassID', SUBCLASS_OTHER))})")
        next_item += 1

    out = []
    out.append("-- Generated by tools/build_data.py from Cataclysm archaeology data. Do not edit by hand.\n")
    out.append("DELETE FROM `mod_archaeology_race`;")
    out.append("INSERT INTO `mod_archaeology_race` (`id`, `name`, `keystone_item`, `unlock_skill`, `find_go`) VALUES\n"
               + ",\n".join(race_rows) + ";\n")
    out.append("DELETE FROM `mod_archaeology_site`;")
    out.append("INSERT INTO `mod_archaeology_site` (`id`, `map`, `race`, `name`, `min_skill`, `min_level`, `enabled`) VALUES\n"
               + ",\n".join(site_rows) + ";\n")
    out.append("DELETE FROM `mod_archaeology_site_point`;")
    out.append("INSERT INTO `mod_archaeology_site_point` (`site`, `idx`, `x`, `y`) VALUES\n"
               + ",\n".join(point_rows) + ";\n")
    out.append("DELETE FROM `mod_archaeology_site_spawn`;")
    out.append("INSERT INTO `mod_archaeology_site_spawn` (`site`, `idx`, `x`, `y`, `z`) VALUES\n"
               + ",\n".join(spawn_rows) + ";\n")
    out.append("DELETE FROM `mod_archaeology_project`;")
    out.append("INSERT INTO `mod_archaeology_project` (`id`, `race`, `name`, `description`, `rare`, `item`, `cost`, "
               "`sockets`, `min_skill`, `chance`, `cata_class`, `cata_subclass`) VALUES\n"
               + ",\n".join(project_rows) + ";\n")
    out.append(f"DELETE FROM `item_template` WHERE `entry` BETWEEN {KEYSTONE_BASE} AND {ITEM_LAST};")
    out.append("INSERT INTO `item_template` (`entry`, `class`, `subclass`, `name`, `displayid`, `Quality`, `BuyPrice`, "
               "`SellPrice`, `InventoryType`, `AllowableClass`, `AllowableRace`, `maxcount`, `stackable`, `bonding`, "
               "`description`) VALUES\n" + ",\n".join(item_rows) + ";\n")
    out.append("DELETE FROM `mod_archaeology_item_source`;")
    out.append("INSERT INTO `mod_archaeology_item_source` (`item`, `cata_item`, `name`) VALUES\n"
               + ",\n".join(item_map_rows) + ";\n")

    # Include the upgrade overrides in regenerated base data too: the updater
    # need not rerun an unchanged z_rewards migration after a later data rebuild.
    rewards = ROOT / "data/sql/db-world/mod_archaeology_world_z_rewards.sql"
    out.append(rewards.read_text(encoding="utf-8"))

    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text("\n".join(out), encoding="utf-8")
    print(f"{len(race_rows)} races, {len(site_rows)} sites, {len(point_rows)} polygon points, "
          f"{len(spawn_rows)} dig spots, {len(project_rows)} projects, {len(item_rows)} items -> {OUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
