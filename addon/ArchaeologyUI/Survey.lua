-- Survey button, survey feedback and the fragments bar.
--
-- The button shows while you stand in one of your dig sites and sends SURVEY. Surveying is an
-- addon message, not a spell, so this is a plain button: no secure template, nothing locked in
-- combat. Shift-drag moves it; right-click opens the research window. Key Bindings has a key for
-- it too.
--
-- A survey answer colours the button's border red, yellow or green and turns an arrow toward the
-- find, kept pointing the right way as you turn. Standing on the find (the server shows a shovel
-- above your head), the button becomes a glowing shovel that sends DIG: the find comes up after
-- a moment of digging, and you click it to collect it. Looted fragments slide a bar in at the top.

local A = ArchaeologyUI
local SURVEY_COOLDOWN = 3       -- seconds; the server's Archaeology.Survey.CooldownMs default
local SURVEY_ICON = "Interface\\Icons\\INV_Misc_Spyglass_02"   -- the telescope a survey puts up
local ARROW_SECONDS = 60
local BAR_IN, BAR_HOLD, BAR_OUT = 0.25, 4, 0.4
local BANDS = {
    RED = { 1, 0.2, 0.2, "Far away" },
    YELLOW = { 1, 0.9, 0.2, "Closer" },
    GREEN = { 0.2, 1, 0.2, "Close" },
}

-- Survey button ----------------------------------------------------------------------------------

local button = CreateFrame("CheckButton", "ArchaeologyUISurveyButton", UIParent, "ActionButtonTemplate")
button:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 180)
button:SetFrameStrata("MEDIUM")
button:SetMovable(true)
button:SetClampedToScreen(true)
button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
button:RegisterForDrag("LeftButton")
button:Hide()

local icon = _G[button:GetName() .. "Icon"]
icon:SetTexture(SURVEY_ICON)
local border = _G[button:GetName() .. "Border"]
local cooldown = _G[button:GetName() .. "Cooldown"]
local hotkey = _G[button:GetName() .. "HotKey"]

local label = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
label:SetPoint("TOP", button, "BOTTOM", 0, -4)
local sublabel = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
sublabel:SetPoint("TOP", label, "BOTTOM", 0, -2)

local lastSurvey = -SURVEY_COOLDOWN
local function survey()
    local now = GetTime()
    if now - lastSurvey < SURVEY_COOLDOWN then
        return
    end
    lastSurvey = now
    CooldownFrame_SetTimer(cooldown, now, SURVEY_COOLDOWN, 1)
    A.Survey()
end
-- On the find the button digs instead; the server says when a dig starts and stops.
local digging = false
local function click()
    if not A.overFind then
        survey()
    elseif not digging then
        A.Dig()
    end
end
A.SurveyButtonClick = click

button:SetScript("OnClick", function(self, mouse)
    self:SetChecked(false)
    if mouse == "RightButton" then
        if A.ToggleWindow then
            A.ToggleWindow()
        end
    else
        click()
    end
end)
button:SetScript("OnDragStart", function(self)
    if IsShiftKeyDown() then
        self:StartMoving()
    end
end)
button:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, relative, x, y = self:GetPoint()
    A.db.survey = { point, relative, x, y }
end)
button:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if A.overFind then
        GameTooltip:SetText("Dig")
        GameTooltip:AddLine("You're standing on the find. Dig it up, then click it to collect it.", 1, 1, 1, true)
    else
        GameTooltip:SetText("Survey")
        GameTooltip:AddLine("Find out which way the nearest artifact lies.", 1, 1, 1, true)
    end
    GameTooltip:AddLine("Right-click: research window. Shift-drag: move.", 0.6, 0.6, 0.6, true)
    GameTooltip:Show()
end)
button:SetScript("OnLeave", function() GameTooltip:Hide() end)

function A.ResetSurveyButton()
    A.db.survey = nil
    button:ClearAllPoints()
    button:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 180)
end

A.On("LOGIN", function()
    local saved = A.db.survey
    if saved then
        button:ClearAllPoints()
        button:SetPoint(saved[1], UIParent, saved[2], saved[3], saved[4])
    end
end)

-- Dig mode: the shovel, a pulsing green glow and "Dig!" on the button ----------------------------

local glow = button:CreateTexture(nil, "OVERLAY")
glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
glow:SetBlendMode("ADD")
glow:SetVertexColor(0.3, 1, 0.3)
glow:SetSize(70, 70)
glow:SetPoint("CENTER")
glow:Hide()
local digText = button:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
digText:SetPoint("BOTTOM", button, "TOP", 0, 6)
digText:SetTextColor(0.3, 1, 0.3)
digText:SetText("Dig!")
digText:Hide()
local pulse = 0
local glowFrame = CreateFrame("Frame", nil, button)
glowFrame:Hide()
glowFrame:SetScript("OnUpdate", function(_, elapsed)
    pulse = pulse + elapsed
    glow:SetAlpha(0.55 + 0.45 * math.sin(pulse * 5))
end)

local function setDigMode(on)
    if on then
        icon:SetTexture(A.SHOVEL)
        glow:Show()
        digText:Show()
        glowFrame:Show()
    else
        icon:SetTexture(SURVEY_ICON)
        glow:Hide()
        digText:Hide()
        glowFrame:Hide()
    end
end

-- Direction arrow --------------------------------------------------------------------------------

local arrow = CreateFrame("Frame", nil, button)
arrow:SetSize(44, 44)
arrow:SetPoint("BOTTOM", button, "TOP", 0, 4)
arrow:Hide()
local arrowTexture = arrow:CreateTexture(nil, "OVERLAY")
arrowTexture:SetAllPoints()
arrowTexture:SetTexture("Interface\\AddOns\\ArchaeologyUI\\Textures\\SurveyArrow")
local arrowText = arrow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
arrowText:SetPoint("BOTTOM", arrow, "TOP", 0, 0)

-- Turn the arrow `angle` radians counter-clockwise from straight up. The texture's art fits in
-- the middle circle, so the corners only ever read inside 0..1.
local HALF = 0.5 / math.sqrt(2)
local function turn(angle)
    local c, s = math.cos(angle), math.sin(angle)
    local function corner(x, y)
        return 0.5 + x * c - y * s, 0.5 + x * s + y * c
    end
    local ulx, uly = corner(-HALF, -HALF)
    local llx, lly = corner(-HALF, HALF)
    local urx, ury = corner(HALF, -HALF)
    local lrx, lry = corner(HALF, HALF)
    arrowTexture:SetTexCoord(ulx, uly, llx, lly, urx, ury, lrx, lry)
end

local surveyAngle, surveyShown = nil, 0
arrow:SetScript("OnUpdate", function(self, elapsed)
    surveyShown = surveyShown + elapsed
    if surveyShown > ARROW_SECONDS or not surveyAngle then
        self:Hide()
        border:Hide()
        return
    end
    -- The world angle and the facing both count counter-clockwise from north.
    turn(surveyAngle - GetPlayerFacing())
end)

local function clearSurvey()
    surveyAngle = nil
    arrow:Hide()
    border:Hide()
end

A.On("OVERFIND", function(on)
    setDigMode(on)
    if on then
        clearSurvey()
        PlaySound("MapPing")
        UIErrorsFrame:AddMessage("You're standing on the find. Dig it up!", 0.2, 1, 0.2)
    elseif digging then
        digging = false
        CooldownFrame_SetTimer(cooldown, 0, 0, 0)
    end
    if GameTooltip:IsOwned(button) then button:GetScript("OnEnter")(button) end
end)

A.On("DIG", function(seconds)
    digging = seconds > 0
    if digging then
        CooldownFrame_SetTimer(cooldown, GetTime(), seconds, 1)
        digText:SetText("Digging...")
    else
        CooldownFrame_SetTimer(cooldown, 0, 0, 0)
        digText:SetText("Dig!")
    end
end)

A.On("SURVEY", function(band, angle)
    local b = BANDS[band]
    if b and angle then
        surveyAngle, surveyShown = angle, 0
        arrowTexture:SetVertexColor(b[1], b[2], b[3])
        arrowText:SetText(b[4])
        arrowText:SetTextColor(b[1], b[2], b[3])
        border:SetVertexColor(b[1], b[2], b[3], 0.7)
        border:Show()
        arrow:Show()
    elseif band == "FOUND" then
        clearSurvey()
        border:SetVertexColor(0.2, 1, 0.2, 0.7)
        border:Show()
        UIErrorsFrame:AddMessage("You found an artifact! Click it to collect it.", 0.2, 1, 0.2)
    else
        clearSurvey()
    end
end)

-- Show the button while you are in a dig site.
local currentSite
local function refreshButton()
    local site = A.skill > 0 and A.CurrentSite() or nil
    if site ~= currentSite then
        currentSite = site
        clearSurvey()
    end
    if site then
        local race = A.races[site.race]
        label:SetText(site.name)
        sublabel:SetText((race and race.name .. ", " or "") .. site.finds .. (site.finds == 1 and " find left" or " finds left"))
        local key = GetBindingKey("ARCHAEOLOGYUI_SURVEY")
        hotkey:SetText(key and GetBindingText(key, "KEY_", 1) or "")
        button:Show()
    else
        button:Hide()
    end
end
A.On("POSITION", refreshButton)
A.On("SITES", refreshButton)

-- Fragments bar ----------------------------------------------------------------------------------

local bar = CreateFrame("Button", "ArchaeologyUIFragmentsBar", UIParent)
bar:SetSize(300, 52)
bar:SetPoint("TOP", UIParent, "TOP", 0, 60)
bar:SetFrameStrata("HIGH")
bar:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
})
-- Without DragonUI, in the stock tooltip's colours; with it, the darker pane it has always had.
local dragonUI = _G.DragonUI ~= nil
if dragonUI then
    bar:SetBackdropColor(0, 0, 0, 0.8)
else
    bar:SetBackdropColor(TOOLTIP_DEFAULT_BACKGROUND_COLOR.r, TOOLTIP_DEFAULT_BACKGROUND_COLOR.g,
        TOOLTIP_DEFAULT_BACKGROUND_COLOR.b)
    bar:SetBackdropBorderColor(TOOLTIP_DEFAULT_COLOR.r, TOOLTIP_DEFAULT_COLOR.g, TOOLTIP_DEFAULT_COLOR.b)
end
bar:Hide()

local barIcon = bar:CreateTexture(nil, "ARTWORK")
barIcon:SetSize(32, 32)
barIcon:SetPoint("LEFT", 10, 0)
barIcon:SetTexture(A.SHOVEL)

local barTitle = bar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
barTitle:SetPoint("TOPLEFT", barIcon, "TOPRIGHT", 8, 0)
barTitle:SetPoint("RIGHT", -10, 0)
barTitle:SetJustifyH("LEFT")

local status = CreateFrame("StatusBar", nil, bar)
status:SetPoint("BOTTOMLEFT", barIcon, "BOTTOMRIGHT", 8, 0)
status:SetPoint("RIGHT", -12, 0)
status:SetHeight(12)
local statusBg = status:CreateTexture(nil, "BACKGROUND")
statusBg:SetAllPoints()
local statusText
if dragonUI then
    status:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    statusBg:SetTexture(0, 0, 0, 0.5)
    statusText = status:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
else
    -- The stock skill bar and its border.
    status:SetStatusBarTexture("Interface\\PaperDollInfoFrame\\UI-Character-Skills-Bar")
    statusBg:SetTexture(1, 1, 1, 0.2)
    local statusBorder = CreateFrame("Frame", nil, status)
    statusBorder:SetAllPoints()
    local edge = statusBorder:CreateTexture(nil, "ARTWORK")
    edge:SetTexture("Interface\\PaperDollInfoFrame\\UI-Character-Skills-BarBorder")
    edge:SetPoint("TOPLEFT", -5, 6)
    edge:SetPoint("BOTTOMRIGHT", 4, -6)
    statusText = statusBorder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
end
statusText:SetPoint("CENTER", status, "CENTER")

local barTime, barRace = 0, nil
bar:SetScript("OnUpdate", function(self, elapsed)
    barTime = barTime + elapsed
    local shown = -70     -- resting offset below the top of the screen
    local y
    if barTime < BAR_IN then
        y = 60 + (shown - 60) * barTime / BAR_IN
    elseif barTime < BAR_IN + BAR_HOLD or MouseIsOver(self) then
        y = shown
        if barTime >= BAR_IN + BAR_HOLD then
            barTime = BAR_IN + BAR_HOLD   -- hold while the mouse is on it
        end
    elseif barTime < BAR_IN + BAR_HOLD + BAR_OUT then
        y = shown + (60 - shown) * (barTime - BAR_IN - BAR_HOLD) / BAR_OUT
    else
        self:Hide()
        return
    end
    self:SetPoint("TOP", UIParent, "TOP", 0, y)
end)
bar:SetScript("OnClick", function()
    if A.ShowRace and barRace then
        A.ShowRace(barRace)
    end
end)

local function slideIn()
    if bar:IsShown() and barTime >= BAR_IN and barTime < BAR_IN + BAR_HOLD then
        barTime = BAR_IN    -- already down: just restart the hold
    else
        barTime = 0
    end
    bar:Show()
end

A.On("FRAGMENTS", function(raceId, gained, total)
    local race = A.races[raceId]
    barRace = raceId
    barIcon:SetTexture(A.RaceIcon and A.RaceIcon(raceId) or A.SHOVEL)
    barTitle:SetText(string.format("+%d %s fragments", gained, race and race.name or ""))
    local cost = race and race.project > 0 and race.cost or 0
    if cost > 0 then
        status:SetMinMaxValues(0, cost)
        status:SetValue(math.min(total, cost))
        if total >= cost then
            status:SetStatusBarColor(0.2, 0.8, 0.2)
            statusText:SetText(string.format("%d / %d  Ready to solve", total, cost))
        else
            status:SetStatusBarColor(0.8, 0.55, 0.15)
            statusText:SetText(string.format("%d / %d", total, cost))
        end
    else
        local cap = race and race.cap or total
        status:SetMinMaxValues(0, math.max(cap, 1))
        status:SetValue(total)
        status:SetStatusBarColor(0.8, 0.55, 0.15)
        statusText:SetText(total)
    end
    slideIn()
end)

A.On("SOLVED", function(projectId, item, rare)
    local p = A.projects[projectId]
    local name = p and p.name or GetItemInfo(item) or "an artifact"
    barRace = p and p.race
    barIcon:SetTexture(GetItemIcon(item) or (barRace and A.RaceIcon and A.RaceIcon(barRace)) or A.SHOVEL)
    barTitle:SetText((rare and "|cffa335ee" or "|cffffffff") .. "Solved: " .. name .. "|r")
    status:SetMinMaxValues(0, 1)
    status:SetValue(1)
    status:SetStatusBarColor(0.2, 0.8, 0.2)
    statusText:SetText("")
    slideIn()
    PlaySound("igQuestListComplete")
end)
