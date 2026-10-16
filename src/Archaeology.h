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

class Player;
class GameObject;

namespace Archaeology
{
    constexpr char const* PREFIX = "ARCH";

    // Continents dig sites roll on, in slot order.
    constexpr std::array<uint32, 4> CONTINENTS = { 0, 1, 530, 571 };

    enum SurveyBand : uint8 { BAND_RED, BAND_YELLOW, BAND_GREEN, BAND_FOUND };

    struct Config
    {
        bool enabled = true;
        uint32 sitesPerContinent = 4;
        uint32 findsPerSite = 3;
        uint32 fragmentsMin = 5;
        uint32 fragmentsMax = 9;
        uint32 fragmentCap = 200;
        float keystoneChance = 12.0f;
        uint32 keystoneValue = 12;
        float redYards = 100.0f;
        float yellowYards = 50.0f;
        float digYards = 8.0f;
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
        uint32 telescopeEntry = 9503400;
        uint32 telescopeSeconds = 6;
        uint32 findSeconds = 180;
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
        uint32 finds = 0;            // finds dug here so far
        int32 spot = -1;             // index into Site::spots of the hidden find, -1 = none yet
    };

    struct RaceProgress
    {
        uint32 fragments = 0;
        uint32 project = 0;          // current project id, 0 = none rolled yet
    };

    struct CharState
    {
        uint32 skill = 0;            // 0 = not learned
        uint32 maxSkill = 0;
        std::array<std::vector<ActiveSite>, CONTINENTS.size()> sites;
        std::unordered_map<uint8, RaceProgress> races;
        std::unordered_map<uint32, uint32> solved;   // project id -> times solved
        uint32 lastSurveyMs = 0;
    };

    Config const& GetConfig();
    void LoadConfig();
    void LoadWorldData();

    Race const* GetRace(uint8 id);
    std::vector<Race> const& AllRaces();
    Site const* GetSite(uint32 id);
    Project const* GetProject(uint32 id);

    // Character state: loaded on login, written through on every change, dropped on logout.
    CharState* GetState(Player* player);
    void LoadCharacter(Player* player);
    void UnloadCharacter(Player* player);
    void SaveSkill(Player* player);
    void SaveSites(Player* player, uint32 continent);
    void SaveRace(Player* player, uint8 race);
    void SaveSolved(Player* player, uint32 project);

    bool IsLearned(Player* player);
    void Learn(Player* player, uint32 maxSkill);
    void AddSkill(Player* player, uint32 amount);
    uint32 IpState(Player* player);
    bool CanDigContinent(Player* player, uint32 continentIndex);
    void RollSites(Player* player);
    void PickProject(Player* player, uint8 race);
    bool IsRaceUnlocked(Player* player, Race const& race);

    // Dig loop.
    void Survey(Player* player);
    bool UseFind(Player* player, GameObject* go);
    void ForgetFinds(Player* player);
    bool Solve(Player* player, uint8 race, uint32 keystones, std::string& error);

    // Addon wire format, both directions: an addon whisper to yourself, "ARCH\t<COMMAND>:...".
    void SendAddon(Player* player, std::string const& payload);
    void SendState(Player* player);
    void SendSites(Player* player);
    void SendRaces(Player* player);
    void SendProject(Player* player, uint32 projectId);
    void Notify(Player* player, std::string const& text);
}

#endif
