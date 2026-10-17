# mod-archaeology

Cataclysm-style Archaeology for AzerothCore (3.3.5a). Characters learn Archaeology from a trainer, get dig sites on each continent, survey for finds, collect race fragments and keystones, and solve artifacts.

The server owns all of it: skill, dig sites, fragments, the survey and the solve roll. Progress is per character, so every character levels its own Archaeology.

## Status

This is the server side of the first build phase.

| Piece | State |
| --- | --- |
| Dig sites, survey, finds, fragments, keystones, solving, skill | Done (this module) |
| 8 races: Dwarf, Night Elf, Troll, Fossil, Draenei, Orc, Nerubian, Vrykul | Data imported; Tol'vir is left out |
| ArchaeologyUI addon (map dig sites, research window, survey button) | First version in `addon/ArchaeologyUI`, not yet tried in the game client |
| Client patch (skill line, telescope model, item icons) | Built by `tools/build_patch.py`, not yet tried in the game client; the module doesn't use the spells or the telescope yet (see [Client patch](#client-patch)) |
| Rare rewards as mounts, pets and toys | Rares are placeholder items for now |

Everything also works without the addon, through `.arch` chat commands.

## Install

1. Clone into your modules folder as `mod-archaeology`:
   ```
   git clone https://github.com/buildthehomelab/wow-mod-archaeology.git modules/mod-archaeology
   ```
2. Re-run CMake and build. The SQL in `data/sql` is applied by the database updater.
3. Copy `conf/mod_archaeology.conf.dist` to `mod_archaeology.conf` and adjust.
4. Spawn the trainer where you want it, for example once in Stormwind and once in Orgrimmar:
   ```
   .npc add 9503500
   ```

## Playing

1. Talk to the trainer (Harrison Jones) to learn Apprentice Archaeology. Higher ranks need skill and level: Journeyman 50/20, Expert 125/20, Artisan 200/35, Master 275/50, Grand Master 350/65.
2. You hold 4 dig sites per continent. `.arch` lists them.
3. Inside a dig site, `.arch survey`. A marker points toward the find, and chat says how far (red, yellow, green) and which way.
4. Within 8 yards the find appears. Click it for fragments, sometimes a keystone, and skill.
5. After 3 finds the site is depleted and a new one is revealed.
6. `.arch solve <race> [keystones]` solves the current project for that race when you have enough fragments. Each keystone counts as 12 fragments.

Outland races open at skill 300, Northrend races at 375. With mod-individual-progression and `Archaeology.IndividualProgression.Enable = 1`, those continents also wait until the character reaches that era.

## Commands

| Command | Who | Does |
| --- | --- | --- |
| `.arch` | Player | Skill, fragments, current projects and dig sites |
| `.arch survey` | Player | Survey where you stand |
| `.arch solve <race> [keystones]` | Player | Solve that race's current project |
| `.arch skill <value>` | GM | Set the selected player's skill (and matching rank) |
| `.arch reload` | Admin | Reload dig sites and projects from the database |

## IDs

| What | Range |
| --- | --- |
| Trainer creature, npc_text | 9503500 |
| Survey marker, finds (gameobject_template) | 9503500, 9503510-9503517 |
| Keystones and artifacts (item_template, Item.dbc) | 9504010-9504499 |
| Item displays (ItemDisplayInfo.dbc) | 950410-950899: 950400 + (item - 9504000) |
| Spells (Spell.dbc, SkillLineAbility.dbc) | 90500-90505 ranks, 90506 Survey (90500-90529 reserved) |
| Skill line (SkillLine.dbc), SkillRaceClassInfo.dbc, SpellIcon.dbc | 794, 90500, 90500 |
| Survey telescope (GameObjectDisplayInfo.dbc) | 10101-10103, Cataclysm's own |
| Tables | `mod_archaeology_*` |

Cataclysm's item ids clash with 3.3.5, so every artifact gets a new id. `mod_archaeology_item_source` records which Cataclysm item each one came from.

## ArchaeologyUI addon

`addon/ArchaeologyUI` is the client side, for the 3.3.5a client (Interface 30300). Copy the folder into `World of Warcraft/Interface/AddOns/`.

- **World map and zone map:** each of your dig sites is shaded over its area, with a shovel in the middle. The tooltip gives the race and the finds left.
- **Minimap:** a shovel pin for each dig site on your continent. Sites out of range wait on the minimap's edge, faded, in their direction. Works with Rotate Minimap and with square minimaps (`GetMinimapShape`).
- **Survey button:** shows while you stand in one of your dig sites. Click it (or bind a key under Key Bindings, ArchaeologyUI) to survey. The border turns red, yellow or green, and an arrow above the button points toward the find as you turn. Shift-drag moves the button; right-click opens the research window.
- **Research window** (`/arch`): a tab per race you can research, with the current project's name, lore and artifact, your fragments against its cost, a socket per keystone the project takes (click to put one in or take it out), and Solve.
- **In DragonUI's professions window:** with DragonUI 2.12 or later (its professions window on), the research window is a page of that window instead, with an Archaeology side tab after your profession tabs once you know Archaeology: races in the list column, the project on the recipe card, your skill on the rank bar. `/arch` and everything else that opens the research window opens that page. Retail Professions also lists Archaeology in its professions book and Training column.
- **Fragments bar:** slides in at the top when you loot fragments, showing progress toward that race's project. Click it to open that race in the research window.

Slash commands: `/arch` (window), `/arch survey`, `/arch reset` (survey button back to its default spot), `/arch refresh` (ask the server again).

Surveying is an addon message, not a spell, so the button is a plain button and nothing is locked in combat. The addon has its own map maths (world bounds of every map in `MapData.lua`), so it needs no Astrolabe. It uses stock 3.3.5 frames and textures for its own window.

The addon assumes the server's defaults for two values it is not sent: `Archaeology.KeystoneValue = 12` (for the progress bar with keystones in) and `Archaeology.Survey.CooldownMs = 3000` (the button's cooldown). The server always has the final say when you solve or survey.

## Addon wire format

Addon whispers to yourself in `LANG_ADDON`, `ARCH\t<COMMAND>[:...]`.

- Client to server: `HELLO`, `SITES`, `RACES`, `PROJ:<id>`, `SURVEY`, `SOLVE:<race>:<keystones>`
- Server to client:
  - `S:<skill>:<max>`
  - `R:<race>,<name>,<fragments>,<cap>,<project>,<cost>,<sockets>,<rare>,<keystones owned>,<unlocked>;...` then `REND`
  - `T:<site>,<map>,<race>,<finds left>,<name>;...`, `G:<site>:<x>,<y>;...` (outline, world coordinates), then `TEND`
  - `P:<id>:<race>:<rare>:<cost>:<sockets>:<item>:<name>`, `D:<id>:<text>` chunks, `DEND:<id>`
  - `V:RED|YELLOW|GREEN:<angle>`, `V:FOUND`, `V:NONE` (survey result)
  - `F:<race>:<gained>:<total>` (fragments looted), `X:<project>:<item>:<rare>` (solved)

## Client patch

The 3.3.5 client has no Archaeology. `tools/build_patch.py` adds what it needs to your realm's client patches, and writes the same rows for the server to `data/sql/db-world/mod_archaeology_world_dbc.sql`:

- SkillLine 794 "Archaeology" (a secondary skill, like Cooking) and a SkillRaceClassInfo row, so `Archaeology.Skill.SkillLine = 794` can show the skill in the Skills tab. Set it only once players have the patch.
- Spells 90500-90505 (Apprentice to Grand Master, each a Skill effect on 794 and a Dummy cast) and 90506 Survey (1 s cast, Dummy), with SkillLineAbility rows. Survey is learned with the skill.
- Item.dbc and ItemDisplayInfo.dbc rows with the Cataclysm icon of every keystone and artifact. Without them the items show a question mark. Icons the client lacks are added to the patch.
- The survey telescope: GameObjectDisplayInfo 10101-10103 (green, yellow, red) and Cataclysm's three models, converted to the 3.3.5 format by [wow-mod-retail-creatures](https://github.com/buildthehomelab/wow-mod-retail-creatures) (clone it next to this repo, or set `RETAIL_CREATURES`).

A patch MPQ replaces whole files and the highest patch wins, so the tool edits the copies your realm already ships:

```
python3 tools/build_patch.py --patch <your spell/item patch>.MPQ --skill-patch <your patch with SkillRaceClassInfo>.MPQ \
    --client <WoW folder> --out <folder> --sql data/sql/db-world/mod_archaeology_world_dbc.sql
```

`--patch` is the patch with your Spell, SkillLineAbility, SpellIcon, Item and ItemDisplayInfo DBCs. `--skill-patch` is the one with SkillRaceClassInfo.dbc, if that is another patch. A DBC neither ships (often SkillLine and GameObjectDisplayInfo) comes from the client's newest copy and goes into `--patch`. Each patch that changed is written to `--out` under its own name, with every other file in it unchanged. It also reads `c_Item.csv`, `c_GODI.csv` (Cataclysm Classic GameObjectDisplayInfo) and `listfile_archaeology.csv` from `tools/cata-data/`. Models and icons come from [wago.tools](https://wago.tools), cached in `tools/cata-data/cache`. Running it again on its own output changes nothing.

The patches carry rows only for the spells, the skill and the telescope; the module itself doesn't use them yet:

- The trainer still sets the skill directly. Teaching the rank spells instead, and opening the research window when the rank spell is cast, is module work still to do.
- Survey (90506) runs the survey (`spell_archaeology_survey`). `.arch survey` and the addon button still work without the patch.
- The survey marker (gameobject 9503500) still uses the excavation banner (display 5191). Showing the telescope means one marker per colour (displays 10101-10103) or setting the display when it spawns.

## Rebuilding the data

`data/sql/db-world/mod_archaeology_world_data.sql` is generated by `tools/build_data.py` from:

- Cataclysm Classic 4.4.2 DB2 exports from [wago.tools](https://wago.tools) (ResearchBranch, ResearchSite, ResearchProject, QuestPOIPoint, SpellEffect, Item, ItemSparse), saved as `tools/cata-data/c_<Table>.csv`
- SkyFire 5.4.8's `research_digsite_data`, `research_digsite_finds` and `research_project_requirements` rows, saved as `tools/cata-data/sf_arch.sql`

`tools/cata-data/` is not committed. Dig sites in Cataclysm-only zones (skill 450) and all Tol'vir rows are dropped. Some old-world sites sit on terrain that changed in Cataclysm; set `enabled = 0` on any site that does not fit your map.

## License

MIT. Game data derived from World of Warcraft belongs to Blizzard Entertainment.
