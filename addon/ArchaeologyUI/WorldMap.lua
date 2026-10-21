-- World map: every dig site on the open zone or continent map gets its area shaded and a shovel
-- icon in the middle, with the race and the finds left in its tooltip.
--
-- The shading is filled scanline by scanline: one plain coloured strip per row span of the
-- outline. That needs no triangle texture and looks the same on every client.

local A = ArchaeologyUI
local SHADE = { 0.85, 0.55, 0.2, 0.35 }
local ICON_SIZE = 20

local overlay = CreateFrame("Frame", "ArchaeologyUIWorldMapOverlay", WorldMapButton)
overlay:SetAllPoints(WorldMapButton)
overlay:SetFrameLevel(WorldMapButton:GetFrameLevel() + 1)

local strips, stripsUsed = {}, 0
local pins, pinsUsed = {}, 0

local function strip()
    stripsUsed = stripsUsed + 1
    local t = strips[stripsUsed]
    if not t then
        t = overlay:CreateTexture(nil, "ARTWORK")
        t:SetTexture(SHADE[1], SHADE[2], SHADE[3], SHADE[4])
        strips[stripsUsed] = t
    end
    t:Show()
    return t
end

local function pinTooltip(self)
    local site = self.site
    local race = A.races[site.race]
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(site.name)
    GameTooltip:AddLine((race and race.name or "Unknown") .. " dig site", 1, 1, 1)
    GameTooltip:AddLine(site.finds .. (site.finds == 1 and " find left" or " finds left"), 0.8, 0.8, 0.8)
    if site.level then
        GameTooltip:AddLine("Recommended level: " .. site.level, 1, 1, 1)
        if site.challenge then GameTooltip:AddLine("Challenging expedition", 1, 0.65, 0.2) end
    end
    GameTooltip:AddLine("Right-click to abandon (30-minute realm default cooldown).", 0.8, 0.8, 0.8, true)
    GameTooltip:Show()
end

StaticPopupDialogs["ARCH_ABANDON_EXPEDITION"] = {
    text = "Abandon %s? Partial site progress is lost. No rewards are granted. A realm cooldown applies.",
    button1 = ACCEPT, button2 = CANCEL, timeout = 0, whileDead = true, hideOnEscape = true,
    OnAccept = function(self) A.Send("ABANDON:" .. self.data) end,
}

local function pin()
    pinsUsed = pinsUsed + 1
    local p = pins[pinsUsed]
    if not p then
        p = CreateFrame("Frame", nil, overlay)
        p:SetSize(ICON_SIZE, ICON_SIZE)
        p:SetFrameLevel(overlay:GetFrameLevel() + 2)
        p.icon = p:CreateTexture(nil, "OVERLAY")
        p.icon:SetAllPoints()
        p.icon:SetTexture(A.SHOVEL)
        p.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        p:EnableMouse(true)
        p:SetScript("OnMouseUp", function(self, button)
            if button == "RightButton" then
                local dialog = StaticPopup_Show("ARCH_ABANDON_EXPEDITION", self.site.name)
                if dialog then dialog.data = self.site.id end
            end
        end)
        p:SetScript("OnEnter", pinTooltip)
        p:SetScript("OnLeave", function() GameTooltip:Hide() end)
        pins[pinsUsed] = p
    end
    p:Show()
    return p
end

-- Fill the polygon (map pixel coordinates, flat x, y list) in rows `step` pixels high, clipped
-- to the w x h map.
local xs = {}
local function fill(px, step, w, h)
    local n = #px
    local top, bottom = math.huge, -math.huge
    for i = 2, n, 2 do
        top, bottom = math.min(top, px[i]), math.max(bottom, px[i])
    end
    local y = math.max(0, math.floor(top))
    bottom = math.min(bottom, h - step)
    while y < bottom do
        local mid = y + step / 2
        wipe(xs)
        local jx, jy = px[n - 1], px[n]
        for i = 1, n, 2 do
            local ix, iy = px[i], px[i + 1]
            if (iy > mid) ~= (jy > mid) then
                tinsert(xs, ix + (mid - iy) * (jx - ix) / (jy - iy))
            end
            jx, jy = ix, iy
        end
        sort(xs)
        for k = 1, #xs - 1, 2 do
            local left, right = math.max(0, xs[k]), math.min(w, xs[k + 1])
            if right - left >= 0.5 then
                local t = strip()
                t:ClearAllPoints()
                t:SetPoint("TOPLEFT", overlay, "TOPLEFT", left, -y)
                t:SetSize(right - left, step)
            end
        end
        y = y + step
    end
end

local function redraw()
    for i = 1, stripsUsed do
        strips[i]:Hide()
    end
    for i = 1, pinsUsed do
        pins[i]:Hide()
    end
    stripsUsed, pinsUsed = 0, 0
    if not WorldMapFrame:IsShown() then
        return
    end
    local bounds = A.MapBounds(false)
    if not bounds then
        return
    end
    local w, h = overlay:GetWidth(), overlay:GetHeight()
    if w <= 0 or h <= 0 then
        return
    end
    -- Zone maps get 2 pixel rows; on a continent a site is only a few pixels tall.
    local step = GetCurrentMapZone() > 0 and 2 or 1
    for _, site in pairs(A.sites) do
        if site.map == bounds[1] then
            local px = {}
            for i = 1, #site.points, 2 do
                local mx, my = A.WorldToMap(bounds, site.points[i], site.points[i + 1])
                px[i], px[i + 1] = mx * w, my * h
            end
            fill(px, step, w, h)
            local mx, my = A.WorldToMap(bounds, site.cx, site.cy)
            if mx >= 0 and mx <= 1 and my >= 0 and my <= 1 then
                local p = pin()
                p.site = site
                p:ClearAllPoints()
                p:SetPoint("CENTER", overlay, "TOPLEFT", mx * w, -my * h)
            end
        end
    end
end
A.RedrawWorldMap = redraw

overlay:RegisterEvent("WORLD_MAP_UPDATE")
overlay:SetScript("OnEvent", redraw)
overlay:SetScript("OnShow", redraw)
overlay:SetScript("OnSizeChanged", redraw)
A.On("SITES", redraw)
A.On("RACES", function()
    if WorldMapFrame:IsShown() then
        redraw()
    end
end)
