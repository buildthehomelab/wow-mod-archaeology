# Accessible expeditions and discovery journal

## Site levels and starter sites

`site-level-audit.json` inventories 71 enabled imported old-world sites. Nearby
non-NPC/non-critter creature spawn levels were compared within 65 horizontal and 20
vertical yards of every imported dig point. Event-only creatures were excluded, as
were native friendly guard/civilian factions and neutral faction 35. The maximum
observed level minus three raises 59 imported minima; none are reduced. This is a
conservative vicinity rule, not a certified hostility/pathfinding test. Rare elites
can raise the minimum, and temporary events can still make an expedition harder.
Outland/Northrend and the existing 27 terrain holds are unchanged.

`tools/site-level-overrides.json` stores reviewed minimum levels and the creature
names/levels supporting them. `build_data.py` consumes these overrides so a later
Cataclysm data regeneration cannot restore the old low requirements.

`tools/beginner-sites.json` stores 24 custom starter sites, source creature GUID/entry
and exact XYZ. Each has at least three real low-level spawn points, low vertical
spread, more than 40 yards of point separation somewhere in the site, and a small
non-overlapping rectangular polygon enclosing the points. Native-friendly camps are
team restricted. The source used only level 1–2 non-NPC/non-critter spawns and screened
the surrounding area for creatures above level 4. These are **database-validated
candidates enabled provisionally in the proposed SQL**, not completed in-client tests.
No terrain heights have been invented or projected from Cataclysm data. Custom
bounding rectangles do not prove every intermediate path unobstructed or the player
able to reach each spawn's exact floor.

Six starting regions have four sites apiece. Blood Elf/Draenei islands do not yet
have bespoke sites; faction-compatible mainland travel remains necessary there.

## Regeneration and upgrades

Run `python3 tools/build_site_access.py`. It needs only the checked-in JSON evidence;
it does not connect to a database. The generated `mod_archaeology_world_zz_access.sql`
creates faction/starter-zone metadata, raises imported level minima and installs the
24 starter polygons/points. It runs after the existing terrain-hold upgrade. Repeating
it does not duplicate points or re-enable an operator-disabled site. A full normal
base-data reimport retains the module's existing destructive world-catalog replacement
semantics; run the access SQL afterwards. Character discoveries/fragments are untouched.

The cooldown and final replacement assignment are committed in one SaveSites transaction.
The separate character cooldown table prevents relogging from bypassing expedition
abandonment. Existing installations need the world and character migrations before
running the new module binary. Removing assignments never removes discovery history.

## Journal protocol and hosts

`COLLECTION` requests `CBEGIN`, per-project `C` rows (id/race/rare/reward/solve-count/name),
per-race `U` unlock requirements, and `CEND`; `TRAITS` requests `JBEGIN`, per-race `J`
state and `K` effect descriptions, and `JEND`. Snapshots commit atomically at their
end marker. A collection request also includes a trait snapshot. The server throttles
requests independently, and the client uses the existing request queue. No catalogue
is stored as authoritative SavedVariables. Project lore uses the existing `PROJ` request.

The shared research page owns the entry button, so it follows both supported host
reparenting paths. `/arch collection` is an additional entry even if a host is absent.
Existing `T` site rows are unchanged; new `E` rows append recommended level/challenge
metadata after `TEND`, maintaining compatibility with older addons.

## Tests

- `python3 -m unittest discover -s test -p 'test_*.py'`: real C++ assignment/abandonment
  bodies under ASan/UBSan, world migration/idempotence/provenance and reward regressions.
- `lua5.1 test/test_collection.lua`: real addon receiver and collection view under a
  minimal frame API, including unique/repeat/rare counts, filters, completion, locked
  races, trait unlock progress and compatible map hints.
- `python3 tools/check_wotlk_sites.py`: existing terrain holds/race coverage.
- `./test/run-rewards.sh`: existing companion-item regression.

The frame fixture verifies behavior, not pixels or a real WoW client.

Not yet tried in a game client: walking every starter site without GM flight (survey direction
and height, all finds, entry paths, low-level hostile encounters, faction restrictions, depletion
and reroll), the collection layout in the standalone, DragonUI and RetailProfessions views,
reward and lore tooltips, a sold reward's collected status, each trait asleep, awake, equipped
and unequipped, completion multipliers, and cooldown persistence across relogs.
