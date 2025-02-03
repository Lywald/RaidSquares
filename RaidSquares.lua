-- RaidSquares.lua

--------------------------------------------------------------------------
-- CONFIG
--------------------------------------------------------------------------
local numSquares  = 40        -- Maximum squares
local baseTexSize = 20        -- “Normal” texture size (used for min–max scaling)
local MIN_SCALE   = 0.3
local MAX_SCALE   = 1.5

-- Because frames must accommodate the largest texture:
local realSize = baseTexSize * MAX_SCALE

-- Grid & spacing
local columns = 8
local rows    = math.ceil(numSquares / columns)
local spacing = 2

-- Track recent damage times
local lastDamageTime = {}

--------------------------------------------------------------------------
-- MAIN FRAME
--------------------------------------------------------------------------
local mainFrame = CreateFrame("Frame", "RaidSquaresFrame", UIParent)
mainFrame:SetSize(
    columns * realSize + (columns - 1) * spacing,
    rows    * realSize + (rows    - 1) * spacing
)
mainFrame:SetPoint("CENTER")
mainFrame:SetMovable(true)

-- Drag handle (CTRL + left‐drag to move)
local dragHandle = CreateFrame("Frame", nil, mainFrame)
dragHandle:SetAllPoints()
dragHandle:EnableMouse(false)
dragHandle:SetFrameLevel(mainFrame:GetFrameLevel() + 10)
dragHandle:RegisterForDrag("LeftButton")

dragHandle.texture = dragHandle:CreateTexture(nil, "OVERLAY")
dragHandle.texture:SetAllPoints()
dragHandle.texture:SetColorTexture(1, 1, 1, 0.1)
dragHandle.texture:Hide()

dragHandle:SetScript("OnDragStart", function() 
    if IsControlKeyDown() then
        mainFrame:StartMoving()
    end
end)
dragHandle:SetScript("OnDragStop", function() 
    mainFrame:StopMovingOrSizing()
end)

local function UpdateDragHandle()
    local isCtrlDown = IsControlKeyDown()
    dragHandle:EnableMouse(isCtrlDown)
    dragHandle.texture:SetShown(isCtrlDown)
end
mainFrame:RegisterEvent("MODIFIER_STATE_CHANGED")

--------------------------------------------------------------------------
-- CREATE THE SQUARES
--------------------------------------------------------------------------
local squares = {}
for i = 1, numSquares do
    local square = CreateFrame(
        "Button", 
        "RaidSquare"..i, 
        mainFrame, 
        "SecureActionButtonTemplate,SecureUnitButtonTemplate,BackdropTemplate"
    )
    square:SetSize(realSize, realSize) -- big enough for max scale
    square:EnableMouse(true)
    square:SetBackdrop({
        bgFile = nil,
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 8,
    })
    square:SetBackdropBorderColor(0, 0, 0, 0)

    -- Click behavior
    square:RegisterForClicks("AnyUp")
    square:SetAttribute("*type1", "target")
    square:SetAttribute("*type2", "menu")

    -- Health texture
    local tex = square:CreateTexture(nil, "BACKGROUND")
    tex:SetColorTexture(1, 1, 1, 1)
    tex:SetPoint("CENTER", square, "CENTER")
    square.texture = tex

    -- 3-letter Name text (NOW CENTERED)
    local txt = square:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    -- Instead of anchoring to the bottom, anchor to the center:
    txt:SetPoint("CENTER", square, "CENTER", 0, 0)
    -- Horizontal justification center; vertical justification often ignored if anchored
    txt:SetJustifyH("CENTER")
    -- txt:SetJustifyV("MIDDLE")  -- optional; often not needed
    txt:SetAlpha(0.3)
    txt:SetTextColor(1, 1, 1)
    square.text = txt

    -- Tooltip
    square:SetScript("OnEnter", function(self)
        local unit = self:GetAttribute("unit")
        if unit and UnitExists(unit) then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetUnit(unit)
            GameTooltip:Show()
        end
    end)
    square:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    -- Place squares in a grid
    local col = (i - 1) % columns
    local row = math.floor((i - 1) / columns)
    square:SetPoint("TOPLEFT", mainFrame, "TOPLEFT",
        col * (realSize + spacing),
        -row * (realSize + spacing)
    )

    squares[i] = square
end

--------------------------------------------------------------------------
-- CLASS COLOR HELPER
--------------------------------------------------------------------------
local function GetUnitClassColor(unit)
    local r, g, b = 1, 1, 1
    if UnitIsPlayer(unit) then
        local _, classToken = UnitClass(unit)
        if classToken and RAID_CLASS_COLORS[classToken] then
            local c = RAID_CLASS_COLORS[classToken]
            r, g, b = c.r, c.g, c.b
        end
    end
    return r, g, b
end

--------------------------------------------------------------------------
-- NONLINEAR SCALING FUNCTION
-- (So squares shrink quickly when health first drops, flattening near 0%)
--------------------------------------------------------------------------
local function HealthScale(perc)
    local exponent = 0.3
    return MIN_SCALE + (MAX_SCALE - MIN_SCALE) * (1 - (1 - perc)^exponent)
end

--------------------------------------------------------------------------
-- UNIT ASSIGNMENT
--------------------------------------------------------------------------
local function UpdateUnitAttributes()
    if InCombatLockdown() then
        print("[RaidSquares] Skipping unit updates due to combat lockdown.")
        return
    end

    local isRaid = IsInRaid()
    local isParty = IsInGroup()

    for i = 1, numSquares do
        local square = squares[i]
        local unit
        if isRaid then
            unit = "raid" .. i
        elseif isParty then
            if i == 1 then
                unit = "player"
            elseif i <= 5 then
                unit = "party" .. (i - 1)
            end
        elseif i == 1 then
            unit = "player"
        end

        if unit then
            square:SetAttribute("unit", unit)
        end
        if unit and UnitExists(unit) then
            square:Show()
        else
            square:Hide()
        end
    end
end

--------------------------------------------------------------------------
-- VISUAL UPDATES
--------------------------------------------------------------------------
local function UpdateSquaresVisual()
    for i = 1, numSquares do
        local square = squares[i]
        local unit = square:GetAttribute("unit")
        if unit and UnitExists(unit) then
            local health    = UnitHealth(unit)
            local maxHealth = UnitHealthMax(unit)
            local isDead    = UnitIsDeadOrGhost(unit)
            local guid      = UnitGUID(unit)

            square:SetBackdropBorderColor(0, 0, 0, 0)

            local name = UnitName(unit) or "???"
            square.text:SetText(name:sub(1, 3))

            if isDead then
                square.texture:SetColorTexture(0, 0, 0)
                square.texture:SetSize(baseTexSize * MIN_SCALE, baseTexSize * MIN_SCALE)
            else
                local perc = (maxHealth > 0) and (health / maxHealth) or 0
                local r, g, b = GetUnitClassColor(unit)
                square.texture:SetColorTexture(r, g, b)

                local sc = HealthScale(perc)
                square.texture:SetSize(baseTexSize * sc, baseTexSize * sc)
            end

            -- Out of range => grey
            local inRange = (unit == "player") or UnitInRange(unit)
            if not inRange then
                square.texture:SetColorTexture(0.5, 0.5, 0.5)
            end

            square:SetAlpha(inRange and 1 or 0.5)

            -- Damaged in last 3s => red border
            local tookDamageRecently = false
            if guid and lastDamageTime[guid] then
                if (GetTime() - lastDamageTime[guid]) <= 3 and inRange then
                    tookDamageRecently = true
                end
            end

            -- Border priority
            if tookDamageRecently then
                square:SetBackdropBorderColor(1, 0, 0, 1)
            elseif UnitIsUnit(unit, "target") then
                -- Big thick outline for current target
                square:SetBackdropBorderColor(1, 1, 1, 1)
                square:SetBackdrop({
                    bgFile = nil,
                    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", -- thicker edge
                    edgeSize = 16,
                })
            else
                -- Revert to normal thin border if not target
                square:SetBackdrop({
                    bgFile = nil,
                    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                    edgeSize = 8,
                })
            end
        end
    end
end

--------------------------------------------------------------------------
-- EVENT HANDLING
--------------------------------------------------------------------------
mainFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
mainFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
mainFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
mainFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")

mainFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "MODIFIER_STATE_CHANGED" then
        UpdateDragHandle()

    elseif event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ENTERING_WORLD" then
        UpdateUnitAttributes()
        UpdateSquaresVisual()

    elseif event == "PLAYER_TARGET_CHANGED" then
        UpdateSquaresVisual()

    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        local _, subEvent, _, _, _, _, _, destGUID = CombatLogGetCurrentEventInfo()
        if subEvent == "SWING_DAMAGE"
        or subEvent == "RANGE_DAMAGE"
        or subEvent == "SPELL_DAMAGE"
        or subEvent == "SPELL_PERIODIC_DAMAGE" then
            lastDamageTime[destGUID] = GetTime()
        end
        -- Not calling UpdateSquaresVisual() here to avoid spam
    end
end)

-- Throttled OnUpdate
local updateInterval = 0.25
local timeSinceLast  = 0
mainFrame:SetScript("OnUpdate", function(self, elapsed)
    timeSinceLast = timeSinceLast + elapsed
    if timeSinceLast >= updateInterval then
        UpdateSquaresVisual()
        timeSinceLast = 0
    end
end)

-- Initial
UpdateUnitAttributes()
UpdateSquaresVisual()
UpdateDragHandle()
