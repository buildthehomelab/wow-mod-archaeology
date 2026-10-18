/*
 * mod-archaeology: the Unearthed Relic, one weapon (or a pair) per character that grows as it digs.
 *
 * Relic Power from finds and solves buys ranks. Each rank can show one more step of a generated
 * item ladder (mod_archaeology_relic_*), but the character's level and progression state decide
 * how far up the ladder the item it holds may be. The state lives in mod_archaeology_char_relic;
 * the item is swapped for the right step whenever that changes, keeping its enchants and gems.
 *
 * Released under the MIT License.
 */

#include "Archaeology.h"
#include "Bag.h"
#include "Chat.h"
#include "Creature.h"
#include "DatabaseEnv.h"
#include "DBCStores.h"
#include "Group.h"
#include "Item.h"
#include "Log.h"
#include "ObjectMgr.h"
#include "Player.h"
#include "QuestDef.h"
#include "Map.h"
#include "ScriptedGossip.h"
#include <algorithm>
#include <atomic>
#include <functional>
#include <mutex>
#include <unordered_set>

namespace
{
    using namespace Archaeology;

    constexpr uint32 FORM_TEXT = 9503501;
    constexpr uint32 SENDER_FORM = 2;
    constexpr char const* ERA_NAMES[3] = { "old world", "Outland", "Northrend" };
    constexpr char const* QUALITY_NAMES[7] = { "Poor", "Common", "Uncommon", "Rare", "Epic", "Legendary", "Artifact" };

    // The boss each era's capstone quest is about. Kel'Thuzad counts in Naxxramas at 40 (individual
    // progression's 351019) and at level 80 (15990): a character that missed the 40-man version
    // before individual progression closes it can still finish the old world's ranks.
    struct CapstoneBoss { uint32 entry; uint8 era; };
    constexpr CapstoneBoss CAPSTONE_BOSSES[] = { { 351019, 0 }, { 15990, 0 }, { 25315, 1 }, { 36597, 2 } };
    constexpr uint32 CAPSTONE_QUESTS[3] = { 9503501, 9503502, 9503503 };   // the module's own, by era

    std::vector<RelicStep> steps;
    std::vector<RelicForm> forms;
    std::unordered_set<uint32> mainItems;
    std::unordered_set<uint32> offItems;
    // Characters whose relic needs a look. Player updates run on several map threads at once.
    std::mutex queueLock;
    std::unordered_set<ObjectGuid> queued;
    std::atomic<uint32> queuedCount { 0 };

    RelicForm* GetForm(uint8 id)
    {
        for (RelicForm& f : forms)
            if (f.id == id)
                return &f;
        return nullptr;
    }

    uint32 RankCount() { return uint32(steps.size()); }

    uint32 RankCost(uint32 rank)
    {
        return rank >= 1 && rank <= steps.size() ? uint32(steps[rank - 1].cost * GetConfig().relicCostRate) : 0;
    }

    uint32 ProgressionState(Player* player)
    {
        return GetConfig().ipEnabled ? IpState(player) : GetConfig().relicStateWithoutIp;
    }

    uint8 RaceEra(Race const& race)
    {
        return race.unlockSkill >= 375 ? 2 : race.unlockSkill >= 300 ? 1 : 0;
    }

    // Rares of an era's races this character has not solved yet.
    uint32 RaresLeft(CharState const& s, uint8 era)
    {
        uint32 left = 0;
        for (Race const& race : AllRaces())
            if (RaceEra(race) == era)
                for (uint32 pid : ProjectsOfRace(race.id))
                    if (GetProject(pid)->rare && !s.solved.count(pid))
                        ++left;
        return left;
    }

    uint32 ProjectsLeft(CharState const& s)
    {
        uint32 left = 0;
        for (Race const& race : AllRaces())
            for (uint32 pid : ProjectsOfRace(race.id))
                if (!s.solved.count(pid))
                    ++left;
        return left;
    }

    // Why the character can't take rank `rank` yet, or "" when it can (Relic Power aside).
    std::string RankBlocked(Player* player, CharState const& s, uint32 rank)
    {
        if (rank < 1 || rank > steps.size())
            return "It has grown as far as it can.";
        RelicStep const& step = steps[rank - 1];
        if (ProgressionState(player) < step.state)
            return "It can't grow further until you progress further through the ages.";
        Config const& cfg = GetConfig();
        if (step.gate == 1)
        {
            if (uint32 left = RaresLeft(s, step.era))
                return Acore::StringFormat("Its next rank needs every {} rare solved ({} left).", ERA_NAMES[step.era], left);
            if (uint32 quest = cfg.capstoneQuest[step.era])
                if (!player->GetQuestRewardStatus(quest))
                {
                    Quest const* q = sObjectMgr->GetQuestTemplate(quest);
                    return Acore::StringFormat("Its next rank needs the quest {}.", q ? q->GetTitle() : std::to_string(quest));
                }
        }
        else if (step.gate == 2)
        {
            if (uint32 left = ProjectsLeft(s))
                return Acore::StringFormat("To awaken it, solve every project of every race ({} left).", left);
            if (cfg.awakenNeedsMaxSkill && s.skill < cfg.maxSkill)
                return Acore::StringFormat("To awaken it, reach {} Archaeology.", cfg.maxSkill);
        }
        return "";
    }

    // The ladder step the item may show: the rank's, held down by level and progression.
    uint32 ShownStep(Player* player, RelicState const& r)
    {
        uint32 state = ProgressionState(player);
        for (uint32 step = std::min<uint32>(r.rank, RankCount()); step-- > 1;)
            if (player->GetLevel() >= steps[step].level && state >= steps[step].state)
                return step;
        return 0;
    }

    // The class, Dual Wield or Titan's Grip, and the weapon skills to use both halves.
    bool CanUseForm(Player* player, RelicForm const& form, uint32 step)
    {
        if (!(form.classes & player->getClassMask()) || form.items.size() != steps.size() || step >= steps.size())
            return false;
        if (form.need == RELIC_NEED_DUAL_WIELD && !player->CanDualWield())
            return false;
        if (form.need == RELIC_NEED_TITANS_GRIP && !player->CanTitanGrip())
            return false;
        for (uint32 entry : { form.items[step].first, form.items[step].second })
            if (ItemTemplate const* proto = entry ? sObjectMgr->GetItemTemplate(entry) : nullptr)
                if (player->CanUseItem(proto) != EQUIP_ERR_OK)
                    return false;
        return true;
    }

    uint32 FormChangeCost(RelicState const& r)
    {
        Config const& cfg = GetConfig();
        return r.formChanges ? cfg.formChangeBase + cfg.formChangePerRank * r.rank : 0;
    }

    bool TryRankUp(Player* player, CharState& s)
    {
        RelicState& r = s.relic;
        uint32 before = r.rank;
        while (r.rank && r.rank < RankCount())
        {
            uint32 cost = RankCost(r.rank + 1);
            if (r.power < cost || !RankBlocked(player, s, r.rank + 1).empty())
                break;
            r.power -= cost;
            ++r.rank;
        }
        if (r.rank == before)
            return false;
        RelicStep const& step = steps[r.rank - 1];
        Notify(player, Acore::StringFormat("|cffe6cc80Your Unearthed Relic has reached rank {} of {}|r (item level {}, {}).",
            r.rank, RankCount(), step.itemLevel, QUALITY_NAMES[std::min<uint8>(step.quality, 6)]));
        QueueTraits(player);   // stronger traits, maybe an achievement
        return true;
    }

    // Every relic item the character holds: equipped, in bags or in the bank.
    struct Held { Item* item; bool off; bool bank; };

    // The rank (1-based) that finishes each era, and the awakened one; 0 = none in the ladder.
    uint32 GateRank(uint8 gate, uint8 era)
    {
        for (uint32 i = 0; i < steps.size(); ++i)
            if (steps[i].gate == gate && (gate == 2 || steps[i].era == era))
                return i + 1;
        return 0;
    }

    void Award(Player* player, uint32 id)
    {
        if (player->HasAchieved(id))
            return;
        if (AchievementEntry const* entry = sAchievementStore.LookupEntry(id))
            player->CompletedAchievement(entry);
    }

    std::vector<Held> FindRelics(Player* player)
    {
        std::vector<Held> found;
        auto check = [&](Item* item, bool bank)
        {
            if (!item)
                return;
            if (mainItems.count(item->GetEntry()))
                found.push_back({ item, false, bank });
            else if (offItems.count(item->GetEntry()))
                found.push_back({ item, true, bank });
        };
        for (uint8 slot = EQUIPMENT_SLOT_START; slot < INVENTORY_SLOT_ITEM_END; ++slot)
            check(player->GetItemByPos(INVENTORY_SLOT_BAG_0, slot), false);
        for (uint8 slot = BANK_SLOT_ITEM_START; slot < BANK_SLOT_ITEM_END; ++slot)
            check(player->GetItemByPos(INVENTORY_SLOT_BAG_0, slot), true);
        for (uint8 bagSlot = INVENTORY_SLOT_BAG_START; bagSlot < BANK_SLOT_BAG_END; ++bagSlot)
        {
            if (bagSlot == INVENTORY_SLOT_BAG_END)
                bagSlot = BANK_SLOT_BAG_START;
            if (Bag* bag = player->GetBagByPos(bagSlot))
                for (uint32 i = 0; i < bag->GetBagSize(); ++i)
                    check(bag->GetItemByPos(uint8(i)), bagSlot >= BANK_SLOT_BAG_START);
        }
        return found;
    }

    // Keep the half recorded in the relic row (or the first found); a second copy of a half can
    // only come from a lost relic restored and then found again, and goes.
    Held const* Keep(Player* player, std::vector<Held>& found, bool off, ObjectGuid::LowType recorded)
    {
        Held const* keep = nullptr;
        for (Held const& h : found)
            if (h.off == off && (!keep || h.item->GetGUID().GetCounter() == recorded))
                keep = &h;
        for (Held& h : found)
            if (h.off == off && &h != keep)
            {
                LOG_INFO("module", "mod-archaeology: {} held a second relic {} ({}), removed", player->GetName(),
                    h.item->GetEntry(), h.item->GetGUID().GetCounter());
                player->DestroyItem(h.item->GetBagSlot(), h.item->GetSlot(), true);
                h.item = nullptr;
            }
        return keep;
    }

    // Replace a relic item with another step's or form's, in the same place (or in the bags when it
    // can't go back in that slot), keeping the gems of sockets the new item also has. The enchant
    // and temporary enchant (poisons, oils) stay only on the same kind of weapon: a staff enchant
    // can't move to a one-hander. Returns nullptr, with the old item untouched, when the new one has
    // nowhere to go.
    Item* Replace(Player* player, Item* old, uint32 entry)
    {
        ItemTemplate const* proto = sObjectMgr->GetItemTemplate(entry);
        ItemTemplate const* oldProto = old->GetTemplate();
        if (!proto || !oldProto)
            return nullptr;
        uint8 bag = old->GetBagSlot(), slot = old->GetSlot();
        bool equipped = old->IsEquipped();

        // Find the new item's place before anything changes. Until it gets enchants or a place it
        // is in no update queue, so it can simply be deleted.
        Item* item = Item::CreateItem(entry, 1, player);
        if (!item)
            return nullptr;
        uint16 equipDest = 0;
        ItemPosCountVec dest;
        bool toSlot = equipped && player->CanEquipItem(slot, equipDest, item, true) == EQUIP_ERR_OK;
        if (!toSlot && (equipped || player->CanStoreItem(bag, slot, dest, item, true) != EQUIP_ERR_OK) &&
            player->CanStoreItem(NULL_BAG, NULL_SLOT, dest, item, false) != EQUIP_ERR_OK)
        {
            delete item;
            return nullptr;
        }

        bool sameKind = proto->InventoryType == oldProto->InventoryType && proto->Class == oldProto->Class &&
            proto->SubClass == oldProto->SubClass;
        struct Enchant { uint32 id, duration, charges; };
        std::array<Enchant, MAX_INSPECTED_ENCHANTMENT_SLOT> enchants;
        for (uint8 e = 0; e < MAX_INSPECTED_ENCHANTMENT_SLOT; ++e)
            enchants[e] = { old->GetEnchantmentId(EnchantmentSlot(e)), old->GetEnchantmentDuration(EnchantmentSlot(e)),
                old->GetEnchantmentCharges(EnchantmentSlot(e)) };
        uint32 maxDurability = old->GetUInt32Value(ITEM_FIELD_MAXDURABILITY);
        uint32 durability = old->GetUInt32Value(ITEM_FIELD_DURABILITY);

        player->DestroyItem(bag, slot, true);
        item->SetBinding(true);
        for (uint8 e = 0; e < MAX_INSPECTED_ENCHANTMENT_SLOT; ++e)
        {
            if (!enchants[e].id || e == BONUS_ENCHANTMENT_SLOT)
                continue;
            bool socket = e >= SOCK_ENCHANTMENT_SLOT && e <= SOCK_ENCHANTMENT_SLOT_3;
            if (socket ? !proto->Socket[e - SOCK_ENCHANTMENT_SLOT].Color : !sameKind)
                continue;
            item->SetEnchantment(EnchantmentSlot(e), enchants[e].id, enchants[e].duration, enchants[e].charges);
        }
        if (proto->socketBonus && item->GemsFitSockets())
            item->SetEnchantment(BONUS_ENCHANTMENT_SLOT, proto->socketBonus, 0, 0);
        if (maxDurability && proto->MaxDurability)
            item->SetUInt32Value(ITEM_FIELD_DURABILITY, uint32(uint64(proto->MaxDurability) * durability / maxDurability));
        return toSlot ? player->EquipItem(equipDest, item, true) : player->StoreItem(dest, item, true);
    }

    Item* GiveNew(Player* player, uint32 entry)
    {
        ItemPosCountVec dest;
        if (player->CanStoreNewItem(NULL_BAG, NULL_SLOT, dest, entry, 1) != EQUIP_ERR_OK)
            return nullptr;
        Item* item = player->StoreNewItem(dest, entry, true);
        if (item)
        {
            item->SetBinding(true);
            player->SendNewItem(item, 1, true, false);
        }
        return item;
    }

    // Bring the items in line with the relic: right step, right form, no strays. With `give`, also
    // hand out halves the character has lost (the trainer's restore, or a new relic). False when a
    // half couldn't change or be handed out for lack of room; what did change is kept. `settle`, if
    // given, runs after the swap and before the save (with whether anything changed and whether
    // anything failed), and the relic row is then saved even if no item changed.
    using Settle = std::function<void(bool changed, bool failed)>;
    bool Sync(Player* player, CharState& s, bool give, Settle const& settle = nullptr)
    {
        RelicState& r = s.relic;
        TryRankUp(player, s);
        RelicForm const* form = GetForm(r.form);
        if (!r.rank || !form || steps.empty() || form->items.size() != steps.size())
            return true;
        auto [wantMain, wantOff] = form->items[ShownStep(player, r)];

        std::vector<Held> found = FindRelics(player);
        Held const* main = Keep(player, found, false, r.mainItem);
        Held const* off = Keep(player, found, true, r.offItem);
        Item* mainItem = main ? main->item : nullptr;
        Item* offItem = off ? off->item : nullptr;
        bool changed = false, failed = false;

        // The off hand first, so a two-hander can take the main hand.
        if (offItem && !wantOff)
        {
            player->DestroyItem(offItem->GetBagSlot(), offItem->GetSlot(), true);
            offItem = nullptr;
            r.offItem = 0;
            changed = true;
        }
        else if (offItem && offItem->GetEntry() != wantOff && !off->bank)
        {
            if (Item* item = Replace(player, offItem, wantOff))
            {
                offItem = item;
                changed = true;
            }
            else
                failed = true;
        }
        if (mainItem && mainItem->GetEntry() != wantMain && !main->bank)
        {
            if (Item* item = Replace(player, mainItem, wantMain))
            {
                mainItem = item;
                changed = true;
            }
            else
                failed = true;
        }
        if (give && !mainItem && (mainItem = GiveNew(player, wantMain)))
            changed = true;
        if (give && wantOff && !offItem && (offItem = GiveNew(player, wantOff)))
            changed = true;
        if (give && (!mainItem || (wantOff && !offItem)))
            failed = true;
        if (failed)
            Notify(player, "Your relic can't take its new shape: make room in your bags. It tries again when you next level, change zones or log in, or ask an archaeology trainer.");

        if (mainItem)
            r.mainItem = mainItem->GetGUID().GetCounter();
        if (offItem)
            r.offItem = offItem->GetGUID().GetCounter();
        if (settle)
            settle(changed, failed);
        else if (!changed)
            return !failed;
        if (changed)
            player->AutoUnequipOffhandIfNeed();
        // Save the swap and the relic row together, so a crash can't leave the row pointing at
        // items the character never had.
        CharacterDatabaseTransaction trans = CharacterDatabase.BeginTransaction();
        player->SaveInventoryAndGoldToDB(trans);
        trans->Append("REPLACE INTO `mod_archaeology_char_relic` (`guid`, `form`, `relic_rank`, `power`, `earned`, `traits`, "
            "`form_changes`, `main_item`, `off_item`) VALUES ({}, {}, {}, {}, {}, {}, {}, {}, {})", player->GetGUID().GetCounter(),
            r.form, r.rank, r.power, r.earned, r.traits, r.formChanges, r.mainItem, r.offItem);
        CharacterDatabase.CommitTransaction(trans);
        SendRelic(player);
        QueueTraits(player);
        return !failed;
    }

    bool HasMissingHalf(Player* player, RelicState const& r)
    {
        RelicForm const* form = GetForm(r.form);
        if (!form || form->items.empty())
            return false;
        bool main = false, off = false;
        for (Held const& h : FindRelics(player))
            (h.off ? off : main) = true;
        return !main || (form->items[0].second && !off);
    }

    void SendFormMenu(Player* player, Creature* creature)
    {
        CharState* s = GetState(player);
        RelicState const& r = s->relic;
        ClearGossipMenuFor(player);
        uint32 cost = r.form ? FormChangeCost(r) : 0;
        uint32 step = ShownStep(player, r);
        for (RelicForm const& form : forms)
        {
            if (form.id == r.form || !CanUseForm(player, form, step))
                continue;
            if (cost)
                AddGossipItemFor(player, GOSSIP_ICON_BATTLE, form.name, SENDER_FORM, form.id,
                    Acore::StringFormat("Reshape your relic into: {}?", form.name), cost, false);
            else
                AddGossipItemFor(player, GOSSIP_ICON_BATTLE, form.name, SENDER_FORM, form.id);
        }
        SendGossipMenuFor(player, FORM_TEXT, creature->GetGUID());
    }
}

namespace Archaeology
{
    void LoadRelicData()
    {
        steps.clear();
        forms.clear();
        mainItems.clear();
        offItems.clear();

        if (QueryResult result = WorldDatabase.Query("SELECT `era`, `required_level`, `item_level`, `quality`, `progression_state`, `cost`, `gate` "
            "FROM `mod_archaeology_relic_step` ORDER BY `step`"))
        {
            do
            {
                Field* f = result->Fetch();
                RelicStep st;
                st.era = std::min<uint8>(f[0].Get<uint8>(), 2);
                st.level = f[1].Get<uint8>();
                st.itemLevel = f[2].Get<uint16>();
                st.quality = f[3].Get<uint8>();
                st.state = f[4].Get<uint8>();
                st.cost = f[5].Get<uint32>();
                st.gate = f[6].Get<uint8>();
                steps.push_back(st);
            } while (result->NextRow());
        }

        if (QueryResult result = WorldDatabase.Query("SELECT `id`, `name`, `classes`, `need` FROM `mod_archaeology_relic_form` ORDER BY `id`"))
        {
            do
            {
                Field* f = result->Fetch();
                RelicForm form;
                form.id = f[0].Get<uint8>();
                form.name = f[1].Get<std::string>();
                form.classes = f[2].Get<uint32>();
                form.need = f[3].Get<uint8>();
                forms.push_back(form);
            } while (result->NextRow());
        }

        if (QueryResult result = WorldDatabase.Query("SELECT `form`, `step`, `main_item`, `off_item` FROM `mod_archaeology_relic_item` ORDER BY `form`, `step`"))
        {
            do
            {
                Field* f = result->Fetch();
                RelicForm* form = GetForm(f[0].Get<uint8>());
                uint32 step = f[1].Get<uint8>();
                uint32 main = f[2].Get<uint32>(), off = f[3].Get<uint32>();
                if (!form || step != form->items.size() || !sObjectMgr->GetItemTemplate(main) || (off && !sObjectMgr->GetItemTemplate(off)))
                {
                    LOG_ERROR("module", "mod-archaeology: relic item row form {} step {} is out of order or names a missing item", f[0].Get<uint8>(), step);
                    continue;
                }
                form->items.emplace_back(main, off);
                mainItems.insert(main);
                if (off)
                    offItems.insert(off);
            } while (result->NextRow());
        }

        for (RelicForm const& form : forms)
            if (form.items.size() != steps.size())
                LOG_ERROR("module", "mod-archaeology: relic form {} has {} of {} steps; it can't be chosen", form.id, form.items.size(), steps.size());
        LOG_INFO("module", "mod-archaeology: relic ladder of {} ranks, {} forms", steps.size(), forms.size());
        for (uint8 era = 0; era < 3; ++era)
            if (!GetConfig().capstoneQuest[era])
                LOG_WARN("module", "mod-archaeology: Archaeology.Relic.CapstoneQuest for the {} is 0: its last rank needs no quest, "
                    "though the trainer still offers quest {}. A config from before the capstones keeps 0; set {} to use it.",
                    ERA_NAMES[era], CAPSTONE_QUESTS[era], CAPSTONE_QUESTS[era]);
    }

    void LoadRelic(Player* player, CharState& s)
    {
        if (QueryResult result = CharacterDatabase.Query("SELECT `form`, `relic_rank`, `power`, `earned`, `traits`, `form_changes`, `main_item`, `off_item` "
            "FROM `mod_archaeology_char_relic` WHERE `guid` = {}", player->GetGUID().GetCounter()))
        {
            Field* f = result->Fetch();
            RelicState& r = s.relic;
            r.form = f[0].Get<uint8>();
            r.rank = f[1].Get<uint8>();
            if (!steps.empty())
                r.rank = std::min<uint32>(r.rank, RankCount());
            r.power = f[2].Get<uint32>();
            r.earned = f[3].Get<uint32>();
            r.traits = f[4].Get<uint32>();
            r.formChanges = f[5].Get<uint16>();
            r.mainItem = f[6].Get<uint32>();
            r.offItem = f[7].Get<uint32>();
            if (r.rank)
                QueueRelic(player);
        }
    }

    void SaveRelic(Player* player)
    {
        CharState* s = GetState(player);
        if (!s)
            return;
        RelicState const& r = s->relic;
        CharacterDatabase.Execute("REPLACE INTO `mod_archaeology_char_relic` (`guid`, `form`, `relic_rank`, `power`, `earned`, `traits`, "
            "`form_changes`, `main_item`, `off_item`) VALUES ({}, {}, {}, {}, {}, {}, {}, {}, {})", player->GetGUID().GetCounter(),
            r.form, r.rank, r.power, r.earned, r.traits, r.formChanges, r.mainItem, r.offItem);
    }

    // Relic Power is earned from the first find on, so digging before the relic quest still counts.
    void AddRelicPower(Player* player, uint32 amount)
    {
        CharState* s = GetState(player);
        if (!GetConfig().relicEnabled || !s || !s->skill || !amount)
            return;
        s->relic.power = uint32(std::min<uint64>(uint64(s->relic.power) + amount, UINT32_MAX));
        s->relic.earned = uint32(std::min<uint64>(uint64(s->relic.earned) + amount, UINT32_MAX));
        if (TryRankUp(player, *s))
            QueueRelic(player);
        SaveRelic(player);
        SendRelic(player);
    }

    void QueueRelic(Player* player)
    {
        CharState* s = GetState(player);
        if (!GetConfig().relicEnabled || !s || !s->relic.rank)
            return;
        std::lock_guard<std::mutex> lock(queueLock);
        if (queued.insert(player->GetGUID()).second)
            ++queuedCount;
    }

    // From the player update: swap items only while nothing else is going on.
    void UpdateQueuedRelic(Player* player)
    {
        if (!queuedCount.load(std::memory_order_relaxed))
            return;
        if (!player->IsInWorld() || !player->IsAlive() || player->IsInCombat() || player->IsBeingTeleported() ||
            player->IsNonMeleeSpellCast(false) || player->HasUnitState(UNIT_STATE_CONTROLLED))
            return;
        {
            std::lock_guard<std::mutex> lock(queueLock);
            if (!queued.erase(player->GetGUID()))
                return;
            --queuedCount;
        }
        if (CharState* s = GetState(player))
            Sync(player, *s, false);
    }

    void ForgetRelic(Player* player)
    {
        std::lock_guard<std::mutex> lock(queueLock);
        if (queued.erase(player->GetGUID()))
            --queuedCount;
    }

    // A relic quest taken before the skill was there completes once it is.
    void RelicSkillChanged(Player* player)
    {
        if (player->GetQuestStatus(RELIC_QUEST) == QUEST_STATUS_INCOMPLETE && CanTakeRelicQuest(player))
            player->CompleteQuest(RELIC_QUEST);
    }

    bool IsRelicItem(uint32 entry)
    {
        return mainItems.count(entry) || offItems.count(entry);
    }

    bool CanTakeRelicQuest(Player* player)
    {
        CharState* s = GetState(player);
        return GetConfig().relicEnabled && !steps.empty() && s && s->skill >= GetConfig().relicSkill;
    }

    void SendRelic(Player* player)
    {
        CharState* s = GetState(player);
        if (!s || !s->skill || !GetConfig().relicEnabled || steps.empty())
            return;
        RelicState const& r = s->relic;
        RelicForm const* form = GetForm(r.form);
        std::string note;
        uint32 ilvl = 0, quality = 0;
        if (!r.rank)
            note = s->skill >= GetConfig().relicSkill ? "Ask an archaeology trainer about A Weapon in Pieces."
                : Acore::StringFormat("At {} Archaeology a trainer can help you piece it together.", GetConfig().relicSkill);
        else
        {
            RelicStep const& step = steps[ShownStep(player, r)];
            ilvl = step.itemLevel;
            quality = step.quality;
            note = RankBlocked(player, *s, r.rank + 1);
            if (!form)
                note = "Choose its form at an archaeology trainer.";
        }
        std::string formName = form ? form->name : "";
        std::replace(formName.begin(), formName.end(), ':', ' ');
        SendAddon(player, Acore::StringFormat("L:{}:{}:{}:{}:{}:{}:{}:{}", r.rank, RankCount(), r.power,
            r.rank < RankCount() ? RankCost(r.rank + 1) : 0, ilvl, quality, formName, note));
    }

    std::string RelicStatusText(Player* player)
    {
        CharState* s = GetState(player);
        if (!GetConfig().relicEnabled || steps.empty())
            return "The Unearthed Relic is turned off on this realm.";
        if (!s || !s->skill)
            return "You don't know Archaeology. Find an archaeology trainer to learn it.";
        RelicState const& r = s->relic;
        if (!r.rank)
            return Acore::StringFormat("Relic Power: {}. {}", r.power, s->skill >= GetConfig().relicSkill
                ? "An archaeology trainer has a task for you: A Weapon in Pieces."
                : Acore::StringFormat("At {} Archaeology an archaeology trainer can help you piece your relic together.", GetConfig().relicSkill));
        RelicForm const* form = GetForm(r.form);
        uint32 shown = ShownStep(player, r);
        RelicStep const& step = steps[shown];
        std::string text = Acore::StringFormat("Unearthed Relic{}: rank {} of {}, item level {} ({}).", form ? " (" + form->name + ")" : "",
            r.rank, RankCount(), step.itemLevel, QUALITY_NAMES[std::min<uint8>(step.quality, 6)]);
        if (!form)
            text += " Choose its form at an archaeology trainer.";
        if (shown + 1 < r.rank)
        {
            RelicStep const& next = steps[shown + 1];
            text += player->GetLevel() < next.level
                ? Acore::StringFormat(" Your level holds it back; at {} it grows to item level {}.", next.level, next.itemLevel)
                : std::string(" Your progress through the ages holds it back.");
        }
        std::string blocked = RankBlocked(player, *s, r.rank + 1);
        if (r.rank < RankCount())
            text += Acore::StringFormat("\nRelic Power: {} of {} for rank {}.", r.power, RankCost(r.rank + 1), r.rank + 1);
        else
            text += Acore::StringFormat("\nRelic Power: {}.", r.power);
        if (!blocked.empty())
            text += " " + blocked;
        std::string traits = TraitStatusText(player);
        if (!traits.empty())
            text += "\n" + traits;
        return text;
    }

    void AddRelicGossip(Player* player)
    {
        CharState* s = GetState(player);
        if (!s || !GetConfig().relicEnabled || !s->relic.rank)
            return;
        RelicState const& r = s->relic;
        if (!r.form)
            AddGossipItemFor(player, GOSSIP_ICON_BATTLE, "Choose the shape of my relic.", GOSSIP_SENDER_MAIN, 10);
        else
        {
            AddGossipItemFor(player, GOSSIP_ICON_CHAT, "Tell me about my relic.", GOSSIP_SENDER_MAIN, 11);
            AddGossipItemFor(player, GOSSIP_ICON_BATTLE, r.formChanges ? Acore::StringFormat("Reshape my relic ({} gold).", FormChangeCost(r) / 10000)
                : std::string("Reshape my relic (free the first time)."), GOSSIP_SENDER_MAIN, 12);
            if (HasMissingHalf(player, r))
                AddGossipItemFor(player, GOSSIP_ICON_CHAT, "I've lost my relic.", GOSSIP_SENDER_MAIN, 13);
        }
    }

    bool RelicGossipSelect(Player* player, Creature* creature, uint32 sender, uint32 action)
    {
        CharState* s = GetState(player);
        if (!s || !GetConfig().relicEnabled || !s->relic.rank)
            return false;
        RelicState& r = s->relic;
        if (sender == GOSSIP_SENDER_MAIN)
        {
            switch (action)
            {
                case 10:
                case 12:
                    SendFormMenu(player, creature);
                    return true;
                case 11:
                    CloseGossipMenuFor(player);
                    Notify(player, RelicStatusText(player));
                    return true;
                case 13:
                    CloseGossipMenuFor(player);
                    if (HasMissingHalf(player, r) && Sync(player, *s, true))
                        creature->Whisper("Dug out of a forgotten corner of my pack. Try to hold on to it this time.", LANG_UNIVERSAL, player);
                    return true;
                default:
                    return false;
            }
        }
        if (sender != SENDER_FORM)
            return false;

        CloseGossipMenuFor(player);
        RelicForm const* form = GetForm(uint8(action));
        if (!form || form->id == r.form || !CanUseForm(player, *form, ShownStep(player, r)))
            return true;
        bool first = !r.form;
        uint32 cost = first ? 0 : FormChangeCost(r);
        if (!player->HasEnoughMoney(cost))
        {
            player->SendBuyError(BUY_ERR_NOT_ENOUGHT_MONEY, creature, 0, 0);
            return true;
        }
        // Room for both halves, so neither has to stay in its old shape.
        if (player->GetFreeInventorySpace() < 2)
        {
            Notify(player, "Make room for two items in your bags first.");
            return true;
        }
        // Paid before the swap and settled before the save, so gold, items and the relic row go in
        // one transaction. If nothing could change, the old form and the gold come back; if one half
        // changed, the reshape is paid for and the next swap (or a restore) finishes it.
        uint8 oldForm = r.form;
        if (!first)
        {
            player->ModifyMoney(-int32(cost));
            ++r.formChanges;
        }
        r.form = form->id;
        bool done = Sync(player, *s, true, [&](bool changed, bool /*failed*/)   // a new relic, or the half a pair needs
        {
            if (changed || first)
                return;
            r.form = oldForm;
            player->ModifyMoney(int32(cost));
            --r.formChanges;
        });
        if (!done)
            return true;
        if (r.form != form->id)
        {
            Notify(player, "Take your relic out of the bank first.");
            return true;
        }
        creature->Whisper(first ? "There. It's barely holding together, but it's yours, and it will grow with every find."
            : "Same history, new shape. Its rank and power are untouched.", LANG_UNIVERSAL, player);
        SendRelic(player);
        return true;
    }

    void RelicQuestRewarded(Player* player, Creature* creature)
    {
        // The quest is used up either way, so the relic is kept even while it is turned off.
        CharState* s = GetState(player);
        if (!s)
            return;
        if (!s->relic.rank)
        {
            s->relic.rank = 1;
            TryRankUp(player, *s);   // Relic Power dug up before the quest counts
            SaveRelic(player);
        }
        SendRelic(player);
        QueueTraits(player);
        if (!s->relic.form && GetConfig().relicEnabled && !steps.empty())
            SendFormMenu(player, creature);
    }

    uint32 RelicShownStep(Player* player)
    {
        CharState* s = GetState(player);
        return s && s->relic.rank && !steps.empty() ? ShownStep(player, s->relic) : 0;
    }

    uint32 RelicRankCount() { return RankCount(); }

    bool IsRelicEquipped(Player* player)
    {
        for (uint8 slot : { EQUIPMENT_SLOT_MAINHAND, EQUIPMENT_SLOT_OFFHAND, EQUIPMENT_SLOT_RANGED })
            if (Item* item = player->GetItemByPos(INVENTORY_SLOT_BAG_0, slot))
                if (IsRelicItem(item->GetEntry()))
                    return true;
        return false;
    }

    bool IsCapstoneQuest(uint32 questId)
    {
        Config const& cfg = GetConfig();
        return questId && (std::find(std::begin(CAPSTONE_QUESTS), std::end(CAPSTONE_QUESTS), questId) != std::end(CAPSTONE_QUESTS) ||
            std::find(cfg.capstoneQuest.begin(), cfg.capstoneQuest.end(), questId) != cfg.capstoneQuest.end());
    }

    // A capstone boss died: everyone in its instance who tapped it (the looting group), has the
    // era's quest and wears the relic gets the kill. Dead raiders count, as long as they're inside.
    void CapstoneBossDied(Creature* boss)
    {
        Config const& cfg = GetConfig();
        if (!cfg.relicEnabled)
            return;
        CapstoneBoss const* match = nullptr;
        for (CapstoneBoss const& b : CAPSTONE_BOSSES)
            if (b.entry == boss->GetEntry())
                match = &b;
        if (!match)
            return;
        // The module's own quest always counts, since the trainer offers it whatever the config
        // says; a quest the config names instead counts too.
        std::vector<Quest const*> quests;
        for (uint32 id : { CAPSTONE_QUESTS[match->era], cfg.capstoneQuest[match->era] })
            if (Quest const* q = id ? sObjectMgr->GetQuestTemplate(id) : nullptr)
                if (std::find(quests.begin(), quests.end(), q) == quests.end())
                    quests.push_back(q);
        Player* recipient = boss->GetLootRecipient();
        Group* group = boss->GetLootRecipientGroup();
        if (quests.empty() || (!recipient && !group))
            return;
        boss->GetMap()->DoForAllPlayers([&](Player* player)
        {
            if ((player != recipient && (!group || player->GetGroup() != group)) || !IsRelicEquipped(player))
                return;
            for (Quest const* quest : quests)
            {
                if (player->GetQuestStatus(quest->GetQuestId()) != QUEST_STATUS_INCOMPLETE)
                    continue;
                // The quest's kill-credit objective if it has one, else the quest as a whole.
                if (quest->RequiredNpcOrGo[0] > 0)
                    player->KilledMonsterCredit(uint32(quest->RequiredNpcOrGo[0]));
                else
                    player->AreaExploredOrEventHappens(quest->GetQuestId());
            }
        });
    }

    // The relic achievements, granted here and never by a boss kill, so individual progression
    // (which reads raid achievements) never sees them. Safe to call any time.
    void CheckRelicAchievements(Player* player)
    {
        CharState* s = GetState(player);
        if (!s || !s->skill)
            return;
        RelicState const& r = s->relic;
        if (player->GetQuestRewardStatus(RELIC_QUEST))
            Award(player, ACHIEVEMENT_WEAPON_IN_PIECES);
        if (r.rank)
        {
            if (uint32 rank = GateRank(1, 0); rank && r.rank >= rank)
                Award(player, ACHIEVEMENT_TEMPERED);
            if (uint32 rank = GateRank(1, 1); rank && r.rank >= rank)
                Award(player, ACHIEVEMENT_LEGEND);
            if (uint32 rank = GateRank(2, 0); rank && r.rank >= rank)
                Award(player, ACHIEVEMENT_AWAKENED);
        }
        bool allAwake = !AllRaces().empty(), allComplete = !AllRaces().empty();
        for (Race const& race : AllRaces())
        {
            allAwake = allAwake && (r.traits & (1u << race.id));
            allComplete = allComplete && IsRaceComplete(*s, race.id);
        }
        if (allAwake && r.rank)
            Award(player, ACHIEVEMENT_EVERY_VOICE);
        if (allComplete)
            Award(player, ACHIEVEMENT_KEEPER);
    }
}
