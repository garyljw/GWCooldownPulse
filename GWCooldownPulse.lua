-- GW Cooldown Pulse
-- When a spell or trinket comes off cooldown, a large, mostly see-through copy
-- of its icon appears, grows 1x -> 3x, then bursts 3x -> 5x while fading out.
--
-- Self-only defensive spells (Divine Shield, Ice Barrier, Evasion, ...) only
-- pulse when they can really be used again: off cooldown, your buff from them
-- has ended or been dispelled, AND any lockout debuff (Forbearance) is gone.
-- Spells you often cast on others (Power Word: Shield, Fear Ward, Blessing of
-- Protection) pulse on their cooldown alone.
--
-- /cdpulse             - open the settings window
-- /cdpulse help        - list of commands
-- Settings window lives in GWCooldownPulse_Config.lua.

local ADDON, ns = ...
local _, CLASS = UnitClass("player")

-- Animation timing (at the default 3 second length) --------------------------
local GROW_TIME  = 2.5  -- 1x -> 3x
local BURST_TIME = 0.5  -- 3x -> 5x, fading out
local TOTAL_TIME = GROW_TIME + BURST_TIME
local MAX_SPEED  = 2    -- fastest catch-up speed when pulses are waiting
local POLL       = 0.1  -- seconds between cooldown checks
local GCD_MAX    = 1.5  -- a cooldown this short is just the global cooldown
local QUESTION   = "Interface\\Icons\\INV_Misc_QuestionMark"

-- Spells that never pulse (auto attacks and wand shots)
local IGNORE_IDS = { [6603] = true, [75] = true, [5019] = true }

-- Defensive spells. `lockout` is a debuff on you that stops it being cast again.
-- Matching is by name, so every rank counts.
local DEFENSIVES = {
    PALADIN = { { spell = 642,  lockout = 25771 },     -- Divine Shield / Forbearance
                { spell = 498,  lockout = 25771 } },   -- Divine Protection
    MAGE    = { { spell = 11958 }, { spell = 45438 },   -- Ice Block (Classic / TBC)
                { spell = 11426 },                      -- Ice Barrier
                { spell = 1463 },                       -- Mana Shield
                { spell = 543 }, { spell = 6143 } },    -- Fire Ward, Frost Ward
    WARLOCK = { { spell = 6229 } },                     -- Shadow Ward
    DRUID   = { { spell = 22812 } },                    -- Barkskin
    WARRIOR = { { spell = 871 }, { spell = 2565 } },    -- Shield Wall, Shield Block
    ROGUE   = { { spell = 5277 }, { spell = 31224 } },  -- Evasion, Cloak of Shadows
    HUNTER  = { { spell = 19263 } },                    -- Deterrence
}

-- Spells you often cast on other people. These pulse only when their cooldown
-- ends; your own buff from them, or a lockout debuff on you, is ignored.
local COOLDOWN_ONLY = {
    PRIEST  = { 17, 6346 },                             -- Power Word: Shield, Fear Ward
    PALADIN = { 1022 },                                 -- Blessing of Protection
}

local TRINKET_SLOTS = { 13, 14 }

-- Settings ---------------------------------------------------------------------
local defaults = {
    size = 64,          -- starting icon size in pixels (grows to 5x)
    alpha = 0.6,        -- how solid the icon is at its strongest
    halo = 1,           -- halo strength, 0 = off
    duration = 3,       -- seconds for the whole animation
    minCD = 2,          -- ignore cooldowns shorter than this
    combatOnly = false,
    trinkets = true,
    point = { "CENTER", 0, 120 },
}
local db
ns.defaults = defaults
function ns.DB() return db end

local function Print(msg) print("|cffff7a1aGW Cooldown Pulse:|r " .. msg) end
ns.Print = Print

-- API helpers (work on both older and newer clients) -------------------------
local function SpellName(id)
    if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(id) end
    if GetSpellInfo then return (GetSpellInfo(id)) end
end

local function SpellIcon(id)
    if C_Spell and C_Spell.GetSpellTexture then return C_Spell.GetSpellTexture(id) end
    if GetSpellTexture then return GetSpellTexture(id) end
end

-- Newer clients hide ("secret") cooldown numbers from addons. Secret values
-- can't be compared or added, so everything below checks before touching one.
local function IsSecret(v)
    return issecretvalue ~= nil and v ~= nil and issecretvalue(v)
end

-- Cooldown state from plain numbers: "cd" (real cooldown), "gcd", nil (ready),
-- or "unknown" when the numbers are secret.
local function NumberState(start, dur, enabled)
    if IsSecret(start) or IsSecret(dur) or IsSecret(enabled) then return "unknown" end
    if enabled == 0 or enabled == false then return "cd" end -- e.g. Stealth: cd starts later
    if start and start > 0 and dur and dur > 0 then
        return dur > GCD_MAX and "cd" or "gcd"
    end
    return nil
end

local function SpellState(id)
    if C_Spell and C_Spell.GetSpellCooldown then
        local c = C_Spell.GetSpellCooldown(id)
        if not c then return nil end
        -- isActive / isOnGCD are never secret, so prefer them.
        if c.isActive ~= nil and not IsSecret(c.isActive) then
            if not c.isActive then return nil end
            if c.isOnGCD ~= nil and not IsSecret(c.isOnGCD) then
                return c.isOnGCD and "gcd" or "cd"
            end
        end
        return NumberState(c.startTime, c.duration, c.isEnabled)
    end
    return NumberState(GetSpellCooldown(id))
end

local function ItemState(slot)
    return NumberState(GetInventoryItemCooldown("player", slot))
end

local function ItemName(id)
    if C_Item and C_Item.GetItemNameByID then return C_Item.GetItemNameByID(id) end
    if GetItemInfo then return (GetItemInfo(id)) end
end

-- Calls fn(spellID) for every active (non-passive) spell in your spellbook.
local function ForEachSpell(fn)
    if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines then
        local bank = Enum.SpellBookSpellBank.Player
        for tab = 1, C_SpellBook.GetNumSpellBookSkillLines() do
            local line = C_SpellBook.GetSpellBookSkillLineInfo(tab)
            if line and not line.shouldHide then
                for i = line.itemIndexOffset + 1, line.itemIndexOffset + line.numSpellBookItems do
                    local item = C_SpellBook.GetSpellBookItemInfo(i, bank)
                    if item and item.itemType == Enum.SpellBookItemType.Spell and item.spellID
                        and not item.isPassive and not item.isOffSpec then
                        fn(item.spellID)
                    end
                end
            end
        end
    else
        for tab = 1, GetNumSpellTabs() do
            local _, _, offset, num = GetSpellTabInfo(tab)
            for i = offset + 1, offset + num do
                local kind, id = GetSpellBookItemInfo(i, BOOKTYPE_SPELL or "spell")
                if kind == "SPELL" and id and not (IsPassiveSpell and IsPassiveSpell(id)) then
                    fn(id)
                end
            end
        end
    end
end

-- Your auras (cached, refreshed on UNIT_AURA) ----------------------------------
local myBuffs, myDebuffs = {}, {}

local function ScanAuras()
    wipe(myBuffs); wipe(myDebuffs)
    for _, filter in ipairs({ "HELPFUL", "HARMFUL" }) do
        for i = 1, 40 do
            local name, source
            if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
                local a = C_UnitAuras.GetAuraDataByIndex("player", i, filter)
                if not a then break end
                name, source = a.name, a.sourceUnit
            else
                local n, _, _, _, _, _, src = UnitAura("player", i, filter)
                if not n then break end
                name, source = n, src
            end
            if name and not IsSecret(name) then
                if filter == "HARMFUL" then
                    myDebuffs[name] = true          -- lockouts count whoever caused them
                elseif source and not IsSecret(source) and UnitIsUnit(source, "player") then
                    myBuffs[name] = true            -- only buffs you cast yourself
                end
            end
        end
    end
end

-- Tracked spells and trinkets ---------------------------------------------------
-- Each entry: { key, name, icon, spell | slot, def, ready, block,
--               cdBusy, busySince, gcdSince, lastDur }
local tracked = {}
ns.tracked = tracked
local lastCast = {}      -- spell name -> GetTime() of your last cast
local defByName = {}     -- spell name -> lockout debuff name (or false)
local quietUntil = 0     -- no pulses until this time (just after login / zoning)

local cdOnlyByName = {}  -- spell name -> true

local function BuildDefensives()
    wipe(defByName); wipe(cdOnlyByName)
    for _, d in ipairs(DEFENSIVES[CLASS] or {}) do
        local n = SpellName(d.spell)
        if n then defByName[n] = d.lockout and SpellName(d.lockout) or false end
    end
    for _, id in ipairs(COOLDOWN_ONLY[CLASS] or {}) do
        local n = SpellName(id)
        if n then cdOnlyByName[n] = true end
    end
end

-- Adds (or updates) a spell. Called for every spellbook spell and for every
-- spell you cast, so tracking still works if the spellbook scan fails.
local function TrackSpell(id)
    if not id or IGNORE_IDS[id] then return end
    local name = SpellName(id)
    if not name then return end
    local key = "spell:" .. name
    local s = tracked[key]
    if not s then
        s = { key = key, name = name }
        tracked[key] = s
    end
    s.spell, s.icon = id, SpellIcon(id) or s.icon  -- several ranks: last one wins
    s.def = defByName[name] ~= nil
    s.lockout = defByName[name] or nil
    s.cdOnly = cdOnlyByName[name] or nil
end

local scanError, scanCount

local function Rebuild()
    local ok, err = pcall(ForEachSpell, TrackSpell)
    scanError = not ok and tostring(err) or nil
    local oldItems = {}
    for key, s in pairs(tracked) do
        if s.slot then oldItems[key] = s; tracked[key] = nil end
    end
    if db.trinkets then
        for _, slot in ipairs(TRINKET_SLOTS) do
            local id = GetInventoryItemID("player", slot)
            if id then
                local key = "item:" .. id .. ":" .. slot
                local s = oldItems[key] or { key = key, slot = slot, itemID = id }
                s.icon = GetInventoryItemTexture("player", slot)
                s.name = ItemName(id) or s.name
                tracked[key] = s
            end
        end
    end
    scanCount = 0
    for _ in pairs(tracked) do scanCount = scanCount + 1 end
    if ns.OnTrackedChanged then ns.OnTrackedChanged() end
end
ns.Rebuild = Rebuild

-- Is a real cooldown running? We only know "real cooldown", "GCD" or "ready",
-- never the numbers, so we time the cooldown ourselves (for minCD).
-- When the last part of a real cooldown is hidden under a GCD, we wait until
-- that GCD ends or 1.5s pass - whichever is first - so a pulse is never early.
local function CooldownBusy(s, state, now)
    if state == "unknown" then state = "cd" end -- secret numbers only appear while a cd runs
    local busy
    if state == "cd" then
        busy, s.gcdSince = true, nil
    elseif state == "gcd" and s.cdBusy then
        s.gcdSince = s.gcdSince or now
        busy = now - s.gcdSince < GCD_MAX
    else
        busy = false
    end
    if busy and not s.cdBusy then
        s.busySince = now
    elseif not busy and s.cdBusy then
        s.lastDur = now - (s.busySince or now)
        s.gcdSince = nil
    end
    s.cdBusy = busy
    return busy
end

-- Returns nil if ready, or why it isn't (used to merge pulses for shared cooldowns).
local function BlockReason(s, now)
    local state
    if s.slot then state = ItemState(s.slot) else state = SpellState(s.spell) end
    if CooldownBusy(s, state, now) then return "cd" .. tostring(s.busySince) end
    if s.slot or s.cdOnly then return nil end
    if s.lockout and myDebuffs[s.lockout] then return "lock:" .. s.lockout end
    -- Your own buff from it still running? Only for defensives and spells
    -- with a real cooldown, so plain long buffs (Inner Fire...) never pulse.
    if (s.def or (s.lastDur or 0) >= db.minCD) and myBuffs[s.name] then return "buff:" .. s.name end
    return nil
end

local function Ignored(s)
    return s.name and db.ignore[s.name:lower()]
end
ns.Ignored = Ignored

function ns.SetIgnored(s, ignored)
    if s.name then db.ignore[s.name:lower()] = ignored or nil end
end

-- Pulse display -----------------------------------------------------------------
local display = CreateFrame("Frame", "GWCooldownPulseAnchor", UIParent)
display:SetFrameStrata("HIGH")
display:SetClampedToScreen(true)
display:SetMovable(true)
display:EnableMouse(false)
display:RegisterForDrag("LeftButton")

local moveBox = display:CreateTexture(nil, "BACKGROUND", nil, -8)
moveBox:SetAllPoints()
moveBox:SetColorTexture(0.2, 0.6, 1, 0.4)
moveBox:Hide()
local moveText = display:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
moveText:SetPoint("TOP", display, "BOTTOM", 0, -4)
moveText:SetText("GW Cooldown Pulse - drag me, then Lock in /cdpulse")
moveText:Hide()

display:SetScript("OnDragStart", display.StartMoving)
display:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, _, x, y = self:GetPoint()
    db.point = { point, x, y }
end)

local function ApplyLayout()
    display:SetSize(db.size, db.size)
    display:ClearAllPoints()
    display:SetPoint(db.point[1], UIParent, db.point[1], db.point[2], db.point[3])
end
ns.ApplyLayout = ApplyLayout

function ns.IsUnlocked() return moveBox:IsShown() end

function ns.SetUnlocked(on)
    moveBox:SetShown(on); moveText:SetShown(on); display:EnableMouse(on)
end

local pool, active, queue, queued = {}, {}, {}, {}

-- p = seconds into the animation -> scale, alpha (0-1, times db.alpha)
-- Grows at a steady rate to 3x, then the burst starts at that same speed and
-- accelerates to 5x, so there's no stall or jump where the two phases meet.
local GROW_SPEED = 2 / GROW_TIME                     -- scale units per second in phase 1
local BURST_LIN  = GROW_SPEED * BURST_TIME           -- part of the burst at the starting speed
local BURST_ACC  = 2 - BURST_LIN                     -- the rest, accelerating

local function Curve(p)
    if p < GROW_TIME then
        local x = p / GROW_TIME
        local a = 1 - 0.35 * x                  -- slowly fading while it grows
        if p < 0.1 then a = a * p / 0.1 end      -- quick fade-in so it doesn't pop
        return 1 + 2 * x, a
    end
    local x = math.min((p - GROW_TIME) / BURST_TIME, 1)
    return 3 + BURST_LIN * x + BURST_ACC * x * x, 0.65 * (1 - x * x)
end

-- Each pulse is the icon cut to a circle (so there are no square corners to
-- blow up), plus two bigger, fainter copies drawn additively behind it: a soft
-- halo in the icon's own colours that blurs the circle's edge.
-- Only the game's own circle mask is used: the Forever client crashed loading
-- a custom mask file shipped with the addon.
local CIRCLE_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local HALOS = { { size = 1.18, alpha = 0.35 }, { size = 1.45, alpha = 0.18 } }

local function NewLayer(blend)
    local t = display:CreateTexture(nil, "ARTWORK")
    t:SetPoint("CENTER")
    t:SetBlendMode(blend)
    local m = display:CreateMaskTexture()
    m:SetTexture(CIRCLE_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    m:SetAllPoints(t)
    t:AddMaskTexture(m)
    -- Let it grow by fractions of a pixel instead of stepping.
    if t.SetSnapToPixelGrid then t:SetSnapToPixelGrid(false) end
    return t
end

local function SetLayers(p, front)
    -- Growing pulse in front; a bursting one drops behind the next pulse.
    if front then
        for i, h in ipairs(p.halos) do h:SetDrawLayer("ARTWORK", i - 1) end
        p.icon:SetDrawLayer("ARTWORK", 3)
    else
        for i, h in ipairs(p.halos) do h:SetDrawLayer("BACKGROUND", i - 1) end
        p.icon:SetDrawLayer("BORDER", 0)
    end
end

local function StartPulse(icon)
    local p = table.remove(pool)
    if not p then
        p = { icon = NewLayer("BLEND"), halos = {} }
        for i = 1, #HALOS do p.halos[i] = NewLayer("ADD") end
    end
    p.icon:SetTexture(icon)
    for _, h in ipairs(p.halos) do h:SetTexture(icon) end
    for _, t in ipairs({ p.icon, unpack(p.halos) }) do
        t:SetTexCoord(0.07, 0.93, 0.07, 0.93)   -- trim the icon's own border
        t:SetAlpha(0)
        t:Show()
    end
    SetLayers(p, true)
    p.age, p.bursting = 0, false
    active[#active + 1] = p
end

local function DrawPulse(p, scale, alpha)
    local s = db.size * scale
    p.icon:SetSize(s, s)
    p.icon:SetAlpha(db.alpha * alpha)
    for i, h in ipairs(p.halos) do
        h:SetSize(s * HALOS[i].size, s * HALOS[i].size)
        h:SetAlpha(math.min(1, db.alpha * alpha * HALOS[i].alpha * db.halo))
    end
end

local function HidePulse(p)
    p.icon:Hide()
    for _, h in ipairs(p.halos) do h:Hide() end
end

local function QueuePulse(s)
    if queued[s.key] then return end
    queued[s.key] = true
    queue[#queue + 1] = s
end

-- A test pulse, using one of your defensive icons if you have one.
function ns.Test()
    local icon = QUESTION
    for _, s in pairs(tracked) do if s.def and s.icon then icon = s.icon; break end end
    StartPulse(icon)
end

-- For live previews from the settings window: only if nothing is showing.
function ns.Preview()
    if #active == 0 then ns.Test() end
end

-- Only one icon grows at a time. The next one starts as soon as the current
-- one reaches its burst, so they only overlap while the old one fades out.
-- With pulses waiting, everything plays faster (up to 2x) to catch up.
local function Animate(elapsed)
    local speed = math.min(MAX_SPEED, 1 + 0.5 * #queue) * TOTAL_TIME / db.duration
    local growing = false
    for i = #active, 1, -1 do
        local p = active[i]
        p.age = p.age + elapsed * speed
        if p.age >= TOTAL_TIME then
            HidePulse(p)
            table.remove(active, i)
            pool[#pool + 1] = p
        else
            if p.age < GROW_TIME then
                growing = true
            elseif not p.bursting then
                p.bursting = true
                SetLayers(p, false)                  -- behind the next icon
            end
            DrawPulse(p, Curve(p.age))
        end
    end
    while not growing and #queue > 0 do
        local s = table.remove(queue, 1)
        queued[s.key] = nil
        if s.ready ~= false then                     -- skip it if you've used it again already
            StartPulse(s.icon or QUESTION)
            growing = true
        end
    end
end

-- Cooldown check ----------------------------------------------------------------
local lastError

local function Check()
    local now = GetTime()
    local canPulse = now >= quietUntil and (not db.combatOnly or UnitAffectingCombat("player"))
    local groups = {}   -- spells freed by the same thing (shared cd, Forbearance) pulse once
    for _, s in pairs(tracked) do
        -- One spell the client won't tell us about mustn't stop all the others.
        local ok, reason = pcall(BlockReason, s, now)
        if not ok then
            lastError = s.name .. ": " .. tostring(reason)
        else
            local ready = reason == nil
            if ready and s.ready == false and canPulse and not Ignored(s)
                and (s.def or (s.lastDur or 0) >= db.minCD) then
                local g = s.block or s.key
                local best = groups[g]
                if not best or (lastCast[s.name] or 0) > (lastCast[best.name] or 0) then groups[g] = s end
            end
            s.ready, s.block = ready, reason
        end
    end
    for _, s in pairs(groups) do QueuePulse(s) end
end

-- Events ------------------------------------------------------------------------
local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("SPELLS_CHANGED")
events:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
events:RegisterUnitEvent("UNIT_AURA", "player")
events:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")

local sinceCheck = 0
events:SetScript("OnUpdate", function(_, elapsed)
    if not db then return end
    Animate(elapsed)
    sinceCheck = sinceCheck + elapsed
    if sinceCheck >= POLL then sinceCheck = 0; Check() end
end)

events:SetScript("OnEvent", function(_, event, arg1, arg2, arg3)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON then return end
        GWCooldownPulseDB = GWCooldownPulseDB or {}
        db = GWCooldownPulseDB
        for k, v in pairs(defaults) do
            if db[k] == nil then db[k] = type(v) == "table" and { unpack(v) } or v end
        end
        db.ignore = db.ignore or {}
        ApplyLayout()
        return
    end
    if not db then return end
    if event == "UNIT_AURA" then
        ScanAuras()
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        if not arg3 or IsSecret(arg3) then return end
        local isNew = not tracked["spell:" .. (SpellName(arg3) or "")]
        TrackSpell(arg3)
        local name = SpellName(arg3)
        if name then lastCast[name] = GetTime() end
        if isNew and ns.OnTrackedChanged then ns.OnTrackedChanged() end
    else
        if event == "PLAYER_ENTERING_WORLD" then quietUntil = GetTime() + 2 end
        BuildDefensives()
        Rebuild()
        ScanAuras()
    end
end)

-- Slash command -----------------------------------------------------------------
local function Debug(rest)
    Print("Tracking " .. (scanCount or 0) .. " spells/trinkets. Spellbook scan: "
        .. (scanError and ("|cffff4040failed:|r " .. scanError) or "ok"))
    Print("Min cooldown " .. db.minCD .. "s, combat only " .. (db.combatOnly and "on" or "off")
        .. ", quiet for " .. string.format("%.1f", math.max(0, quietUntil - GetTime())) .. "s")
    if rest ~= "" then
        local s
        for _, t in pairs(tracked) do
            if t.name and t.name:lower() == rest:lower() then s = t end
        end
        if not s then
            Print("'" .. rest .. "' isn't tracked yet - cast it once, then try again.")
        else
            local state
            if s.slot then state = ItemState(s.slot) else state = SpellState(s.spell) end
            Print(string.format("%s (id %s): ready=%s block=%s cooldown now=%s lastDur=%s defensive=%s ignored=%s",
                s.name, tostring(s.spell or s.itemID), tostring(s.ready), tostring(s.block),
                tostring(state or "ready"),
                s.lastDur and string.format("%.1fs", s.lastDur) or "none yet",
                tostring(s.def), tostring(Ignored(s) or false)))
        end
    end
    Print("Last error: " .. (lastError or "none"))
end

function ns.ResetSettings()
    local ignore = db.ignore
    wipe(db)
    for k, v in pairs(defaults) do db[k] = type(v) == "table" and { unpack(v) } or v end
    db.ignore = ignore
    ApplyLayout()
    Rebuild()
end

SLASH_GWCOOLDOWNPULSE1 = "/cdpulse"
SLASH_GWCOOLDOWNPULSE2 = "/cooldownpulse"
SlashCmdList.GWCOOLDOWNPULSE = function(msg)
    msg = (msg or ""):trim()
    local cmd, rest = msg:match("^(%S*)%s*(.-)$")
    cmd = (cmd or ""):lower()

    if cmd == "" or cmd == "config" or cmd == "options" then
        if ns.ToggleConfig then ns.ToggleConfig() end
    elseif cmd == "test" then
        ns.Test()
    elseif cmd == "move" then
        ns.SetUnlocked(not ns.IsUnlocked())
        Print(ns.IsUnlocked() and "Drag the blue box, then /cdpulse move again to lock." or "Locked.")
    elseif cmd == "debug" then
        Debug(rest)
    elseif cmd == "reset" then
        ns.ResetSettings()
        Print("Settings and position reset (spell choices kept).")
    else
        Print("/cdpulse - settings window")
        Print("/cdpulse test | move | reset | debug [spell name]")
    end
end
