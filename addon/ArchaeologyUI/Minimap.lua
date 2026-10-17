-- Minimap: a shovel pin for each dig site on the map you are on. A site in range sits where it
-- is; one farther away waits on the minimap's edge, a little faded, pointing the way.
--
-- Our own pin math (no Astrolabe): the minimap shows a fixed number of yards across at each zoom
-- level, a different set indoors, and turns with the player when "Rotate Minimap" is on.

local A = ArchaeologyUI
local UPDATE_INTERVAL = 0.05
local PIN_SIZE = 14
local EDGE_ALPHA = 0.6

-- Yards across the whole minimap by zoom level (0 = farthest out).
local DIAMETER = {
    outdoor = { [0] = 466 + 2 / 3, 400, 333 + 1 / 3, 266 + 2 / 3, 200, 133 + 1 / 3 },
    indoor = { [0] = 300, 240, 180, 120, 80, 50 },
}

local holder = CreateFrame("Frame", nil, Minimap)
holder:SetAllPoints(Minimap)
holder:SetFrameLevel(Minimap:GetFrameLevel() + 5)

local pins = {}

local function pinTooltip(self)
    local site = self.site
    local race = A.races[site.race]
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText(site.name)
    GameTooltip:AddLine((race and race.name or "Unknown") .. " dig site", 1, 1, 1)
    GameTooltip:AddLine(site.finds .. (site.finds == 1 and " find left" or " finds left"), 0.8, 0.8, 0.8)
    if self.distance then
        GameTooltip:AddLine(math.floor(self.distance) .. " yards", 0.8, 0.8, 0.8)
    end
    GameTooltip:Show()
end

local function pin(i)
    local p = pins[i]
    if not p then
        p = CreateFrame("Frame", nil, holder)
        p:SetSize(PIN_SIZE, PIN_SIZE)
        p.icon = p:CreateTexture(nil, "OVERLAY")
        p.icon:SetAllPoints()
        p.icon:SetTexture(A.SHOVEL)
        p.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        p:EnableMouse(true)
        p:SetScript("OnEnter", pinTooltip)
        p:SetScript("OnLeave", function() GameTooltip:Hide() end)
        pins[i] = p
    end
    return p
end

-- The minimap keeps one zoom indoors and one outdoors. When both CVars match we can't tell which
-- is in use without nudging the zoom, so do that once and put it back.
local indoors, checking = false, false
local function checkIndoors()
    if checking then
        return  -- our own SetZoom below fires MINIMAP_UPDATE_ZOOM again
    end
    checking = true
    local zoom = Minimap:GetZoom()
    if GetCVar("minimapZoom") == GetCVar("minimapInsideZoom") then
        Minimap:SetZoom(zoom < 2 and zoom + 1 or zoom - 1)
    end
    indoors = tonumber(GetCVar("minimapZoom")) ~= Minimap:GetZoom()
    Minimap:SetZoom(zoom)
    checking = false
end

local function isSquare()
    return GetMinimapShape and GetMinimapShape() == "SQUARE"
end

local function hideAll(from)
    for i = from, #pins do
        pins[i]:Hide()
    end
end

local function update()
    local pos = A.position
    if not pos.valid then
        hideAll(1)
        return
    end
    local radius = Minimap:GetWidth() / 2
    local yards = (DIAMETER[indoors and "indoor" or "outdoor"][Minimap:GetZoom()] or 400) / 2
    local scale = radius / yards
    local rotate = GetCVar("rotateMinimap") == "1"
    local facing = rotate and GetPlayerFacing() or 0
    local s, c = math.sin(-facing), math.cos(-facing)
    local square, edge = isSquare(), radius - PIN_SIZE / 2 - 2

    local n = 0
    for _, site in pairs(A.sites) do
        if site.map == pos.map then
            -- North is world +x, east is world -y; screen right is +x, up is +y.
            local dx, dy = pos.y - site.cy, site.cx - pos.x
            if rotate then
                dx, dy = dx * c - dy * s, dx * s + dy * c
            end
            local distance = math.sqrt(dx * dx + dy * dy)
            local sx, sy = dx * scale, dy * scale
            local reach = square and math.max(math.abs(sx), math.abs(sy)) or math.sqrt(sx * sx + sy * sy)
            n = n + 1
            local p = pin(n)
            p.site, p.distance = site, distance
            if reach > edge then
                sx, sy = sx * edge / reach, sy * edge / reach
                p:SetAlpha(EDGE_ALPHA)
            else
                p:SetAlpha(1)
            end
            p:ClearAllPoints()
            p:SetPoint("CENTER", holder, "CENTER", sx, sy)
            p:Show()
        end
    end
    hideAll(n + 1)
end

local elapsedSince = 0
holder:SetScript("OnUpdate", function(self, elapsed)
    elapsedSince = elapsedSince + elapsed
    if elapsedSince >= UPDATE_INTERVAL then
        elapsedSince = 0
        update()
    end
end)

holder:RegisterEvent("MINIMAP_UPDATE_ZOOM")
holder:RegisterEvent("PLAYER_ENTERING_WORLD")
holder:RegisterEvent("ZONE_CHANGED_NEW_AREA")
holder:RegisterEvent("ZONE_CHANGED_INDOORS")
holder:SetScript("OnEvent", function()
    checkIndoors()
end)
A.On("SITES", update)
