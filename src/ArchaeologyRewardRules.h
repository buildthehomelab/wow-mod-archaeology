#pragma once
#include <array>
#include <cstdint>

namespace ArchaeologyRewards
{
    struct Companion { uint32_t item; uint32_t spell; };
    constexpr std::array<Companion, 5> Companions = {{
        {9504036, 410266}, {9504083, 400386}, {9504070, 90560}, {9504144, 90561}, {9504145, 90562}
    }};

    constexpr bool IsCompanion(uint32_t item, uint32_t spell)
    {
        for (auto const& companion : Companions)
            if (companion.item == item && companion.spell == spell)
                return true;
        return false;
    }
}
