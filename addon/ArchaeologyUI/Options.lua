-- Interface Options page (Interface > AddOns > ArchaeologyUI): turn the minimap pins on or off.
-- /arch options opens it.

local A = ArchaeologyUI

local panel = CreateFrame("Frame", "ArchaeologyUIOptions", UIParent)
panel.name = "ArchaeologyUI"
panel:Hide()

local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
title:SetPoint("TOPLEFT", 16, -16)
title:SetText("ArchaeologyUI")

local minimap = CreateFrame("CheckButton", "ArchaeologyUIOptionsMinimap", panel, "InterfaceOptionsCheckButtonTemplate")
minimap:SetPoint("TOPLEFT", title, "BOTTOMLEFT", -2, -12)
_G[minimap:GetName() .. "Text"]:SetText("Show dig sites on the minimap")
minimap:SetScript("OnClick", function(self)
    A.SetMinimapShown(self:GetChecked() and true or false)
end)

panel:SetScript("OnShow", function()
    minimap:SetChecked(A.MinimapShown())
end)
A.On("MINIMAP", function(on)
    minimap:SetChecked(on)
end)

InterfaceOptions_AddCategory(panel)

function A.OpenOptions()
    -- Twice: the first call on a fresh session only opens the frame on its first category.
    InterfaceOptionsFrame_OpenToCategory(panel)
    InterfaceOptionsFrame_OpenToCategory(panel)
end
