/*
 * Functional archaeology rewards. Released under the MIT License.
 */
#include "Item.h"
#include "Player.h"
#include "ScriptMgr.h"

class ArchaeologyFossilizedHatchling : public ItemScript
{
public:
    ArchaeologyFossilizedHatchling() : ItemScript("item_archaeology_fossilized_hatchling") { }

    bool OnUse(Player* player, Item* item, SpellCastTargets const& /*targets*/) override
    {
        if (!player || !item || item->GetEntry() != 9504036)
            return false;

        ItemTemplate const* proto = item->GetTemplate();
        // Previously awarded placeholders persist zero charges. CheckItems
        // would reject them against the new -1-charge template. Initialize
        // just this known learning slot before the default cast checks run.
        if (proto && proto->Spells[0].SpellId == 55884 && proto->Spells[1].SpellId == 410266
            && proto->Spells[0].SpellCharges == -1 && item->GetSpellCharges(0) == 0)
        {
            item->SetSpellCharges(0, -1);
            item->SetState(ITEM_CHANGED, player);
        }

        // Let the core perform ordinary companion learning, validation and
        // item consumption; do not learn spells or destroy items here.
        return false;
    }
};

void AddArchaeologyRewardScripts()
{
    new ArchaeologyFossilizedHatchling();
}
