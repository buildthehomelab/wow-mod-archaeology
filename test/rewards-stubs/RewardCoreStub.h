#pragma once
#include <cstdint>
struct Player { };
struct SpellCastTargets { };
constexpr int ITEM_CHANGED = 1;
struct ItemTemplate
{
    struct Slot { int SpellId = 0; int SpellCharges = 0; };
    Slot Spells[2] = { {55884, -1}, {410266, 0} };
};
struct Item
{
    uint32_t entry = 9504036;
    int charge = 0;
    bool changed = false;
    ItemTemplate proto;
    uint32_t GetEntry() const { return entry; }
    ItemTemplate const* GetTemplate() const { return &proto; }
    int GetSpellCharges(unsigned) const { return charge; }
    void SetSpellCharges(unsigned, int value) { charge = value; }
    void SetState(int, Player*) { changed = true; }
};
class ItemScript
{
public:
    explicit ItemScript(char const*) { }
    virtual ~ItemScript() = default;
    virtual bool OnUse(Player*, Item*, SpellCastTargets const&) { return false; }
};
