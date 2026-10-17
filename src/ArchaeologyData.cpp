/*
 * mod-archaeology: config, world data, per-character state, dig-site rolling and project picks.
 *
 * Released under the MIT License.
 */

#include "Archaeology.h"
#include "Config.h"
#include "Containers.h"
#include "DatabaseEnv.h"
#include "DBCStores.h"
#include "Log.h"
#include "Player.h"
#include "Random.h"
#include <algorithm>

namespace
{
    Archaeology::Config config;
    std::vector<Archaeology::Race> races;
    std::unordered_map<uint32, Archaeology::Site> sites;
    std::unordered_map<uint32, std::vector<uint32>> sitesByMap;
    std::unordered_map<uint32, Archaeology::Project> projects;
    std::unordered_map<uint8, std::vector<uint32>> projectsByRace;
    std::unordered_map<ObjectGuid::LowType, Archaeology::CharState> states;
}

namespace Archaeology
{
    Config const& GetConfig() { return config; }

    void LoadConfig()
    {
        Config c;
        c.enabled = sConfigMgr->GetOption<bool>("Archaeology.Enable", true);
        c.sitesPerContinent = std::clamp<uint32>(sConfigMgr->GetOption<uint32>("Archaeology.SitesPerContinent", 4), 1, 8);
        c.findsPerSite = std::max<uint32>(sConfigMgr->GetOption<uint32>("Archaeology.FindsPerSite", 3), 1);
        c.fragmentsMin = sConfigMgr->GetOption<uint32>("Archaeology.FragmentsPerFind.Min", 5);
        c.fragmentsMax = std::max(c.fragmentsMin, sConfigMgr->GetOption<uint32>("Archaeology.FragmentsPerFind.Max", 9));
        c.fragmentCap = sConfigMgr->GetOption<uint32>("Archaeology.FragmentCap", 200);
        c.keystoneChance = sConfigMgr->GetOption<float>("Archaeology.KeystoneChance", 12.0f);
        c.keystoneValue = sConfigMgr->GetOption<uint32>("Archaeology.KeystoneValue", 12);
        c.redYards = sConfigMgr->GetOption<float>("Archaeology.Survey.RedYards", 100.0f);
        c.yellowYards = sConfigMgr->GetOption<float>("Archaeology.Survey.YellowYards", 50.0f);
        c.digYards = sConfigMgr->GetOption<float>("Archaeology.Survey.DigYards", 8.0f);
        c.minSpotYards = sConfigMgr->GetOption<float>("Archaeology.Survey.MinSpotYards", 40.0f);
        c.surveyCooldownMs = sConfigMgr->GetOption<uint32>("Archaeology.Survey.CooldownMs", 3000);
        c.skillPerFindUntil = sConfigMgr->GetOption<uint32>("Archaeology.Skill.FindsUntil", 50);
        c.skillPerCommon = sConfigMgr->GetOption<uint32>("Archaeology.Skill.PerCommon", 5);
        c.skillPerRare = sConfigMgr->GetOption<uint32>("Archaeology.Skill.PerRare", 15);
        c.maxSkill = sConfigMgr->GetOption<uint32>("Archaeology.Skill.Max", 450);
        c.skillLine = sConfigMgr->GetOption<uint32>("Archaeology.Skill.SkillLine", 0);
        c.minLevel = sConfigMgr->GetOption<uint32>("Archaeology.MinLevel", 1);
        c.ipEnabled = sConfigMgr->GetOption<bool>("Archaeology.IndividualProgression.Enable", false);
        c.ipOutlandState = sConfigMgr->GetOption<uint32>("Archaeology.IndividualProgression.OutlandState", 8);
        c.ipNorthrendState = sConfigMgr->GetOption<uint32>("Archaeology.IndividualProgression.NorthrendState", 13);
        c.ipQuestBase = sConfigMgr->GetOption<uint32>("Archaeology.IndividualProgression.QuestBase", 66000);
        c.ipMaxState = sConfigMgr->GetOption<uint32>("Archaeology.IndividualProgression.MaxState", 18);
        c.telescopeEntry[BAND_RED] = sConfigMgr->GetOption<uint32>("Archaeology.Telescope.Red", 9503502);
        c.telescopeEntry[BAND_YELLOW] = sConfigMgr->GetOption<uint32>("Archaeology.Telescope.Yellow", 9503501);
        c.telescopeEntry[BAND_GREEN] = sConfigMgr->GetOption<uint32>("Archaeology.Telescope.Green", 9503500);
        c.telescopeSeconds = sConfigMgr->GetOption<uint32>("Archaeology.Telescope.Seconds", 6);
        c.findSeconds = sConfigMgr->GetOption<uint32>("Archaeology.Find.Seconds", 180);
        config = c;
    }

    void LoadWorldData()
    {
        races.clear();
        sites.clear();
        sitesByMap.clear();
        projects.clear();
        projectsByRace.clear();

        if (QueryResult result = WorldDatabase.Query("SELECT `id`, `name`, `keystone_item`, `unlock_skill`, `find_go` FROM `mod_archaeology_race` ORDER BY `id`"))
        {
            do
            {
                Field* f = result->Fetch();
                Race r;
                r.id = f[0].Get<uint8>();
                r.name = f[1].Get<std::string>();
                r.keystoneItem = f[2].Get<uint32>();
                r.unlockSkill = f[3].Get<uint32>();
                r.findGo = f[4].Get<uint32>();
                races.push_back(r);
            } while (result->NextRow());
        }

        if (QueryResult result = WorldDatabase.Query("SELECT `id`, `map`, `race`, `name`, `min_skill`, `min_level` FROM `mod_archaeology_site` WHERE `enabled` = 1"))
        {
            do
            {
                Field* f = result->Fetch();
                Site s;
                s.id = f[0].Get<uint32>();
                s.map = f[1].Get<uint32>();
                s.race = f[2].Get<uint8>();
                s.name = f[3].Get<std::string>();
                s.minSkill = f[4].Get<uint32>();
                s.minLevel = f[5].Get<uint32>();
                sites[s.id] = s;
            } while (result->NextRow());
        }

        if (QueryResult result = WorldDatabase.Query("SELECT `site`, `x`, `y` FROM `mod_archaeology_site_point` ORDER BY `site`, `idx`"))
        {
            do
            {
                Field* f = result->Fetch();
                auto itr = sites.find(f[0].Get<uint32>());
                if (itr != sites.end())
                    itr->second.polygon.push_back({ f[1].Get<float>(), f[2].Get<float>() });
            } while (result->NextRow());
        }

        if (QueryResult result = WorldDatabase.Query("SELECT `site`, `x`, `y`, `z` FROM `mod_archaeology_site_spawn` ORDER BY `site`, `idx`"))
        {
            do
            {
                Field* f = result->Fetch();
                auto itr = sites.find(f[0].Get<uint32>());
                if (itr != sites.end())
                    itr->second.spots.push_back({ f[1].Get<float>(), f[2].Get<float>(), f[3].Get<float>() });
            } while (result->NextRow());
        }

        for (auto itr = sites.begin(); itr != sites.end();)
        {
            Site& s = itr->second;
            if (s.polygon.size() < 3 || s.spots.empty() || !GetRace(s.race))
            {
                itr = sites.erase(itr);
                continue;
            }
            for (Point const& p : s.polygon)
            {
                s.center.x += p.x / s.polygon.size();
                s.center.y += p.y / s.polygon.size();
            }
            sitesByMap[s.map].push_back(s.id);
            ++itr;
        }

        if (QueryResult result = WorldDatabase.Query("SELECT `id`, `race`, `name`, `description`, `rare`, `item`, `cost`, `sockets`, `min_skill`, `chance` FROM `mod_archaeology_project` WHERE `enabled` = 1"))
        {
            do
            {
                Field* f = result->Fetch();
                Project p;
                p.id = f[0].Get<uint32>();
                p.race = f[1].Get<uint8>();
                p.name = f[2].Get<std::string>();
                p.description = f[3].Get<std::string>();
                p.rare = f[4].Get<bool>();
                p.item = f[5].Get<uint32>();
                p.cost = f[6].Get<uint32>();
                p.sockets = f[7].Get<uint32>();
                p.minSkill = f[8].Get<uint32>();
                p.chance = f[9].Get<float>();
                projects[p.id] = p;
                projectsByRace[p.race].push_back(p.id);
            } while (result->NextRow());
        }

        LOG_INFO("module", "mod-archaeology: {} races, {} dig sites, {} projects", races.size(), sites.size(), projects.size());
    }

    Race const* GetRace(uint8 id)
    {
        for (Race const& r : races)
            if (r.id == id)
                return &r;
        return nullptr;
    }

    std::vector<Race> const& AllRaces() { return races; }

    Site const* GetSite(uint32 id)
    {
        auto itr = sites.find(id);
        return itr != sites.end() ? &itr->second : nullptr;
    }

    Project const* GetProject(uint32 id)
    {
        auto itr = projects.find(id);
        return itr != projects.end() ? &itr->second : nullptr;
    }

    CharState* GetState(Player* player)
    {
        auto itr = states.find(player->GetGUID().GetCounter());
        return itr != states.end() ? &itr->second : nullptr;
    }

    void LoadCharacter(Player* player)
    {
        ObjectGuid::LowType guid = player->GetGUID().GetCounter();
        CharState& s = states[guid];
        s = CharState();

        // Most characters never learn archaeology; one query and done for them.
        QueryResult skill = CharacterDatabase.Query("SELECT `skill`, `max_skill` FROM `mod_archaeology_char` WHERE `guid` = {}", guid);
        if (!skill)
            return;
        s.skill = skill->Fetch()[0].Get<uint32>();
        s.maxSkill = skill->Fetch()[1].Get<uint32>();

        if (QueryResult result = CharacterDatabase.Query("SELECT `continent`, `site`, `finds` FROM `mod_archaeology_char_site` WHERE `guid` = {} ORDER BY `continent`, `slot`", guid))
        {
            do
            {
                Field* f = result->Fetch();
                uint32 continent = f[0].Get<uint32>();
                uint32 siteId = f[1].Get<uint32>();
                if (continent < CONTINENTS.size() && GetSite(siteId))
                    s.sites[continent].push_back({ siteId, f[2].Get<uint32>(), -1 });
            } while (result->NextRow());
        }

        if (QueryResult result = CharacterDatabase.Query("SELECT `race`, `fragments`, `project` FROM `mod_archaeology_char_race` WHERE `guid` = {}", guid))
        {
            do
            {
                Field* f = result->Fetch();
                RaceProgress& r = s.races[f[0].Get<uint8>()];
                r.fragments = f[1].Get<uint32>();
                r.project = GetProject(f[2].Get<uint32>()) ? f[2].Get<uint32>() : 0;
            } while (result->NextRow());
        }

        if (QueryResult result = CharacterDatabase.Query("SELECT `project`, `solved` FROM `mod_archaeology_char_history` WHERE `guid` = {}", guid))
        {
            do
            {
                Field* f = result->Fetch();
                s.solved[f[0].Get<uint32>()] = f[1].Get<uint32>();
            } while (result->NextRow());
        }

        if (s.skill)
        {
            AddSkill(player, 0);   // re-mirror to the skill line, if one is configured
            RollSites(player);
            for (Race const& race : races)
                if (IsRaceUnlocked(player, race) && !s.races[race.id].project)
                    PickProject(player, race.id);
        }
    }

    void UnloadCharacter(Player* player)
    {
        states.erase(player->GetGUID().GetCounter());
    }

    void SaveSkill(Player* player)
    {
        CharState* s = GetState(player);
        if (!s)
            return;
        CharacterDatabase.Execute("REPLACE INTO `mod_archaeology_char` (`guid`, `skill`, `max_skill`) VALUES ({}, {}, {})",
            player->GetGUID().GetCounter(), s->skill, s->maxSkill);
    }

    void SaveSites(Player* player, uint32 continent)
    {
        CharState* s = GetState(player);
        if (!s || continent >= CONTINENTS.size())
            return;
        ObjectGuid::LowType guid = player->GetGUID().GetCounter();
        CharacterDatabaseTransaction trans = CharacterDatabase.BeginTransaction();
        trans->Append("DELETE FROM `mod_archaeology_char_site` WHERE `guid` = {} AND `continent` = {}", guid, continent);
        uint32 slot = 0;
        for (ActiveSite const& a : s->sites[continent])
            trans->Append("INSERT INTO `mod_archaeology_char_site` (`guid`, `continent`, `slot`, `site`, `finds`) VALUES ({}, {}, {}, {}, {})",
                guid, continent, slot++, a.site, a.finds);
        CharacterDatabase.CommitTransaction(trans);
    }

    void SaveRace(Player* player, uint8 race)
    {
        CharState* s = GetState(player);
        if (!s)
            return;
        RaceProgress const& r = s->races[race];
        CharacterDatabase.Execute("REPLACE INTO `mod_archaeology_char_race` (`guid`, `race`, `fragments`, `project`) VALUES ({}, {}, {}, {})",
            player->GetGUID().GetCounter(), race, r.fragments, r.project);
    }

    void SaveSolved(Player* player, uint32 project)
    {
        CharState* s = GetState(player);
        if (!s)
            return;
        CharacterDatabase.Execute("INSERT INTO `mod_archaeology_char_history` (`guid`, `project`, `solved`, `first_solved`) VALUES ({}, {}, {}, UNIX_TIMESTAMP()) "
            "ON DUPLICATE KEY UPDATE `solved` = VALUES(`solved`)", player->GetGUID().GetCounter(), project, s->solved[project]);
    }

    bool IsLearned(Player* player)
    {
        CharState* s = GetState(player);
        return s && s->skill > 0;
    }

    void Learn(Player* player, uint32 maxSkill)
    {
        CharState* s = GetState(player);
        if (!s)
            return;
        bool first = !s->skill;
        s->skill = std::max<uint32>(s->skill, 1);
        s->maxSkill = std::min(std::max(s->maxSkill, maxSkill), config.maxSkill);
        SaveSkill(player);
        AddSkill(player, 0);
        if (first)
        {
            RollSites(player);
            for (Race const& race : races)
                if (IsRaceUnlocked(player, race) && !s->races[race.id].project)
                    PickProject(player, race.id);
        }
        SendState(player);
        SendRaces(player);
        SendSites(player);
    }

    void AddSkill(Player* player, uint32 amount)
    {
        CharState* s = GetState(player);
        if (!s || !s->skill)
            return;
        uint32 before = s->skill;
        s->skill = std::min(s->skill + amount, s->maxSkill);
        if (s->skill != before)
        {
            SaveSkill(player);
            Notify(player, Acore::StringFormat("Your skill in Archaeology has increased to {}.", s->skill));
            // New races or continents may have opened up.
            RollSites(player);
            for (Race const& race : races)
                if (IsRaceUnlocked(player, race) && !s->races[race.id].project)
                    PickProject(player, race.id);
            SendState(player);
        }
        if (config.skillLine && sSkillLineStore.LookupEntry(config.skillLine))
            player->SetSkill(config.skillLine, std::max<uint32>(s->maxSkill / 75, 1), s->skill, s->maxSkill);
    }

    uint32 IpState(Player* player)
    {
        for (uint32 state = config.ipMaxState; state > 0; --state)
            if (player->GetQuestRewardStatus(config.ipQuestBase + state))
                return state;
        return 0;
    }

    bool CanDigContinent(Player* player, uint32 continentIndex)
    {
        if (!config.ipEnabled)
            return true;
        uint32 map = CONTINENTS[continentIndex];
        if (map == 530)
            return IpState(player) >= config.ipOutlandState;
        if (map == 571)
            return IpState(player) >= config.ipNorthrendState;
        return true;
    }

    bool IsRaceUnlocked(Player* player, Race const& race)
    {
        CharState* s = GetState(player);
        return s && s->skill && s->skill >= race.unlockSkill;
    }

    void RollSites(Player* player)
    {
        CharState* s = GetState(player);
        if (!s || !s->skill)
            return;

        for (uint32 c = 0; c < CONTINENTS.size(); ++c)
        {
            if (!CanDigContinent(player, c))
                continue;
            std::vector<ActiveSite>& held = s->sites[c];
            if (held.size() >= config.sitesPerContinent)
                continue;

            std::vector<uint32> pool;
            std::vector<double> weights;
            for (uint32 id : sitesByMap[CONTINENTS[c]])
            {
                Site const& site = sites[id];
                if (site.minSkill > s->skill || site.minLevel > player->GetLevel())
                    continue;
                if (std::any_of(held.begin(), held.end(), [id](ActiveSite const& a) { return a.site == id; }))
                    continue;
                // Races whose rares are all solved come up less often (Cataclysm 4.1).
                bool raresLeft = false;
                for (uint32 pid : projectsByRace[site.race])
                    if (projects[pid].rare && !s->solved.count(pid))
                        raresLeft = true;
                pool.push_back(id);
                weights.push_back(raresLeft ? 4.0 : 1.0);
            }

            bool changed = false;
            while (held.size() < config.sitesPerContinent && !pool.empty())
            {
                std::size_t pick = Acore::Containers::SelectRandomWeightedContainerElement(pool, weights) - pool.begin();
                held.push_back({ pool[pick], 0, -1 });
                pool.erase(pool.begin() + pick);
                weights.erase(weights.begin() + pick);
                changed = true;
            }
            if (changed)
                SaveSites(player, c);
        }
    }

    void PickProject(Player* player, uint8 race)
    {
        CharState* s = GetState(player);
        if (!s)
            return;
        RaceProgress& progress = s->races[race];
        uint32 current = progress.project;

        std::vector<uint32> commons;
        for (uint32 pid : projectsByRace[race])
        {
            Project const& p = projects[pid];
            if (p.id == current || p.minSkill > s->skill)
                continue;
            if (p.rare)
            {
                if (!s->solved.count(pid) && roll_chance_f(p.chance))
                {
                    progress.project = pid;
                    SaveRace(player, race);
                    return;
                }
                continue;
            }
            commons.push_back(pid);
        }

        // Prefer commons this character has never solved, as the Cataclysm collection did.
        std::vector<uint32> fresh;
        for (uint32 pid : commons)
            if (!s->solved.count(pid))
                fresh.push_back(pid);
        std::vector<uint32> const& from = fresh.empty() ? commons : fresh;
        progress.project = from.empty() ? current : Acore::Containers::SelectRandomContainerElement(from);
        SaveRace(player, race);
    }
}
