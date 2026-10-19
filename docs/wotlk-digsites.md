# WotLK digsite terrain audit

Target: Evermore's 3.3.5a terrain, including ground access in Eastern Kingdoms
and Kalimdor. Archaeology itself is backported; there is no original WotLK
archaeology location dataset to substitute for the Cataclysm dataset.

## Finding and scope

The generator previously accepted any imported site on maps 0, 1, 530 or 571
below skill 450. This excluded new expansion zones but did not check old-world
terrain, height, cave access, flooding or flight-only approaches. All 156 site
records were inventoried; this is a source/geography risk audit, not a completed
collision or pathfinding audit. The per-site inventory is
[wotlk-digsite-audit.csv](wotlk-digsite-audit.csv).

27 sites are disabled. Darkmist (289) is the user's reported WotLK access
failure. Eldre'Thar (179), Unearthed Grounds (181), and Red Reaches (203) depend
on Cataclysm additions. Other disabled sites are precautionary holds in changed
terrain, **not claims that every point there is proven unreachable**. Reasons
are recorded per ID in `tools/wotlk-disabled-sites.json` and the audit CSV.

129 sites remain enabled provisionally. Outland and Northrend are retained;
their presence in WotLK does not prove the imported point heights or every
approach correct. Unflagged old-world locations also still require point-level
verification. No coordinates have been invented, relabeled as WotLK exports,
or automatically projected onto potentially wrong floors.

Bael Modan is the only imported dwarf site in Kalimdor. Its precautionary hold
means dwarf fragments must currently be gathered in Eastern Kingdoms. This is
a deliberate availability tradeoff until a WotLK-compatible Bael Modan polygon
and spawn set can be verified. All eight races retain enabled sites overall.

## Evidence

- [Darkmist Ruins](https://warcraft.wiki.gg/wiki/Darkmist_Ruins) and the
  Evermore player's report of an unavailable cave approach.
- [Cataclysm Stonetalon exploration](https://warcraft.blizzplanet.com/blog/comments/cataclysm_stonetalon_mountains_spoilers)
  directly describes Eldre'Thar's new canyon and the Unearthed Grounds.
- [Red Reaches](https://wowwiki-archive.fandom.com/wiki/Red_Reaches)
  identifies the Cataclysm coastal area.
- Compare the pre-Shattering and post-Shattering zone geography for the
  precautionary holds: [Wetlands](https://warcraft.wiki.gg/wiki/Wetlands),
  [Hillsbrad](https://warcraft.wiki.gg/wiki/Hillsbrad_Foothills),
  [Badlands](https://warcraft.wiki.gg/wiki/Badlands),
  [Darkshore](https://warcraft.wiki.gg/wiki/Darkshore),
  [Azshara](https://warcraft.wiki.gg/wiki/Azshara),
  [Southern Barrens](https://warcraft.wiki.gg/wiki/Southern_Barrens),
  and [Tanaris](https://warcraft.wiki.gg/wiki/Tanaris).
  These are geography references, not machine-verified collision data.

## Applying and validating

Apply the normal base/generated world SQL, followed by
`mod_archaeology_world_z_wotlk_sites.sql`. The latter is idempotent and only
turns the listed IDs off; it preserves unrelated operator-disabled sites.
Generation also emits explicit flags so rebuilding the data cannot re-enable
the held sites. A full base-data reimport retains its existing behavior of
replacing the tables, including resetting other local flags.

Restart the worldserver after applying SQL so its enabled-site cache reloads.
On the next character login, existing code ignores saved disabled sites and
fills vacant continent slots through `RollSites`; fragments, projects, relics
and solve history are untouched. No character database migration is needed.
Do not apply this while expecting already loaded character state to refresh.

Before re-enabling a held site, validate **every** polygon and spawn against
Evermore's actual 3.3.5a maps/vmaps/mmaps and client patches. Enter from normal
paths without GM movement or old-world flying; confirm the correct floor,
water depth, cave entrance, survey indicator and successful dig. Check that all
spawn points lie inside the usable survey polygon. Remap or replace the site
using those verified WotLK coordinates, update the policy and audit, and repeat
the same review. The WotLK map assets and live game client were unavailable
for this source audit, so that validation remains pending.

Local verification: `python3 tools/check_wotlk_sites.py` checks all 156 flags,
the complete inventory, starting pools, race availability and the existing-world
upgrade (including repeat application and unrelated local holds). Full data
regeneration needs the uncommitted source exports and was not performed.

Delivery requires a reviewed module PR, then a reviewed wow-server pin PR to
the actual merged module commit. SQL application, restart and live deployment
are separate, unperformed steps.
