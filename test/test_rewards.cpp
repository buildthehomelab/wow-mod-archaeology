// Exercise the real item hook with old/new instance charges. The core-stub
// surface is deliberately limited to the hook, not a claim of in-game learning.
#include "../src/ArchaeologyRewards.cpp"
#include <cassert>

int main()
{
    ArchaeologyFossilizedHatchling script;
    Player player;
    SpellCastTargets targets;
    Item oldItem;
    assert(!script.OnUse(&player, &oldItem, targets)); // stock cast must continue
    assert(oldItem.charge == -1 && oldItem.changed);
    oldItem.changed = false;
    assert(!script.OnUse(&player, &oldItem, targets));
    assert(oldItem.charge == -1 && !oldItem.changed); // fresh/repaired item unchanged

    Item unrelated;
    unrelated.entry = 9504037;
    assert(!script.OnUse(&player, &unrelated, targets));
    assert(unrelated.charge == 0 && !unrelated.changed);
    Item differentSpell;
    differentSpell.proto.Spells[1].SpellId = 410267;
    assert(!script.OnUse(&player, &differentSpell, targets));
    assert(differentSpell.charge == 0 && !differentSpell.changed);
    Item differentCharges;
    differentCharges.proto.Spells[0].SpellCharges = 5;
    assert(!script.OnUse(&player, &differentCharges, targets));
    assert(differentCharges.charge == 0 && !differentCharges.changed);
    assert(!script.OnUse(nullptr, &oldItem, targets));
    assert(!script.OnUse(&player, nullptr, targets));
}
