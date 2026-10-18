/*
 * mod-archaeology: ArchaeologyUI addon messages, the .arch command, the trainer and the
 * player/world hooks that load and drop state.
 *
 * Addon wire format, both directions: an addon whisper to yourself, "ARCH\t<COMMAND>[:...]".
 *   client -> server  HELLO, SITES, RACES, PROJ:<id>, SURVEY, SOLVE:<race>:<keystones>
 *   server -> client  S:<skill>:<max skill>               skill (0 = not learned)
 *                     R:<race>,<name>,<fragments>,<cap>,<project>,<cost>,<sockets>,<rare>,<keystones owned>,<unlocked>;...  REND
 *                     T:<site>,<map>,<race>,<finds left>,<name>;...  TEND   your dig sites
 *                     G:<site>:<x>,<y>;<x>,<y>;...                    a site's outline (world coordinates)
 *                     P:<id>:<race>:<rare>:<cost>:<sockets>:<item>:<name>   D:<id>:<text> ...  DEND:<id>
 *                     V:RED|YELLOW|GREEN:<angle> | V:FOUND | V:NONE   survey result
 *                     F:<race>:<gained>:<total>                       fragments looted
 *                     X:<project>:<item>:<rare>                       project solved
 *                     L:<rank>:<ranks>:<power>:<next cost>:<item level>:<quality>:<form>:<note>   the relic
 *
 * Released under the MIT License.
 */

#include "Archaeology.h"
#include "Chat.h"
#include "ChatCommand.h"
#include "Creature.h"
#include "DatabaseEnv.h"
#include "GameTime.h"
#include "Item.h"
#include "Player.h"
#include "QuestDef.h"
#include "ScriptMgr.h"
#include "ScriptedGossip.h"
#include "Tokenize.h"
#include "WorldPacket.h"
#include "WorldSession.h"
#include <algorithm>

using namespace Acore::ChatCommands;
using namespace Archaeology;

namespace
{
    constexpr std::size_t MAX_PAYLOAD = 240;
    constexpr Milliseconds REQUEST_COOLDOWN = 1s;
    constexpr uint32 TRAINER_TEXT = 9503500;

    enum Request : uint8 { REQUEST_HELLO, REQUEST_SITES, REQUEST_RACES, REQUEST_PROJ, REQUEST_SOLVE, REQUEST_COUNT };
    std::unordered_map<ObjectGuid::LowType, std::array<Milliseconds, REQUEST_COUNT>> lastRequest;

    bool Throttled(Player* player, Request request)
    {
        Milliseconds now = GameTime::GetGameTimeMS();
        Milliseconds& last = lastRequest[player->GetGUID().GetCounter()][request];
        if (last.count() && now - last < REQUEST_COOLDOWN)
            return true;
        last = now;
        return false;
    }

    // Names go inside comma and semicolon separated rows.
    std::string Clean(std::string s)
    {
        std::replace(s.begin(), s.end(), ',', ' ');
        std::replace(s.begin(), s.end(), ';', ' ');
        std::replace(s.begin(), s.end(), ':', ' ');
        return s;
    }

    void SendRows(Player* player, std::string const& header, std::vector<std::string> const& rows, std::string const& end)
    {
        std::string line;
        std::size_t const budget = MAX_PAYLOAD - header.size() - 1;
        for (std::string const& row : rows)
        {
            if (!line.empty() && line.size() + 1 + row.size() > budget)
            {
                SendAddon(player, header + ":" + line);
                line.clear();
            }
            if (!line.empty())
                line += ';';
            line += row;
        }
        if (!line.empty())
            SendAddon(player, header + ":" + line);
        if (!end.empty())
            SendAddon(player, end);
    }

    // Trainer ranks: max skill granted, skill needed, character level needed (Cataclysm values).
    struct Rank { uint32 max; uint32 skill; uint32 level; char const* name; };
    constexpr Rank RANKS[] = {
        { 75, 0, 0, "Apprentice" }, { 150, 50, 20, "Journeyman" }, { 225, 125, 20, "Expert" },
        { 300, 200, 35, "Artisan" }, { 375, 275, 50, "Master" }, { 450, 350, 65, "Grand Master" },
    };

    Rank const* NextRank(Player* player)
    {
        CharState* s = GetState(player);
        uint32 have = s ? s->maxSkill : 0;
        for (Rank const& r : RANKS)
            if (r.max > have && r.max <= GetConfig().maxSkill)
                return &r;
        return nullptr;
    }

    bool CanTrain(Player* player, Rank const& rank)
    {
        CharState* s = GetState(player);
        uint32 level = std::max(rank.level, GetConfig().minLevel);
        return s && (s->skill >= rank.skill || (rank.skill == 0 && !s->skill)) && player->GetLevel() >= level;
    }

    std::string StatusText(Player* player)
    {
        CharState* s = GetState(player);
        if (!s || !s->skill)
            return "You don't know Archaeology. Find an archaeology trainer to learn it.";
        std::string text = Acore::StringFormat("Archaeology {}/{}.", s->skill, s->maxSkill);
        for (Race const& race : AllRaces())
        {
            if (!IsRaceUnlocked(player, race))
                continue;
            RaceProgress const& r = s->races[race.id];
            Project const* p = GetProject(r.project);
            text += Acore::StringFormat("\n  {}: {} fragments{}", race.name, r.fragments,
                p ? Acore::StringFormat(", project {}{} ({})", p->name, p->rare ? " [rare]" : "", p->cost) : "");
        }
        text += "\nDig sites:";
        for (uint32 c = 0; c < CONTINENTS.size(); ++c)
            for (ActiveSite const& a : s->sites[c])
                if (Site const* site = GetSite(a.site))
                    text += Acore::StringFormat("\n  {} ({}, {} of {} finds left)", site->name, GetRace(site->race)->name,
                        GetConfig().findsPerSite - a.finds, GetConfig().findsPerSite);
        return text;
    }
}

namespace Archaeology
{
    void SendAddon(Player* player, std::string const& payload)
    {
        std::string full = std::string(PREFIX) + "\t" + payload;
        WorldPacket data;
        ChatHandler::BuildChatPacket(data, CHAT_MSG_WHISPER, LANG_ADDON, player, player, full);
        player->GetSession()->SendPacket(&data);
    }

    void Notify(Player* player, std::string const& text)
    {
        ChatHandler(player->GetSession()).SendSysMessage(text);
    }

    void SendState(Player* player)
    {
        CharState* s = GetState(player);
        SendAddon(player, Acore::StringFormat("S:{}:{}", s ? s->skill : 0, s ? s->maxSkill : 0));
    }

    void SendRaces(Player* player)
    {
        CharState* s = GetState(player);
        if (!s || !s->skill)
        {
            SendAddon(player, "REND");
            return;
        }
        std::vector<std::string> rows;
        for (Race const& race : AllRaces())
        {
            RaceProgress const& r = s->races[race.id];
            Project const* p = GetProject(r.project);
            rows.push_back(Acore::StringFormat("{},{},{},{},{},{},{},{},{},{}", race.id, Clean(race.name), r.fragments,
                GetConfig().fragmentCap, p ? p->id : 0, p ? p->cost : 0, p ? p->sockets : 0, p && p->rare ? 1 : 0,
                race.keystoneItem ? player->GetItemCount(race.keystoneItem) : 0, IsRaceUnlocked(player, race) ? 1 : 0));
        }
        SendRows(player, "R", rows, "REND");
    }

    void SendSites(Player* player)
    {
        CharState* s = GetState(player);
        if (!s || !s->skill)
        {
            SendAddon(player, "TEND");
            return;
        }
        std::vector<std::string> rows;
        std::vector<Site const*> held;
        for (uint32 c = 0; c < CONTINENTS.size(); ++c)
            for (ActiveSite const& a : s->sites[c])
                if (Site const* site = GetSite(a.site))
                {
                    rows.push_back(Acore::StringFormat("{},{},{},{},{}", site->id, site->map, site->race,
                        GetConfig().findsPerSite - a.finds, Clean(site->name)));
                    held.push_back(site);
                }
        SendRows(player, "T", rows, "");
        for (Site const* site : held)
        {
            std::vector<std::string> points;
            for (Point const& p : site->polygon)
                points.push_back(Acore::StringFormat("{},{}", int32(p.x), int32(p.y)));
            SendRows(player, Acore::StringFormat("G:{}", site->id), points, "");
        }
        SendAddon(player, "TEND");
    }

    void SendProject(Player* player, uint32 projectId)
    {
        Project const* p = GetProject(projectId);
        if (!p)
            return;
        SendAddon(player, Acore::StringFormat("P:{}:{}:{}:{}:{}:{}:{}", p->id, p->race, p->rare ? 1 : 0, p->cost, p->sockets,
            p->item, Clean(p->name)));
        std::string const header = Acore::StringFormat("D:{}:", p->id);
        std::size_t const chunk = MAX_PAYLOAD - header.size();
        for (std::size_t pos = 0; pos < p->description.size(); pos += chunk)
            SendAddon(player, header + p->description.substr(pos, chunk));
        SendAddon(player, Acore::StringFormat("DEND:{}", p->id));
    }
}

class ArchaeologyPlayerScript : public PlayerScript
{
public:
    ArchaeologyPlayerScript() : PlayerScript("ArchaeologyPlayerScript", {
        PLAYERHOOK_ON_LOGIN, PLAYERHOOK_ON_LOGOUT, PLAYERHOOK_ON_DELETE, PLAYERHOOK_ON_LEVEL_CHANGED,
        PLAYERHOOK_CAN_PLAYER_USE_PRIVATE_CHAT, PLAYERHOOK_ON_UPDATE, PLAYERHOOK_ON_MAP_CHANGED, PLAYERHOOK_ON_EQUIP,
        PLAYERHOOK_ON_BEFORE_QUEST_COMPLETE }) { }

    void OnPlayerLogin(Player* player) override
    {
        if (GetConfig().enabled)
            LoadCharacter(player);
    }

    void OnPlayerLogout(Player* player) override
    {
        lastRequest.erase(player->GetGUID().GetCounter());
        ForgetFinds(player);
        ForgetRelic(player);
        UnloadCharacter(player);
    }

    void OnPlayerDelete(ObjectGuid guid, uint32 /*accountId*/) override
    {
        ObjectGuid::LowType low = guid.GetCounter();
        CharacterDatabase.Execute("DELETE FROM `mod_archaeology_char` WHERE `guid` = {}", low);
        CharacterDatabase.Execute("DELETE FROM `mod_archaeology_char_site` WHERE `guid` = {}", low);
        CharacterDatabase.Execute("DELETE FROM `mod_archaeology_char_race` WHERE `guid` = {}", low);
        CharacterDatabase.Execute("DELETE FROM `mod_archaeology_char_history` WHERE `guid` = {}", low);
        CharacterDatabase.Execute("DELETE FROM `mod_archaeology_char_relic` WHERE `guid` = {}", low);
    }

    // Higher levels open more dig sites, and let the relic grow.
    void OnPlayerLevelChanged(Player* player, uint8 /*oldLevel*/) override
    {
        if (IsLearned(player))
        {
            RollSites(player);
            SendSites(player);
            QueueRelic(player);
        }
    }

    // Progression state rises in raids; look again on the way out.
    void OnPlayerMapChanged(Player* player) override
    {
        QueueRelic(player);
    }

    // A relic taken out of the bank may be an older step.
    void OnPlayerEquip(Player* player, Item* item, uint8 /*bag*/, uint8 /*slot*/, bool /*update*/) override
    {
        if (item && IsRelicItem(item->GetEntry()))
            QueueRelic(player);
    }

    void OnPlayerUpdate(Player* player, uint32 /*diff*/) override
    {
        UpdateQueuedRelic(player);
    }

    bool OnPlayerBeforeQuestComplete(Player* player, uint32 questId) override
    {
        return questId != RELIC_QUEST || CanTakeRelicQuest(player);
    }

    // CMSG_MESSAGECHAT runs on the world thread.
    bool OnPlayerCanUseChat(Player* player, uint32 type, uint32 language, std::string& msg, Player* receiver) override
    {
        if (type != CHAT_MSG_WHISPER || language != LANG_ADDON || receiver != player)
            return true;
        std::string const prefixTab = std::string(PREFIX) + "\t";
        if (msg.compare(0, prefixTab.size(), prefixTab) != 0)
            return true;
        if (!GetConfig().enabled || !GetState(player))
            return false;

        std::string_view command = std::string_view(msg).substr(prefixTab.size());
        if (command == "HELLO")
        {
            if (!Throttled(player, REQUEST_HELLO))
            {
                SendState(player);
                SendRaces(player);
                SendSites(player);
                SendRelic(player);
            }
        }
        else if (command == "SITES")
        {
            if (!Throttled(player, REQUEST_SITES))
                SendSites(player);
        }
        else if (command == "RACES")
        {
            if (!Throttled(player, REQUEST_RACES))
                SendRaces(player);
        }
        else if (command == "SURVEY")
            Survey(player);   // has its own cooldown
        else if (command.substr(0, 5) == "PROJ:")
        {
            if (!Throttled(player, REQUEST_PROJ))
                if (Optional<uint32> id = Acore::StringTo<uint32>(command.substr(5)))
                    SendProject(player, *id);
        }
        else if (command.substr(0, 6) == "SOLVE:")
        {
            if (Throttled(player, REQUEST_SOLVE))
                return false;
            std::vector<std::string_view> parts = Acore::Tokenize(command.substr(6), ':', false);
            Optional<uint32> race = parts.size() > 0 ? Acore::StringTo<uint32>(parts[0]) : std::nullopt;
            Optional<uint32> keys = parts.size() > 1 ? Acore::StringTo<uint32>(parts[1]) : std::nullopt;
            std::string error;
            if (race && !Solve(player, uint8(*race), keys.value_or(0), error))
                Notify(player, error);
        }
        return false;
    }
};

class ArchaeologyWorldScript : public WorldScript
{
public:
    ArchaeologyWorldScript() : WorldScript("ArchaeologyWorldScript", { WORLDHOOK_ON_AFTER_CONFIG_LOAD, WORLDHOOK_ON_STARTUP }) { }

    void OnAfterConfigLoad(bool /*reload*/) override
    {
        LoadConfig();
    }

    void OnStartup() override
    {
        LoadWorldData();
    }
};

class npc_archaeology_trainer : public CreatureScript
{
public:
    npc_archaeology_trainer() : CreatureScript("npc_archaeology_trainer") { }

    enum Actions : uint32 { ACTION_TRAIN = 1, ACTION_STATUS = 2 };   // 10-13: the relic's, ArchaeologyRelic.cpp

    // A Weapon in Pieces waits for skill 50, which the quest system can't see.
    static bool OffersRelicQuest(Player* player)
    {
        return player->GetQuestStatus(RELIC_QUEST) != QUEST_STATUS_NONE || CanTakeRelicQuest(player);
    }

    uint32 GetDialogStatus(Player* player, Creature* /*creature*/) override
    {
        return OffersRelicQuest(player) ? DIALOG_STATUS_SCRIPTED_NO_STATUS : DIALOG_STATUS_NONE;
    }

    bool OnQuestReward(Player* player, Creature* creature, Quest const* quest, uint32 /*opt*/) override
    {
        if (quest->GetQuestId() != RELIC_QUEST)
            return false;
        RelicQuestRewarded(player, creature);
        return true;
    }

    bool OnGossipHello(Player* player, Creature* creature) override
    {
        ClearGossipMenuFor(player);
        if (GetConfig().enabled && GetState(player))
        {
            if (OffersRelicQuest(player))
                player->PrepareQuestMenu(creature->GetGUID());
            if (Rank const* rank = NextRank(player))
            {
                if (CanTrain(player, *rank))
                    AddGossipItemFor(player, GOSSIP_ICON_TRAINER, Acore::StringFormat("Train {} Archaeology (skill up to {}).", rank->name, rank->max),
                        GOSSIP_SENDER_MAIN, ACTION_TRAIN);
                else
                    AddGossipItemFor(player, GOSSIP_ICON_CHAT, Acore::StringFormat("{} Archaeology needs skill {} and level {}.", rank->name, rank->skill,
                        std::max(rank->level, GetConfig().minLevel)), GOSSIP_SENDER_MAIN, ACTION_STATUS);
            }
            if (IsLearned(player))
                AddGossipItemFor(player, GOSSIP_ICON_CHAT, "Where are my dig sites?", GOSSIP_SENDER_MAIN, ACTION_STATUS);
            AddRelicGossip(player);
        }
        SendGossipMenuFor(player, TRAINER_TEXT, creature->GetGUID());
        return true;
    }

    bool OnGossipSelect(Player* player, Creature* creature, uint32 sender, uint32 action) override
    {
        if (RelicGossipSelect(player, creature, sender, action))
            return true;
        CloseGossipMenuFor(player);
        if (action == ACTION_TRAIN)
        {
            Rank const* rank = NextRank(player);
            if (rank && CanTrain(player, *rank))
            {
                Learn(player, rank->max);
                creature->Whisper(Acore::StringFormat("You are now a {} archaeologist. Your dig sites are marked on your map.", rank->name),
                    LANG_UNIVERSAL, player);
            }
        }
        else if (action == ACTION_STATUS)
            Notify(player, StatusText(player));
        return true;
    }
};

class ArchaeologyCommandScript : public CommandScript
{
public:
    ArchaeologyCommandScript() : CommandScript("ArchaeologyCommandScript") { }

    ChatCommandTable GetCommands() const override
    {
        static ChatCommandTable relicCommands =
        {
            { "",      HandleRelic,      SEC_PLAYER,     Console::No },
            { "power", HandleRelicPower, SEC_GAMEMASTER, Console::No },
        };
        static ChatCommandTable subCommands =
        {
            { "relic",  relicCommands },
            { "",       HandleStatus, SEC_PLAYER,        Console::No },
            { "survey", HandleSurvey, SEC_PLAYER,        Console::No },
            { "solve",  HandleSolve,  SEC_PLAYER,        Console::No },
            { "skill",  HandleSkill,  SEC_GAMEMASTER,    Console::No },
            { "reload", HandleReload, SEC_ADMINISTRATOR, Console::Yes },
        };
        static ChatCommandTable commandTable =
        {
            { "arch", subCommands },
        };
        return commandTable;
    }

    static bool HandleStatus(ChatHandler* handler)
    {
        handler->SendSysMessage(StatusText(handler->GetPlayer()));
        return true;
    }

    static bool HandleSurvey(ChatHandler* handler)
    {
        Survey(handler->GetPlayer());
        return true;
    }

    // .arch solve <race name or id> [keystones]
    static bool HandleSolve(ChatHandler* handler, std::string raceArg, Optional<uint32> keystones)
    {
        Race const* race = nullptr;
        if (Optional<uint32> id = Acore::StringTo<uint32>(raceArg))
            race = GetRace(uint8(*id));
        else
            for (Race const& r : AllRaces())
                if (StringEqualI(r.name, raceArg) || (r.name.find(' ') != std::string::npos && StringStartsWithI(r.name, raceArg)))
                    race = &r;
        if (!race)
        {
            handler->SendErrorMessage("Unknown race. Use a name such as Dwarf, Troll or Fossil.");
            return false;
        }
        std::string error;
        if (!Solve(handler->GetPlayer(), race->id, keystones.value_or(0), error))
        {
            handler->SendErrorMessage("{}", error);
            return false;
        }
        return true;
    }

    // .arch skill <value>: GM sets the selected player's skill (learns the matching rank).
    static bool HandleSkill(ChatHandler* handler, uint32 value)
    {
        Player* target = handler->getSelectedPlayerOrSelf();
        CharState* s = target ? GetState(target) : nullptr;
        if (!s)
            return false;
        uint32 max = 75;
        for (Rank const& r : RANKS)
            if (r.skill <= value)
                max = r.max;
        Learn(target, std::min(max, GetConfig().maxSkill));
        s->skill = std::min(std::max<uint32>(value, 1), s->maxSkill);
        AddSkill(target, 0);
        SaveSkill(target);
        RollSites(target);
        SendState(target);
        handler->PSendSysMessage("{} now has Archaeology {}/{}.", target->GetName(), s->skill, s->maxSkill);
        return true;
    }

    static bool HandleRelic(ChatHandler* handler)
    {
        handler->SendSysMessage(RelicStatusText(handler->GetPlayer()));
        return true;
    }

    // .arch relic power <amount>: GM gives the selected player Relic Power.
    static bool HandleRelicPower(ChatHandler* handler, uint32 amount)
    {
        Player* target = handler->getSelectedPlayerOrSelf();
        if (!target || !IsLearned(target))
        {
            handler->SendErrorMessage("That character doesn't know Archaeology.");
            return false;
        }
        AddRelicPower(target, amount);
        QueueRelic(target);
        handler->PSendSysMessage("{} gets {} Relic Power.", target->GetName(), amount);
        return true;
    }

    static bool HandleReload(ChatHandler* handler)
    {
        LoadWorldData();
        handler->SendSysMessage("Archaeology data reloaded.");
        return true;
    }
};

void AddArchaeologyAddonScripts()
{
    new ArchaeologyPlayerScript();
    new ArchaeologyWorldScript();
    new npc_archaeology_trainer();
    new ArchaeologyCommandScript();
}
