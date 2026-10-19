-- Without DragonUI's professions window, RetailProfessions' own profession window (1.17 and
-- later: its RetailProfessions.Pages) takes the research view the same way: Archaeology's side
-- tab there opens it as a page of that window, the other tabs staying. The relic and the races
-- go in the list column, the project on the recipe card and your skill on the window's skill
-- bar. /arch, the key binding, the survey button's right-click and the fragments bar open that
-- page; our own window (Research.lua) is used when RetailProfessions isn't loaded, or when it
-- isn't using its own window (it lives in DragonUI's, which Hosted.lua serves, or /prof classic).

local A = ArchaeologyUI
local R = A.Research
local PAGE = "archaeology"
local TITLE = "Archaeology"
-- Where the headers start in the list column, their height, the indent of the races under them.
local AREA_X, AREA_Y, HEADER_H, INDENT = 8, -8, 25, 10
-- Archaeology has no DragonUI art of its own: with that art, the bar's fill and the card's drawing are Mining's.
local ART_KEY = "Mining"

-- RetailProfessions' pages, when it has them.
local function api()
    local RP = _G.RetailProfessions
    local Pages = type(RP) == "table" and RP.Pages
    if type(Pages) == "table" and (Pages.VERSION or 0) >= 1 and Pages.Add and Pages.Has and Pages.Open
            and Pages.Toggle and Pages.Shown and Pages.Refresh then
        return Pages
    end
    return nil
end

local panel, rows = nil, {}

-- The relic header and its line go when there is no relic; the races header moves up.
local function layout(hasRelic)
    local relic = panel.relic
    if hasRelic then
        relic:Show()
        relic.line:Show()
    else
        relic:Hide()
        relic.line:Hide()
    end
    panel.races:ClearAllPoints()
    panel.races:SetPoint("TOPLEFT", panel.list, "TOPLEFT", AREA_X, hasRelic and AREA_Y - HEADER_H - 30 or AREA_Y)
    panel.races:SetPoint("RIGHT", panel.list, "RIGHT", -AREA_X, 0)
end

local function rowFor(i)
    local row = rows[i]
    if row then return row end
    row = R.NewRaceRow(panel.list)
    row:SetPoint("TOPLEFT", panel.races, "BOTTOMLEFT", INDENT, -4 - (i - 1) * R.ROW_HEIGHT)
    row:SetPoint("RIGHT", panel.races, "RIGHT", 0, 0)
    rows[i] = row
    return row
end

-- The page's column: the relic on top (where the search box is on the recipes), then the races.
local function build(p)
    panel = p
    local list = p.list
    local relic = p.Header(list, "Unearthed Relic")
    relic:SetPoint("TOPLEFT", list, "TOPLEFT", AREA_X, AREA_Y)
    relic:SetPoint("RIGHT", list, "RIGHT", -AREA_X, 0)
    relic:EnableMouse(true)
    relic:SetScript("OnEnter", function(self)
        if not self.tip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Unearthed Relic")
        GameTooltip:AddLine(self.tip, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    relic:SetScript("OnLeave", function() GameTooltip:Hide() end)
    relic.line = list:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    relic.line:SetPoint("TOPLEFT", relic, "BOTTOMLEFT", 8, -6)
    relic.line:SetPoint("RIGHT", relic, "RIGHT", -8, 0)
    relic.line:SetJustifyH("LEFT")
    relic.line:SetWordWrap(false)
    p.relic = relic
    p.races = p.Header(list, "Races")
    layout(false)
end

-- The project on the page's card, and the empty-state text over the page; our window has them
-- back when it is the one used (R.TakeBack).
local function attach()
    local card = panel.card
    local page = R.page
    if page:GetParent() ~= card then
        page:SetParent(card)
        page:ClearAllPoints()
        if panel.art then
            page:SetPoint("TOPLEFT", card, "TOPLEFT", 18, -18)
            page:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -16, 14)
        else
            page:SetPoint("TOPLEFT", card, "TOPLEFT", 12, -12)
            page:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -12, 10)
        end
        -- On DragonUI's parchment the card is the box.
        R.LoreBox(not panel.art)
        local empty = R.empty
        empty:SetParent(panel)
        empty:ClearAllPoints()
        empty:SetPoint("CENTER", panel, "CENTER", 0, -20)
        empty:SetWidth(360)
    end
    if ArchaeologyUIFrame and ArchaeologyUIFrame:IsShown() then ArchaeologyUIFrame:Hide() end
end

local function drawRelic(text)
    local r = A.relic
    if not (r and text and text ~= "") then
        layout(false)
        return
    end
    local relic = panel.relic
    local color = r.rank > 0 and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[r.quality]
    if color then
        relic.label:SetTextColor(color.r, color.g, color.b)
    else
        relic.label:SetTextColor(0.9, 0.8, 0.5)
    end
    local power = r.cost > 0 and string.format("Relic Power %d/%d", r.power, r.cost)
        or string.format("Relic Power %d", r.power)
    if r.rank > 0 then
        relic.note:SetText(string.format("Rank %d/%d", r.rank, r.ranks))
        relic.line:SetText(string.format("Item level %d  -  %s", r.itemLevel, power))
    else
        relic.note:SetText("")
        relic.line:SetText(power)
    end
    -- The server's note (how to get it, what holds it back) is too long for the column.
    relic.tip = r.note ~= "" and r.note or nil
    if relic.tip and r.rank == 0 then relic.line:SetText(power .. "  -  " .. r.note) end
    layout(true)
end

local function drawRaces(races, current)
    for i, race in ipairs(races) do
        R.DrawRaceRow(rowFor(i), race, current)
    end
    for i = #races + 1, #rows do
        R.DrawRaceRow(rows[i], nil)
    end
end

local function start()
    local Pages = api()
    if not Pages then return end
    -- Whatever had the view before (our window, or DragonUI's page when that takes it).
    local prev = { shown = R.shown, drawSkill = R.drawSkill, drawRaces = R.drawRaces, drawRelic = R.drawRelic,
        toggle = R.toggle }
    local function on()
        return panel ~= nil and Pages.Shown(PAGE)
    end

    R.shown = function()
        return on() or prev.shown()
    end
    -- The window's skill bar reads it (skill below).
    R.drawSkill = function(skill, maxSkill)
        if on() then Pages.Refresh() else prev.drawSkill(skill, maxSkill) end
    end
    R.drawRelic = function(text)
        if on() then drawRelic(text) else prev.drawRelic(text) end
    end
    R.drawRaces = function(races, current)
        if on() then drawRaces(races, current) else prev.drawRaces(races, current) end
    end
    R.toggle = function(open)
        if Pages.Has(PAGE) then
            if open then Pages.Open(PAGE) else Pages.Toggle(PAGE) end
            return
        end
        if panel and R.page:GetParent() == panel.card then R.TakeBack() end
        prev.toggle(open)
    end

    Pages.Add(PAGE, {
        title = TITLE,
        icon = A.Icon,
        art = ART_KEY,
        skill = function()
            if (A.skill or 0) > 0 then return TITLE, A.skill, A.maxSkill end
        end,
        build = build,
        onShow = function()
            attach()
            R.Opened()
        end,
    })
end

A.On("LOGIN", start)
