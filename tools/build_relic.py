#!/usr/bin/env python3
"""Build the Unearthed Relic's item ladder: data/sql/db-world/mod_archaeology_world_relic.sql.

The relic is one weapon (or a pair) per character. Its real state lives in the characters table
mod_archaeology_char_relic; the item a player holds is only a projection of it. This script writes
the items that projection picks from:

  steps   the ladder rungs: required level, item level, quality, the progression state that
          opens the rung, its Relic Power cost, and whether it is the last rung of an era
  kinds   one weapon or shield each (two-hand sword, main-hand dagger, shield, ...)
  forms   what a character chooses: one kind, or a main-hand + off-hand pair of kinds
  items   item_template + item_dbc rows, one per step x kind, at 9505000 + step * 30 + kind

Stats come from a budget per item level fitted to the 3.3.5 raid weapons of each tier (see ANCHOR
and DPS), split by each kind's stat profile. Change the tables below and run the script again.

Usage: python3 tools/build_relic.py
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "data" / "sql" / "db-world" / "mod_archaeology_world_relic.sql"

ITEM_BASE, ITEM_LAST, KINDS_PER_STEP = 9505000, 9505999, 30

# step: (required level, item level, quality, progression state, power to reach it, gate)
# gate 1 = last rung of its era: every rare of the era's races solved (and the era's capstone
# quest, if configured). gate 2 = awakened: every project of every race solved at max skill.
STEPS = [
    (20, 25, 2, 0, 0, 0), (25, 31, 2, 0, 100, 0), (30, 37, 2, 0, 150, 0), (35, 43, 3, 0, 200, 0),
    (40, 49, 3, 0, 250, 0), (45, 54, 3, 0, 350, 0), (50, 58, 3, 0, 450, 0), (55, 61, 3, 0, 550, 0),
    (58, 63, 3, 0, 650, 0),
    # Molten Core to Naxxramas (progression states 1-7)
    (60, 66, 4, 1, 750, 0), (60, 71, 4, 2, 800, 0), (60, 77, 4, 3, 900, 0), (60, 80, 4, 4, 1000, 0),
    (60, 84, 4, 5, 1100, 0), (60, 88, 4, 6, 1200, 0), (60, 92, 4, 7, 1500, 1),
    # The Burning Crusade (8-12); the last rung is Legendary
    (68, 115, 4, 8, 1200, 0), (70, 125, 4, 8, 1500, 0), (70, 141, 4, 9, 1800, 0), (70, 154, 4, 10, 2200, 0),
    (70, 164, 5, 12, 3000, 1),
    # Wrath of the Lich King (13-18); the awakened rung is Artifact quality
    (78, 187, 4, 13, 1800, 0), (80, 226, 4, 13, 2200, 0), (80, 245, 4, 14, 2600, 0), (80, 258, 4, 15, 3000, 0),
    (80, 264, 4, 16, 3500, 0), (80, 271, 4, 17, 4500, 0), (80, 277, 4, 18, 6000, 1), (80, 277, 6, 18, 8000, 2),
]
ERA_FIRST = [0, 16, 21]   # first step of vanilla, Burning Crusade, Wrath

# Stat points of the best two-hand weapon at an item level (AP counted half, spell power apart),
# and its DPS: fitted to 3.3.5's epic and rare weapons of each tier.
ANCHOR = {25: 14, 31: 20, 37: 27, 43: 32, 49: 37, 54: 41, 58: 46, 61: 49, 63: 52, 66: 56, 71: 63, 77: 72,
          80: 76, 84: 80, 88: 85, 92: 90, 115: 115, 125: 140, 141: 160, 154: 172, 164: 185, 187: 270,
          226: 400, 245: 460, 258: 520, 264: 555, 271: 585, 277: 610}
DPS = {25: 21, 31: 25.6, 37: 32.6, 43: 39, 49: 45, 54: 48, 58: 51, 61: 53, 63: 59.4, 66: 62.6, 71: 68,
       77: 76.1, 80: 80.4, 84: 86.6, 88: 90, 92: 95, 115: 114.1, 125: 119.9, 141: 130.4, 154: 140.5,
       164: 148.7, 187: 170, 226: 222.9, 245: 255.7, 258: 281.7, 264: 294.7, 271: 311, 277: 325.7}
SHIELD_ARMOR = {25: 600, 31: 750, 37: 900, 43: 1100, 49: 1300, 54: 1500, 58: 1700, 61: 1900, 63: 2100,
                66: 2400, 71: 2650, 77: 2900, 80: 3050, 84: 3200, 88: 3300, 92: 3450, 115: 4500, 125: 5000,
                141: 5500, 154: 5900, 164: 6250, 187: 6700, 226: 7800, 245: 8300, 258: 8650, 264: 8870,
                271: 9050, 277: 9260}
SHIELD_BLOCK = {25: 12, 31: 15, 37: 19, 43: 23, 49: 27, 54: 31, 58: 35, 61: 40, 63: 45, 66: 48, 71: 52,
                77: 57, 80: 60, 84: 63, 88: 65, 92: 68, 115: 110, 125: 120, 141: 135, 154: 145, 164: 155,
                187: 170, 226: 205, 245: 225, 258: 240, 264: 248, 271: 254, 277: 259}
QUALITY_SCALE = {2: 0.85, 3: 1.0, 4: 1.0, 5: 1.0, 6: 1.0}   # greens a little under the blues
SPELL_POWER = 1.37                                          # spell power of caster weapons, per anchor point
SOCKETS_FROM_ILVL, THIRD_SOCKET_FROM_ILVL = 115, 264

# Item stat ids
AGI, STR, INT, SPI, STA, DEF, DODGE, PARRY, HIT, CRIT, HASTE, EXP, AP, SP = 3, 4, 5, 6, 7, 12, 13, 14, 31, 32, 36, 37, 38, 45
RED, YELLOW, BLUE = 2, 4, 8
PROFILES = {   # (stat, share of the points), socket bonus (SpellItemEnchantment), spell power?
    "str": ([(STR, .32), (STA, .30), (CRIT, .20), (HASTE, .18)], 3312, False),
    "agi": ([(AGI, .30), (STA, .24), (AP, .16), (HIT, .15), (HASTE, .15)], 2877, False),
    "str1h": ([(STR, .32), (STA, .28), (CRIT, .20), (HIT, .20)], 3312, False),
    "caster": ([(INT, .30), (STA, .26), (CRIT, .22), (HASTE, .22)], 3753, True),
    "feral": ([(AGI, .32), (STA, .30), (CRIT, .20), (HIT, .18)], 2877, False),
    "heal": ([(INT, .34), (STA, .22), (SPI, .22), (HASTE, .22)], 3753, True),
    "ranged": ([(AGI, .30), (STA, .24), (AP, .16), (CRIT, .16), (HIT, .14)], 2936, False),
    "tank": ([(STA, .34), (STR, .16), (DEF, .17), (PARRY, .17), (EXP, .16)], 2868, False),
    "tank2h": ([(STA, .36), (STR, .22), (DEF, .16), (PARRY, .13), (EXP, .13)], 2868, False),
    "shield": ([(STA, .40), (STR, .26), (DEF, .18), (PARRY, .16)], 2868, False),
}

# Item class/subclass, InventoryType, sheath, material
WEAPON, ARMOR = 2, 4
AXE, AXE2, BOW, GUN, MACE, MACE2, SWORD, SWORD2, STAFF, FIST, DAGGER, SHIELD = 0, 1, 2, 3, 4, 5, 7, 8, 10, 13, 15, 6
T_SHIELD, T_BOW, T_2H, T_MH, T_OH, T_GUN = 14, 15, 17, 21, 22, 26

# kind: name, class, subclass, InventoryType, slot ("2h", "1h", "ranged", "shield"), speed (s),
#       DPS share of a two-hand weapon, profile, display (existing 3.3.5 ItemDisplayInfo), sheath, material
KINDS = [
    ("Oath of the Forgotten", WEAPON, SWORD2, T_2H, "2h", 3.6, 1.0, "str", 53938, 1, 1),      # 0 Claymore of Ancient Power
    ("Empire's End", WEAPON, AXE2, T_2H, "2h", 3.6, 1.0, "str", 50965, 1, 1),        # 1 Titansteel Defender
    ("Weight of Ages", WEAPON, MACE2, T_2H, "2h", 3.6, 1.0, "str", 52966, 1, 1),       # 2 Titansteel Destroyer
    ("Oath", WEAPON, SWORD, T_MH, "1h", 2.6, .77, "agi", 59382, 3, 1),       # 3 Titanguard
    ("Reckoning", WEAPON, SWORD, T_OH, "1h", 1.6, .77, "agi", 59382, 3, 1),        # 4
    ("Grasp", WEAPON, FIST, T_MH, "1h", 2.6, .77, "agi", 58897, 7, 1),        # 5 Golden Saronite Dragon
    ("Defiance", WEAPON, FIST, T_OH, "1h", 2.6, .77, "agi", 58897, 7, 1),         # 6
    ("Ruin", WEAPON, AXE, T_MH, "1h", 2.6, .77, "agi", 50076, 3, 1),         # 7 Notched Cobalt War Axe
    ("Remembrance", WEAPON, AXE, T_OH, "1h", 2.6, .77, "agi", 50076, 3, 1),          # 8
    ("Secret", WEAPON, DAGGER, T_MH, "1h", 1.8, .77, "agi", 53471, 3, 1),      # 9 Titansteel Shanker
    ("Silence", WEAPON, DAGGER, T_OH, "1h", 1.4, .77, "agi", 53471, 3, 1),       # 10
    ("Oath", WEAPON, SWORD, T_MH, "1h", 2.6, .77, "str1h", 59382, 3, 1),     # 11
    ("Reckoning", WEAPON, SWORD, T_OH, "1h", 2.6, .77, "str1h", 59382, 3, 1),      # 12
    ("Ruin", WEAPON, AXE, T_MH, "1h", 2.6, .77, "str1h", 50076, 3, 1),       # 13
    ("Remembrance", WEAPON, AXE, T_OH, "1h", 2.6, .77, "str1h", 50076, 3, 1),        # 14
    ("Oath of the Forgotten", WEAPON, SWORD2, T_2H, "2h", 3.6, 1.0, "str", 53938, 1, 1),       # 15 Titan's Grip off hand
    ("Empire's End", WEAPON, AXE2, T_2H, "2h", 3.6, 1.0, "str", 50965, 1, 1),         # 16
    ("Memory of the First Dawn", WEAPON, STAFF, T_2H, "2h", 2.1, .77, "caster", 43323, 2, 2),    # 17 Oronok's Ancient Scepter
    ("Root of Ages", WEAPON, STAFF, T_2H, "2h", 3.0, 1.0, "feral", 20269, 2, 2),     # 18 Explorer's Walking Stick
    ("Weight of Ages", WEAPON, MACE2, T_2H, "2h", 3.4, 1.0, "feral", 25047, 1, 2),     # 19 Hammer of the Titans
    ("Light of the Lost", WEAPON, MACE, T_MH, "1h", 1.8, .475, "heal", 53032, 3, 1),      # 20 Titansteel Guardian
    ("Whisper of Ages", WEAPON, BOW, T_BOW, "ranged", 2.8, .88, "ranged", 54501, 0, 2), # 21 Titanium Compound Bow
    ("The Last Word", WEAPON, GUN, T_GUN, "ranged", 2.8, .88, "ranged", 28636, 0, 1), # 22 Dwarven Hand Cannon
    ("The Unbroken Oath", WEAPON, SWORD, T_MH, "1h", 2.4, .77, "tank", 59382, 3, 1),      # 23
    ("Vigil of Stone", WEAPON, MACE, T_MH, "1h", 2.4, .77, "tank", 53030, 3, 1),       # 24 Titansteel Bonecrusher
    ("Bastion of the Forgotten", ARMOR, SHIELD, T_SHIELD, "shield", 0, 0, "shield", 53532, 4, 1),  # 25 Titansteel Shield Wall
    ("The Unbroken Oath", WEAPON, SWORD2, T_2H, "2h", 3.6, 1.0, "tank2h", 52261, 1, 1),   # 26 Titansteel Deflector
    ("Empire's End", WEAPON, AXE2, T_2H, "2h", 3.6, 1.0, "tank2h", 50965, 1, 1),     # 27
]
SLOT_SHARE = {"2h": 1.0, "1h": .47, "ranged": .40, "shield": .55}
CASTER_2H_SHARE, CASTER_1H_SHARE = 1.0, .44    # caster staves and one-handers: stats on top of their spell power
DURABILITY = {"2h": 100, "1h": 75, "ranged": 75, "shield": 100}

WAR, PAL, HUN, ROG, PRI, DK, SHA, MAG, WLK, DRU = 1, 2, 4, 8, 16, 32, 64, 128, 256, 1024
NEED_NONE, NEED_DUAL_WIELD, NEED_TITANS_GRIP = 0, 1, 2
# form: name (gossip text), classes, need, main kind, off kind (-1 = none)
FORMS = [
    ("Two-handed sword (Strength)", WAR | PAL | DK, NEED_NONE, 0, -1),
    ("Two-handed axe (Strength)", WAR | PAL | DK, NEED_NONE, 1, -1),
    ("Two-handed mace (Strength)", WAR | PAL | DK, NEED_NONE, 2, -1),
    ("Pair of swords (Agility)", ROG, NEED_DUAL_WIELD, 3, 4),
    ("Pair of fist weapons (Agility)", ROG | SHA, NEED_DUAL_WIELD, 5, 6),
    ("Pair of axes (Agility)", SHA, NEED_DUAL_WIELD, 7, 8),
    ("Pair of daggers (Agility)", ROG, NEED_DUAL_WIELD, 9, 10),
    ("Pair of swords (Strength)", WAR | DK, NEED_DUAL_WIELD, 11, 12),
    ("Pair of axes (Strength)", WAR | DK, NEED_DUAL_WIELD, 13, 14),
    ("Pair of two-handed swords (Titan's Grip)", WAR, NEED_TITANS_GRIP, 0, 15),
    ("Pair of two-handed axes (Titan's Grip)", WAR, NEED_TITANS_GRIP, 1, 16),
    ("Staff (Intellect)", PRI | SHA | MAG | WLK | DRU, NEED_NONE, 17, -1),
    ("Staff (Agility)", DRU, NEED_NONE, 18, -1),
    ("Two-handed mace (Agility)", SHA | DRU, NEED_NONE, 19, -1),
    ("One-handed mace (Intellect, Spirit)", PAL | PRI | SHA | DRU, NEED_NONE, 20, -1),
    ("Bow (Agility)", HUN, NEED_NONE, 21, -1),
    ("Gun (Agility)", HUN, NEED_NONE, 22, -1),
    ("Sword and shield (Tank)", WAR | PAL, NEED_NONE, 23, 25),
    ("Mace and shield (Tank)", WAR | PAL, NEED_NONE, 24, 25),
    ("Two-handed sword (Tank)", DK, NEED_NONE, 26, -1),
    ("Two-handed axe (Tank)", DK, NEED_NONE, 27, -1),
]

DESCRIPTION = "Pieced together from your finds. Relic Power from digging and solving raises its rank; how far you have come through the ages sets how far it can grow."
AWAKENED = "Awakened by every race's history. Relic Power from digging and solving raised it; it has gone as far as the ages allow."


def item_id(step, kind):
    return ITEM_BASE + step * KINDS_PER_STEP + kind


def sql_str(s):
    return "'" + s.replace("\\", "\\\\").replace("'", "''") + "'"


def item_row(step, kind):
    level, ilvl, quality, _ip, _cost, _gate = STEPS[step]
    name, cls, sub, inv, slot, speed, dps_share, profile, display, sheath, material = KINDS[kind]
    if quality == 6:
        name = "Awakened " + name
    stats, bonus, spell = PROFILES[profile]
    points = ANCHOR[ilvl] * QUALITY_SCALE[quality]
    share = CASTER_2H_SHARE if spell and slot == "2h" else CASTER_1H_SHARE if spell else SLOT_SHARE[slot]
    values = []
    for stat, part in stats:
        v = round(points * share * part * (2 if stat == AP else 1))
        if v > 0:
            values.append((stat, v))
    if spell:
        values.append((SP, round(points * SPELL_POWER)))

    dmg_min = dmg_max = 0.0
    if dps_share:
        avg = DPS[ilvl] * (0.9 if quality == 2 else 1.0) * dps_share * speed
        dmg_min, dmg_max = round(avg * 0.8), round(avg * 1.2)
    armor = SHIELD_ARMOR[ilvl] if slot == "shield" else 0
    block = SHIELD_BLOCK[ilvl] if slot == "shield" else 0

    sockets = []
    if ilvl >= SOCKETS_FROM_ILVL:
        sockets = [RED, YELLOW] if slot == "2h" else [RED]
        if slot == "2h" and ilvl >= THIRD_SOCKET_FROM_ILVL:
            sockets.append(BLUE)
    classes = 0
    for _n, mask, _need, main, off in FORMS:
        if kind in (main, off):
            classes |= mask

    stat_cols = []
    for i in range(10):
        stat_cols += list(values[i]) if i < len(values) else [0, 0]
    socket_cols = []
    for i in range(3):
        socket_cols += [sockets[i] if i < len(sockets) else 0, 0]
    ammo = 2 if sub == BOW else 3 if sub == GUN else 0
    return [item_id(step, kind), cls, sub, -1, sql_str(name), display, quality, 0, 0, 1, 0, 0, inv, classes, -1,
            ilvl, level, 0, 0, 0, 0, 0, 0, 0, 1, 1, 0] + stat_cols + [
            "%g" % dmg_min, "%g" % dmg_max, 0, armor, int(speed * 1000), ammo, 100 if slot == "ranged" else 0,
            1, sql_str(AWAKENED if quality == 6 else DESCRIPTION), material, sheath, block,
            DURABILITY[slot]] + socket_cols + [bonus if sockets else 0, -1, 0]


ITEM_COLUMNS = ("entry, class, subclass, SoundOverrideSubclass, name, displayid, Quality, Flags, FlagsExtra, BuyCount, "
                "BuyPrice, SellPrice, InventoryType, AllowableClass, AllowableRace, ItemLevel, RequiredLevel, "
                "RequiredSkill, RequiredSkillRank, requiredspell, requiredhonorrank, RequiredCityRank, "
                "RequiredReputationFaction, RequiredReputationRank, maxcount, stackable, ContainerSlots, "
                + ", ".join("stat_type%d, stat_value%d" % (i, i) for i in range(1, 11)) +
                ", dmg_min1, dmg_max1, dmg_type1, armor, delay, ammo_type, RangedModRange, bonding, description, "
                "Material, sheath, block, MaxDurability, socketColor_1, socketContent_1, socketColor_2, socketContent_2, "
                "socketColor_3, socketContent_3, socketBonus, RequiredDisenchantSkill, VerifiedBuild")


def values(rows):
    return ",\n".join("(" + ", ".join(str(v) for v in r) + ")" for r in rows)


def main():
    if item_id(len(STEPS) - 1, KINDS_PER_STEP - 1) > ITEM_LAST or len(KINDS) > KINDS_PER_STEP:
        raise SystemExit("the ladder doesn't fit in %d-%d" % (ITEM_BASE, ITEM_LAST))
    for _l, ilvl, *_ in STEPS:
        for table in (ANCHOR, DPS, SHIELD_ARMOR, SHIELD_BLOCK):
            if ilvl not in table:
                raise SystemExit("item level %d is missing from a budget table" % ilvl)
    for name, *_ in FORMS:
        if len(name) > 64:
            raise SystemExit("form name too long: " + name)
    if max(len(DESCRIPTION), len(AWAKENED)) > 255:
        raise SystemExit("item description over 255 characters")

    used = sorted({k for f in FORMS for k in (f[3], f[4]) if k >= 0})
    items = [item_row(s, k) for s in range(len(STEPS)) for k in used]
    eras = [max(i for i, first in enumerate(ERA_FIRST) if first <= s) for s in range(len(STEPS))]

    out = [
        "-- mod-archaeology: the Unearthed Relic's item ladder.",
        "-- Generated by tools/build_relic.py: change the tables there and run it again, don't edit this file.",
        "-- Items 9505000-9505999 (9505000 + step * 30 + kind). Idempotent: safe to run again.",
        "",
        "CREATE TABLE IF NOT EXISTS `mod_archaeology_relic_step` (",
        "  `step` TINYINT UNSIGNED NOT NULL COMMENT 'rank - 1',",
        "  `era` TINYINT UNSIGNED NOT NULL COMMENT '0 vanilla, 1 Burning Crusade, 2 Wrath of the Lich King',",
        "  `required_level` TINYINT UNSIGNED NOT NULL,",
        "  `item_level` SMALLINT UNSIGNED NOT NULL,",
        "  `quality` TINYINT UNSIGNED NOT NULL,",
        "  `progression_state` TINYINT UNSIGNED NOT NULL COMMENT 'individual progression state that opens this rank',",
        "  `cost` INT UNSIGNED NOT NULL COMMENT 'Relic Power to reach this rank',",
        "  `gate` TINYINT UNSIGNED NOT NULL DEFAULT 0 COMMENT '1 last rank of its era: all its rares; 2 awakened: every project',",
        "  PRIMARY KEY (`step`)",
        ") ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;",
        "",
        "CREATE TABLE IF NOT EXISTS `mod_archaeology_relic_form` (",
        "  `id` TINYINT UNSIGNED NOT NULL,",
        "  `name` VARCHAR(64) NOT NULL,",
        "  `classes` INT UNSIGNED NOT NULL COMMENT 'class mask',",
        "  `need` TINYINT UNSIGNED NOT NULL DEFAULT 0 COMMENT '1 dual wield, 2 Titan''s Grip',",
        "  PRIMARY KEY (`id`)",
        ") ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;",
        "",
        "CREATE TABLE IF NOT EXISTS `mod_archaeology_relic_item` (",
        "  `form` TINYINT UNSIGNED NOT NULL,",
        "  `step` TINYINT UNSIGNED NOT NULL,",
        "  `main_item` INT UNSIGNED NOT NULL,",
        "  `off_item` INT UNSIGNED NOT NULL DEFAULT 0,",
        "  PRIMARY KEY (`form`, `step`)",
        ") ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;",
        "",
        "DELETE FROM `mod_archaeology_relic_step`;",
        "INSERT INTO `mod_archaeology_relic_step` (`step`, `era`, `required_level`, `item_level`, `quality`, `progression_state`, `cost`, `gate`) VALUES",
        values([(s, eras[s], lv, il, q, ip, cost, gate) for s, (lv, il, q, ip, cost, gate) in enumerate(STEPS)]) + ";",
        "",
        "DELETE FROM `mod_archaeology_relic_form`;",
        "INSERT INTO `mod_archaeology_relic_form` (`id`, `name`, `classes`, `need`) VALUES",
        values([(i + 1, sql_str(n), mask, need) for i, (n, mask, need, _m, _o) in enumerate(FORMS)]) + ";",
        "",
        "DELETE FROM `mod_archaeology_relic_item`;",
        "INSERT INTO `mod_archaeology_relic_item` (`form`, `step`, `main_item`, `off_item`) VALUES",
        values([(i + 1, s, item_id(s, m), item_id(s, o) if o >= 0 else 0)
                for i, (_n, _c, _need, m, o) in enumerate(FORMS) for s in range(len(STEPS))]) + ";",
        "",
        "DELETE FROM `item_template` WHERE `entry` BETWEEN %d AND %d;" % (ITEM_BASE, ITEM_LAST),
        "INSERT INTO `item_template` (%s) VALUES" % ITEM_COLUMNS,
        values(items) + ";",
        "",
        "-- The client needs Item.dbc rows for these (the patch builder adds them); the server reads the same rows here.",
        "DELETE FROM `item_dbc` WHERE `ID` BETWEEN %d AND %d;" % (ITEM_BASE, ITEM_LAST),
        "INSERT INTO `item_dbc` (`ID`, `ClassID`, `SubclassID`, `Sound_override_subclassid`, `Material`, `DisplayInfoID`, `InventoryType`, `SheatheType`) VALUES",
        values([(r[0], r[1], r[2], -1, KINDS[(r[0] - ITEM_BASE) % KINDS_PER_STEP][10], r[5], r[12],
                 KINDS[(r[0] - ITEM_BASE) % KINDS_PER_STEP][9]) for r in items]) + ";",
    ]
    OUT.write_text("\n".join(out) + "\n", encoding="utf-8", newline="\n")
    print("wrote %s: %d steps, %d forms, %d items" % (OUT.relative_to(ROOT), len(STEPS), len(FORMS), len(items)))


if __name__ == "__main__":
    main()
