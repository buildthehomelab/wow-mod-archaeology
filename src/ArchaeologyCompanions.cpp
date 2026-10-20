/* Functional archaeology companions. Released under the MIT License. */
#include "Item.h"
#include "Player.h"
#include "ScriptMgr.h"
#include "ArchaeologyRewardRules.h"

class ArchaeologyCompanion : public ItemScript
{
public:
    ArchaeologyCompanion() : ItemScript("item_archaeology_companion") { }

    bool OnUse(Player* player, Item* item, SpellCastTargets const& /*targets*/) override
    {
        if (!player || !item)
            return false;
        ItemTemplate const* proto = item->GetTemplate();
        // Old placeholders persist zero charges. Repair before default CheckItems.
        if (proto && proto->Spells[0].SpellId == 55884 && proto->Spells[0].SpellCharges == -1
            && ArchaeologyRewards::IsCompanion(item->GetEntry(), proto->Spells[1].SpellId)
            && item->GetSpellCharges(0) == 0)
        {
            item->SetSpellCharges(0, -1);
            item->SetState(ITEM_CHANGED, player);
        }
        return false; // ordinary core companion learning and consumption
    }
};

void AddArchaeologyCompanionScripts()
{
    new ArchaeologyCompanion();
}
