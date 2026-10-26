/*
 * mod-archaeology: the dig loop. Survey inside a dig site, walk toward the telescope, dig up the
 * find when close, and solve projects with fragments and keystones.
 *
 * Released under the MIT License.
 */

#include "Archaeology.h"
#include "DBCStores.h"
#include "GameObject.h"
#include "GameObjectAI.h"
#include "GameTime.h"
#include "Item.h"
#include "Map.h"
#include "Player.h"
#include "Random.h"
#include "ScriptMgr.h"
#include "SpellScript.h"
#include "SpellMgr.h"
#include "SpellScriptLoader.h"
#include "WorldSession.h"
#include <algorithm>
#include <cmath>

namespace
{
    using namespace Archaeology;

    // Not on the ground: a flight path, a flying mount or form, or falling.
    bool Airborne(Player* player)
    {
        return player->IsInFlight() || player->IsFlying() || player->IsFalling();
    }

    int32 ContinentIndex(uint32 map)
    {
        for (std::size_t i = 0; i < CONTINENTS.size(); ++i)
            if (CONTINENTS[i] == map)
                return int32(i);
        return -1;
    }

    bool InPolygon(std::vector<Point> const& poly, float x, float y)
    {
        bool inside = false;
        for (std::size_t i = 0, j = poly.size() - 1; i < poly.size(); j = i++)
        {
            if (((poly[i].y > y) != (poly[j].y > y)) &&
                (x < (poly[j].x - poly[i].x) * (y - poly[i].y) / (poly[j].y - poly[i].y) + poly[i].x))
                inside = !inside;
        }
        return inside;
    }

    float Dist2d(float x1, float y1, float x2, float y2)
    {
        return std::sqrt((x1 - x2) * (x1 - x2) + (y1 - y2) * (y1 - y2));
    }

    // Map angle (0 = north, counter-clockwise) to a compass word.
    char const* Compass(float angle)
    {
        static char const* const words[8] = { "north", "northwest", "west", "southwest", "south", "southeast", "east", "northeast" };
        float a = std::fmod(angle + float(M_PI) / 8.0f, 2.0f * float(M_PI));
        if (a < 0.0f)
            a += 2.0f * float(M_PI);
        return words[int(a / (float(M_PI) / 4.0f)) % 8];
    }

    ActiveSite* SiteHere(Player* player, CharState& state, uint32& continentOut)
    {
        int32 c = ContinentIndex(player->GetMapId());
        if (c < 0)
            return nullptr;
        for (ActiveSite& a : state.sites[c])
        {
            Site const* site = DugOut(a) ? nullptr : GetSite(a.site);
            if (site && InPolygon(site->polygon, player->GetPositionX(), player->GetPositionY()))
            {
                continentOut = uint32(c);
                return &a;
            }
        }
        return nullptr;
    }

    constexpr uint32 SHOVEL_SPELL = 90522;   // the shovel above your head (client patch)

    // Where a find stands: on this map's ground, not at Cataclysm's elevation for the spot.
    float GroundZ(Player* player, Spot const& spot)
    {
        float z = player->GetMap()->GetHeight(player->GetPhaseMask(), spot.x, spot.y, spot.z + 10.0f, true, 50.0f);
        return z <= INVALID_HEIGHT ? spot.z : z;
    }

    // The dig site whose hidden find you stand on (within Archaeology.Dig.ShovelYards, on its
    // floor), or nullptr.
    ActiveSite* OverFind(Player* player, CharState& state, uint32& continent)
    {
        if (!GetConfig().enabled || !state.skill || !player->IsAlive() || player->IsInFlight() || player->GetTransport())
            return nullptr;
        ActiveSite* active = SiteHere(player, state, continent);
        if (!active)
            return nullptr;
        Site const* site = GetSite(active->site);
        if (active->spot < 0 || active->spot >= int32(site->spots.size()))
            return nullptr;
        Spot const& spot = site->spots[active->spot];
        if (Dist2d(player->GetPositionX(), player->GetPositionY(), spot.x, spot.y) > GetConfig().shovelYards)
            return nullptr;
        return std::abs(player->GetPositionZ() - GroundZ(player, spot)) <= 3.0f ? active : nullptr;
    }

    // The find comes up at its spot and is yours at once: fragments, sometimes a keystone, skill
    // and Relic Power. The artifact stands on the ground a moment to look at (Archaeology.Find.Seconds),
    // nothing to click. The next survey hides another find.
    void CollectFind(Player* player, CharState& state, ActiveSite& active, uint32 continent)
    {
        Config const& cfg = GetConfig();
        uint32 siteId = active.site;
        Site const* site = GetSite(siteId);
        Spot const& spot = site->spots[active.spot];
        Race const* race = GetRace(site->race);
        float ang = player->GetAngle(spot.x, spot.y);
        if (GameObject* go = player->SummonGameObject(race->findGo, spot.x, spot.y, GroundZ(player, spot), ang, 0.0f, 0.0f,
            std::sin(ang / 2.0f), std::cos(ang / 2.0f), cfg.findSeconds))
            go->SetGameObjectFlag(GO_FLAG_NOT_SELECTABLE);
        active.spot = -1;
        player->RemoveAurasDueToSpell(SHOVEL_SPELL);
        Notify(player, Acore::StringFormat("|cff20ff20You've found a {} artifact!|r", race->name));
        SendAddon(player, "V:FOUND");

        RaceProgress& progress = state.races[race->id];
        uint32 gained = urand(cfg.fragmentsMin, cfg.fragmentsMax);
        uint32 before = progress.fragments;
        progress.fragments = std::min(progress.fragments + gained, cfg.fragmentCap);
        if (!progress.project)
            PickProject(player, race->id);
        SaveRace(player, race->id);
        Notify(player, Acore::StringFormat("You receive {} {} fragments ({}/{}).", progress.fragments - before, race->name,
            progress.fragments, cfg.fragmentCap));
        SendAddon(player, Acore::StringFormat("F:{}:{}:{}", race->id, progress.fragments - before, progress.fragments));

        if (race->keystoneItem && roll_chance_f(cfg.keystoneChance))
            player->AddItem(race->keystoneItem, 1);

        if (state.skill < cfg.skillPerFindUntil)
            AddSkill(player, 1);
        if (state.relic.rank)   // finds count once the relic is in hand: a new relic starts at rank 1
            AddRelicPower(player, cfg.powerPerFind);

        // `active` lives in this vector: nothing touches it past here.
        std::vector<ActiveSite>& held = state.sites[continent];
        for (auto a = held.begin(); a != held.end(); ++a)
        {
            if (a->site != siteId)
                continue;
            if (++a->finds >= cfg.findsPerSite)
            {
                RollSites(player);   // `a` is gone past here: the site stays (dug out) or makes way
                if (std::none_of(held.begin(), held.end(), [siteId](ActiveSite const& b) { return b.site == siteId; }))
                    Notify(player, Acore::StringFormat("{} has been depleted. A new dig site has been revealed.", site->name));
                else
                {
                    AreaTableEntry const* zone = sAreaTableStore.LookupEntry(site->zone);
                    Notify(player, Acore::StringFormat("{} has been depleted. Dig out your other sites in {} to reveal new ones.", site->name,
                        zone ? zone->area_name[player->GetSession()->GetSessionDbcLocale()] : "this zone"));
                }
            }
            break;
        }
        SaveSites(player, continent);
        SendRaces(player);
        SendSites(player);
    }

    // Surveying and digging give you away: stealth (Prowl, Shadowmeld too) and invisibility drop.
    void BreakStealth(Player* player)
    {
        player->RemoveAurasByType(SPELL_AURA_MOD_STEALTH);
        player->RemoveAurasByType(SPELL_AURA_MOD_INVISIBILITY);
    }

    void StopDig(Player* player, CharState& state, char const* why)
    {
        state.digMs = 0;
        player->SetUInt32Value(UNIT_NPC_EMOTESTATE, EMOTE_ONESHOT_NONE);
        SendAddon(player, "Q:0");
        if (why)
            Notify(player, why);
    }

    // A dig in progress: moving, a fight, mounting or dying stops it; at the end the find is yours.
    void UpdateDig(Player* player, CharState& state, uint32 diff)
    {
        if (!player->IsAlive() || player->IsInCombat() || player->IsMounted() || player->IsInFlight() ||
            Dist2d(player->GetPositionX(), player->GetPositionY(), state.digX, state.digY) > 0.5f)
        {
            StopDig(player, state, "You stop digging.");
            return;
        }
        if (diff < state.digMs)
        {
            state.digMs -= diff;
            return;
        }
        StopDig(player, state, nullptr);
        uint32 continent = 0;
        if (ActiveSite* active = OverFind(player, state, continent))
            CollectFind(player, state, *active, continent);
        else
            Notify(player, "There is nothing buried here.");
    }
}

namespace Archaeology
{
    // Standing on the hidden find shows the shovel above your head and tells the addon (its Dig
    // button); it never selects a spot or digs. Also runs a dig in progress.
    void UpdateFindShovel(Player* player, uint32 diff)
    {
        CharState* state = GetState(player);
        if (!state)
        {
            player->RemoveAurasDueToSpell(SHOVEL_SPELL);
            return;
        }
        if (state->digMs)
            UpdateDig(player, *state, diff);
        state->shovelCheckMs += diff;
        if (state->shovelCheckMs < 200)
            return;
        state->shovelCheckMs = 0;

        uint32 continent = 0;
        bool overFind = OverFind(player, *state, continent) != nullptr;
        if (overFind != state->overFind)
        {
            state->overFind = overFind;
            SendAddon(player, overFind ? "O:1" : "O:0");
        }
        if (!overFind)
            player->RemoveAurasDueToSpell(SHOVEL_SPELL);
        else if (!player->HasAura(SHOVEL_SPELL) && sSpellMgr->GetSpellInfo(SHOVEL_SPELL))
            player->AddAura(SHOVEL_SPELL, player);
    }

    // Dig where you stand: on the find (the shovel above your head) it comes up, and is yours, after
    // Archaeology.Dig.Ms of digging. Mounted on the ground, you get off first; not in the air.
    void Dig(Player* player)
    {
        Config const& cfg = GetConfig();
        CharState* state = GetState(player);
        if (!cfg.enabled || !state || !state->skill)
        {
            Notify(player, "You don't know Archaeology. Find an archaeology trainer to learn it.");
            return;
        }
        if (state->digMs)
            return;
        if (player->IsInCombat() || player->GetTransport() || Airborne(player))
        {
            Notify(player, "You can't dig right now.");
            return;
        }
        uint32 continent = 0;
        ActiveSite* active = OverFind(player, *state, continent);
        if (!active)
        {
            Notify(player, "There is nothing buried here. Survey to find the spot, then stand where the shovel shows.");
            return;
        }
        if (player->IsMounted())
        {
            player->RemoveAurasByType(SPELL_AURA_MOUNTED);
            if (player->IsMounted())
                player->Dismount();
        }
        BreakStealth(player);
        if (!cfg.digMs)
        {
            CollectFind(player, *state, *active, continent);
            return;
        }
        state->digMs = cfg.digMs;
        state->digX = player->GetPositionX();
        state->digY = player->GetPositionY();
        player->SetUInt32Value(UNIT_NPC_EMOTESTATE, EMOTE_STATE_WORK_MINING);
        SendAddon(player, Acore::StringFormat("Q:{}", cfg.digMs));
    }

    void Survey(Player* player)
    {
        Config const& cfg = GetConfig();
        CharState* state = GetState(player);
        if (!cfg.enabled || !state || !state->skill)
        {
            Notify(player, "You don't know Archaeology. Find an archaeology trainer to learn it.");
            return;
        }
        if (player->IsInCombat() || player->IsMounted() || player->GetTransport() || Airborne(player))
        {
            Notify(player, "You can't survey right now.");
            return;
        }

        uint32 now = GameTime::GetGameTimeMS().count();
        if (state->lastSurveyMs && now - state->lastSurveyMs < cfg.surveyCooldownMs)
            return;
        state->lastSurveyMs = now;

        uint32 continent = 0;
        ActiveSite* active = SiteHere(player, *state, continent);
        if (!active)
        {
            Notify(player, "You must be in a dig site to survey. Open your map to see your dig sites.");
            SendAddon(player, "V:NONE");
            return;
        }
        Site const* site = GetSite(active->site);
        BreakStealth(player);

        float px = player->GetPositionX(), py = player->GetPositionY();
        if (active->spot < 0 || active->spot >= int32(site->spots.size()))
        {
            // Hide the next find at a spot away from the player; fall back to the farthest one.
            std::vector<int32> far;
            int32 farthest = 0;
            float best = -1.0f;
            for (std::size_t i = 0; i < site->spots.size(); ++i)
            {
                float d = Dist2d(px, py, site->spots[i].x, site->spots[i].y);
                if (d >= cfg.minSpotYards)
                    far.push_back(int32(i));
                if (d > best)
                {
                    best = d;
                    farthest = int32(i);
                }
            }
            active->spot = far.empty() ? farthest : Acore::Containers::SelectRandomContainerElement(far);
        }

        Spot const& spot = site->spots[active->spot];
        float dist = Dist2d(px, py, spot.x, spot.y);
        Race const* race = GetRace(site->race);

        if (dist <= cfg.digYards && !cfg.shovelDig)
        {
            CollectFind(player, *state, *active, continent);
            return;
        }
        if (cfg.shovelDig && OverFind(player, *state, continent))
        {
            Notify(player, Acore::StringFormat("|cff20ff20You're standing on the {} find. Dig it up!|r", race->name));
            state->overFind = true;
            SendAddon(player, "O:1");
            return;
        }

        uint8 band = dist > cfg.redYards ? BAND_RED : dist > cfg.yellowYards ? BAND_YELLOW : BAND_GREEN;
        float error = band == BAND_RED ? frand(-0.5f, 0.5f) : band == BAND_YELLOW ? frand(-0.25f, 0.25f) : 0.0f;
        float ang = Position::NormalizeOrientation(player->GetAngle(spot.x, spot.y) + error);

        float tx = px + std::cos(ang) * 1.5f, ty = py + std::sin(ang) * 1.5f;
        player->SummonGameObject(cfg.telescopeEntry[band], tx, ty, player->GetPositionZ(), ang, 0.0f, 0.0f,
            std::sin(ang / 2.0f), std::cos(ang / 2.0f), cfg.telescopeSeconds);

        static char const* const colours[3] = { "|cffff2020far away (red)|r", "|cffffff20closer (yellow)|r", "|cff20ff20close (green)|r" };
        if (dist <= cfg.digYards)
        {
            int32 yards = std::max(1, int32(std::lround(dist)));
            Notify(player, Acore::StringFormat("|cff20ff20The find is {} {} away|r, to the {}. Stand on it and dig.",
                yards, yards == 1 ? "yard" : "yards", Compass(ang)));
        }
        else
            Notify(player, Acore::StringFormat("The find is {}, to the {}.", colours[band], Compass(ang)));
        SendAddon(player, Acore::StringFormat("V:{}:{:.3f}", band == BAND_RED ? "RED" : band == BAND_YELLOW ? "YELLOW" : "GREEN", ang));
    }

    void ForgetFinds(Player* player)
    {
        player->RemoveAurasDueToSpell(SHOVEL_SPELL);
        if (CharState* state = GetState(player))
        {
            if (state->digMs)
                StopDig(player, *state, nullptr);
            state->overFind = false;
        }
    }

    bool Solve(Player* player, uint8 raceId, uint32 keystones, std::string& error)
    {
        Config const& cfg = GetConfig();
        CharState* state = GetState(player);
        Race const* race = GetRace(raceId);
        if (!cfg.enabled || !state || !state->skill || !race || !IsRaceUnlocked(player, *race))
        {
            error = "You can't research that race yet.";
            return false;
        }
        RaceProgress& progress = state->races[raceId];
        Project const* project = GetProject(progress.project);
        if (!project)
        {
            error = "You have no project for that race yet. Dig up some fragments first.";
            return false;
        }

        uint32 owned = race->keystoneItem ? player->GetItemCount(race->keystoneItem) : 0;
        uint32 useKeys = std::min({ keystones, project->sockets, owned });
        if (cfg.keystoneValue)
            useKeys = std::min(useKeys, (project->cost + cfg.keystoneValue - 1) / cfg.keystoneValue);
        uint32 keyValue = useKeys * cfg.keystoneValue;
        uint32 needFragments = project->cost > keyValue ? project->cost - keyValue : 0;
        if (progress.fragments < needFragments)
        {
            error = Acore::StringFormat("You need {} more {} fragments.", needFragments - progress.fragments, race->name);
            return false;
        }

        ItemPosCountVec dest;
        if (player->CanStoreNewItem(NULL_BAG, NULL_SLOT, dest, project->item, 1) != EQUIP_ERR_OK)
        {
            error = "Your bags are full.";
            return false;
        }

        progress.fragments -= needFragments;
        if (useKeys)
            player->DestroyItemCount(race->keystoneItem, useKeys, true);
        if (Item* item = player->StoreNewItem(dest, project->item, true))
            player->SendNewItem(item, 1, true, false);

        uint32 times = ++state->solved[project->id];
        SaveSolved(player, project->id);
        Notify(player, Acore::StringFormat("{}You have solved {}{}.|r", project->rare ? "|cffa335ee" : "|cffffffff",
            project->name, times > 1 ? Acore::StringFormat(" ({} times)", times) : std::string()));
        SendAddon(player, Acore::StringFormat("X:{}:{}:{}", project->id, project->item, project->rare ? 1 : 0));

        AddSkill(player, project->rare ? cfg.skillPerRare : cfg.skillPerCommon);
        UpdateTraitWake(player, true);
        QueueTraits(player);   // a trait may wake or double, an achievement may be due
        AddRelicPower(player, (project->rare ? cfg.powerPerRare : cfg.powerPerCommon) + (times == 1 ? cfg.powerFirstSolve : 0));
        PickProject(player, raceId);
        SaveRace(player, raceId);
        SendRaces(player);
        SendSites(player);   // a skill-up can open new dig sites
        return true;
    }
}

class go_archaeology_find : public GameObjectScript
{
public:
    go_archaeology_find() : GameObjectScript("go_archaeology_find") { }

    // Finds are collected as they come up and stand unselectable; one from an older build can only say so.
    bool OnGossipHello(Player* player, GameObject* /*go*/) override
    {
        Archaeology::Notify(player, "There is nothing left to dig up here.");
        return true;
    }
};

// Survey (spell 90506 in the client patch): a Dummy on yourself; the module does the survey.
class spell_archaeology_survey : public SpellScript
{
    PrepareSpellScript(spell_archaeology_survey);

    void HandleDummy(SpellEffIndex /*effIndex*/)
    {
        if (Player* player = GetCaster() ? GetCaster()->ToPlayer() : nullptr)
            Archaeology::Survey(player);
    }

    void Register() override
    {
        OnEffectHitTarget += SpellEffectFn(spell_archaeology_survey::HandleDummy, EFFECT_0, SPELL_EFFECT_DUMMY);
    }
};

void AddArchaeologyDigScripts()
{
    new go_archaeology_find();
    RegisterSpellScript(spell_archaeology_survey);
}
