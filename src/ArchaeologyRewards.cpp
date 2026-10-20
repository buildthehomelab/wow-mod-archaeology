/* Functional archaeology toys. Released under the MIT License. */
#include "Archaeology.h"
#include "Chat.h"
#include "Creature.h"
#include "Item.h"
#include "Map.h"
#include "MotionMaster.h"
#include "Player.h"
#include "Random.h"
#include "ScriptMgr.h"
#include "SpellInfo.h"
#include "SpellScript.h"
#include "SpellScriptLoader.h"
#include "TemporarySummon.h"
#include <array>
#include <vector>

namespace
{
    uint32 ToyItem(uint32 spell)
    {
        switch (spell)
        {
            case 90530: return 9504063;
            case 90531: return 9504064;
            case 90532: return 9504071;
            case 90533: return 9504079;
            case 90534: return 9504101;
            case 90535: return 9504102;
            case 90536: return 9504119;
            case 90537: return 9504120;
            case 90538: return 9504129;
            case 90539: return 9504133;
            case 90540: return 9504141;
            case 90541: return 9504142;
            case 90542: return 9504143;
            default: return 0;
        }
    }

    Creature* Cosmetic(Player* player, uint32 entry, float distance, float angle, uint32 lifetime)
    {
        Creature* creature = player->SummonCreature(entry, player->GetNearPosition(distance, angle), TEMPSUMMON_TIMED_DESPAWN, lifetime);
        if (creature)
        {
            creature->SetReactState(REACT_PASSIVE);
            creature->SetFacingToObject(player);
        }
        return creature;
    }

    bool TravelBlocked(Player* player)
    {
        return player->IsInCombat() || player->IsInFlight() || player->IsFlying()
            || player->GetTransport() || player->GetVehicle() || player->GetMap()->IsDungeon()
            || player->InBattleground() || player->InArena();
    }

    struct Refuge { uint32 map; float x, y, z, orientation; uint8 minLevel; uint8 continent; };
    constexpr std::array<Refuge, 6> Refuges = {{
        {1, -955.0f, -3679.0f, 8.0f, 0.0f, 1, 1},       // Ratchet
        {0, -14406.0f, 419.0f, 22.0f, 0.0f, 30, 0},      // Booty Bay
        {1, -7177.0f, -3785.0f, 9.0f, 0.0f, 40, 1},      // Gadgetzan
        {1, 7536.0f, -2850.0f, 460.0f, 0.0f, 10, 1},     // Moonglade
        {530, -1863.0f, 5400.0f, -12.0f, 0.0f, 60, 2},   // Shattrath
        {571, 5807.0f, 588.0f, 660.0f, 0.0f, 70, 3}      // Dalaran
    }};
}

class spell_archaeology_reward : public SpellScript
{
    PrepareSpellScript(spell_archaeology_reward);

    SpellCastResult CheckCast()
    {
        Player* player = GetCaster()->ToPlayer();
        Item* item = GetCastItem();
        if (!player || !item || item->GetEntry() != ToyItem(GetSpellInfo()->Id))
            return SPELL_FAILED_BAD_TARGETS;
        if (player->IsInCombat())
            return SPELL_FAILED_AFFECTING_COMBAT;
        if (player->InBattleground() || player->InArena())
            return SPELL_FAILED_NOT_HERE;
        if (GetSpellInfo()->Id == 90535 && TravelBlocked(player))
            return SPELL_FAILED_NOT_HERE;
        if ((GetSpellInfo()->Id == 90536 || GetSpellInfo()->Id == 90538 || GetSpellInfo()->Id == 90539)
            && player->GetShapeshiftForm() != FORM_NONE)
            return SPELL_FAILED_NOT_SHAPESHIFT;
        return SPELL_CAST_OK;
    }

    void HandleHit()
    {
        Player* player = GetCaster()->ToPlayer();
        if (!player)
            return;
        switch (GetSpellInfo()->Id)
        {
            case 90530:
                if (Creature* reflection = Cosmetic(player, 9503603, 3.0f, 0.0f, 60000))
                    player->CastSpell(reflection, 90580, true);
                break;
            case 90531:
                for (uint32 entry : {9503604u, 9503605u})
                    if (Creature* statue = Cosmetic(player, entry, 2.0f, entry == 9503604 ? 1.5f : -1.5f, 10000))
                    {
                        statue->SetEmoteState(EMOTE_STATE_KNEEL);
                        statue->CastSpell(statue, 90581, true);
                    }
                player->CastSpell(player, 90581, true);
                break;
            case 90532:
                for (uint8 i = 0; i < 4; ++i)
                    if (Creature* dancer = Cosmetic(player, 9503606, 3.0f, float(i) * 1.5707963f, 30000))
                        dancer->SetEmoteState(EMOTE_STATE_DANCE);
                break;
            case 90533:
                player->PlayDistanceSound(6674); // stock non-looping night elf bell
                player->CastSpell(player, 90581, true);
                break;
            case 90534:
                if (Creature* naaru = Cosmetic(player, 9503607, 3.0f, 0.0f, 30000))
                    naaru->CastSpell(naaru, 90582, true);
                break;
            case 90535:
            {
                // Recheck at completion; movement/transport state can change during the cast.
                if (TravelBlocked(player))
                    break;
                std::vector<Refuge const*> allowed;
                for (auto const& refuge : Refuges)
                    if (player->GetLevel() >= refuge.minLevel && Archaeology::CanDigContinent(player, refuge.continent))
                        allowed.push_back(&refuge);
                if (!allowed.empty())
                {
                    Refuge const& refuge = *allowed[urand(0, uint32(allowed.size() - 1))];
                    player->TeleportTo(refuge.map, refuge.x, refuge.y, refuge.z, refuge.orientation);
                }
                break;
            }
            case 90537:
            {
                static constexpr std::array<char const*, 6> whispers = {{
                    "Something beneath the earth has noticed you.",
                    "The box remembers hands that have not touched it yet.",
                    "Behind the last door, another door is breathing.",
                    "You count the corners again. There is one more now.",
                    "A voice asks you to stop dreaming its name.",
                    "The silence inside is much larger than the box."
                }};
                ChatHandler(player->GetSession()).PSendSysMessage("|cffb080d0The puzzle box whispers: {}|r", whispers[urand(0, 5)]);
                break;
            }
            case 90540:
            {
                Position pos = player->GetNearPosition(2.0f, 0.0f);
                player->SummonGameObject(9503530, pos.GetPositionX(), pos.GetPositionY(), pos.GetPositionZ(),
                    pos.GetOrientation(), 0, 0, 0, 1, 30);
                player->PlayDistanceSound(11773); // stock non-looping war drum
                break;
            }
            case 90542:
                player->SetDrunkValue(60, 9504143);
                break;
            default:
                break; // cosmetic auras use ordinary core handling
        }
    }

    void Register() override
    {
        OnCheckCast += SpellCheckCastFn(spell_archaeology_reward::CheckCast);
        OnHit += SpellHitFn(spell_archaeology_reward::HandleHit);
    }
};

class spell_archaeology_innkeepers_daughter : public SpellScript
{
    PrepareSpellScript(spell_archaeology_innkeepers_daughter);

    void AfterHearth()
    {
        Item* item = GetCastItem();
        Player* player = GetCaster()->ToPlayer();
        if (!player || !item || item->GetEntry() != 9504126 || !roll_chance_i(20))
            return;
        if (Creature* spirit = Cosmetic(player, 9503610, 2.0f, 0.0f, 15000))
        {
            spirit->GetMotionMaster()->MoveFollow(player, 2.0f, 0.0f);
            spirit->CastSpell(spirit, 90582, true);
        }
    }

    void Register() override
    {
        AfterCast += SpellCastFn(spell_archaeology_innkeepers_daughter::AfterHearth);
    }
};

void AddArchaeologyCompanionScripts();

void AddArchaeologyRewardScripts()
{
    AddArchaeologyCompanionScripts();
    RegisterSpellScript(spell_archaeology_reward);
    RegisterSpellScript(spell_archaeology_innkeepers_daughter);
}
