/*
 * mod-archaeology: the dig loop. Survey inside a dig site, walk toward the telescope, dig up the
 * find when close, and solve projects with fragments and keystones.
 *
 * Released under the MIT License.
 */

#include "Archaeology.h"
#include "GameObject.h"
#include "GameObjectAI.h"
#include "GameTime.h"
#include "Item.h"
#include "Map.h"
#include "Player.h"
#include "Random.h"
#include "ScriptMgr.h"
#include <cmath>

namespace
{
    using namespace Archaeology;

    // A find spawned by a survey, waiting for its owner to dig it up.
    struct PendingFind
    {
        ObjectGuid owner;
        uint32 continent;
        uint32 site;
    };
    std::unordered_map<ObjectGuid, PendingFind> pendingFinds;

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
            Site const* site = GetSite(a.site);
            if (site && InPolygon(site->polygon, player->GetPositionX(), player->GetPositionY()))
            {
                continentOut = uint32(c);
                return &a;
            }
        }
        return nullptr;
    }
}

namespace Archaeology
{
    void Survey(Player* player)
    {
        Config const& cfg = GetConfig();
        CharState* state = GetState(player);
        if (!cfg.enabled || !state || !state->skill)
        {
            Notify(player, "You don't know Archaeology. Find an archaeology trainer to learn it.");
            return;
        }
        if (player->IsInCombat() || player->IsMounted() || player->IsInFlight() || player->GetTransport())
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

        if (dist <= cfg.digYards)
        {
            // Dig spots come from Cataclysm data; stand the find on this map's ground instead.
            float z = player->GetMap()->GetHeight(player->GetPhaseMask(), spot.x, spot.y, spot.z + 10.0f, true, 50.0f);
            if (z <= INVALID_HEIGHT)
                z = spot.z;
            float ang = player->GetAngle(spot.x, spot.y);
            if (GameObject* go = player->SummonGameObject(race->findGo, spot.x, spot.y, z, ang, 0.0f, 0.0f,
                std::sin(ang / 2.0f), std::cos(ang / 2.0f), cfg.findSeconds))
            {
                pendingFinds[go->GetGUID()] = { player->GetGUID(), continent, active->site };
                active->spot = -1;
                Notify(player, Acore::StringFormat("|cff20ff20You've found a {} artifact!|r", race->name));
                SendAddon(player, "V:FOUND");
            }
            return;
        }

        uint8 band = dist > cfg.redYards ? BAND_RED : dist > cfg.yellowYards ? BAND_YELLOW : BAND_GREEN;
        float error = band == BAND_RED ? frand(-0.5f, 0.5f) : band == BAND_YELLOW ? frand(-0.25f, 0.25f) : 0.0f;
        float ang = Position::NormalizeOrientation(player->GetAngle(spot.x, spot.y) + error);

        float tx = px + std::cos(ang) * 1.5f, ty = py + std::sin(ang) * 1.5f;
        player->SummonGameObject(cfg.telescopeEntry, tx, ty, player->GetPositionZ(), ang, 0.0f, 0.0f,
            std::sin(ang / 2.0f), std::cos(ang / 2.0f), cfg.telescopeSeconds);

        static char const* const colours[3] = { "|cffff2020far away (red)|r", "|cffffff20closer (yellow)|r", "|cff20ff20close (green)|r" };
        Notify(player, Acore::StringFormat("The find is {}, to the {}.", colours[band], Compass(ang)));
        SendAddon(player, Acore::StringFormat("V:{}:{:.3f}", band == BAND_RED ? "RED" : band == BAND_YELLOW ? "YELLOW" : "GREEN", ang));
    }

    void ForgetFinds(Player* player)
    {
        for (auto itr = pendingFinds.begin(); itr != pendingFinds.end();)
            itr = itr->second.owner == player->GetGUID() ? pendingFinds.erase(itr) : std::next(itr);
    }

    bool UseFind(Player* player, GameObject* go)
    {
        auto itr = pendingFinds.find(go->GetGUID());
        if (itr == pendingFinds.end())
            return false;
        if (itr->second.owner != player->GetGUID())
        {
            Notify(player, "Someone else uncovered this find.");
            return true;
        }

        Config const& cfg = GetConfig();
        PendingFind find = itr->second;
        pendingFinds.erase(itr);
        go->DespawnOrUnsummon();

        CharState* state = GetState(player);
        Site const* site = GetSite(find.site);
        Race const* race = site ? GetRace(site->race) : nullptr;
        if (!state || !race)
            return true;

        RaceProgress& progress = state->races[race->id];
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

        if (state->skill < cfg.skillPerFindUntil)
            AddSkill(player, 1);

        std::vector<ActiveSite>& held = state->sites[find.continent];
        for (auto a = held.begin(); a != held.end(); ++a)
        {
            if (a->site != find.site)
                continue;
            if (++a->finds >= cfg.findsPerSite)
            {
                held.erase(a);
                Notify(player, Acore::StringFormat("{} has been depleted. A new dig site has been revealed.", site->name));
                RollSites(player);
            }
            break;
        }
        SaveSites(player, find.continent);
        SendRaces(player);
        SendSites(player);
        return true;
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

    bool OnGossipHello(Player* player, GameObject* go) override
    {
        if (!Archaeology::UseFind(player, go))
            Archaeology::Notify(player, "There is nothing left to dig up here.");
        return true;
    }
};

void AddArchaeologyDigScripts()
{
    new go_archaeology_find();
}
