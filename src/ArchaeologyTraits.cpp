/*
 * mod-archaeology: the Unearthed Relic's traits, one per race.
 *
 * A race's trait wakes when one of its rares is solved, or after enough of its commons. While
 * the relic is equipped every awake trait is an aura on the character (spells 90507-90514, with
 * rows in the client patch for the tooltips); what it does comes from mod_archaeology_relic_trait.
 * A trait is stronger the further up its ladder the relic stands, and twice as strong once every
 * project of its race is solved. The aura carries that strength, so a proc needs no lookup of
 * the character's archaeology state.
 *
 * Released under the MIT License.
 */

#include "Archaeology.h"
#include "GameTime.h"
#include "Group.h"
#include "Log.h"
#include "Player.h"
#include "Random.h"
#include "SpellAuraEffects.h"
#include "SpellInfo.h"
#include "SpellMgr.h"
#include "SpellScript.h"
#include "SpellScriptLoader.h"
#include <atomic>
#include <cmath>
#include <mutex>
#include <unordered_set>

namespace
{
    using namespace Archaeology;

    constexpr uint32 MODULE_SPELL_FIRST = 90500;
    constexpr uint32 MODULE_SPELL_LAST = 90529;
    constexpr float STRENGTH_SCALE = 10000.0f;   // strengths are stored on the aura as factor x 10000

    enum TraitKind : uint8
    {
        TRAIT_EMBER = 1,   // hits add fire damage: value % of attack or spell power
        TRAIT_FOCUS,       // restore value % of max mana, or value2 rage or runic power (energy 2 x value2)
        TRAIT_VIGOR,       // value % haste
        TRAIT_AMBER,       // when struck (ppm = % chance per hit): absorb value % of max health
        TRAIT_NAARU,       // heal you or the most hurt group member within value2 yards for value % of max health
        TRAIT_HORDE,       // up to value % more damage, all of it at value2 % health
        TRAIT_VENOM,       // stacking poison: value % of attack or spell power per stack over its duration
        TRAIT_MERCY,       // a killing blow leaves you at value % health; cooldown_ms between saves
        TRAIT_KIND_END
    };

    constexpr char const* KIND_TEXT[TRAIT_KIND_END] = {
        "",
        "your hits sometimes add Fire damage",
        "your hits and spells sometimes restore mana, rage, energy or runic power",
        "your hits and spells sometimes grant a burst of haste",
        "being struck sometimes wraps you in a damage-absorbing shield",
        "your hits and heals sometimes heal you or a hurt ally",
        "you deal more damage as your health falls",
        "your hits sometimes poison the target, stacking up to 5 times",
        "a killing blow leaves you alive instead, once every so often",
    };

    struct Trait
    {
        uint8 race = 0;
        uint8 kind = 0;
        std::string name;
        uint32 aura = 0;
        uint32 effect = 0;
        float ppm = 0.0f;
        uint32 cooldownMs = 0;
        float value = 0.0f;
        float value2 = 0.0f;
    };

    std::vector<Trait> traits;
    // Characters whose trait auras need a look. Player updates run on several map threads at once.
    std::mutex queueLock;
    std::unordered_set<ObjectGuid> queued;
    std::atomic<uint32> queuedCount { 0 };

    Trait const* TraitByAura(uint32 spell)
    {
        for (Trait const& t : traits)
            if (t.aura == spell)
                return &t;
        return nullptr;
    }

    bool TraitsOn()
    {
        Config const& cfg = GetConfig();
        return cfg.enabled && cfg.relicEnabled && cfg.traitsEnabled;
    }

    // Checked again on every use: an aura can outlive its relic by a moment (a relic deleted
    // straight from its slot), and must do nothing then.
    // A lingering aura asks for a refresh, which takes it off.
    bool TraitWorks(Unit* owner)
    {
        Player* player = owner ? owner->ToPlayer() : nullptr;
        if (!player)
            return false;
        if (TraitsOn() && IsRelicEquipped(player))
            return true;
        QueueTraits(player);
        return false;
    }

    // The strengths on the aura are the module's, never the spell's base points: a reload from
    // the character's saved auras keeps them instead of recalculating them to 0.
    void KeepAmount(AuraEffect const* /*aurEff*/, int32& /*amount*/, bool& canBeRecalculated)
    {
        canBeRecalculated = false;
    }

    uint32 CommonSolves(CharState const& s, uint8 race, bool& rare)
    {
        uint32 commons = 0;
        rare = false;
        for (uint32 pid : ProjectsOfRace(race))
        {
            auto itr = s.solved.find(pid);
            if (itr == s.solved.end() || !itr->second)
                continue;
            if (GetProject(pid)->rare)
                rare = true;
            else
                commons += itr->second;
        }
        return commons;
    }

    bool Earned(CharState const& s, uint8 race)
    {
        bool rare = false;
        uint32 commons = CommonSolves(s, race, rare);
        return rare || commons >= GetConfig().traitWakeCommons;
    }

    uint32 CompleteBits(CharState const& s)
    {
        uint32 bits = 0;
        for (Race const& race : AllRaces())
            if (IsRaceComplete(s, race.id))
                bits |= 1u << race.id;
        return bits;
    }

    // first rank strength at the bottom of the ladder, 1.0 at the top; the step the relic shows,
    // so level and progression hold traits back just as they hold back the item.
    float RankFactor(Player* player)
    {
        Config const& cfg = GetConfig();
        uint32 count = RelicRankCount();
        float climb = count > 1 ? float(std::min(RelicShownStep(player), count - 1)) / float(count - 1) : 1.0f;
        return cfg.traitFirstRank + (1.0f - cfg.traitFirstRank) * climb;
    }

    // The effect holding a trait's strength, and for Val'kyr's Mercy the one holding its bonus.
    SpellEffIndex StrengthEffect(Trait const& t)
    {
        return t.kind == TRAIT_HORDE || t.kind == TRAIT_MERCY ? EFFECT_1 : EFFECT_0;
    }

    void SetAmount(Aura* aura, SpellEffIndex index, int32 amount)
    {
        if (AuraEffect* eff = aura->GetEffect(index))
            if (eff->GetAmount() != amount)
                eff->ChangeAmount(amount);
    }

    void RefreshTraits(Player* player)
    {
        CharState* s = GetState(player);
        bool on = TraitsOn() && s && s->relic.rank && IsRelicEquipped(player);
        float factor = on ? RankFactor(player) : 0.0f;
        for (Trait const& t : traits)
        {
            bool want = on && (s->relic.traits & (1u << t.race));
            Aura* aura = player->GetAura(t.aura);
            if (!want)
            {
                if (aura)
                    player->RemoveAurasDueToSpell(t.aura);
                continue;
            }
            if (!aura && !(aura = player->AddAura(t.aura, player)))
                continue;
            float bonus = IsRaceComplete(*s, t.race) ? GetConfig().traitCompleteBonus : 1.0f;
            if (t.kind == TRAIT_MERCY)
            {
                // The bonus shortens Mercy's cooldown instead of raising the health it leaves.
                SetAmount(aura, EFFECT_1, int32(std::lround(factor * STRENGTH_SCALE)));
                SetAmount(aura, EFFECT_2, int32(std::lround(bonus * STRENGTH_SCALE)));
            }
            else
                SetAmount(aura, StrengthEffect(t), int32(std::lround(factor * bonus * STRENGTH_SCALE)));
        }
    }

    // What a trait's percentages of "power" are of: the higher of attack and spell power.
    float Power(Player* player)
    {
        return std::max({ player->GetTotalAttackPowerValue(BASE_ATTACK), player->GetTotalAttackPowerValue(RANGED_ATTACK),
            float(player->SpellBaseDamageBonusDone(SPELL_SCHOOL_MASK_MAGIC)), float(player->SpellBaseHealingBonusDone(SPELL_SCHOOL_MASK_ALL)) });
    }

    int32 AtLeastOne(float value)
    {
        return std::max<int32>(1, int32(std::lround(value)));
    }

    // You, or the group member within `yards` missing the largest share of their health.
    Unit* MostHurtAlly(Player* player, float yards)
    {
        Unit* best = player;
        Group* group = player->GetGroup();
        if (!group)
            return best;
        for (GroupReference* ref = group->GetFirstMember(); ref; ref = ref->next())
        {
            Player* member = ref->GetSource();
            if (!member || member == player || member->GetMap() != player->GetMap() || !member->IsInWorld() || !member->IsAlive() ||
                !member->IsWithinDistInMap(player, yards))
                continue;
            if (member->GetHealthPct() < best->GetHealthPct())
                best = member;
        }
        return best;
    }
}

// The traits that proc: Thaurissan's Ember, Highborne Focus, Zandalari Vigor, Amber Ward,
// Light of the Naaru and Ahn'kahar Venom. A proc chance per minute is turned into a chance per
// hit from the speed of the weapon that hit (a cast's time for spells), and split between the
// hands when two weapons swing, so a pair procs as often as a two-hander. A spell that hits many
// targets rolls once, on its first target.
class spell_archaeology_trait_proc : public AuraScript
{
    PrepareAuraScript(spell_archaeology_trait_proc);

    // The cast that rolled last. A Spell's address is reused once it's freed, so the spell id and
    // the tick (a cast's targets are all hit in one) make sure it really is the same cast.
    Spell const* _lastCast = nullptr;
    uint32 _lastCastSpell = 0;
    uint32 _lastCastTime = 0;

    void CalcStrength(AuraEffect const* aurEff, int32& amount, bool& canBeRecalculated)
    {
        KeepAmount(aurEff, amount, canBeRecalculated);
    }

    bool CheckProc(ProcEventInfo& eventInfo)
    {
        Trait const* t = TraitByAura(GetId());
        Player* player = GetUnitOwner()->ToPlayer();
        if (!t || !player || !TraitWorks(player))
            return false;
        SpellInfo const* spell = eventInfo.GetSpellInfo();
        if (spell && spell->Id >= MODULE_SPELL_FIRST && spell->Id <= MODULE_SPELL_LAST)
            return false;
        if (t->kind == TRAIT_AMBER)
            return roll_chance_f(t->ppm);
        if (Spell const* cast = eventInfo.GetProcSpell(); cast && spell)
        {
            uint32 now = GameTime::GetGameTimeMS().count();
            if (cast == _lastCast && spell->Id == _lastCastSpell && now == _lastCastTime)
                return false;
            _lastCast = cast;
            _lastCastSpell = spell->Id;
            _lastCastTime = now;
        }

        float seconds = 1.5f;
        uint32 hands = 1;
        if (!spell || spell->DmgClass == SPELL_DAMAGE_CLASS_MELEE || spell->DmgClass == SPELL_DAMAGE_CLASS_RANGED)
        {
            WeaponAttackType attack = eventInfo.GetDamageInfo() ? eventInfo.GetDamageInfo()->GetAttackType() : BASE_ATTACK;
            seconds = player->GetAttackTime(attack) / 1000.0f;
            if (attack != RANGED_ATTACK && player->HasOffhandWeaponForAttack())
                hands = 2;
        }
        else
            seconds = std::max(1.5f, spell->CalcCastTime(player) / 1000.0f);
        return roll_chance_f(t->ppm * seconds / 60.0f / hands * 100.0f);
    }

    void HandleProc(AuraEffect const* aurEff, ProcEventInfo& eventInfo)
    {
        PreventDefaultAction();
        Trait const* t = TraitByAura(GetId());
        Player* player = GetUnitOwner()->ToPlayer();
        if (!t || !player)
            return;
        float scale = aurEff->GetAmount() / STRENGTH_SCALE;
        Unit* target = eventInfo.GetActionTarget();
        bool hostile = target && target != player && player->IsValidAttackTarget(target);
        bool fired = true;
        switch (t->kind)
        {
            case TRAIT_EMBER:
            {
                if (!hostile)
                    return;
                int32 damage = AtLeastOne(Power(player) * t->value / 100.0f * scale);
                player->CastCustomSpell(target, t->effect, &damage, nullptr, nullptr, true, nullptr, aurEff);
                break;
            }
            case TRAIT_FOCUS:
            {
                Powers power = player->getPowerType();
                float amount = 0.0f;
                if (power == POWER_MANA)
                    amount = player->GetMaxPower(POWER_MANA) * t->value / 100.0f;
                else if (power == POWER_RAGE || power == POWER_RUNIC_POWER)
                    amount = t->value2 * 10.0f;   // rage and runic power count in tenths
                else if (power == POWER_ENERGY)
                    amount = t->value2 * 2.0f;
                if (amount <= 0.0f)
                    return;
                player->EnergizeBySpell(player, t->effect, uint32(AtLeastOne(amount * scale)), power);
                break;
            }
            case TRAIT_VIGOR:
            {
                int32 haste = AtLeastOne(t->value * scale);
                player->CastCustomSpell(player, t->effect, &haste, &haste, &haste, true, nullptr, aurEff);
                break;
            }
            case TRAIT_AMBER:
            {
                int32 absorb = AtLeastOne(player->GetMaxHealth() * t->value / 100.0f * scale);
                player->CastCustomSpell(player, t->effect, &absorb, nullptr, nullptr, true, nullptr, aurEff);
                break;
            }
            case TRAIT_NAARU:
            {
                Unit* ally = MostHurtAlly(player, t->value2);
                int32 heal = AtLeastOne(ally->GetMaxHealth() * t->value / 100.0f * scale);
                player->CastCustomSpell(ally, t->effect, &heal, nullptr, nullptr, true, nullptr, aurEff);
                break;
            }
            case TRAIT_VENOM:
            {
                SpellInfo const* venom = sSpellMgr->GetSpellInfo(t->effect);
                if (!hostile || !venom || !venom->Effects[EFFECT_0].Amplitude)
                    return;
                int32 ticks = std::max<int32>(1, venom->GetMaxDuration() / int32(venom->Effects[EFFECT_0].Amplitude));
                int32 tick = AtLeastOne(Power(player) * t->value / 100.0f * scale / ticks);
                player->CastCustomSpell(target, t->effect, &tick, nullptr, nullptr, true, nullptr, aurEff);
                break;
            }
            default:
                fired = false;
                break;
        }
        if (fired && t->cooldownMs)
            GetAura()->AddProcCooldown(std::chrono::steady_clock::now() + Milliseconds(t->cooldownMs));
    }

    void Register() override
    {
        DoEffectCalcAmount += AuraEffectCalcAmountFn(spell_archaeology_trait_proc::CalcStrength, EFFECT_0, SPELL_AURA_DUMMY);
        DoCheckProc += AuraCheckProcFn(spell_archaeology_trait_proc::CheckProc);
        OnEffectProc += AuraEffectProcFn(spell_archaeology_trait_proc::HandleProc, EFFECT_0, SPELL_AURA_DUMMY);
    }
};

// Blood of the Horde: effect 0 is the damage bonus, worked out each second from health.
class spell_archaeology_trait_horde : public AuraScript
{
    PrepareAuraScript(spell_archaeology_trait_horde);

    void HandlePeriodic(AuraEffect const* aurEff)
    {
        Trait const* t = TraitByAura(GetId());
        AuraEffect* bonus = GetEffect(EFFECT_0);
        Unit* owner = GetUnitOwner();
        if (!t || !bonus)
            return;
        int32 want = 0;
        if (TraitWorks(owner) && owner->IsAlive())
        {
            float span = std::max(1.0f, 100.0f - t->value2);
            float fallen = std::clamp((100.0f - owner->GetHealthPct()) / span, 0.0f, 1.0f);
            want = int32(std::lround(t->value * aurEff->GetAmount() / STRENGTH_SCALE * fallen));
        }
        if (bonus->GetAmount() != want)
            bonus->ChangeAmount(want);
    }

    void CalcStrength(AuraEffect const* aurEff, int32& amount, bool& canBeRecalculated)
    {
        KeepAmount(aurEff, amount, canBeRecalculated);
    }

    void Register() override
    {
        DoEffectCalcAmount += AuraEffectCalcAmountFn(spell_archaeology_trait_horde::CalcStrength, EFFECT_1, SPELL_AURA_PERIODIC_DUMMY);
        OnEffectPeriodic += AuraEffectPeriodicFn(spell_archaeology_trait_horde::HandlePeriodic, EFFECT_1, SPELL_AURA_PERIODIC_DUMMY);
    }
};

// Val'kyr's Mercy: an endless absorb that only takes a killing blow, leaving value % health.
// The effect spell is its cooldown, a debuff that lasts cooldown_ms (shortened by the bonus).
class spell_archaeology_trait_mercy : public AuraScript
{
    PrepareAuraScript(spell_archaeology_trait_mercy);

    void CalculateAmount(AuraEffect const* /*aurEff*/, int32& amount, bool& /*canBeRecalculated*/)
    {
        amount = -1;
    }

    void CalcStrength(AuraEffect const* aurEff, int32& amount, bool& canBeRecalculated)
    {
        KeepAmount(aurEff, amount, canBeRecalculated);
    }

    // The share of an absorb the attacker ignores; the core takes it off after this script.
    static float IgnoredAbsorbPct(Unit* attacker, DamageInfo const& dmgInfo)
    {
        if (!attacker)
            return 0.0f;
        SpellSchoolMask school = dmgInfo.GetSchoolMask();
        SpellInfo const* spell = dmgInfo.GetSpellInfo();
        float pct = float(attacker->GetMaxPositiveAuraModifierByMiscMask(SPELL_AURA_MOD_TARGET_ABSORB_SCHOOL, school));
        pct = std::max(pct, float(attacker->GetMaxPositiveAuraModifier(SPELL_AURA_MOD_TARGET_ABILITY_ABSORB_SCHOOL, [spell, school](AuraEffect const* eff)
        {
            return (eff->GetMiscValue() & school) && eff->IsAffectedOnSpell(spell);
        })));
        return std::clamp(pct, 0.0f, 100.0f);
    }

    void Absorb(AuraEffect* aurEff, DamageInfo& dmgInfo, uint32& absorbAmount)
    {
        Trait const* t = TraitByAura(GetId());
        Unit* target = GetTarget();
        AuraEffect const* strength = GetEffect(EFFECT_1);
        AuraEffect const* bonus = GetEffect(EFFECT_2);
        if (!t || !strength || !bonus || target->HasAura(t->effect) || dmgInfo.GetDamage() < target->GetHealth() || !TraitWorks(target))
            return;
        // Not in a duel: a duel never kills.
        Unit* attacker = dmgInfo.GetAttacker();
        if (Player* foe = attacker ? attacker->GetCharmerOrOwnerPlayerOrPlayerItself() : nullptr)
            if (target->ToPlayer() && target->ToPlayer()->duel && target->ToPlayer()->duel->Opponent == foe)
                return;
        // Other shields that will take the hit leave the save unspent. Only when the attacker
        // ignores none of it: otherwise a shield already used on this hit still shows an amount,
        // and counting it could let the player die with the save unspent. Whatever the attacker
        // ignores of this absorb counts against the save.
        float kept = 1.0f - IgnoredAbsorbPct(attacker, dmgInfo) / 100.0f;
        uint64 shields = 0;
        if (kept >= 1.0f)
            for (AuraEffect const* other : target->GetAuraEffectsByType(SPELL_AURA_SCHOOL_ABSORB))
                if (other != aurEff && other->GetAmount() > 0 && (other->GetMiscValue() & dmgInfo.GetSchoolMask()))
                    shields += uint32(other->GetAmount());
        uint32 damage = dmgInfo.GetDamage();
        uint32 through = uint32(damage - std::min<uint64>(damage, uint64(shields * kept)));
        if (through < target->GetHealth())
            return;

        uint32 keep = std::max<uint32>(1, target->CountPctFromMaxHealth(int32(std::lround(t->value * strength->GetAmount() / STRENGTH_SCALE))));
        keep = std::min(keep, target->GetHealth());
        uint32 need = through - target->GetHealth() + keep;
        if (kept <= 0.0f || need > damage * kept)
            return;   // the attacker ignores too much of it: the save couldn't hold, so it isn't spent
        absorbAmount = std::min<uint32>(damage, uint32(std::ceil(need / kept)));
        if (Aura* spent = target->AddAura(t->effect, target))
        {
            int32 ms = int32(t->cooldownMs / std::max(1.0f, bonus->GetAmount() / STRENGTH_SCALE));
            spent->SetMaxDuration(ms);
            spent->SetDuration(ms);
        }
    }

    void Register() override
    {
        DoEffectCalcAmount += AuraEffectCalcAmountFn(spell_archaeology_trait_mercy::CalculateAmount, EFFECT_0, SPELL_AURA_SCHOOL_ABSORB);
        DoEffectCalcAmount += AuraEffectCalcAmountFn(spell_archaeology_trait_mercy::CalcStrength, EFFECT_1, SPELL_AURA_DUMMY);
        DoEffectCalcAmount += AuraEffectCalcAmountFn(spell_archaeology_trait_mercy::CalcStrength, EFFECT_2, SPELL_AURA_DUMMY);
        OnEffectAbsorb += AuraEffectAbsorbFn(spell_archaeology_trait_mercy::Absorb, EFFECT_0);
    }
};

namespace Archaeology
{
    void LoadTraitData()
    {
        traits.clear();
        if (QueryResult result = WorldDatabase.Query("SELECT `race`, `kind`, `name`, `aura_spell`, `effect_spell`, `ppm`, `cooldown_ms`, `value`, `value2` "
            "FROM `mod_archaeology_relic_trait` ORDER BY `race`"))
        {
            do
            {
                Field* f = result->Fetch();
                Trait t;
                t.race = f[0].Get<uint8>();
                t.kind = f[1].Get<uint8>();
                t.name = f[2].Get<std::string>();
                t.aura = f[3].Get<uint32>();
                t.effect = f[4].Get<uint32>();
                t.ppm = f[5].Get<float>();
                t.cooldownMs = f[6].Get<uint32>();
                t.value = f[7].Get<float>();
                t.value2 = f[8].Get<float>();
                if (t.race >= 32 || !GetRace(t.race) || !t.kind || t.kind >= TRAIT_KIND_END || !sSpellMgr->GetSpellInfo(t.aura) ||
                    !sSpellMgr->GetSpellInfo(t.effect))
                {
                    LOG_ERROR("module", "mod-archaeology: relic trait for race {} names an unknown race, kind or spell; left out", t.race);
                    continue;
                }
                traits.push_back(t);
            } while (result->NextRow());
        }
        LOG_INFO("module", "mod-archaeology: {} relic traits", traits.size());
    }

    bool IsRaceComplete(CharState const& s, uint8 race)
    {
        std::vector<uint32> const& projects = ProjectsOfRace(race);
        if (projects.empty())
            return false;
        for (uint32 pid : projects)
            if (!s.solved.count(pid))
                return false;
        return true;
    }

    // Wake traits whose race has earned it. The bits are kept (never cleared), so a trait stays
    // awake whatever the config says later. With `announce`, new traits and doublings are told.
    void UpdateTraitWake(Player* player, bool announce)
    {
        CharState* s = GetState(player);
        if (!s || !s->skill)
            return;
        RelicState& r = s->relic;
        uint32 before = r.traits, wasComplete = r.complete;
        for (Race const& race : AllRaces())
            if (race.id < 32 && Earned(*s, race.id))
                r.traits |= 1u << race.id;
        r.complete = CompleteBits(*s);
        if (r.traits != before)
            SaveRelic(player);
        if (!announce || !r.rank)
            return;
        for (Trait const& t : traits)
        {
            uint32 bit = 1u << t.race;
            Race const* race = GetRace(t.race);
            if ((r.traits & bit) && !(before & bit))
                Notify(player, Acore::StringFormat("|cffe6cc80{} wakes in your Unearthed Relic:|r {}.", t.name, KIND_TEXT[t.kind]));
            if ((r.complete & bit) && !(wasComplete & bit) && race)
                Notify(player, Acore::StringFormat("|cffe6cc80{} grows twice as strong:|r you have solved every {} project.", t.name, race->name));
        }
    }

    void QueueTraits(Player* player)
    {
        std::lock_guard<std::mutex> lock(queueLock);
        if (queued.insert(player->GetGUID()).second)
            ++queuedCount;
    }

    // From the player update, combat or not: traits follow the weapon at once.
    void UpdateQueuedTraits(Player* player)
    {
        if (!queuedCount.load(std::memory_order_relaxed) || !player->IsInWorld())
            return;
        {
            std::lock_guard<std::mutex> lock(queueLock);
            if (!queued.erase(player->GetGUID()))
                return;
            --queuedCount;
        }
        RefreshTraits(player);
        CheckRelicAchievements(player);
    }

    void ForgetTraits(Player* player)
    {
        std::lock_guard<std::mutex> lock(queueLock);
        if (queued.erase(player->GetGUID()))
            --queuedCount;
    }

    void RemoveTraits(Player* player)
    {
        for (Trait const& t : traits)
            player->RemoveAurasDueToSpell(t.aura);
    }

    std::string TraitStatusText(Player* player)
    {
        CharState* s = GetState(player);
        if (!s || !s->relic.rank || traits.empty() || !GetConfig().traitsEnabled)
            return "";
        float factor = RankFactor(player);
        bool equipped = IsRelicEquipped(player);
        std::string text = equipped ? "Traits:" : "Traits (equip the relic to use them):";
        for (Trait const& t : traits)
        {
            Race const* race = GetRace(t.race);
            if (s->relic.traits & (1u << t.race))
            {
                bool complete = IsRaceComplete(*s, t.race);
                float strength = factor * (complete && t.kind != TRAIT_MERCY ? GetConfig().traitCompleteBonus : 1.0f);
                text += Acore::StringFormat("\n  {}: {} ({}% strength{}).", t.name, KIND_TEXT[t.kind], int32(std::lround(strength * 100.0f)),
                    complete ? (t.kind == TRAIT_MERCY ? ", shorter cooldown" : ", doubled") : "");
            }
            else if (race)
            {
                bool rare = false;
                uint32 commons = CommonSolves(*s, t.race, rare);
                text += Acore::StringFormat("\n  {}: asleep. Solve a {} rare, or {} commons ({} so far).", t.name, race->name,
                    GetConfig().traitWakeCommons, commons);
            }
        }
        return text;
    }
}

void AddArchaeologyTraitScripts()
{
    RegisterSpellScript(spell_archaeology_trait_proc);
    RegisterSpellScript(spell_archaeology_trait_horde);
    RegisterSpellScript(spell_archaeology_trait_mercy);
}
