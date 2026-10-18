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
#include "Item.h"
#include "Log.h"
#include "ObjectMgr.h"
#include "Player.h"
#include "QuestDef.h"
#include "ScriptedGossip.h"
#include <algorithm>
#include <unordered_set>

namespace
{
    using namespace Archaeology;

    constexpr uint32 FORM_TEXT = 9503501;
    constexpr uint32 SENDER_FORM = 2;
    constexpr char const* ERA_NAMES[3] = { "old world", "Outland", "Northrend" };
    constexpr char const* QUALITY_NAMES[7] = { "Poor", "Common", "Uncommon", "Rare", "Epic", "Legendary", "Artifact" };

    std::vector<RelicStep> steps;
    std::vector<RelicForm> forms;
    std::unordered_set<uint32> mainItems;
    std::unordered_set<uint32> offItems;
    std::unordered_set<ObjectGuid> queued;

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

    bool CanUseForm(Player* player, RelicForm const& form)
    {
        if (!(form.classes & player->getClassMask()))
            return false;
        if (form.need == RELIC_NEED_DUAL_WIELD && !player->CanDualWield())
            return false;
        if (form.need == RELIC_NEED_TITANS_GRIP && !player->CanTitanGrip())
            return false;
        return form.items.size() == steps.size();
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
        return true;
    }

    // Every relic item the character holds: equipped, in bags or in the bank.
    struct Held { Item* item; bool off; bool bank; };

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

    // Replace a relic item with another step's or form's, in the same place, keeping its enchant,
    // temporary enchant (poisons, oils) and the gems of sockets the new item also has.
    Item* Replace(Player* player, Item* old, uint32 entry)
    {
        ItemTemplate const* proto = sObjectMgr->GetItemTemplate(entry);
        if (!proto)
            return old;
        uint8 bag = old->GetBagSlot(), slot = old->GetSlot();
        bool equipped = old->IsEquipped();
        struct Enchant { uint32 id, duration, charges; };
        std::array<Enchant, MAX_INSPECTED_ENCHANTMENT_SLOT> enchants;
        for (uint8 e = 0; e < MAX_INSPECTED_ENCHANTMENT_SLOT; ++e)
            enchants[e] = { old->GetEnchantmentId(EnchantmentSlot(e)), old->GetEnchantmentDuration(EnchantmentSlot(e)),
                old->GetEnchantmentCharges(EnchantmentSlot(e)) };
        uint32 maxDurability = old->GetUInt32Value(ITEM_FIELD_MAXDURABILITY);
        uint32 durability = old->GetUInt32Value(ITEM_FIELD_DURABILITY);

        player->DestroyItem(bag, slot, true);
        Item* item = Item::CreateItem(entry, 1, player);
        if (!item)
            return nullptr;
        item->SetBinding(true);
        for (uint8 e = 0; e < MAX_INSPECTED_ENCHANTMENT_SLOT; ++e)
        {
            if (!enchants[e].id || e == BONUS_ENCHANTMENT_SLOT)
                continue;
            if (e >= SOCK_ENCHANTMENT_SLOT && e <= SOCK_ENCHANTMENT_SLOT_3 && !proto->Socket[e - SOCK_ENCHANTMENT_SLOT].Color)
                continue;
            item->SetEnchantment(EnchantmentSlot(e), enchants[e].id, enchants[e].duration, enchants[e].charges);
        }
        if (proto->socketBonus && item->GemsFitSockets())
            item->SetEnchantment(BONUS_ENCHANTMENT_SLOT, proto->socketBonus, 0, 0);
        if (maxDurability && proto->MaxDurability)
            item->SetUInt32Value(ITEM_FIELD_DURABILITY, uint32(uint64(proto->MaxDurability) * durability / maxDurability));

        // Back where it was; an item that can't go in that slot (a main-hand weapon where a Titan's
        // Grip two-hander sat in the off hand) goes in the bags instead.
        uint16 equipDest = 0;
        if (equipped && player->CanEquipItem(slot, equipDest, item, false) == EQUIP_ERR_OK)
            return player->EquipItem(equipDest, item, true);
        ItemPosCountVec dest;
        if ((!equipped && player->CanStoreItem(bag, slot, dest, item, false) == EQUIP_ERR_OK) ||
            player->CanStoreItem(NULL_BAG, NULL_SLOT, dest, item, false) == EQUIP_ERR_OK)
            return player->StoreItem(dest, item, true);
        delete item;
        return nullptr;
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
    // hand out halves the character has lost (the trainer's restore, or a new relic).
    void Sync(Player* player, CharState& s, bool give)
    {
        RelicState& r = s.relic;
        TryRankUp(player, s);
        RelicForm const* form = GetForm(r.form);
        if (!r.rank || !form || form->items.size() != steps.size())
            return;
        auto [wantMain, wantOff] = form->items[ShownStep(player, r)];

        std::vector<Held> found = FindRelics(player);
        Held const* main = Keep(player, found, false, r.mainItem);
        Held const* off = Keep(player, found, true, r.offItem);
        Item* mainItem = main ? main->item : nullptr;
        Item* offItem = off ? off->item : nullptr;
        bool changed = false;

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
            offItem = Replace(player, offItem, wantOff);
            changed = true;
        }
        if (mainItem && mainItem->GetEntry() != wantMain && !main->bank)
        {
            mainItem = Replace(player, mainItem, wantMain);
            changed = true;
        }
        if (give && !mainItem && (mainItem = GiveNew(player, wantMain)))
            changed = true;
        if (give && wantOff && !offItem && (offItem = GiveNew(player, wantOff)))
            changed = true;
        if (give && (!mainItem || (wantOff && !offItem)))
            Notify(player, "Make room in your bags for your relic, then ask again.");

        if (mainItem)
            r.mainItem = mainItem->GetGUID().GetCounter();
        if (offItem)
            r.offItem = offItem->GetGUID().GetCounter();
        if (!changed)
            return;
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
        for (RelicForm const& form : forms)
        {
            if (form.id == r.form || !CanUseForm(player, form))
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
    }

    void LoadRelic(Player* player, CharState& s)
    {
        if (QueryResult result = CharacterDatabase.Query("SELECT `form`, `relic_rank`, `power`, `earned`, `traits`, `form_changes`, `main_item`, `off_item` "
            "FROM `mod_archaeology_char_relic` WHERE `guid` = {}", player->GetGUID().GetCounter()))
        {
            Field* f = result->Fetch();
            RelicState& r = s.relic;
            r.form = f[0].Get<uint8>();
            r.rank = std::min<uint32>(f[1].Get<uint8>(), RankCount());
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
        s->relic.power += amount;
        s->relic.earned += amount;
        if (TryRankUp(player, *s))
            QueueRelic(player);
        SaveRelic(player);
        SendRelic(player);
    }

    void QueueRelic(Player* player)
    {
        CharState* s = GetState(player);
        if (GetConfig().relicEnabled && s && s->relic.rank)
            queued.insert(player->GetGUID());
    }

    // From the player update: swap items only while nothing else is going on.
    void UpdateQueuedRelic(Player* player)
    {
        if (queued.empty() || !queued.count(player->GetGUID()))
            return;
        if (!player->IsInWorld() || !player->IsAlive() || player->IsInCombat() || player->IsBeingTeleported())
            return;
        queued.erase(player->GetGUID());
        if (CharState* s = GetState(player))
            Sync(player, *s, false);
    }

    void ForgetRelic(Player* player)
    {
        queued.erase(player->GetGUID());
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
        if (!s || !s->skill || !GetConfig().relicEnabled)
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
                    if (HasMissingHalf(player, r))
                    {
                        Sync(player, *s, true);
                        if (!HasMissingHalf(player, r))
                            creature->Whisper("Dug out of a forgotten corner of my pack. Try to hold on to it this time.", LANG_UNIVERSAL, player);
                    }
                    return true;
                default:
                    return false;
            }
        }
        if (sender != SENDER_FORM)
            return false;

        CloseGossipMenuFor(player);
        RelicForm const* form = GetForm(uint8(action));
        if (!form || form->id == r.form || !CanUseForm(player, *form))
            return true;
        bool first = !r.form;
        if (!first)
        {
            uint32 cost = FormChangeCost(r);
            if (!player->HasEnoughMoney(cost))
            {
                player->SendBuyError(BUY_ERR_NOT_ENOUGHT_MONEY, creature, 0, 0);
                return true;
            }
            player->ModifyMoney(-int32(cost));
            ++r.formChanges;
        }
        r.form = form->id;
        SaveRelic(player);
        Sync(player, *s, true);   // a new relic, or the off-hand half a pair needs
        creature->Whisper(first ? "There. It's barely holding together, but it's yours, and it will grow with every find."
            : "Same history, new shape. Its rank and power are untouched.", LANG_UNIVERSAL, player);
        SendRelic(player);
        return true;
    }

    void RelicQuestRewarded(Player* player, Creature* creature)
    {
        CharState* s = GetState(player);
        if (!s || !GetConfig().relicEnabled || steps.empty())
            return;
        if (!s->relic.rank)
        {
            s->relic.rank = 1;
            TryRankUp(player, *s);   // Relic Power dug up before the quest counts
            SaveRelic(player);
        }
        SendRelic(player);
        if (!s->relic.form)
            SendFormMenu(player, creature);
    }
}
