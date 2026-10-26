/*
 * mod-archaeology: Cataclysm-style Archaeology for AzerothCore (3.3.5a).
 *
 * The server owns everything: skill, dig sites, fragments, the survey and the solve roll. The
 * ArchaeologyUI addon only draws it. All progress is per character.
 *
 * Released under the MIT License.
 */

#ifndef MOD_ARCHAEOLOGY_H
#define MOD_ARCHAEOLOGY_H

#include "Define.h"
#include "ObjectGuid.h"
#include <array>
#include <string>
#include <unordered_map>
#include <vector>

class Creature;
class GameObject;
class Player;
struct Position;

namespace Archaeology
{
    constexpr char const* PREFIX = "ARCH";

    // Continents dig sites roll on, in slot order.
    constexpr std::array<uint32, 4> CONTINENTS = { 0, 1, 530, 571 };

    // The client patch's rank spells: Apprentice (90500) to Grand Master (90505).
    constexpr uint32 RANK_SPELL_FIRST = 90500;
    constexpr uint32 RANK_SPELLS = 6;

    enum SurveyBand : uint8 { BAND_RED, BAND_YELLOW, BAND_GREEN, BAND_FOUND };

    struct Config
    {
        bool enabled = true;
        uint32 sitesPerContinent = 4;
        uint32 abandonSeconds = 1800;
        uint32 challengeLevels = 3;
        uint32 starterSitesMaxSkill = 50;   // beginner (starter-zone) sites come up only while skill <= this; 0 = always
        uint32 findsPerSite = 3;
        uint32 fragmentsMin = 5;
        uint32 fragmentsMax = 9;
        uint32 fragmentCap = 200;
        float keystoneChance = 12.0f;
        uint32 keystoneValue = 12;
        float redYards = 100.0f;
        float yellowYards = 50.0f;
        float digYards = 8.0f;
        bool shovelDig = true;          // the find comes up only when you dig standing on it
        float shovelYards = 3.0f;       // how close "standing on it" is (also the overhead shovel)
        uint32 digMs = 1500;
        float minSpotYards = 40.0f;
        uint32 surveyCooldownMs = 3000;
        uint32 skillPerFindUntil = 50;
        uint32 skillPerCommon = 5;
        uint32 skillPerRare = 15;
        uint32 maxSkill = 450;
        uint32 skillLine = 0;           // 0 = skill lives only in the module; else mirror to this SkillLine id
        uint32 minLevel = 1;
        bool ipEnabled = false;
        uint32 ipOutlandState = 8;
        uint32 ipNorthrendState = 13;
        uint32 ipQuestBase = 66000;
        uint32 ipMaxState = 18;
        std::array<uint32, 3> telescopeEntry = { 9503502, 9503501, 9503500 };   // by SurveyBand: red, yellow, green
        uint32 telescopeSeconds = 6;
        uint32 findSeconds = 15;        // how long the unearthed artifact stands there (already collected)

        // The Unearthed Relic
        bool relicEnabled = true;
        uint32 relicSkill = 50;              // skill that opens "A Weapon in Pieces"
        uint32 powerPerFind = 10;
        uint32 powerPerCommon = 30;
        uint32 powerPerRare = 300;
        uint32 powerFirstSolve = 100;
        float relicCostRate = 1.0f;
        uint32 relicStateWithoutIp = 18;     // progression state the relic assumes without individual progression
        std::array<uint32, 3> capstoneQuest = { 0, 0, 0 };   // by era; 0 = none needed
        bool awakenNeedsMaxSkill = true;
        uint32 formChangeBase = 100000;      // copper
        uint32 formChangePerRank = 20000;
        bool traitsEnabled = true;
        uint32 traitWakeCommons = 10;        // common solves of a race that wake its trait
        float traitFirstRank = 0.4f;         // a trait's strength at the first rank (1.0 at full rank)
        float traitCompleteBonus = 2.0f;     // multiplier once every project of the race is solved

        // Dig Orders, the daily quest
        bool digOrdersEnabled = true;
        uint32 cacheFragmentsMin = 15;
        uint32 cacheFragmentsMax = 25;
        float cacheKeystoneChance = 50.0f;
        uint32 digOrdersRelicPower = 50;
    };

    struct Race
    {
        uint8 id = 0;
        std::string name;
        uint32 keystoneItem = 0;
        uint32 unlockSkill = 0;
        uint32 findGo = 0;
    };

    struct Point { float x, y; };
    struct Spot { float x, y, z; };

    struct Site
    {
        uint32 id = 0;
        uint32 map = 0;
        uint8 race = 0;
        std::string name;
        uint32 minSkill = 0;
        uint32 minLevel = 0;
        uint8 team = 0;
        uint32 starterZone = 0;
        uint32 zone = 0;             // mod_archaeology_site_zone (tools/build_site_zones.py), 0 = unknown
        std::vector<Point> polygon;
        std::vector<Spot> spots;
        Point center { 0.0f, 0.0f };
    };

    struct Project
    {
        uint32 id = 0;
        uint8 race = 0;
        std::string name;
        std::string description;
        bool rare = false;
        uint32 item = 0;
        uint32 cost = 0;
        uint32 sockets = 0;
        uint32 minSkill = 0;
        float chance = 100.0f;
    };

    // One dig site a character holds, with the find currently hidden in it.
    struct ActiveSite
    {
        uint32 site = 0;
        uint32 finds = 0;            // finds dug here so far; Archaeology.FindsPerSite = dug out
        int32 spot = -1;             // index into Site::spots of the hidden find, -1 = none yet
    };

    struct RaceProgress
    {
        uint32 fragments = 0;
        uint32 project = 0;          // current project id, 0 = none rolled yet
    };

    // The Unearthed Relic. The real state is here (mod_archaeology_char_relic); the item a player
    // holds is only a projection of it, picked from the ladder in mod_archaeology_relic_*.
    struct RelicState
    {
        uint8 form = 0;              // mod_archaeology_relic_form id, 0 = not chosen yet
        uint8 rank = 0;              // 0 = no relic yet; rank r can show ladder step r - 1
        uint32 power = 0;            // Relic Power not spent on ranks yet
        uint32 earned = 0;           // all Relic Power ever earned
        uint32 traits = 0;           // awake trait bits: 1 << race id
        uint32 complete = 0;         // races with every project solved (not stored: worked out on load)
        uint32 formChanges = 0;
        ObjectGuid::LowType mainItem = 0;   // the relic's item guid
        ObjectGuid::LowType offItem = 0;    // its off-hand half or shield
    };

    struct RelicStep
    {
        uint8 era = 0;               // 0 vanilla, 1 Burning Crusade, 2 Wrath of the Lich King
        uint8 level = 0;             // required level
        uint32 itemLevel = 0;
        uint8 quality = 0;
        uint32 state = 0;            // progression state that opens this rank
        uint32 cost = 0;             // Relic Power to reach this rank
        uint8 gate = 0;              // 1 last rank of its era, 2 awakened
    };

    enum RelicNeed : uint8 { RELIC_NEED_NONE, RELIC_NEED_DUAL_WIELD, RELIC_NEED_TITANS_GRIP };

    struct RelicForm
    {
        uint8 id = 0;
        std::string name;
        uint32 classes = 0;
        uint8 need = RELIC_NEED_NONE;
        std::vector<std::pair<uint32, uint32>> items;   // by step: main item, off item (0 = none)
    };

    struct CharState
    {
        uint32 skill = 0;            // 0 = not learned
        uint32 maxSkill = 0;
        std::array<std::vector<ActiveSite>, CONTINENTS.size()> sites;
        std::unordered_map<uint8, RaceProgress> races;
        std::unordered_map<uint32, uint32> solved;   // project id -> times solved
        uint32 shovelCheckMs = 0;
        bool overFind = false;       // last O: sent to the addon
        uint32 digMs = 0;            // a dig in progress: time left
        float digX = 0.0f, digY = 0.0f;
        uint32 lastSurveyMs = 0;
        uint32 abandonUntil = 0;
        uint32 excludedSite = 0; // transient replacement exclusion
        uint32 innkeeperWaitMs = 0; // transient: summon only after hearth transfer completes
        uint32 digOrderSite = 0;     // the dig site the Dig Orders of digOrderDay name, 0 = none
        uint32 digOrderDay = 0;      // daily reset time those orders belong to
        uint32 digCacheDay = 0;      // daily reset time of the last fragment cache: one a day
        ObjectGuid digCacheGuid;     // the unopened cache, if any
        uint8 digCacheRace = 0;
        uint32 questSweepMs = 0;     // non-archaeologists: time since archaeologist-only quests were last swept
        RelicState relic;
    };

    Config const& GetConfig();
    void LoadConfig();
    // A dug-out site keeps its slot, hidden, until the other sites you hold in its zone are dug too.
    inline bool DugOut(ActiveSite const& a) { return a.finds >= GetConfig().findsPerSite; }
    void LoadWorldData();

    Race const* GetRace(uint8 id);
    std::vector<Race> const& AllRaces();
    Site const* GetSite(uint32 id);
    Project const* GetProject(uint32 id);
    std::vector<uint32> const& ProjectsOfRace(uint8 race);

    // Character state: loaded on login, written through on every change, dropped on logout.
    CharState* GetState(Player* player);
    void LoadCharacter(Player* player);
    void UnloadCharacter(Player* player);
    void SaveSkill(Player* player);
    void SaveSites(Player* player, uint32 continent, bool persistAbandonCooldown = false);
    void SaveRace(Player* player, uint8 race);
    void SaveSolved(Player* player, uint32 project);

    bool IsLearned(Player* player);
    void Learn(Player* player, uint32 maxSkill);
    void AddSkill(Player* player, uint32 amount);
    void LearnRankSpell(Player* player, uint32 step);
    uint32 IpState(Player* player);
    bool CanDigContinent(Player* player, uint32 continentIndex);
    void RollSites(Player* player, uint32 deferredContinent = CONTINENTS.size());
    bool AbandonSite(Player* player, uint32 site, std::string& error);
    void SendCollection(Player* player);
    void SendTraits(Player* player);
    void PickProject(Player* player, uint8 race);
    bool IsRaceUnlocked(Player* player, Race const& race);

    // Dig loop.
    void Survey(Player* player);
    void Dig(Player* player);
    void UpdateFindShovel(Player* player, uint32 diff);
    void UpdateRewardCosmetics(Player* player, uint32 diff);
    void ForgetFinds(Player* player);
    bool Solve(Player* player, uint8 race, uint32 keystones, std::string& error);

    // Addon wire format, both directions: an addon whisper to yourself, "ARCH\t<COMMAND>:...".
    void SendAddon(Player* player, std::string const& payload);
    void SendState(Player* player);
    void SendSites(Player* player);
    void SendRaces(Player* player);
    void SendProject(Player* player, uint32 projectId);
    void Notify(Player* player, std::string const& text);

    // The Unearthed Relic (ArchaeologyRelic.cpp).
    constexpr uint32 RELIC_QUEST = 9503500;
    // Relic achievements (achievement_dbc, written by tools/build_patch.py).
    enum RelicAchievement : uint32
    {
        ACHIEVEMENT_WEAPON_IN_PIECES = 9240,   // the relic quest
        ACHIEVEMENT_TEMPERED = 9241,           // last rank of the old world
        ACHIEVEMENT_LEGEND = 9242,             // last rank of Outland (Legendary)
        ACHIEVEMENT_EVERY_VOICE = 9243,        // every trait awake
        ACHIEVEMENT_KEEPER = 9244,             // every project of every race solved
        ACHIEVEMENT_AWAKENED = 9245,           // the awakened rank (Artifact)
    };
    void LoadRelicData();
    void LoadRelic(Player* player, CharState& state);
    void SaveRelic(Player* player);
    void AddRelicPower(Player* player, uint32 amount);
    void QueueRelic(Player* player);      // re-check rank and item when it is safe to swap
    void UpdateQueuedRelic(Player* player);
    void ForgetRelic(Player* player);
    bool IsRelicItem(uint32 entry);
    bool CanTakeRelicQuest(Player* player);
    void RelicSkillChanged(Player* player);
    void SendRelic(Player* player);
    std::string RelicStatusText(Player* player);
    // Trainer: gossip options, their actions, and the relic quest's reward.
    void AddRelicGossip(Player* player);
    bool RelicGossipSelect(Player* player, Creature* creature, uint32 sender, uint32 action);
    void RelicQuestRewarded(Player* player, Creature* creature);
    bool IsCapstoneQuest(uint32 questId);
    bool CapstoneQuestOpen(Player* player, uint32 questId);   // progression reached its rank's state
    void CapstoneBossDied(Creature* boss);
    void CheckRelicAchievements(Player* player);
    uint32 RelicShownStep(Player* player);   // ladder step the relic shows, 0 without one
    uint32 RelicRankCount();
    bool IsRelicEquipped(Player* player);

    // Relic traits (ArchaeologyTraits.cpp): one per race, server-side auras while the relic is equipped.
    void LoadTraitData();
    bool IsRaceComplete(CharState const& state, uint8 race);
    void UpdateTraitWake(Player* player, bool announce);   // wake the traits that have earned it
    void QueueTraits(Player* player);         // re-check the trait auras on the next update
    void UpdateQueuedTraits(Player* player);
    void ForgetTraits(Player* player);
    std::string TraitStatusText(Player* player);

    // Dig Orders (ArchaeologyDigOrders.cpp): a daily quest from the trainer to dig up one of your
    // own dig sites; the last find of the order uncovers a fragment cache.
    constexpr uint32 DIG_ORDERS_QUEST = 9503504;
    constexpr uint32 DIG_ORDERS_CREDIT = 9503513;   // kill credit, one per find at the ordered site
    constexpr uint32 DIG_ORDERS_CACHE = 9503520;    // gameobject
    bool OffersDigOrders(Player* player);
    void LoadDigOrders(Player* player, CharState& state);
    void DigOrdersAccepted(Player* player);
    void DigOrdersDropped(Player* player);         // abandoned
    void DigOrdersRewarded(Player* player);
    void CheckDigOrders(Player* player);           // name another site if the ordered one is gone
    void DigOrdersFind(Player* player, uint32 site, bool depleted, Position const& where);
    bool UseDigOrdersCache(Player* player, GameObject* go);
    void SendDigOrders(Player* player);
    std::string DigOrdersText(Player* player);
}

#endif
