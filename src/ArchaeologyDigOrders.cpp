/*
 * mod-archaeology: Dig Orders, a daily quest from the archaeology trainer. Accepting it names one
 * of the character's own dig sites; each find dug up there counts, and the last one uncovers a
 * fragment cache with bonus fragments of that site's race. Turning it in gives Relic Power.
 *
 * The quest system can't say which site: the module keeps it (mod_archaeology_char_dig_orders),
 * tells the player, and the addon marks it on the maps.
 *
 * Released under the MIT License.
 */

#include "Archaeology.h"
#include "Containers.h"
#include "DatabaseEnv.h"
#include "GameObject.h"
#include "ObjectMgr.h"
#include "Player.h"
#include "QuestDef.h"
#include "Random.h"
#include "ScriptMgr.h"
#include <cmath>

namespace
{
    using namespace Archaeology;

    constexpr uint32 CACHE_SECONDS = 300;

    // A fragment cache waiting for its owner to open it.
    struct PendingCache
    {
        ObjectGuid owner;
        uint8 race;
    };
    std::unordered_map<ObjectGuid, PendingCache> pendingCaches;

    bool OnOrders(Player* player)
    {
        return player->GetQuestStatus(DIG_ORDERS_QUEST) == QUEST_STATUS_INCOMPLETE;
    }

    // Finds the orders ask for: the quest's own objective count, so it can be changed in SQL.
    uint32 FindsNeeded()
    {
        Quest const* quest = sObjectMgr->GetQuestTemplate(DIG_ORDERS_QUEST);
        return quest ? std::max<uint32>(quest->RequiredNpcOrGoCount[0], 1) : 0;
    }

    uint32 FindsDone(Player* player)
    {
        QuestStatusMap& quests = player->getQuestStatusMap();
        auto itr = quests.find(DIG_ORDERS_QUEST);
        return itr != quests.end() ? itr->second.CreatureOrGOCount[0] : 0;
    }

    bool Holds(CharState const& state, uint32 site)
    {
        for (std::vector<ActiveSite> const& held : state.sites)
            for (ActiveSite const& a : held)
                if (a.site == site)
                    return true;
        return false;
    }

    // One of the character's dig sites: on the continent they stand on if they can, and one they
    // haven't started digging if they can.
    uint32 PickSite(Player* player, CharState const& state)
    {
        std::vector<uint32> best;
        int32 bestScore = -1;
        for (uint32 c = 0; c < CONTINENTS.size(); ++c)
        {
            if (!CanDigContinent(player, c))
                continue;
            for (ActiveSite const& a : state.sites[c])
            {
                Site const* site = GetSite(a.site);
                if (!site)
                    continue;
                int32 score = (site->map == player->GetMapId() ? 2 : 0) + (a.finds == 0 ? 1 : 0);
                if (score > bestScore)
                {
                    best.clear();
                    bestScore = score;
                }
                if (score == bestScore)
                    best.push_back(a.site);
            }
        }
        return best.empty() ? 0 : Acore::Containers::SelectRandomContainerElement(best);
    }

    void SaveOrder(Player* player, uint32 site)
    {
        ObjectGuid::LowType guid = player->GetGUID().GetCounter();
        if (site)
            CharacterDatabase.Execute("REPLACE INTO `mod_archaeology_char_dig_orders` (`guid`, `site`) VALUES ({}, {})", guid, site);
        else
            CharacterDatabase.Execute("DELETE FROM `mod_archaeology_char_dig_orders` WHERE `guid` = {}", guid);
    }

    std::string SiteLabel(Site const* site)
    {
        Race const* race = GetRace(site->race);
        return Acore::StringFormat("{} ({})", site->name, race ? race->name : "Unknown");
    }

    void OpenCache(Player* player, uint8 raceId)
    {
        Config const& cfg = GetConfig();
        CharState* state = GetState(player);
        Race const* race = GetRace(raceId);
        if (!state || !race)
            return;
        RaceProgress& progress = state->races[race->id];
        uint32 before = progress.fragments;
        progress.fragments = std::min(progress.fragments + urand(cfg.cacheFragmentsMin, cfg.cacheFragmentsMax), cfg.fragmentCap);
        if (!progress.project)
            PickProject(player, race->id);
        SaveRace(player, race->id);
        Notify(player, Acore::StringFormat("You open the fragment cache: {} {} fragments ({}/{}).", progress.fragments - before, race->name,
            progress.fragments, cfg.fragmentCap));
        SendAddon(player, Acore::StringFormat("F:{}:{}:{}", race->id, progress.fragments - before, progress.fragments));
        if (race->keystoneItem && roll_chance_f(cfg.cacheKeystoneChance))
            player->AddItem(race->keystoneItem, 1);
        SendRaces(player);
    }
}

namespace Archaeology
{
    bool OffersDigOrders(Player* player)
    {
        return GetConfig().digOrdersEnabled && IsLearned(player) && sObjectMgr->GetQuestTemplate(DIG_ORDERS_QUEST);
    }

    void LoadDigOrders(Player* player, CharState& state)
    {
        QueryResult result = CharacterDatabase.Query("SELECT `site` FROM `mod_archaeology_char_dig_orders` WHERE `guid` = {}",
            player->GetGUID().GetCounter());
        if (!result)
            return;
        // Orders turned in or dropped while the module was off leave a stale row.
        if (player->GetQuestStatus(DIG_ORDERS_QUEST) == QUEST_STATUS_NONE)
            SaveOrder(player, 0);
        else
            state.digOrderSite = result->Fetch()[0].Get<uint32>();
    }

    void DigOrdersAccepted(Player* player)
    {
        CharState* state = GetState(player);
        if (!state || !state->skill)
            return;
        state->digOrderSite = PickSite(player, *state);
        SaveOrder(player, state->digOrderSite);
        if (Site const* site = GetSite(state->digOrderSite))
            Notify(player, Acore::StringFormat("|cffffd200Dig Orders:|r dig up {} finds at {}. It's marked on your map.", FindsNeeded(), SiteLabel(site)));
        else
            Notify(player, "|cffffd200Dig Orders:|r you have no dig sites yet. Your orders will name one as soon as you do.");
        SendDigOrders(player);
    }

    void DigOrdersDropped(Player* player)
    {
        CharState* state = GetState(player);
        if (!state || !state->digOrderSite)
            return;
        state->digOrderSite = 0;
        SaveOrder(player, 0);
        SendDigOrders(player);
    }

    void DigOrdersRewarded(Player* player)
    {
        CharState* state = GetState(player);
        if (state && state->relic.rank)   // like finds: Relic Power once the relic is in hand
            AddRelicPower(player, GetConfig().digOrdersRelicPower);
        DigOrdersDropped(player);
    }

    // The ordered site can go away (abandoned, or no longer fits the character): name another.
    void CheckDigOrders(Player* player)
    {
        CharState* state = GetState(player);
        if (!GetConfig().digOrdersEnabled || !state || !state->skill || !OnOrders(player))
            return;
        if (state->digOrderSite && Holds(*state, state->digOrderSite))
            return;
        uint32 site = PickSite(player, *state);
        if (site == state->digOrderSite)
            return;
        state->digOrderSite = site;
        SaveOrder(player, site);
        if (Site const* s = GetSite(site))
            Notify(player, Acore::StringFormat("|cffffd200Dig Orders:|r your orders now name {}.", SiteLabel(s)));
        SendDigOrders(player);
    }

    // A find was dug up. At the ordered site it counts; a depleted site fills the orders, since
    // there is nothing left there to dig. The last find uncovers the fragment cache.
    void DigOrdersFind(Player* player, uint32 site, bool depleted, Position const& where)
    {
        CharState* state = GetState(player);
        if (!GetConfig().digOrdersEnabled || !state || !state->digOrderSite || site != state->digOrderSite || !OnOrders(player))
            return;
        uint32 need = FindsNeeded();
        for (uint32 i = 0; i < need && OnOrders(player); ++i)
        {
            player->KilledMonsterCredit(DIG_ORDERS_CREDIT);
            if (!depleted)
                break;
        }
        SendDigOrders(player);
        if (player->GetQuestStatus(DIG_ORDERS_QUEST) != QUEST_STATUS_COMPLETE)
            return;

        Site const* s = GetSite(site);
        float ang = player->GetAngle(where.GetPositionX(), where.GetPositionY());
        if (GameObject* go = s ? player->SummonGameObject(DIG_ORDERS_CACHE, where.GetPositionX(), where.GetPositionY(), where.GetPositionZ(),
            ang, 0.0f, 0.0f, std::sin(ang / 2.0f), std::cos(ang / 2.0f), CACHE_SECONDS) : nullptr)
        {
            pendingCaches[go->GetGUID()] = { player->GetGUID(), s->race };
            Notify(player, "|cff20ff20Your Dig Orders are filled, and the last find turned up a fragment cache!|r Open it, then report to an archaeology trainer.");
        }
        else
            Notify(player, "|cff20ff20Your Dig Orders are filled.|r Report to an archaeology trainer.");
    }

    bool UseDigOrdersCache(Player* player, GameObject* go)
    {
        auto itr = pendingCaches.find(go->GetGUID());
        if (itr == pendingCaches.end())
            return false;
        if (itr->second.owner != player->GetGUID())
        {
            Notify(player, "This cache belongs to someone else's dig.");
            return true;
        }
        uint8 race = itr->second.race;
        pendingCaches.erase(itr);
        player->RemoveGameObject(go, true);
        OpenCache(player, race);
        return true;
    }

    void ForgetDigOrdersCaches(Player* player)
    {
        for (auto itr = pendingCaches.begin(); itr != pendingCaches.end();)
            itr = itr->second.owner == player->GetGUID() ? pendingCaches.erase(itr) : std::next(itr);
    }

    // W:<site>:<finds done>:<finds needed>, site 0 = no orders being worked.
    void SendDigOrders(Player* player)
    {
        CharState* state = GetState(player);
        if (!state || !state->digOrderSite || !OnOrders(player))
        {
            SendAddon(player, "W:0:0:0");
            return;
        }
        SendAddon(player, Acore::StringFormat("W:{}:{}:{}", state->digOrderSite, FindsDone(player), FindsNeeded()));
    }

    std::string DigOrdersText(Player* player)
    {
        CharState* state = GetState(player);
        Quest const* quest = sObjectMgr->GetQuestTemplate(DIG_ORDERS_QUEST);
        if (!GetConfig().digOrdersEnabled || !state || !state->skill || !quest)
            return "";
        switch (player->GetQuestStatus(DIG_ORDERS_QUEST))
        {
            case QUEST_STATUS_INCOMPLETE:
                if (Site const* site = GetSite(state->digOrderSite))
                    return Acore::StringFormat("Dig Orders: {}, {}/{} finds.", SiteLabel(site), FindsDone(player), FindsNeeded());
                return "Dig Orders: waiting for a dig site.";
            case QUEST_STATUS_COMPLETE:
                return "Dig Orders: filled. Report to an archaeology trainer.";
            default:
                return player->CanTakeQuest(quest, false) ? "Dig Orders: an archaeology trainer has new orders for you."
                    : "Dig Orders: done for today.";
        }
    }
}

class go_archaeology_dig_orders_cache : public GameObjectScript
{
public:
    go_archaeology_dig_orders_cache() : GameObjectScript("go_archaeology_dig_orders_cache") { }

    bool OnGossipHello(Player* player, GameObject* go) override
    {
        if (!Archaeology::UseDigOrdersCache(player, go))
            Archaeology::Notify(player, "The cache is empty.");
        return true;
    }
};

void AddArchaeologyDigOrdersScripts()
{
    new go_archaeology_dig_orders_cache();
}
