# mod-archaeology

Cataclysm-style Archaeology for AzerothCore (3.3.5a). Characters learn Archaeology from a trainer, get dig sites on each continent, survey for finds, collect race fragments and keystones, and solve artifacts. Archaeologists also piece together the Unearthed Relic, a weapon of their own that grows as they dig.

The server owns all of it: skill, dig sites, fragments, the survey and the solve roll. Progress is per character, so every character levels its own Archaeology.

## Status

The dig loop is done, and so is the relic: ranks, forms, item ladder, traits, capstone quests and achievements. Its Cataclysm looks are not in yet.

| Piece | State |
| --- | --- |
| Dig sites, survey, finds, fragments, keystones, solving, skill | Done (this module) |
| 8 races: Dwarf, Night Elf, Troll, Fossil, Draenei, Orc, Nerubian, Vrykul | Data imported; Tol'vir is left out |
| ArchaeologyUI addon (map dig sites, research window, survey button) | First version in `addon/ArchaeologyUI`, not yet tried in the game client |
| Client patch (skill line, telescope model, item icons) | Built by `tools/build_patch.py`; Survey, the rank spells and the telescope are used (see [Client patch](#client-patch)) |
| Rare rewards | All 26 implemented: 5 pets/mounts, 14 toys/utilities and 7 usable equipment rewards; matching patch required |
| Unearthed Relic: ranks, forms, item ladder, quest | Done; not yet tried in the game client |
| Relic traits, capstone raid quests, relic achievements | Done; not yet tried in the game client |
| Relic looks (Cataclysm rare weapons, awakened looks) | Not started |

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
4. Close to the find, a survey says how many yards away it is. Standing on it (within 3 yards) shows a shovel above your head, and the survey button turns into a glowing shovel: click it (or `.arch dig`) to dig. After a moment of digging (moving, a fight or mounting stops it) the find comes up; click it for fragments, sometimes a keystone, and skill. The overhead shovel needs the matching client patch; the Dig button and `.arch dig` work without it. With `Archaeology.Dig.Shovel = 0` a survey within 8 yards uncovers the find instead, as before.
5. After 3 finds the site is depleted and a new one is revealed.
6. `.arch solve <race> [keystones]` solves the current project for that race when you have enough fragments. Each keystone counts as 12 fragments.

7. At 50 skill, the trainer has a quest, *A Weapon in Pieces*. Turn it in and choose your relic's form (see [The Unearthed Relic](#the-unearthed-relic)). At 60, 70 and 80 the trainer has a capstone quest for each era's last raid boss.

Outland races open at skill 300, Northrend races at 375. With mod-individual-progression and `Archaeology.IndividualProgression.Enable = 1`, those continents also wait until the character reaches that era.

## Rare rewards

All 26 rares now have functional reward items. See [the complete behavior, balance and delivery matrix](docs/rare-rewards.md). The current Retail Collection port contains mounts and pets; these Archaeology toys are implemented here and registered in Journal. The full reward update requires rebuilt module, SQL and a matching spell/item client patch.

### Fossilized Hatchling reward

The Fossilized Hatchling rare (project 106) awards item **9504036**. Right-click
it to learn the **Fossilized Hatchling** companion, then summon it from the Pets
tab (or Journal). It teaches Retail Collection's existing spell **410266**, so
it shares ownership with that module's teaching item rather than making a second pet.

This reward requires **mod-retail-collection** and its existing client patch
(and Retail Library assets). Evermore already pins those modules. The Hatchling alone reuses those existing assets; the complete reward update needs the matching spell/item patch. No addon update is required. The remaining rare rewards are implemented in the complete reward catalog below.

Previously awarded Hatchling items use the same item template, including ones
in bags or the bank: no re-solve, replacement item or character database edit
is needed. The item script initializes the zero charges stored by older placeholder
items on use, then lets the core handle normal companion learning and consumption.
Deploy the SQL **and rebuilt module**, then restart the server. Refresh
the client item cache; Evermore's cache-version module/launcher normally handles
this after the world item data changes. In-game learning, item consumption,
duplicate ownership, summoning and existing-item behavior still need validation.

`mod_archaeology_world_z_rewards.sql` applies the upgrade on existing databases.
`tools/build_data.py` also appends those overrides to regenerated base data, so
a later base-data rebuild cannot turn the reward back into a placeholder.

## Commands

| Command | Who | Does |
| --- | --- | --- |
| `.arch` | Player | Skill, fragments, current projects and dig sites |
| `.arch survey` | Player | Survey where you stand |
| `.arch dig` | Player | Dig where you stand (on the find, the shovel above your head) |
| `.arch solve <race> [keystones]` | Player | Solve that race's current project |
| `.arch relic` | Player | Your relic's rank, Relic Power, what holds it back, and its traits |
| `.arch skill <value>` | GM | Set the selected player's skill (and matching rank) |
| `.arch relic power <amount>` | GM | Give the selected player Relic Power |
| `.arch reload` | Admin | Reload dig sites and projects from the database |

## IDs

| What | Range |
| --- | --- |
| Trainer creature (also the relic quest giver), npc_text | 9503500, npc_text 9503500-9503501 |
| Capstone kill credit (creature_template, never spawned) | 9503510-9503512 |
| Quests: *A Weapon in Pieces*, capstones | 9503500, 9503501-9503503 (9503500-9503519 reserved) |
| Relic items (item_template, Item.dbc) | 9505000-9505999: 9505000 + step x 30 + kind |
| Survey telescopes + banner, finds (gameobject_template) | 9503500-9503503, 9503510-9503517 |
| Keystones and artifacts (item_template, Item.dbc) | 9504010-9504499 |
| Item displays (ItemDisplayInfo.dbc) | 950410-950899: 950400 + (item - 9504000) |
| Spells (Spell.dbc, SkillLineAbility.dbc) | 90500-90505 ranks, 90506 Survey, 90507-90514 relic traits, 90515-90521 what they cast, 90522 cosmetic overhead shovel (90500-90529 reserved) |
| Achievements (Achievement.dbc, Achievement_Criteria.dbc) | 9240-9245, criteria 19240 (9240-9259 and 19240-19279 reserved) |
| Skill line (SkillLine.dbc), SkillRaceClassInfo.dbc, SpellIcon.dbc | 794, 90500, 90500 |
| Survey telescope (GameObjectDisplayInfo.dbc) | 10101-10103, Cataclysm's own |
| Tables | `mod_archaeology_*` |

Cataclysm's item ids clash with 3.3.5, so every artifact gets a new id. `mod_archaeology_item_source` records which Cataclysm item each one came from.

## The Unearthed Relic

One weapon per character, pieced together from its finds. It never leaves the character: it is soulbound, can't be sold, mailed or disenchanted, and alts start their own from nothing.

**Getting it.** At 50 Archaeology (`Archaeology.Relic.Skill`), the trainer gives *A Weapon in Pieces*. Turning it in gives the relic at rank 1 and asks for its form. The trainer also tells you about it, reshapes it (the first time free, then `FormChange.Cost` + `CostPerRank` x rank), and gives it back if you lose it.

**Forms.** 21, by class: two-handed sword, axe or mace (Strength); pairs of swords, axes, fist weapons or daggers for dual wield (Agility or Strength); a pair of two-handers with Titan's Grip; staff (Intellect or Agility); two-handed mace (Agility); one-handed mace (Intellect, Spirit); bow or gun; sword or mace and shield, two-handed sword or axe (tank). A pair is two items sharing one rank: a main hand and off hand (or shield), each with a one-hander's stats. Pairs need Dual Wield or Titan's Grip, as the character has them when it chooses.

**Weapon names.** Each form has a name that stays with it as it grows. The final awakened rank adds *Awakened* to the item name.

| Form | Item name(s) |
| --- | --- |
| Two-handed sword (Strength, including Titan's Grip) | Oath of the Forgotten |
| Two-handed axe (Strength or Tank, including Titan's Grip) | Empire's End |
| Two-handed mace (Strength or Agility) | Weight of Ages |
| Pair of swords (Agility or Strength) | Oath / Reckoning |
| Pair of axes (Agility or Strength) | Ruin / Remembrance |
| Pair of daggers | Secret / Silence |
| Pair of fist weapons | Grasp / Defiance |
| Staff (Intellect) | Memory of the First Dawn |
| Staff (Agility) | Root of Ages |
| One-handed mace (Intellect, Spirit) | Light of the Lost |
| Bow | Whisper of Ages |
| Gun | The Last Word |
| Tank sword (one-handed or two-handed) | The Unbroken Oath |
| Tank mace | Vigil of Stone |
| Shield | Bastion of the Forgotten |

**Ranks.** Relic Power comes only from archaeology: per find, per common and rare solve, and extra for a project solved for the first time (`Archaeology.Relic.Power*`). Finds count once the character has the relic, so a relic starts at rank 1 however much was dug before; projects solved before the quest still count. Power buys ranks one after the other, at each rank's cost (`mod_archaeology_relic_step.cost` x `CostRate`); the last ranks of each era cost the most. There are 29:

| Ranks | Item level | Quality | Opens at |
| --- | --- | --- | --- |
| 1-9 | 25-63, with required level 20-58 | Uncommon, then Rare | progression state 0 |
| 10-16 | 66-92 | Epic | states 1-7 (Molten Core to Naxxramas) |
| 17-21 | 115-164 | Epic; rank 21 Legendary | states 8-12 (Burning Crusade) |
| 22-28 | 187-277 | Epic | states 13-18 (Wrath of the Lich King) |
| 29 | 277 | Artifact (awakened) | state 18 |

**What holds it back.**

- **Progression.** With mod-individual-progression and `Archaeology.IndividualProgression.Enable = 1`, a rank only opens at its progression state. Without it, every character counts as `Archaeology.Relic.StateWithoutProgression` (18: no cap).
- **Level.** The item a character holds is the highest rank its level can use, so a low-level character banks ranks and its relic catches up as it levels.
- **The last rank of an era** (16, 21, 28) needs every rare of that era's races solved: Dwarf, Night Elf, Troll and Fossil; Draenei and Orc; Nerubian and Vrykul. It also needs that era's capstone quest (`Archaeology.Relic.CapstoneQuest.*`, see below).
- **Awakening** (29) needs every project of every race solved, and the top skill (`AwakenNeedsMaxSkill`).

Ranks are never lost. When rank, level or progression changes what the relic should be, the module swaps the item for that step in the same place (equipped or in a bag), out of combat. Its enchant, temporary enchant (poisons, oils) and the gems of sockets the new item also has carry over, as does a transmogrified look (stored per slot). A relic in the bank is swapped when it is equipped. Sockets start at rank 17: one on one-handers, shields and ranged weapons, two on two-handers, and a third from rank 26.

**Capstone quests.** The last rank of each era waits for a quest from the trainer that takes the relic into the era's last raid:

| Quest | Offered at | Slay, with the relic equipped |
| --- | --- | --- |
| 9503501 *The Lich in the Necropolis* | level 60 | Kel'Thuzad in Naxxramas: the 40-man one (mod-individual-progression's 351019) or the level-80 one (15990) |
| 9503502 *The Deceiver's Fall* | level 70 | Kil'jaeden, Sunwell Plateau |
| 9503503 *The Frozen Throne* | level 80 | The Lich King, Icecrown Citadel |

They open once the character has the relic. Everyone in the instance who is in the group that tapped the boss gets the kill, if they have the quest and wear the relic, dead or alive, as long as they are inside the instance. They are raid quests, so a raid group counts. The 80 Kel'Thuzad counts too because individual progression closes the 40-man Naxxramas later on, and a character that missed it there could otherwise never finish the old world's ranks. The quests give nothing but the rank they unlock. Set a `CapstoneQuest` to 0 to drop it; ranks already earned are never taken back, whatever the config says. Upgrading: a `mod_archaeology.conf` copied before the capstones existed still has `CapstoneQuest.* = 0`, so the quests unlock nothing there; set them to 9503501-9503503 (the server logs a warning at startup for each one left at 0).

**Traits.** One per race, waking when one of that race's rares is solved, or after 10 of its commons (`Archaeology.Relic.Traits.WakeCommons`, repeats count). While the relic is equipped, every awake trait is an aura on the character (spells 90507-90514). The numbers below are at full rank. A trait starts at 40% of them (`FirstRankStrength`) and grows with the ladder step the relic shows, so level and progression hold it back as they do the item. Solving every project of its race doubles it (`RaceCompleteMultiplier`).

| Race | Trait | What it does (full rank) |
| --- | --- | --- |
| Dwarf | Thaurissan's Ember | 3 procs a minute: Fire damage worth 40% of attack or spell power (the higher) |
| Night Elf | Highborne Focus | 2 a minute: 4% of max mana, or 10 rage or runic power, or 20 energy |
| Troll | Zandalari Vigor | 1.5 a minute: 8% melee, ranged and casting haste for 10 sec |
| Fossil | Amber Ward | 10% of hits taken (15 sec cooldown): absorb 5% of max health for 10 sec |
| Draenei | Light of the Naaru | 2 a minute: heal you or the most hurt group member within 30 yards for 4% of their max health |
| Orc | Blood of the Horde | Up to 8% more damage as your health falls, all of it at 20% health |
| Nerubian | Ahn'kahar Venom | 3 a minute: Nature poison worth 10% of attack or spell power over 12 sec, stacking to 5 |
| Vrykul | Val'kyr's Mercy | A killing blow leaves you at 20% health instead, once every 10 minutes (race complete: every 5). Other shields take the hit first, and duels don't spend it |

Procs come from melee and ranged hits and from spells (helpful ones too, for the non-damage traits). A chance per minute becomes a chance per hit from the weapon's speed (a spell's cast time, at least 1.5 sec), and two weapons swinging share it, so a pair procs as often as a two-hander. A spell that hits many targets rolls once. Hits from triggered spells don't roll (so the second strike of Mutilate or Stormstrike doesn't, but the white hits do). The numbers live in `mod_archaeology_relic_trait` (world database); change them there and restart. `.arch relic` lists each trait, its strength and what wakes the ones still asleep.

**Achievements**, under Professions, granted by the module (and none of them a boss kill, so mod-individual-progression's raid checks never see them): *A Weapon in Pieces* (the relic), *Tempered by the Ages* (rank 16), *Legend of the Outlands* (rank 21, Legendary), *Every Voice Awake* (all eight traits), *Keeper of All Ages* (every project of every race), *Awakened* (rank 29, Artifact). Characters that already qualify get them at their next login.

**The ladder** is generated by `tools/build_relic.py` into `data/sql/db-world/mod_archaeology_world_relic.sql`: the steps, the forms, which item each form shows at each step, and the 812 item_template + item_dbc rows. Stats come from a budget per item level fitted to 3.3.5's best raid weapons of each tier, so at the top of a tier the relic matches that tier's best item. The items use weapon models the client already has; `tools/build_patch.py` adds their Item.dbc rows to the client patch, which the client needs to draw them. Change the tables in the script and run it again rather than editing the SQL.

## ArchaeologyUI addon

`addon/ArchaeologyUI` is the client side, for the 3.3.5a client (Interface 30300). Copy the folder into `World of Warcraft/Interface/AddOns/`.

- **World map and zone map:** each of your dig sites is shaded over its area, with a shovel in the middle. The tooltip gives the race and the finds left.
- **Minimap:** a shovel pin for each dig site on your continent. Sites out of range wait on the minimap's edge, faded, in their direction. Works with Rotate Minimap and with square minimaps (`GetMinimapShape`). To turn the pins off: right-click one, `/arch minimap`, the key binding, or the checkbox under Interface, AddOns, ArchaeologyUI. The choice is saved for all your characters; the world map keeps its dig sites either way.
- **Survey button:** shows while you stand in one of your dig sites. Click it (or bind a key under Key Bindings, ArchaeologyUI) to survey. The border turns red, yellow or green, and an arrow above the button points toward the find as you turn. Standing on the find, it turns from the spyglass into a pulsing green shovel marked **Dig!**: the same click or key digs, the dig time runs on the button, and the find comes up to click. Shift-drag moves the button; right-click opens the research window.
- **Research window** (`/arch`): a tab per race you can research, with the current project's name, lore and artifact, your fragments against its cost, a socket per keystone the project takes (click to put one in or take it out), and Solve.
- **In DragonUI's professions window:** with DragonUI 2.12 or later (its professions window on), the research window is a page of that window instead, with an Archaeology side tab after your profession tabs once you know Archaeology: races in the list column, the project on the recipe card, your skill on the rank bar. `/arch` and everything else that opens the research window opens that page. Retail Professions also lists Archaeology in its professions book and Training column.
- **In Retail Professions' window:** without DragonUI's window, Retail Professions 1.17 or later takes the research view the same way: its Archaeology side tab opens it as a page of its profession window, the other tabs staying, with the relic and races in the list column, the project on the card and your skill on the skill bar. `/arch` and everything else that opens the research window opens that page too (with the window closed, it opens on it). With `/prof classic`, or without Retail Professions, the research window is used.
- **Relic line:** the Unearthed Relic's rank out of the maximum unlocked by your current IP progression, its form, item level and Relic Power toward the next rank, and what holds it back, along the bottom of the research window (in the list column on the DragonUI and Retail Professions pages, with the weapon's icon and a Relic Power bar). Hover it for the weapon's own tooltip (stats, enchants, gems) followed by Relic Power still to go, the next rank's item level, what holds the item back (your level, or your progress through the ages) and which traits are awake. Shift-click links the relic in chat, Ctrl-click tries it on.
- **Fragments bar:** slides in at the top when you loot fragments, showing progress toward that race's project. Click it to open that race in the research window.

Slash commands: `/arch` (window), `/arch survey`, `/arch dig`, `/arch reset` (survey button back to its default spot), `/arch refresh` (ask the server again), `/arch minimap` (dig sites on the minimap on or off), `/arch options` (the Interface Options page).

Surveying is an addon message, not a spell, so the button is a plain button and nothing is locked in combat. The addon has its own map maths (world bounds of every map in `MapData.lua`), so it needs no Astrolabe. It uses stock 3.3.5 frames and textures for its own window.

The addon assumes the server's defaults for two values it is not sent: `Archaeology.KeystoneValue = 12` (for the progress bar with keystones in) and `Archaeology.Survey.CooldownMs = 3000` (the button's cooldown). The server always has the final say when you solve or survey.

## Addon wire format

Addon whispers to yourself in `LANG_ADDON`, `ARCH\t<COMMAND>[:...]`.

- Client to server: `HELLO`, `SITES`, `RACES`, `PROJ:<id>`, `SURVEY`, `DIG`, `SOLVE:<race>:<keystones>`
- Server to client:
  - `S:<skill>:<max>`
  - `R:<race>,<name>,<fragments>,<cap>,<project>,<cost>,<sockets>,<rare>,<keystones owned>,<unlocked>;...` then `REND`
  - `T:<site>,<map>,<race>,<finds left>,<name>;...`, `G:<site>:<x>,<y>;...` (outline, world coordinates), then `TEND`
  - `P:<id>:<race>:<rare>:<cost>:<sockets>:<item>:<name>`, `D:<id>:<text>` chunks, `DEND:<id>`
  - `V:RED|YELLOW|GREEN:<angle>`, `V:FOUND`, `V:NONE` (survey result)
  - `O:1`, `O:0` (you stand on the hidden find, or left it), `Q:<ms>`, `Q:0` (digging started for ms, stopped)
  - `F:<race>:<gained>:<total>` (fragments looted), `X:<project>:<item>:<rare>` (solved)
  - `L:<rank>:<ranks>:<power>:<next cost>:<item level>:<quality>:<form>:<note>` (the relic; rank 0 = not yet; ranks = current progression ceiling, at least the earned rank)

## Client patch

The 3.3.5 client has no Archaeology. `tools/build_patch.py` adds what it needs to your realm's client patches, and writes the same rows for the server to `data/sql/db-world/mod_archaeology_world_dbc.sql`:

- SkillLine 794 "Archaeology" (a secondary skill, like Cooking) and a SkillRaceClassInfo row, so `Archaeology.Skill.SkillLine = 794` can show the skill in the Skills tab. Set it only once players have the patch.
- Spells 90500-90505 (Apprentice to Grand Master, each a Skill effect on 794 and a Dummy cast) and 90506 Survey (1 s cast, Dummy), with SkillLineAbility rows. Survey is learned with the skill.
- Spells 90507-90521, the relic's traits and what they cast, so their buffs, debuffs and combat log lines have names, icons and tooltips. The module sets the numbers.
- Achievement.dbc 9240-9245 and Achievement_Criteria.dbc 19240, the relic achievements (category Professions).
- Item.dbc and ItemDisplayInfo.dbc rows with the Cataclysm icon of every keystone and artifact. Without them the items show a question mark. Icons the client lacks are added to the patch.
- Item.dbc rows for the relic's 812 items (9505000-9505999), from `mod_archaeology_world_relic.sql`. They use models the client has, so they need no display rows; the server already has the same rows in that file.
- `Interface\Archeology\` art for the collection view: every race's crest (small and big), every rare artifact's sketch, the book page and the progress bar, Cataclysm's own textures (45 files, from `c_ResearchBranch.csv`, `c_ResearchProject.csv` and the listfile). Only ArchaeologyUI 0.7.0 and later draws them.
- The survey telescope: GameObjectDisplayInfo 10101-10103 (green, yellow, red) and Cataclysm's three models, converted to the 3.3.5 format by [wow-mod-retail-creatures](https://github.com/buildthehomelab/wow-mod-retail-creatures) (clone it next to this repo, or set `RETAIL_CREATURES`).

A patch MPQ replaces whole files and the highest patch wins, so the tool edits the copies your realm already ships:

```
python3 tools/build_patch.py --patch <your spell/item patch>.MPQ --skill-patch <your patch with SkillRaceClassInfo>.MPQ \
    --client <WoW folder> --out <folder> --sql data/sql/db-world/mod_archaeology_world_dbc.sql \
    --rewards-sql data/sql/db-world/mod_archaeology_world_z_rewards_dbc.sql
```

`--patch` is the patch with your Spell, SkillLineAbility, SpellIcon, Item and ItemDisplayInfo DBCs. `--skill-patch` is the one with SkillRaceClassInfo.dbc, if that is another patch. `--also-patch` (repeatable) adds any other patch carrying a DBC the tool edits, such as Achievement.dbc. A DBC neither ships (often SkillLine and GameObjectDisplayInfo) comes from the client's newest copy and goes into `--patch`. Each patch that changed is written to `--out` under its own name, with every other file in it unchanged. It also reads `c_Item.csv`, `c_GODI.csv` (Cataclysm Classic GameObjectDisplayInfo), `c_ResearchBranch.csv`, `c_ResearchProject.csv` and `listfile_archaeology.csv` from `tools/cata-data/`. Models and icons come from [wago.tools](https://wago.tools), cached in `tools/cata-data/cache`. Running it again on its own output changes nothing. `--sql` gets every row but the rare rewards'; `--rewards-sql` writes those, the same file `tools/reward_patch.py` writes, so one run keeps both SQL files in step with the patch.

The survey shows Cataclysm's telescope (gameobjects 9503500-9503502, displays 10101-10103) in the colour of the distance band. A client without the patch doesn't see it; set `Archaeology.Telescope.Green/Yellow/Red` to 9503503 (the excavation banner) until the patch is out. How the module uses the patch's spells:

- With `Archaeology.Skill.SkillLine = 794` the module teaches the rank spell for the skill (90500-90505, a `spell_ranks` chain like Cooking's) whenever it sets the skill line: from the trainer, `.arch skill` and at login, so characters who already have Archaeology get it too. It is in the spellbook, and casting it opens ArchaeologyUI's research window (0.5.0). The skill and its spells stay on each character: they are on skill line 794, not one of the professions an account-wide profession module shares. Turning the mirror off (`Archaeology.Skill.SkillLine = 0`) later leaves those spells and skill 794 on characters; the `character_spell`, `character_action` and `character_skills` lines of `data/sql/uninstall/mod_archaeology_uninstall_characters.sql` remove them.
- Survey (90506) runs the survey (`spell_archaeology_survey`). `.arch survey` and the addon button still work without the patch.

## Rebuilding the data

`data/sql/db-world/mod_archaeology_world_data.sql` is generated by `tools/build_data.py` from:

- Cataclysm Classic 4.4.2 DB2 exports from [wago.tools](https://wago.tools) (ResearchBranch, ResearchSite, ResearchProject, QuestPOIPoint, SpellEffect, Item, ItemSparse), saved as `tools/cata-data/c_<Table>.csv`
- SkyFire 5.4.8's `research_digsite_data`, `research_digsite_finds` and `research_project_requirements` rows, saved as `tools/cata-data/sf_arch.sql`

`tools/cata-data/` is not committed. Dig sites in Cataclysm-only zones (skill 450) and all Tol'vir rows are dropped. Old-world coordinates are not automatically WotLK compatible. `tools/wotlk-disabled-sites.json` holds known incompatible sites and conservative terrain holds; the generator writes their `enabled = 0` flags explicitly. The matching `mod_archaeology_world_z_wotlk_sites.sql` disables them on existing installations after base data import. See [the WotLK terrain audit](docs/wotlk-digsites.md) and its complete site inventory. Remaining sites are provisional until their individual points and approaches are checked on 3.3.5 terrain.

## License

MIT. Game data derived from World of Warcraft belongs to Blizzard Entertainment.

## Overhead shovel delivery and validation

Spell 90522 is a hidden, cosmetic dummy aura, checked every 200 ms against the existing buried spot. It does not select spots, survey, spawn finds or grant rewards. The indicator uses `Archaeology.Dig.ShovelYards` (3 yards) horizontally and a 3-yard ground-height tolerance to avoid showing on another floor; the same test decides where you can dig (`O:1` tells the addon), so the shovel above your head and the Dig button always agree. It clears on leaving the spot, revealing a find, death, map change or logout.

Rebuild the archaeology client patch with `tools/build_patch.py` for its matching Spell row, SpellVisual, SpellVisualKit, SpellVisualEffectName and billboard M2/skin. Pass every realm patch carrying these visual tables with `--also-patch`, including the visible-bags/torch patches as applicable, to preserve their rows. IDs 90522 in those three visual tables are reserved here. The ordinary shovel icon already exists in the 3.3.5 client. Ship the client patch alongside the module and SQL; no addon update is needed.

The source and generated model can be checked locally, but the server build and actual head placement, billboard orientation, sizing across races, cleanup and floor checks must be verified in the 3.3.5 client before deployment. The full patch requires the realm's current MPQs and source data, which are not in this workspace. Review the change before merging, and deploy the merged commit.

### Keystone reagent bank

With the matching mod-reagent-bank-account keystone inclusions, all seven keystones can be deposited through the bank’s existing manual and periodic deposit flows. In the research page, click the **Bank** keystone slot, enter a quantity (defaults to one), and press **Withdraw**. The server transfers available keystones into your bags, subject to bag space. Artifact sockets still select keystones from your bags; solving does not consume banked items directly. Fossil has no keystone slot. This requires the updated bank SQL and a server restart to reload deposit inclusions; no client patch change is needed.

## Accessible expeditions and collection journal

The archaeology research page (including its DragonUI/RetailProfessions host) has a
**Collection & Bonuses** button. `/arch collection` and `/arch bonuses` open the same
view. Every race, including locked ones, has a catalogue with collected/missing filters,
unique and rare discovery counts, repeat solve counts, reward inspection and artifact
lore. A discovery is a positive saved solve count, independent of item ownership.
Race completion requires all of that race's unique projects; repeated commons only
advance their solve counter and trait unlock, not catalogue completion.

The view looks like Cataclysm's: each race's crest in the race list and, big, at the top
of its page; a click on an artifact shows its lore and, for a rare, its sketch. With
DragonUI's professions window it is a second page of that window under the Archaeology
tab (races in the list column, the race's page on the recipe card, artifacts found on
the rank bar, **Back to Research** under the races). Otherwise it is a window of its own,
with Cataclysm's book page behind the race's page. The art comes from the client patch
(see [Client patch](#client-patch)); without it the crests are the race icons and the
page has no sketches or book.

Race bonuses show their configured unlock target, current relic strength, actual
active/inactive status and completion multiplier. They remain server-owned relic
auras, not learned spellbook spells: open archaeology through the professions entry
to inspect them. Val'kyr's Mercy's completion bonus shortens recovery rather than
multiplying the health saved. The catalogue is fetched on demand; the visible journal
refreshes lightweight trait state every five seconds and discovery history after solves.

New assignments respect faction restrictions and prefer nearby regions. Characters
below level 10 in one of the six supported starter zones receive their local starter
pool on that continent. There are 24 native beginner sites (four each in Northshire,
Coldridge, Deathknell, Shadowglen, Red Cloud Mesa and Valley of Trials). Their exact
find XYZ comes from the test realm's actual low-level creature spawns; polygons are
custom bounds. These placements are **provisional until surveyed in the game client**.
They do not add sites to the Blood Elf or Draenei starter islands; those characters
can use their faction's mainland sites after travelling there.

59 imported old-world sites have conservatively raised minimum levels based on the
3.3.5 spawn vicinity, including Broken Commons (0 -> 51). Outland/Northrend requirements
and progression gates are retained. With enough comfortable alternatives, new rolls
reserve all but at most one slot for sites at least `Archaeology.ChallengeLevels`
(default 3) below the player. Level-one training sites always count as comfortable.
This is an allocation rule, not enemy scaling or a guarantee of a safe travel route.
Existing eligible partial digs survive; saved assignments that no longer meet level,
skill or faction requirements are replaced on the next roll/login.

Right-click a map digsite to abandon it, or use `.arch abandon <site id>` (IDs are
listed by `.arch`). Abandoning loses partial site progress, grants no rewards, excludes
that site from the immediate replacement and starts a persistent character cooldown
(default 1,800 seconds). If no alternative exists, it leaves the assignment and cooldown
untouched. The realm may configure a different cooldown.

Apply normal module SQL including `mod_archaeology_char_expedition.sql` and
`mod_archaeology_world_zz_access.sql`, rebuild the module, and distribute ArchaeologyUI
0.6.0 together. No new client DBC/MPQ patch is required for these UI/access changes.
The existing archaeology patch is still required by the module's skill/items/auras.
The upgrade preserves operator-disabled sites. See [the access audit](docs/accessible-expeditions.md)
for provenance, generation, tests and the remaining client validation checklist.
