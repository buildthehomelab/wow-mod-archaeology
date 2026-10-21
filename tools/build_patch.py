#!/usr/bin/env python3
"""The client side of mod-archaeology: DBC rows, icons and the survey telescope for your realm's
client patches, and the same rows for the server.

    python3 tools/build_patch.py --patch patch-spells.MPQ --skill-patch patch-skills.MPQ \\
        --client /path/to/WoW --out out/ --sql data/sql/db-world/mod_archaeology_world_dbc.sql

A patch MPQ replaces whole files, and the highest patch wins, so every DBC this tool changes has
to be the copy your realm already ships. Each DBC is edited in the first of --patch and
--skill-patch that carries it; a DBC neither carries is taken from the client (--client, its
newest archive that has it) and added to --patch. Every other file in those patches is copied
unchanged, and each patch that changed is written to --out under its own file name. --also-patch
adds more of your realm's patches to look in (for Achievement.dbc, if a third patch carries it).

What the client gets:

- SkillLine.dbc 794 "Archaeology", a secondary skill (category 9), on Cooking's row (185), so
  the server can show its skill in the Skills tab (Archaeology.Skill.SkillLine = 794).
- SkillRaceClassInfo.dbc 90500: every race and class can hold it, with Cooking's tiers (to 450).
  Without this row the core drops the skill when the character logs in.
- Spell.dbc 90500-90505, the six ranks (Apprentice to Grand Master, max skill 75 to 450), copies
  of Cooking's ranks on skill 794 whose cast is a Dummy on yourself instead of the trade skill
  window; and 90506 Survey, 1 s cast, a Dummy on yourself (the module does the survey).
- SkillLineAbility.dbc 90500-90506: those spells on the skill line. Survey is learned with the
  skill (AcquireMethod 1), the ranks replace each other.
- Spell.dbc 90507-90521, the Unearthed Relic's traits: 90507-90514 the eight trait auras the
  module puts on a character wearing the relic, 90515-90521 what they cast (fire damage, energize,
  haste, absorb, heal, poison, Val'kyr's Mercy's cooldown). The numbers are the module's; these
  rows give the names, icons and tooltips.
- Achievement.dbc 9240-9245 and Achievement_Criteria.dbc 19240, the relic achievements under
  Professions. Only "A Weapon in Pieces" has a criteria (the quest); the module grants the rest.
- SpellIcon.dbc 90500 Trade_Archaeology, and Interface\\Icons\\Trade_Archaeology.blp.
- Item.dbc and ItemDisplayInfo.dbc rows for every keystone and artifact in
  mod_archaeology_item_source, with the Cataclysm item's icon (Item.csv IconFileDataID and the
  listfile). An item's display is 950400 + (item - 9504000). Icons the client lacks are
  downloaded into --cache and added under Interface\\Icons.
- Item.dbc rows for the Unearthed Relic's ladder, 9505000-9505999, as tools/build_relic.py wrote
  them in data/sql/db-world/mod_archaeology_world_relic.sql (which gives the server the same
  rows). They use weapon models the client already has, so no display rows are added.
- GameObjectDisplayInfo.dbc 10101-10103 (Cataclysm's ids): the survey telescope, green, yellow
  and red, and its three models converted to the 3.3.5 format with wow-mod-retail-creatures'
  converter (RETAIL_CREATURES, or a mod-retail-creatures / wow-mod-retail-creatures checkout
  next to this one). --no-models leaves the telescope out.
- Interface\\Archeology\\*.blp, Cataclysm's research art that ArchaeologyUI's collection view
  draws: each race's crest, small and big (ResearchBranch TextureFileID and BigTextureFileID),
  each rare artifact's sketch (ResearchProject TextureFileID), the book page and progress bar.

--sql writes the server's rows (skillline_dbc, skillraceclassinfo_dbc, skilllineability_dbc,
spell_dbc, item_dbc, itemdisplayinfo_dbc, gameobjectdisplayinfo_dbc, achievement_dbc,
achievement_criteria_dbc) from the same DBC rows, so
client and server can't disagree, and sets the items' display id in item_template. The rare
rewards' rows (tools/reward_patch.py's add_rewards) are left out of it: --rewards-sql writes them,
the file tools/reward_patch.py writes too (mod_archaeology_world_z_rewards_dbc.sql).

Inputs from tools/cata-data/ (see the README): c_Item.csv, c_GODI.csv, c_ResearchBranch.csv,
c_ResearchProject.csv, listfile_archaeology.csv,
and data/sql/db-world/mod_archaeology_world_data.sql for the item map. Models and icons come from
wago.tools by file data id. Running it again on its own output changes nothing. Needs Python 3
and StormLib (`STORMLIB`, default /usr/local/lib/libstorm.dylib).
"""

import argparse
import csv
import ctypes
import glob
import importlib.util
import os
import re
import struct
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CATA = os.path.join(ROOT, "tools", "cata-data")
WORLD_DATA = os.path.join(ROOT, "data", "sql", "db-world", "mod_archaeology_world_data.sql")
RELIC_DATA = os.path.join(ROOT, "data", "sql", "db-world", "mod_archaeology_world_relic.sql")
RELIC_FIRST, RELIC_LAST = 9505000, 9505999

SKILL = 794
SKILL_NAME = "Archaeology"
SKILL_DESCRIPTION = ("Higher archaeology skill allows you to complete more valuable artifacts and collect more "
                     "artifact fragments. Fragments can be found in ruins and dig sites.")
SKILL_CATEGORY_SECONDARY = 9
COOKING = 185
RACE_CLASS_ID = 90500

FIRST_SPELL = 90500
RANKS = [  # Cooking's rank spell, rank name, max skill
    (2550, "Apprentice", 75), (3102, "Journeyman", 150), (3413, "Expert", 225),
    (18260, "Artisan", 300), (33359, "Master", 375), (51296, "Grand Master", 450),
]
RANK_DESCRIPTION = "Allows an archaeologist to find artifact fragments and complete artifacts up to a " \
                   "maximum potential skill of %d."
SURVEY = FIRST_SPELL + len(RANKS)
SURVEY_NAME = "Survey"
SURVEY_DESCRIPTION = ("Survey for archaeology fragments within a dig site. Each survey will direct you closer "
                      "to the location of the fragments.")
SURVEY_ICON = "INV_Misc_Shovel_01"          # Cataclysm's Survey icon, already in the 3.3.5 client
DUMMY_SPELL = 18282                         # "Dummy Spell": instant, self, no cost

ICON_ID = 90500
ICON = "Trade_Archaeology"
ICON_FDID = 441139

ITEM_FIRST, ITEM_LAST = 9504000, 9504499
DISPLAY_BASE = 950400                       # ItemDisplayInfo id = DISPLAY_BASE + (item - ITEM_FIRST)
TEMPLATE_ITEM_DISPLAY = 20629               # an icon and nothing else (Cat Carrier (Bombay))
UNSET = 0xFFFFFFFF

TELESCOPE_DIR = "World\\Expansion03\\Doodads\\Archaeology"
TELESCOPE = [  # GameObjectDisplayInfo id (Cataclysm's), model name
    (10101, "Tradeskill_Archaeology_SurveyTool_Green"),
    (10102, "Tradeskill_Archaeology_SurveyTool_Yellow"),
    (10103, "Tradeskill_Archaeology_SurveyTool_Red"),
]

# Spell.dbc (3.3.5a, build 12340)
SPELL_FIELDS = 234
F_CATEGORY = 1
F_ATTRIBUTES = 4
F_CAST_TIME, F_RECOVERY, F_CATEGORY_RECOVERY, F_INTERRUPT = 28, 29, 30, 31
F_RANGE = 46
F_EFFECT, F_BASE_POINTS, F_TARGET_A, F_TARGET_B, F_MISC = 71, 80, 86, 89, 110
F_ICON, F_ACTIVE_ICON, F_NAME, F_SUBTEXT, F_DESCRIPTION, F_AURA_TEXT = 133, 134, 136, 153, 170, 187
F_GCD_CATEGORY, F_GCD = 205, 206
SPELL_STRINGS = set(range(136, 152)) | set(range(153, 169)) | set(range(170, 186)) | set(range(187, 203))
SPELL_FLOATS = {47, 77, 78, 79, 101, 102, 103, 119, 120, 121, 216, 217, 218, 229, 230, 231}
# Plain `int` columns of AC's spell_dbc; every other integer column is unsigned.
SPELL_SIGNED = {0, 13, 15, 41, *range(52, 71), 74, 75, 76, 80, 81, 82, *range(110, 116), 224, 228}
EFFECT_DUMMY, EFFECT_TRADE_SKILL, EFFECT_SKILL = 3, 47, 118
TARGET_UNIT_CASTER = 1
CAST_1S = 4                                 # SpellCastTimes.dbc, as Cataclysm's Survey
INTERRUPT_MOVE_PUSHBACK_INTERRUPT = 0x1F
RANGE_SELF = 1
GCD_CATEGORY, GCD = 133, 1500
SURVEY_RECOVERY = 3000                      # Cataclysm's; matches Archaeology.Survey.CooldownMs

F_ATTRIBUTES_EX3, F_ATTRIBUTES_EX4 = 7, 8
F_PROC_FLAGS, F_PROC_CHANCE, F_DURATION, F_STACK = 34, 35, 40, 49
F_AURA, F_AMPLITUDE, F_VISUAL = 95, 98, 131
F_DMG_CLASS, F_DMG_MULTIPLIER, F_SCHOOL = 213, 216, 225
SPELL_LANG_MASKS = (152, 169, 186, 203)
CAST_INSTANT = 1
RANGE_ANYWHERE = 13
DURATION = {"10s": 1, "12s": 29, "10min": 6, "infinite": 21}   # SpellDuration.dbc
EFFECT_SCHOOL_DAMAGE, EFFECT_HEAL, EFFECT_APPLY_AURA, EFFECT_ENERGIZE = 2, 10, 6, 30
AURA_PERIODIC_DAMAGE, AURA_DUMMY, AURA_CASTING_SPEED, AURA_SCHOOL_ABSORB = 3, 4, 65, 69
AURA_DAMAGE_PERCENT, AURA_MELEE_HASTE, AURA_RANGED_HASTE, AURA_PERIODIC_DUMMY = 79, 138, 140, 226
TARGET_UNIT_TARGET_ENEMY, TARGET_UNIT_TARGET_ALLY = 6, 21
ATTR0_AURA_IS_DEBUFF, ATTR0_NO_IMMUNITIES, ATTR0_NO_AURA_CANCEL = 0x04000000, 0x20000000, 0x80000000
ATTR3_ALLOW_AURA_WHILE_DEAD = 0x00100000
ATTR4_ALLOW_ENTERING_ARENA = 0x00200000
SCHOOL_PHYSICAL, SCHOOL_HOLY, SCHOOL_FIRE, SCHOOL_NATURE, SCHOOL_ALL = 1, 2, 4, 8, 127
DMG_CLASS_MAGIC = 1
# Proc flags, the same as spell_proc in mod_archaeology_world_traits.sql (the server reads those).
PROC_DONE_HARM, PROC_DONE_ALL, PROC_TAKEN_HARM = 69972, 87380, 139944

TRAIT_TEXT = "Stronger with every rank of the Unearthed Relic, and stronger still once every %s project is solved."
MERCY_TEXT = "Stronger with every rank of the Unearthed Relic; recovers faster once every %s project is solved."
# The relic's traits: aura spells first, then what they cast. effects: (effect, aura, target, misc, amplitude).
# visual: a stock spell whose SpellVisual the row borrows, 0 for none.
TRAIT_AURA = dict(attr0=ATTR0_NO_AURA_CANCEL, attr3=ATTR3_ALLOW_AURA_WHILE_DEAD, attr4=ATTR4_ALLOW_ENTERING_ARENA,
                  duration="infinite", subtext="Relic trait")
TRAITS = [
    dict(id=90507, name="Thaurissan's Ember", icon="Spell_Fire_Incinerate", proc=PROC_DONE_HARM, race="Dwarf",
         text="Your melee and ranged attacks and harmful spells sometimes burn the target for Fire damage.",
         effects=[(EFFECT_APPLY_AURA, AURA_DUMMY, TARGET_UNIT_CASTER, 0, 0)], **TRAIT_AURA),
    dict(id=90508, name="Highborne Focus", icon="Spell_Arcane_MindMastery", proc=PROC_DONE_ALL, race="Night Elf",
         text="Your attacks, spells and heals sometimes restore mana, rage, energy or runic power.",
         effects=[(EFFECT_APPLY_AURA, AURA_DUMMY, TARGET_UNIT_CASTER, 0, 0)], **TRAIT_AURA),
    dict(id=90509, name="Zandalari Vigor", icon="Racial_Troll_Berserk", proc=PROC_DONE_ALL, race="Troll",
         text="Your attacks, spells and heals sometimes grant a burst of haste.",
         effects=[(EFFECT_APPLY_AURA, AURA_DUMMY, TARGET_UNIT_CASTER, 0, 0)], **TRAIT_AURA),
    dict(id=90510, name="Amber Ward", icon="INV_Misc_Gem_Topaz_02", proc=PROC_TAKEN_HARM, race="Fossil",
         text="When you are struck, you sometimes gain a shield that absorbs damage.",
         effects=[(EFFECT_APPLY_AURA, AURA_DUMMY, TARGET_UNIT_CASTER, 0, 0)], **TRAIT_AURA),
    dict(id=90511, name="Light of the Naaru", icon="Spell_Holy_SummonLightwell", proc=PROC_DONE_ALL, race="Draenei",
         text="Your attacks, spells and heals sometimes heal you or the most wounded member of your group nearby.",
         effects=[(EFFECT_APPLY_AURA, AURA_DUMMY, TARGET_UNIT_CASTER, 0, 0)], **TRAIT_AURA),
    dict(id=90512, name="Blood of the Horde", icon="Ability_Racial_BloodRage", proc=0, race="Orc",
         text="You deal more damage the lower your health falls.",
         effects=[(EFFECT_APPLY_AURA, AURA_DAMAGE_PERCENT, TARGET_UNIT_CASTER, SCHOOL_ALL, 0),
                  (EFFECT_APPLY_AURA, AURA_PERIODIC_DUMMY, TARGET_UNIT_CASTER, 0, 1000)], **TRAIT_AURA),
    dict(id=90513, name="Ahn'kahar Venom", icon="Ability_Creature_Poison_05", proc=PROC_DONE_HARM, race="Nerubian",
         text="Your melee and ranged attacks and harmful spells sometimes poison the target, stacking up to 5 times.",
         effects=[(EFFECT_APPLY_AURA, AURA_DUMMY, TARGET_UNIT_CASTER, 0, 0)], **TRAIT_AURA),
    dict(id=90514, name="Val'kyr's Mercy", icon="Spell_Holy_GuardianSpirit", proc=0, race="Vrykul",
         text="A killing blow leaves you alive instead, then it needs time to recover.", race_text=MERCY_TEXT,
         effects=[(EFFECT_APPLY_AURA, AURA_SCHOOL_ABSORB, TARGET_UNIT_CASTER, SCHOOL_ALL, 0),
                  (EFFECT_APPLY_AURA, AURA_DUMMY, TARGET_UNIT_CASTER, 0, 0),
                  (EFFECT_APPLY_AURA, AURA_DUMMY, TARGET_UNIT_CASTER, 0, 0)], **TRAIT_AURA),
    dict(id=90515, name="Thaurissan's Ember", icon="Spell_Fire_Incinerate", visual=13897, school=SCHOOL_FIRE,
         dmg_class=DMG_CLASS_MAGIC, range=RANGE_ANYWHERE, description="Burns the target for Fire damage.",
         effects=[(EFFECT_SCHOOL_DAMAGE, 0, TARGET_UNIT_TARGET_ENEMY, 0, 0)]),
    dict(id=90516, name="Highborne Focus", icon="Spell_Arcane_MindMastery", description="Restores power.",
         effects=[(EFFECT_ENERGIZE, 0, TARGET_UNIT_CASTER, 0, 0)]),
    dict(id=90517, name="Zandalari Vigor", icon="Racial_Troll_Berserk", visual=26297, duration="10s",
         description="Increases melee, ranged and casting speed for 10 sec.", aura_text="Haste increased.",
         effects=[(EFFECT_APPLY_AURA, AURA_MELEE_HASTE, TARGET_UNIT_CASTER, 0, 0),
                  (EFFECT_APPLY_AURA, AURA_RANGED_HASTE, TARGET_UNIT_CASTER, 0, 0),
                  (EFFECT_APPLY_AURA, AURA_CASTING_SPEED, TARGET_UNIT_CASTER, 0, 0)]),
    dict(id=90518, name="Amber Ward", icon="INV_Misc_Gem_Topaz_02", visual=17, duration="10s",
         description="Absorbs damage for 10 sec.", aura_text="Absorbs damage.",
         effects=[(EFFECT_APPLY_AURA, AURA_SCHOOL_ABSORB, TARGET_UNIT_CASTER, SCHOOL_ALL, 0)]),
    dict(id=90519, name="Light of the Naaru", icon="Spell_Holy_SummonLightwell", visual=2061, school=SCHOOL_HOLY,
         dmg_class=DMG_CLASS_MAGIC, range=RANGE_ANYWHERE, description="Heals a friendly target.",
         effects=[(EFFECT_HEAL, 0, TARGET_UNIT_TARGET_ALLY, 0, 0)]),
    dict(id=90520, name="Ahn'kahar Venom", icon="Ability_Creature_Poison_05", visual=2818, school=SCHOOL_NATURE,
         dmg_class=DMG_CLASS_MAGIC, range=RANGE_ANYWHERE, duration="12s", stack=5,
         description="Nature damage every 3 sec for 12 sec. Stacks up to 5 times.", aura_text="Nature damage every 3 sec.",
         effects=[(EFFECT_APPLY_AURA, AURA_PERIODIC_DAMAGE, TARGET_UNIT_TARGET_ENEMY, 0, 3000)]),
    dict(id=90521, name="Val'kyr's Mercy", icon="Spell_Holy_GuardianSpirit", duration="10min",
         # Not removable by immunities (Divine Shield, Ice Block) or by entering an arena, or the
         # save would come back early.
         attr0=ATTR0_AURA_IS_DEBUFF | ATTR0_NO_IMMUNITIES | ATTR0_NO_AURA_CANCEL, attr3=ATTR3_ALLOW_AURA_WHILE_DEAD,
         attr4=ATTR4_ALLOW_ENTERING_ARENA,
         description="Recently spared by Val'kyr's Mercy.", aura_text="Val'kyr's Mercy can't save you again yet.",
         effects=[(EFFECT_APPLY_AURA, AURA_DUMMY, TARGET_UNIT_CASTER, 0, 0)]),
]

# Relic achievements, ids as the module's src/Archaeology.h. (id, title, description, points, icon)
ACHIEVEMENT_CATEGORY = 169                  # Professions
# Tables other modules' patches often carry too: taken from a realm patch only through --also-patch.
SHARED_TABLES = {"Achievement", "Achievement_Criteria", "SpellVisual", "SpellVisualKit", "SpellVisualEffectName"}
ACHIEVEMENT_TEMPLATE = 1563                 # Hail to the Chef: its language masks
RELIC_QUEST = 9503500
ACHIEVEMENTS = [
    (9240, "A Weapon in Pieces", "Piece together the Unearthed Relic.", 10, "Trade_Archaeology"),
    (9241, "Tempered by the Ages", "Raise the Unearthed Relic to the last rank of the old world.", 10,
     "achievement_boss_kelthuzad_01"),
    (9242, "Legend of the Outlands", "Raise the Unearthed Relic to Legendary quality.", 10, "Achievement_Boss_Kiljaedan"),
    (9243, "Every Voice Awake", "Wake all eight traits of the Unearthed Relic.", 10, "INV_Misc_Rune_01"),
    (9244, "Keeper of All Ages", "Solve every archaeology project of every race.", 25, "INV_Misc_Book_11"),
    (9245, "Awakened", "Awaken the Unearthed Relic to Artifact quality.", 25, "achievement_boss_lichking"),
]
CRITERIA = [(19240, 9240, 27, RELIC_QUEST, 1, "A Weapon in Pieces")]   # (id, achievement, type, asset, count, text)

# Other tables: field count, string fields, float fields, unsigned fields (AC's *_dbc columns)
TABLES = {
    "SkillLine": (56, {*range(3, 19), *range(20, 36), *range(38, 54)}, set(), {19, 36, 54}),
    "SkillLineAbility": (14, set(), set(), set()),
    "SkillRaceClassInfo": (8, set(), set(), set()),
    "Item": (8, set(), set(), set()),
    "ItemDisplayInfo": (25, {1, 2, 3, 4, 5, 6, *range(15, 23)}, set(), set()),
    "GameObjectDisplayInfo": (19, {1}, set(range(12, 18)), set()),
    "SpellIcon": (2, {1}, set(), set()),
    "SpellVisual": (32, set(), set(), set()),
    "SpellVisualKit": (38, set(), set(), set()),
    "SpellVisualEffectName": (7, {1, 2}, set(), set()),
    "Achievement": (62, {*range(4, 20), *range(21, 37), *range(43, 59)}, set(), {20, 37, 59}),
    "Achievement_Criteria": (31, set(range(9, 25)), set(), {25}),
    "Spell": (SPELL_FIELDS, SPELL_STRINGS, SPELL_FLOATS, set(range(SPELL_FIELDS)) - SPELL_SIGNED),
}
SQL_TABLES = [("SkillLine", "skillline_dbc"), ("SkillRaceClassInfo", "skillraceclassinfo_dbc"),
              ("SkillLineAbility", "skilllineability_dbc"), ("Spell", "spell_dbc"), ("Item", "item_dbc"),
              ("ItemDisplayInfo", "itemdisplayinfo_dbc"), ("GameObjectDisplayInfo", "gameobjectdisplayinfo_dbc"),
              ("Achievement", "achievement_dbc"), ("Achievement_Criteria", "achievement_criteria_dbc")]


# --- DBC ---------------------------------------------------------------------------------------

class Dbc:
    def __init__(self, path, table):
        with open(path, "rb") as source:
            data = source.read()
        magic, count, fields, size, strsize = struct.unpack_from("<4s4I", data, 0)
        if magic != b"WDBC" or size != fields * 4:
            sys.exit("%s isn't a plain WDBC file" % table)
        if fields != TABLES[table][0]:
            sys.exit("%s.dbc has %d fields, not %d" % (table, fields, TABLES[table][0]))
        self.table, self.fields = table, fields
        self.rows = {}
        for i in range(count):
            row = list(struct.unpack_from("<%dI" % fields, data, 20 + i * size))
            if row[0] in self.rows:
                sys.exit("%s.dbc has row %d twice" % (table, row[0]))
            self.rows[row[0]] = row
        self.strings = bytearray(data[20 + count * size:20 + count * size + strsize])
        self.ours = []
        self.by_id = list(self.rows) == sorted(self.rows)

    def write(self, path):
        # A file in id order stays so; any other keeps its own order, our new rows after it (a
        # replaced row keeps its place). The client needs that: it indexes SkillRaceClassInfo.dbc
        # by runs of rows with the same skill, so a skill's rows have to stay together, as in
        # Blizzard's file. Apart (sorted by id), the client reaches only one run, and most
        # characters lose the skill (First Aid, Defense, weapon skills, Riding) from the Skills
        # tab and the spellbook.
        keys = sorted(self.rows) if self.by_id else list(self.rows)
        if self.table == "SkillRaceClassInfo":
            seen, last = set(), None
            for key in keys:
                skill = self.rows[key][1]
                if skill != last and skill in seen:
                    sys.exit("SkillRaceClassInfo.dbc: skill %d's rows aren't together; build on a "
                             "copy in Blizzard's order (grouped by skill)" % skill)
                seen.add(skill)
                last = skill
        with open(path, "wb") as f:
            f.write(struct.pack("<4s4I", b"WDBC", len(self.rows), self.fields, self.fields * 4, len(self.strings)))
            for key in keys:
                f.write(struct.pack("<%dI" % self.fields, *self.rows[key]))
            f.write(self.strings)

    def string(self, at):
        return self.strings[at:self.strings.index(b"\0", at)].decode("utf-8")

    def add_string(self, text):
        """Offset of text in the string block, appended unless it is already there as a whole string."""
        if not text:
            return 0
        raw = text.encode("utf-8") + b"\0"
        at = self.strings.find(b"\0" + raw)
        if at >= 0:
            return at + 1
        at = len(self.strings)
        self.strings.extend(raw)
        return at

    def template(self, row_id, what):
        if row_id not in self.rows:
            sys.exit("%s.dbc row %d (%s) is missing" % (self.table, row_id, what))
        return list(self.rows[row_id])

    def put(self, row, owner_field=None, owner=None):
        """Adds or replaces one of our rows. A row already there is only replaced if it is ours:
        owner_field's string (or value) equals owner."""
        old = self.rows.get(row[0])
        if old and owner_field is not None:
            if owner_field in TABLES[self.table][1]:
                have = self.string(old[owner_field])
                mine = have.lower() == owner.lower()
            else:
                have = old[owner_field]
                mine = have == owner
            if not mine:
                sys.exit("%s.dbc row %d is taken by %r" % (self.table, row[0], have))
        self.rows[row[0]] = row
        self.ours.append(row)

    def find_string(self, field, text):
        """Id of the first row whose field holds text (case-insensitive), or None."""
        for key in sorted(self.rows):
            if self.rows[key][field] and self.string(self.rows[key][field]).lower() == text.lower():
                return key
        return None


# --- MPQ ---------------------------------------------------------------------------------------

def stormlib():
    lib = ctypes.CDLL(os.environ.get("STORMLIB", "/usr/local/lib/libstorm.dylib"))
    H = ctypes.c_void_p
    lib.SFileOpenArchive.argtypes = [ctypes.c_char_p, ctypes.c_uint, ctypes.c_uint, ctypes.POINTER(H)]
    lib.SFileExtractFile.argtypes = [H, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_uint]
    lib.SFileHasFile.argtypes = [H, ctypes.c_char_p]
    lib.SFileFindFirstFile.argtypes = [H, ctypes.c_char_p, ctypes.c_void_p, ctypes.c_char_p]
    lib.SFileFindFirstFile.restype = H
    lib.SFileFindNextFile.argtypes = [H, ctypes.c_void_p]
    lib.SFileFindClose.argtypes = [H]
    lib.SFileCreateArchive.argtypes = [ctypes.c_char_p, ctypes.c_uint, ctypes.c_uint, ctypes.POINTER(H)]
    lib.SFileAddFileEx.argtypes = [H, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_uint, ctypes.c_uint, ctypes.c_uint]
    lib.SFileCloseArchive.argtypes = [H]
    for fn in (lib.SFileOpenArchive, lib.SFileExtractFile, lib.SFileHasFile, lib.SFileFindNextFile,
               lib.SFileFindClose, lib.SFileCreateArchive, lib.SFileAddFileEx, lib.SFileCloseArchive):
        fn.restype = ctypes.c_bool
    return lib, H


def open_mpq(lib, H, mpq):
    h = H()
    if not lib.SFileOpenArchive(mpq.encode(), 0, 0x100, ctypes.byref(h)):
        sys.exit("can't open " + mpq)
    return h


def unpack(mpq, folder):
    """Extracts every file; returns {archive name: local path}."""
    lib, H = stormlib()
    h = open_mpq(lib, H, mpq)
    names = []
    found = ctypes.create_string_buffer(2048)  # SFILE_FIND_DATA starts with the name (1024 bytes)
    find = lib.SFileFindFirstFile(h, b"*", found, None)
    while find:
        name = found.value.decode("latin-1")
        if name not in ("(listfile)", "(attributes)", "(signature)"):
            names.append(name)
        if not lib.SFileFindNextFile(find, found):
            lib.SFileFindClose(find)
            break
    os.makedirs(folder, exist_ok=True)
    files = {}
    for i, name in enumerate(names):
        local = os.path.join(folder, "%05d" % i)
        if not lib.SFileExtractFile(h, name.encode("latin-1"), local.encode(), 0):
            sys.exit("can't extract %s from %s" % (name, mpq))
        files[name] = local
    lib.SFileCloseArchive(h)
    if not files:
        sys.exit("%s has no files (or no listfile)" % mpq)
    return files


def pack(out, files):
    """files: [(local path, archive name)]. zlib-compressed, with listfile and attributes."""
    lib, H = stormlib()
    if os.path.exists(out):
        os.remove(out)
    h = H()
    if not lib.SFileCreateArchive(out.encode(), 0x00300000, max(64, len(files) * 2), ctypes.byref(h)):
        sys.exit("can't create " + out)
    for src, name in files:
        if not lib.SFileAddFileEx(h, src.encode(), name.encode("latin-1"), 0x80000200, 0x02, 0x02):
            lib.SFileCloseArchive(h)
            os.remove(out)
            sys.exit("can't add " + name)
    if not lib.SFileCloseArchive(h):
        os.remove(out)
        sys.exit("can't finish " + out)


class Client:
    """The base client's archives, newest first: the extra Data/patch-*.MPQ in reverse name order,
    then Blizzard's locale and general patches, then the base archives. Our own patches (skip)
    are left out: the tool reads those itself."""

    def __init__(self, folder, locale, skip):
        data = os.path.join(folder, "Data") if os.path.isdir(os.path.join(folder, "Data")) else folder
        loc = os.path.join(data, locale)
        if not os.path.isdir(loc):
            sys.exit("no %s folder in %s: --client is the WoW folder or its Data folder" % (locale, data))
        blizzard = {"patch.mpq", "patch-2.mpq", "patch-3.mpq"}
        extra = sorted((p for p in glob.glob(os.path.join(data, "patch-*.[mM][pP][qQ]"))
                        if os.path.basename(p).lower() not in blizzard | skip), key=lambda p: os.path.basename(p).lower())
        # patch-enUS.MPQ, then patch-enUS-2.MPQ, patch-enUS-3.MPQ, ...
        stem = len("patch-" + locale)
        locale_patches = sorted(glob.glob(os.path.join(loc, "patch-%s*.[mM][pP][qQ]" % locale)),
                                key=lambda p: os.path.basename(p).lower()[stem:-4])
        self.extra = {os.path.basename(p).lower() for p in extra}   # patches that aren't Blizzard's
        order = extra[::-1] + locale_patches[::-1]
        order += [os.path.join(data, n) for n in ("patch-3.MPQ", "patch-2.MPQ", "patch.MPQ")]
        order += [os.path.join(loc, n % locale) for n in ("lichking-locale-%s.MPQ", "expansion-locale-%s.MPQ",
                                                           "locale-%s.MPQ")]
        order += [os.path.join(data, n) for n in ("lichking.MPQ", "expansion.MPQ", "common-2.MPQ", "common.MPQ")]
        self.lib, H = stormlib()
        self.archives = []
        for path in order:
            if os.path.exists(path):
                self.archives.append((path, open_mpq(self.lib, H, path)))

    def has(self, name):
        return any(self.lib.SFileHasFile(h, name.encode("latin-1")) for _p, h in self.archives)

    def extract(self, name, dst):
        """The newest copy of name; returns the archive it came from."""
        for path, h in self.archives:
            if self.lib.SFileHasFile(h, name.encode("latin-1")):
                if not self.lib.SFileExtractFile(h, name.encode("latin-1"), dst.encode(), 0):
                    sys.exit("can't extract %s from %s" % (name, path))
                return os.path.basename(path)
        sys.exit("the client has no " + name)


# --- inputs ------------------------------------------------------------------------------------

def retail_tools():
    """wow-mod-retail-creatures' tools folder (the converter and the wago.tools downloads)."""
    here = os.path.dirname(ROOT)
    for path in (os.environ.get("RETAIL_CREATURES"), os.path.join(here, "mod-retail-creatures"),
                 os.path.join(here, "wow-mod-retail-creatures")):
        if path and os.path.exists(os.path.join(path, "tools", "m2creature.py")):
            return os.path.join(path, "tools")
    sys.exit("wow-mod-retail-creatures not found: clone it next to this repo or set RETAIL_CREATURES")


def load_retail():
    tools = retail_tools()
    sys.path.insert(1, tools)
    spec = importlib.util.spec_from_file_location("retail_build_patch", os.path.join(tools, "build_patch.py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def read_csv(name):
    path = os.path.join(CATA, name)
    if not os.path.exists(path):
        sys.exit("missing %s; see the README, 'Rebuilding the data'" % path)
    with open(path, newline="", encoding="utf-8") as f:
        return list(csv.DictReader(f))


def module_items():
    """[(item, cata item, class, subclass)] from the generated world data."""
    text = open(WORLD_DATA, encoding="utf-8").read()

    def block(table):
        start = text.index("INSERT INTO `%s`" % table)
        end = text.find("\nDELETE FROM", start)
        return text[start:end if end >= 0 else len(text)]

    classes = {int(m.group(1)): (int(m.group(2)), int(m.group(3)))
               for m in re.finditer(r"^\((\d+), (\d+), (\d+), '", block("item_template"), re.M)}
    items = []
    for m in re.finditer(r"^\((\d+), (\d+), '", block("mod_archaeology_item_source"), re.M):
        item, cata = int(m.group(1)), int(m.group(2))
        if not ITEM_FIRST <= item <= ITEM_LAST:
            sys.exit("item %d is outside %d-%d" % (item, ITEM_FIRST, ITEM_LAST))
        if item not in classes:
            sys.exit("item %d has no item_template row in %s" % (item, WORLD_DATA))
        items.append((item, cata) + classes[item])
    if not items:
        sys.exit("no items in " + WORLD_DATA)
    return items


def relic_items():
    """Item.dbc rows of the relic ladder, from the item_dbc block tools/build_relic.py wrote."""
    text = open(RELIC_DATA, encoding="utf-8").read()
    block = text[text.index("INSERT INTO `item_dbc`"):]
    rows = [[int(v) for v in m.groups()] for m in
            re.finditer(r"^\((\d+), (\d+), (\d+), (-?\d+), (\d+), (\d+), (\d+), (\d+)\)", block, re.M)]
    for row in rows:
        if not RELIC_FIRST <= row[0] <= RELIC_LAST:
            sys.exit("relic item %d is outside %d-%d" % (row[0], RELIC_FIRST, RELIC_LAST))
    if not rows:
        sys.exit("no relic items in " + RELIC_DATA)
    return rows


def add_relic(dbc, rows):
    for row in rows:
        dbc["Item"].put([v & 0xFFFFFFFF for v in row])
    print("Item.dbc: %d relic items" % len(rows))


def icon_paths(fdids, cache, retail):
    """{file data id: listfile path} from the filtered listfile, else the full one (downloaded)."""
    paths = {}
    for line in open(os.path.join(CATA, "listfile_archaeology.csv"), encoding="utf-8"):
        i, _, p = line.strip().partition(";")
        if i.isdigit() and int(i) in fdids:
            paths[int(i)] = p
    missing = set(fdids) - set(paths)
    if missing:
        paths.update(retail.listfile(cache, missing))
    return paths


# The collection view's book page and progress bar (Cataclysm's ArchaeologyFrame), by listfile name.
RESEARCH_ART = ("arch-bookcompletedleft", "arch-bookcompletedright", "arch-progress-bg", "arch-progress-fill")


def module_projects():
    """[(project, race, rare)] from the generated world data."""
    text = open(WORLD_DATA, encoding="utf-8").read()
    block = text[text.index("INSERT INTO `mod_archaeology_project`"):]
    block = block[:block.find(";\n")]
    return [(int(m.group(1)), int(m.group(2)), m.group(3) == "1") for m in
            re.finditer(r"^\((\d+), (\d+), '(?:[^']|'')*', '(?:[^']|'')*', (\d+),", block, re.M)]


def add_research_art(files, cache, retail):
    """The races' crests, the rares' sketches and the book art, under Interface\\Archeology."""
    projects = module_projects()
    branches = {int(r["ID"]): r for r in read_csv("c_ResearchBranch.csv")}
    cata = {int(r["ID"]): r for r in read_csv("c_ResearchProject.csv")}
    fdids = set()
    for race in sorted({race for _p, race, _r in projects}):
        if race not in branches:
            sys.exit("race %d isn't in c_ResearchBranch.csv" % race)
        fdids.update(int(branches[race][k]) for k in ("TextureFileID", "BigTextureFileID"))
    for project, _race, rare in projects:
        if rare:
            if project not in cata or not int(cata[project]["TextureFileID"]):
                sys.exit("rare project %d has no sketch in c_ResearchProject.csv" % project)
            fdids.add(int(cata[project]["TextureFileID"]))
    names = {}
    for line in open(os.path.join(CATA, "listfile_archaeology.csv"), encoding="utf-8"):
        i, _, path = line.strip().partition(";")
        names[path.lower()] = int(i) if i.isdigit() else None
    for art in RESEARCH_ART:
        fdid = names.get("interface/archeology/%s.blp" % art)
        if not fdid:
            sys.exit("%s isn't in listfile_archaeology.csv" % art)
        fdids.add(fdid)
    paths = icon_paths(fdids, cache, retail)
    for fdid in sorted(fdids):
        path = paths.get(fdid, "").replace("/", "\\")
        if not path.lower().startswith("interface\\archeology\\") or not path.lower().endswith(".blp"):
            sys.exit("research art %d is %r, not Interface\\Archeology art" % (fdid, path))
        blp = retail.fetch.casc_path(cache, fdid)
        if open(blp, "rb").read(4) != b"BLP2":
            sys.exit("research art %d isn't a BLP2 file" % fdid)
        files["Interface\\Archeology\\" + os.path.basename(path.replace("\\", "/"))] = blp
    print("Interface\\Archeology: %d textures (crests, sketches, book)" % len(fdids))


# --- the rows ----------------------------------------------------------------------------------

def add_skill(dbc):
    icons = dbc["SpellIcon"]
    icons.put([ICON_ID, icons.add_string("Interface\\Icons\\" + ICON)], 1, "Interface\\Icons\\" + ICON)

    lines = dbc["SkillLine"]
    row = lines.template(COOKING, "Cooking")
    row[0] = SKILL
    row[1] = SKILL_CATEGORY_SECONDARY
    row[2] = 0
    for field in TABLES["SkillLine"][1]:
        row[field] = 0
    row[3] = lines.add_string(SKILL_NAME)
    row[20] = lines.add_string(SKILL_DESCRIPTION)
    row[37] = ICON_ID
    row[55] = 0
    lines.put(row, 3, SKILL_NAME)

    race_class = dbc["SkillRaceClassInfo"]
    cooking = [r for r in race_class.rows.values() if r[1] == COOKING]
    if len(cooking) != 1:
        sys.exit("SkillRaceClassInfo.dbc has %d Cooking rows, expected 1" % len(cooking))
    row = list(cooking[0])
    row[0] = RACE_CLASS_ID
    row[1] = SKILL
    race_class.put(row, 1, SKILL)


def add_spells(dbc):
    spells = dbc["Spell"]
    abilities = dbc["SkillLineAbility"]
    survey_icon = dbc["SpellIcon"].find_string(1, "Interface\\Icons\\" + SURVEY_ICON)
    if survey_icon is None:
        sys.exit("SpellIcon.dbc has no %s" % SURVEY_ICON)

    for n, (cooking, rank, max_skill) in enumerate(RANKS):
        spell_id = FIRST_SPELL + n
        row = spells.template(cooking, "Cooking " + rank)
        steps = [i for i in range(3) if row[F_EFFECT + i] == EFFECT_SKILL and row[F_MISC + i] == COOKING]
        if len(steps) != 1:
            sys.exit("Spell.dbc %d (Cooking %s) has no Skill effect on Cooking" % (cooking, rank))
        row[0] = spell_id
        row[F_MISC + steps[0]] = SKILL
        for i in range(3):
            if row[F_EFFECT + i] == EFFECT_TRADE_SKILL:
                # Clicking the spell opens Archaeology through the module, not an empty trade skill window.
                row[F_EFFECT + i] = EFFECT_DUMMY
                row[F_TARGET_A + i] = TARGET_UNIT_CASTER
                row[F_TARGET_B + i] = 0
        row[F_ICON] = ICON_ID
        row[F_ACTIVE_ICON] = 0
        for field in SPELL_STRINGS:
            row[field] = 0
        row[F_NAME] = spells.add_string(SKILL_NAME)
        row[F_SUBTEXT] = spells.add_string(rank)
        row[F_DESCRIPTION] = spells.add_string(RANK_DESCRIPTION % max_skill)
        spells.put(row, F_NAME, SKILL_NAME)

        ability = next((list(r) for r in abilities.rows.values() if r[2] == cooking), [0] * 14)
        ability[0] = spell_id
        ability[1] = SKILL
        ability[2] = spell_id
        ability[3:7] = [0, 0, 0, 0]
        ability[7] = 1
        ability[8] = spell_id + 1 if n + 1 < len(RANKS) else 0
        ability[9] = 0
        abilities.put(ability, 1, SKILL)

    row = spells.template(DUMMY_SPELL, "Dummy Spell")
    row[0] = SURVEY
    row[F_CATEGORY] = 0
    row[F_CAST_TIME] = CAST_1S
    row[F_RECOVERY] = SURVEY_RECOVERY
    row[F_CATEGORY_RECOVERY] = 0
    row[F_INTERRUPT] = INTERRUPT_MOVE_PUSHBACK_INTERRUPT
    row[F_RANGE] = RANGE_SELF
    row[F_EFFECT] = EFFECT_DUMMY
    row[F_TARGET_A] = TARGET_UNIT_CASTER
    row[F_ICON] = survey_icon
    row[F_ACTIVE_ICON] = 0
    for field in SPELL_STRINGS:
        row[field] = 0
    row[F_NAME] = spells.add_string(SURVEY_NAME)
    row[F_DESCRIPTION] = spells.add_string(SURVEY_DESCRIPTION)
    row[F_GCD_CATEGORY] = GCD_CATEGORY
    row[F_GCD] = GCD
    spells.put(row, F_NAME, SURVEY_NAME)
    # Learned with the skill (AcquireMethod 1 from rank 1): the core teaches it when the skill is set.
    abilities.put([SURVEY, SKILL, SURVEY, 0, 0, 0, 0, 1, 0, 1, 1, 1, 0, 0], 1, SKILL)
    print("Spell.dbc %d-%d Archaeology ranks, %d Survey" % (FIRST_SPELL, FIRST_SPELL + len(RANKS) - 1, SURVEY))


def add_items(dbc, items, client, files, cache, retail):
    cata = {int(r["ID"]): r for r in read_csv("c_Item.csv")}
    fdids = {}
    for item, cata_item, _c, _s in items:
        if cata_item not in cata or not int(cata[cata_item]["IconFileDataID"]):
            sys.exit("Cataclysm item %d (our %d) has no icon in c_Item.csv" % (cata_item, item))
        fdids[item] = int(cata[cata_item]["IconFileDataID"])
    paths = icon_paths(set(fdids.values()), cache, retail)

    table, displays = dbc["Item"], dbc["ItemDisplayInfo"]
    template = displays.template(TEMPLATE_ITEM_DISPLAY, "an icon-only display")
    shipped, reused = set(), set()
    in_patch = {n.lower() for n in files}
    for item, cata_item, item_class, subclass in items:
        fdid = fdids[item]
        if fdid not in paths:
            sys.exit("icon %d of item %d isn't in the listfile" % (fdid, item))
        path = paths[fdid].replace("/", "\\")
        if not path.lower().startswith("interface\\icons\\") or not path.lower().endswith(".blp"):
            sys.exit("icon %d of item %d is %s, not an icon" % (fdid, item, path))
        icon = os.path.basename(path.replace("\\", "/"))[:-4]
        archive_name = "Interface\\Icons\\%s.blp" % icon
        if archive_name.lower() in in_patch:
            pass
        elif client.has(archive_name):
            reused.add(icon)
        else:
            blp = retail.fetch.casc_path(cache, fdid)
            if open(blp, "rb").read(4) != b"BLP2":
                sys.exit("icon %d isn't a BLP2 file" % fdid)
            files[archive_name] = blp
            in_patch.add(archive_name.lower())
            shipped.add(icon)
        display_id = DISPLAY_BASE + item - ITEM_FIRST
        row = list(template)
        row[0] = display_id
        for field in TABLES["ItemDisplayInfo"][1]:
            row[field] = 0
        row[5] = displays.add_string(icon)
        displays.put(row, 5, icon)
        material = int(cata[cata_item]["Material"]) & 0xFFFFFFFF
        table.put([item, item_class, subclass, UNSET, material, display_id, 0, 0], 5, display_id)
    print("Item.dbc + ItemDisplayInfo.dbc: %d items, %d icons the client has, %d icons added"
          % (len(items), len(reused), len(shipped)))


def add_telescope(dbc, client, files, cache, retail, work, max_texture):
    godi = {int(r["ID"]): r for r in read_csv("c_GODI.csv")}
    local = os.path.join(work, "AnimationData.dbc")
    client.extract("DBFilesClient\\AnimationData.dbc", local)
    data = open(local, "rb").read()
    count, fields = struct.unpack_from("<II", data, 4)
    valid = {struct.unpack_from("<I", data, 20 + i * fields * 4)[0] for i in range(count)}

    table = dbc["GameObjectDisplayInfo"]
    texture_names, texture_fdid = {}, {}
    for display, stem in TELESCOPE:
        src = godi.get(display)
        if not src or os.path.basename(src["ModelName"].replace("\\", "/")).lower() != stem.lower() + ".mdx":
            sys.exit("c_GODI.csv row %d isn't %s" % (display, stem))
        fdid = int(src["FileDataID"])
        raw = retail.casc(cache, fdid)
        model = retail.Retail(raw)
        skin = retail.casc(cache, model.sfid[0])
        afiles = {(a, s): retail.casc(cache, f) for a, s, f in model.afid if f}
        conv = retail.Converter(raw, skin, afiles, valid, stem)
        drawn = conv.batch_textures()
        textures = []
        for i, (ttype, tflags, _n, _o) in enumerate(model.arr("textures", "<IIII")):
            fd = model.txid[i] if i < len(model.txid) else 0
            if ttype != 0 or i not in drawn or not fd:
                textures.append((None, tflags, None))
                continue
            if fd not in texture_names:
                listed = retail.listfile(cache, [fd]).get(fd, "")
                name = os.path.basename(listed) or "T%d.blp" % fd
                stock = listed.replace("/", "\\")
                # A texture the client already has keeps its own path; a new one goes next to the model.
                texture_names[fd] = stock if stock and client.has(stock) else "%s\\%s" % (TELESCOPE_DIR, name)
                texture_fdid[texture_names[fd]] = fd
            textures.append((0, tflags, texture_names[fd]))
        m2, skin_out = conv.convert(textures)
        errors, info = retail.check(m2, skin_out)
        if errors:
            sys.exit("%s fails the 3.3.5 checks: %s" % (stem, errors[:5]))
        for i, use in conv.texture_use.items():
            ttype, _f, name = textures[i]
            if ttype == 0 and name.startswith(TELESCOPE_DIR) and name not in files:
                blp = retail.shrink_blp(retail.casc(cache, texture_fdid[name]), max_texture)
                if 1 in use and max(use) < 2:
                    blp = retail.key_alpha_blp(blp)
                path = os.path.join(work, os.path.basename(name))
                open(path, "wb").write(blp)
                files[name] = path
        for ext, blob in ((".m2", m2), ("00.skin", skin_out)):
            path = os.path.join(work, stem + ext)
            open(path, "wb").write(blob)
            files["%s\\%s%s" % (TELESCOPE_DIR, stem, ext)] = path
        row = [0] * 19
        row[0] = display
        model_name = "%s\\%s.mdx" % (TELESCOPE_DIR, stem)
        row[1] = table.add_string(model_name)
        for k in range(6):
            row[12 + k] = struct.unpack("<I", struct.pack("<f", float(src["GeoBox_%d" % k])))[0]
        table.put(row, 1, model_name)
        print("GameObjectDisplayInfo.dbc %d %s: %d anims, %d vertices, %d batches"
              % (display, stem, info["sequences"], info["vertices"], info["batches"]))


def icon_id(dbc, name):
    icon = dbc["SpellIcon"].find_string(1, "Interface\\Icons\\" + name)
    if icon is None:
        sys.exit("SpellIcon.dbc has no %s" % name)
    return icon


def float_bits(value):
    return struct.unpack("<I", struct.pack("<f", value))[0]


def add_traits(dbc):
    spells = dbc["Spell"]
    template = spells.template(DUMMY_SPELL, "Dummy Spell")
    for t in TRAITS:
        row = [0] * SPELL_FIELDS
        for field in SPELL_LANG_MASKS:
            row[field] = template[field]
        row[0] = t["id"]
        row[F_ATTRIBUTES] = t.get("attr0", 0)
        row[F_ATTRIBUTES_EX3] = t.get("attr3", 0)
        row[F_ATTRIBUTES_EX4] = t.get("attr4", 0)
        row[F_CAST_TIME] = CAST_INSTANT
        row[F_PROC_FLAGS] = t.get("proc", 0)
        row[F_PROC_CHANCE] = 100 if t.get("proc") else 0
        row[F_DURATION] = DURATION[t["duration"]] if "duration" in t else 0
        row[F_RANGE] = t.get("range", RANGE_SELF)
        row[F_STACK] = t.get("stack", 0)
        for i, (effect, aura, target, misc, amplitude) in enumerate(t["effects"]):
            row[F_EFFECT + i] = effect
            row[F_TARGET_A + i] = target
            row[F_AURA + i] = aura
            row[F_MISC + i] = misc
            row[F_AMPLITUDE + i] = amplitude
            row[F_DMG_MULTIPLIER + i] = float_bits(1.0)
        if t.get("visual"):
            row[F_VISUAL] = spells.template(t["visual"], "visual for " + t["name"])[F_VISUAL]
        row[F_ICON] = icon_id(dbc, t["icon"])
        row[F_NAME] = spells.add_string(t["name"])
        row[F_SUBTEXT] = spells.add_string(t.get("subtext", ""))
        if "race" in t:
            text = t["text"] + " " + t.get("race_text", TRAIT_TEXT) % t["race"]
            row[F_DESCRIPTION] = spells.add_string(text)
            row[F_AURA_TEXT] = spells.add_string(text)
        else:
            row[F_DESCRIPTION] = spells.add_string(t["description"])
            row[F_AURA_TEXT] = spells.add_string(t.get("aura_text", ""))
        row[F_DMG_CLASS] = t.get("dmg_class", 0)
        row[F_SCHOOL] = t.get("school", SCHOOL_PHYSICAL)
        spells.put(row, F_NAME, t["name"])
    print("Spell.dbc %d-%d relic traits" % (TRAITS[0]["id"], TRAITS[-1]["id"]))



SHOVEL_SPELL = 90522
SHOVEL_NAME = "Buried Find"
SHOVEL_MODEL = "Spells\\EvermoreArchaeologyShovel"


def add_find_shovel_spell(dbc):
    spells = dbc["Spell"]
    template = spells.template(DUMMY_SPELL, "Dummy Spell")
    row = [0] * SPELL_FIELDS
    for field in SPELL_LANG_MASKS:
        row[field] = template[field]
    row[0] = SHOVEL_SPELL
    row[F_ATTRIBUTES] = 0x80 | 0x100 | ATTR0_NO_AURA_CANCEL  # hidden, cosmetic aura
    row[F_CAST_TIME] = CAST_INSTANT
    row[F_DURATION] = DURATION["infinite"]
    row[F_RANGE] = RANGE_SELF
    row[F_EFFECT], row[F_AURA], row[F_TARGET_A] = EFFECT_APPLY_AURA, AURA_DUMMY, TARGET_UNIT_CASTER
    row[F_DMG_MULTIPLIER] = float_bits(1.0)
    row[F_VISUAL] = SHOVEL_SPELL
    row[F_NAME] = spells.add_string(SHOVEL_NAME)
    row[F_SCHOOL] = SCHOOL_PHYSICAL
    spells.put(row, F_NAME, SHOVEL_NAME)


def add_find_shovel_visual(dbc, files, work):
    from shovel_model import quad
    visual = [0] * 32
    visual[0], visual[4] = SHOVEL_SPELL, SHOVEL_SPELL
    dbc["SpellVisual"].put(visual, 4, SHOVEL_SPELL)
    kit = [0] * 38
    kit[0], kit[1], kit[2], kit[3], kit[37] = SHOVEL_SPELL, 0xFFFFFFFF, 0xFFFFFFFF, SHOVEL_SPELL, 0x40
    for field in range(17, 21):
        kit[field] = 0xFFFFFFFF
    dbc["SpellVisualKit"].put(kit, 3, SHOVEL_SPELL)
    effects = dbc["SpellVisualEffectName"]
    effects.put([SHOVEL_SPELL, effects.add_string(SHOVEL_NAME), effects.add_string(SHOVEL_MODEL + ".mdx"),
                 float_bits(0.0), float_bits(1.0), float_bits(0.01), float_bits(100.0)], 1, SHOVEL_NAME)
    model, skin = quad("EvermoreArchaeologyShovel", "Interface\\Icons\\INV_Misc_Shovel_01.blp", size=0.22)
    for payload, suffix in ((model, ".m2"), (skin, "00.skin")):
        local = os.path.join(work, "EvermoreArchaeologyShovel" + suffix)
        with open(local, "wb") as output:
            output.write(payload)
        files[SHOVEL_MODEL + suffix] = local


def add_achievements(dbc):
    table = dbc["Achievement"]
    template = table.template(ACHIEVEMENT_TEMPLATE, "Hail to the Chef")
    for order, (ach_id, title, description, points, icon) in enumerate(ACHIEVEMENTS, 1):
        row = [0] * TABLES["Achievement"][0]
        row[0] = ach_id
        row[1] = row[2] = UNSET                 # either faction, any map
        row[4] = table.add_string(title)
        row[21] = table.add_string(description)
        for field in (20, 37, 59):
            row[field] = template[field]
        row[38] = ACHIEVEMENT_CATEGORY
        row[39] = points
        row[40] = order
        row[42] = icon_id(dbc, icon)
        table.put(row, 4, title)
    criteria = dbc["Achievement_Criteria"]
    template = next((r for r in criteria.rows.values() if r[2] == 27), None)
    if template is None:
        sys.exit("Achievement_Criteria.dbc has no complete-quest criteria to copy")
    for crit_id, ach_id, crit_type, asset, count, text in CRITERIA:
        row = [0] * TABLES["Achievement_Criteria"][0]
        row[0:5] = [crit_id, ach_id, crit_type, asset, count]
        row[9] = criteria.add_string(text)
        row[25] = template[25]
        row[30] = 1
        criteria.put(row, 1, ach_id)
    print("Achievement.dbc %d-%d, Achievement_Criteria.dbc %d relic achievements"
          % (ACHIEVEMENTS[0][0], ACHIEVEMENTS[-1][0], CRITERIA[0][0]))


# --- SQL ---------------------------------------------------------------------------------------

def sql_str(s):
    return "'" + s.replace("\\", "\\\\").replace("'", "''") + "'"


def sql_values(table, dbc_table, row):
    fields, strings, floats, unsigned = TABLES[table]
    out = []
    for i, v in enumerate(row):
        if i in strings:
            out.append(sql_str(dbc_table.string(v)) if v else "''")
        elif i in floats:
            out.append("%g" % struct.unpack("<f", struct.pack("<I", v))[0])
        elif i in unsigned:
            out.append(str(v))
        else:
            out.append(str(struct.unpack("<i", struct.pack("<I", v))[0]))
    if len(out) != fields:
        sys.exit("%s row %d has %d values, not %d" % (table, row[0], len(out), fields))
    return "(" + ", ".join(out) + ")"


def id_list(ids):
    """`ID` IN (...) with runs written as BETWEEN."""
    ids, parts, i = sorted(set(ids)), [], 0
    while i < len(ids):
        j = i
        while j + 1 < len(ids) and ids[j + 1] == ids[j] + 1:
            j += 1
        parts.append("`ID` BETWEEN %d AND %d" % (ids[i], ids[j]) if j - i >= 2 else
                     " OR ".join("`ID` = %d" % x for x in ids[i:j + 1]))
        i = j + 1
    return " OR ".join(parts)


def write_sql(path, dbc, items, rewards=None):
    out = ["-- mod-archaeology: the client patch's DBC rows, as the server needs them.",
           "-- Generated by tools/build_patch.py from the same rows the client patch gets:",
           "-- run the tool again, don't edit this file.", ""]
    for table, sql_table in SQL_TABLES:
        t = dbc.get(table)
        if not t or not t.ours:
            continue
        # The relic's item_dbc rows are in mod_archaeology_world_relic.sql already, and the rare
        # rewards' rows (ours[start:end], rewards[table] = (start, end)) in
        # mod_archaeology_world_z_rewards_dbc.sql. A row the rewards replace (a reward item's
        # equipment class and display) stays out too: the server applies this file again
        # whenever it changes, and it must not put back what the rewards file changed.
        start, end = (rewards or {}).get(table, (0, 0))
        theirs = {r[0] for r in t.ours[start:end]}
        ours = [r for r in t.ours[:start] + t.ours[end:] if r[0] not in theirs]
        rows = sorted({r[0]: r for r in ours if table != "Item" or not RELIC_FIRST <= r[0] <= RELIC_LAST}.values(),
                      key=lambda r: r[0])
        if not rows:
            continue
        out.append("DELETE FROM `%s` WHERE %s;" % (sql_table, id_list(r[0] for r in rows)))
        out.append("INSERT INTO `%s` VALUES\n%s;\n" % (sql_table, ",\n".join(sql_values(table, t, r) for r in rows)))
    if dbc["Item"].ours:
        out.append("-- The core copies these from item_dbc anyway (DBC.EnforceItemAttributes); this keeps")
        out.append("-- item_template in step and the startup log quiet.")
        out.append("UPDATE `item_template` it JOIN `item_dbc` d ON d.`ID` = it.`entry`")
        out.append("SET it.`displayid` = d.`DisplayInfoID`, it.`Material` = d.`Material`")
        out.append("WHERE it.`entry` BETWEEN %d AND %d;" % (ITEM_FIRST, ITEM_LAST))
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(out) + "\n")
    print("wrote", os.path.relpath(path))


# --- main --------------------------------------------------------------------------------------

def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--patch", required=True, help="your realm's spell/item patch (Spell.dbc, Item.dbc, ...)")
    ap.add_argument("--skill-patch", help="your realm's patch with SkillRaceClassInfo.dbc, if another one has it")
    ap.add_argument("--also-patch", action="append", default=[],
                    help="another of your realm's patches carrying a DBC this tool edits (Achievement.dbc, ...)")
    ap.add_argument("--client", required=True, help="the WoW folder (or its Data folder) the patches go on")
    ap.add_argument("--locale", default="enUS")
    ap.add_argument("--out", help="write the changed patches here, under their own names")
    ap.add_argument("--sql", help="write the server's rows here (all but the rare rewards')")
    ap.add_argument("--rewards-sql", help="write the rare rewards' server rows here "
                    "(data/sql/db-world/mod_archaeology_world_z_rewards_dbc.sql)")
    ap.add_argument("--cache", default=os.path.join(CATA, "cache"), help="downloads (default tools/cata-data/cache)")
    ap.add_argument("--max-texture", type=int, default=512, help="largest telescope texture side (default 512)")
    ap.add_argument("--no-models", action="store_true", help="leave the telescope out")
    args = ap.parse_args()
    if not args.out and not args.sql and not args.rewards_sql:
        sys.exit("nothing to do: give --out, --sql, --rewards-sql or some of them")

    retail = load_retail()
    items = module_items()
    patches = [args.patch] + ([args.skill_patch] if args.skill_patch else []) + args.also_patch
    skip = {os.path.basename(p).lower() for p in patches}
    client = Client(args.client, args.locale, skip)

    with tempfile.TemporaryDirectory() as tmp:
        unpacked = [unpack(p, os.path.join(tmp, "patch%d" % i)) for i, p in enumerate(patches)]
        work = os.path.join(tmp, "work")
        os.makedirs(work)

        dbc, where = {}, {}
        tables = ["SpellIcon", "SkillLine", "SkillRaceClassInfo", "Spell", "SkillLineAbility", "Item",
                  "ItemDisplayInfo", "Achievement", "Achievement_Criteria",
                  "SpellVisual", "SpellVisualKit", "SpellVisualEffectName"] + ([] if args.no_models else ["GameObjectDisplayInfo"])
        for table in tables:
            name = "DBFilesClient\\%s.dbc" % table
            owner = next((i for i, files in enumerate(unpacked) if name in files), None)
            if owner is None:
                owner = 0
                local = os.path.join(work, table + ".dbc")
                source = client.extract(name, local)
                if table in SHARED_TABLES and source.lower() in client.extra:
                    sys.exit("%s.dbc comes from %s, one of your realm's own patches: pass it with --also-patch, or this "
                             "patch's copy would hide its rows (or be hidden by it)" % (table, source))
                unpacked[0][name] = local
                print("%s.dbc: none of the patches has it; the client's copy from %s goes into %s"
                      % (table, source, os.path.basename(patches[0])))
            dbc[table] = Dbc(unpacked[owner][name], table)
            where[table] = owner
        if SKILL in dbc["SkillLine"].rows and dbc["SkillLine"].string(dbc["SkillLine"].rows[SKILL][3]) != SKILL_NAME:
            sys.exit("SkillLine.dbc %d is taken" % SKILL)

        add_skill(dbc)
        add_spells(dbc)
        add_traits(dbc)
        add_find_shovel_spell(dbc)
        add_find_shovel_visual(dbc, unpacked[0], work)
        add_achievements(dbc)
        files = unpacked[0]
        files["Interface\\Icons\\%s.blp" % ICON] = retail.fetch.casc_path(args.cache, ICON_FDID)
        add_items(dbc, items, client, files, args.cache, retail)
        add_research_art(files, args.cache, retail)
        add_relic(dbc, relic_items())
        from reward_patch import add_rewards, write_sql as write_rewards_sql
        before = {t: len(dbc[t].ours) for t in tables}
        add_rewards(dbc)
        rewards = {t: (before[t], len(dbc[t].ours)) for t in tables}
        if not args.no_models:
            add_telescope(dbc, client, files, args.cache, retail, work, args.max_texture)

        for table in tables:
            dbc[table].write(unpacked[where[table]]["DBFilesClient\\%s.dbc" % table])
        if args.out:
            os.makedirs(args.out, exist_ok=True)
            for i, patch in enumerate(patches):
                if not any(where[t] == i and dbc[t].ours for t in tables) and i:
                    print("%s: unchanged" % os.path.basename(patch))
                    continue
                out = os.path.join(args.out, os.path.basename(patch))
                if os.path.abspath(out) == os.path.abspath(patch):
                    sys.exit("--out would overwrite %s" % patch)
                pack(out, [(local, name) for name, local in sorted(unpacked[i].items())])
                print("%s: %d files, %.1f MB" % (out, len(unpacked[i]), os.path.getsize(out) / 1e6))
        if args.sql:
            write_sql(args.sql, dbc, items, rewards)
        if args.rewards_sql:
            write_rewards_sql(args.rewards_sql, dbc, rewards)
            print("wrote", os.path.relpath(args.rewards_sql))


if __name__ == "__main__":
    main()
