-- GW Cooldown Pulse - settings window
-- Opened with /cdpulse, or from the game's Options > AddOns > GW Cooldown Pulse.
-- Widgets are built by hand (only long-standing templates are used) so the
-- window works on both older and newer clients.

local ADDON, ns = ...

local WIDTH, HEIGHT = 560, 470
local LIST_W, ROW_H = 220, 22

local frame                 -- the window, built the first time it is opened
local controls = {}         -- everything with a :Refresh()

-- Small widget helpers ---------------------------------------------------------
local function Label(parent, text, font)
    local fs = parent:CreateFontString(nil, "ARTWORK", font or "GameFontNormal")
    fs:SetText(text)
    fs:SetJustifyH("LEFT")
    return fs
end

local function Slider(parent, text, min, max, step, fmt, key, onChange)
    local s = CreateFrame("Slider", nil, parent)
    s:SetOrientation("HORIZONTAL")
    s:SetSize(220, 16)
    s:SetHitRectInsets(0, 0, -6, -6)
    s:SetMinMaxValues(min, max)
    s:SetValueStep(step)
    if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end

    local track = s:CreateTexture(nil, "BACKGROUND")
    track:SetPoint("LEFT"); track:SetPoint("RIGHT")
    track:SetHeight(4)
    track:SetColorTexture(0.3, 0.3, 0.3, 0.9)
    s:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    local thumb = s:GetThumbTexture()
    if thumb then thumb:SetSize(32, 32) end

    s.label = Label(s, text)
    s.label:SetPoint("BOTTOMLEFT", s, "TOPLEFT", 0, 3)
    s.value = Label(s, "", "GameFontHighlight")
    s.value:SetPoint("BOTTOMRIGHT", s, "TOPRIGHT", 0, 3)

    s:SetScript("OnValueChanged", function(self, v)
        v = math.floor(v / step + 0.5) * step
        self.value:SetText(fmt(v))
        if self.updating then return end
        ns.DB()[key] = v
        if onChange then onChange(v) end
    end)
    s:EnableMouseWheel(true)
    s:SetScript("OnMouseWheel", function(self, delta)
        self:SetValue(self:GetValue() + delta * step)
    end)
    function s:Refresh()
        self.updating = true
        self:SetValue(ns.DB()[key])
        self.value:SetText(fmt(ns.DB()[key]))
        self.updating = false
    end
    controls[#controls + 1] = s
    return s
end

local function Check(parent, text, key, onChange)
    local c = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    c:SetSize(24, 24)
    if c.Text then c.Text:SetText("") end      -- we use our own label
    c.label = Label(c, text, "GameFontHighlight")
    c.label:SetPoint("LEFT", c, "RIGHT", 2, 1)
    c:SetScript("OnClick", function(self)
        ns.DB()[key] = self:GetChecked() and true or false
        if onChange then onChange() end
    end)
    function c:Refresh() self:SetChecked(ns.DB()[key]) end
    controls[#controls + 1] = c
    return c
end

local function Button(parent, text, width, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width, 24)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    return b
end

-- Spell list -------------------------------------------------------------------
local list = { rows = {} }

-- Only list things that can actually pulse: trinkets, defensives, and spells
-- with a real cooldown (from the spell's data, or one we've seen it on).
local function BaseCooldownMS(id)
    local ms
    if C_Spell and C_Spell.GetSpellBaseCooldown then
        ms = C_Spell.GetSpellBaseCooldown(id)
    elseif GetSpellBaseCooldown then
        ms = GetSpellBaseCooldown(id)
    end
    if type(ms) ~= "number" or (issecretvalue and issecretvalue(ms)) then return nil end
    return ms
end

local function CanPulse(s)
    if s.slot or s.def then return true end
    if (s.lastDur or 0) > 1.5 then return true end
    local ms = s.spell and BaseCooldownMS(s.spell)
    return ms ~= nil and ms > 1500
end

local function SortedSpells()
    local out = {}
    for _, s in pairs(ns.tracked) do
        if s.name and CanPulse(s) then out[#out + 1] = s end
    end
    table.sort(out, function(a, b)
        if (a.slot ~= nil) ~= (b.slot ~= nil) then return a.slot ~= nil end -- trinkets first
        return a.name < b.name
    end)
    return out
end

local function GetRow(i)
    local row = list.rows[i]
    if row then return row end
    row = CreateFrame("Frame", nil, list.content)
    row:SetSize(LIST_W - 4, ROW_H)
    row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)

    row.check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    row.check:SetSize(22, 22)
    row.check:SetPoint("LEFT", 0, 0)
    if row.check.Text then row.check.Text:SetText("") end
    row.check:SetScript("OnClick", function(self)
        ns.SetIgnored(row.spell, not self:GetChecked())
        row.name:SetAlpha(self:GetChecked() and 1 or 0.45)
        row.icon:SetDesaturated(not self:GetChecked())
    end)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(18, 18)
    row.icon:SetPoint("LEFT", row.check, "RIGHT", 2, 0)
    row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    row.name = Label(row, "", "GameFontHighlightSmall")
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
    row.name:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    row.name:SetWordWrap(false)

    list.rows[i] = row
    return row
end

local function RefreshList()
    if not frame or not frame:IsShown() then return end
    local spells = SortedSpells()
    for i, s in ipairs(spells) do
        local row = GetRow(i)
        local on = not ns.Ignored(s)
        row.spell = s
        row.icon:SetTexture(s.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
        row.icon:SetDesaturated(not on)
        row.name:SetText(s.slot and (s.name .. " |cff888888(trinket)|r") or s.name)
        row.name:SetAlpha(on and 1 or 0.45)
        row.check:SetChecked(on)
        row:Show()
    end
    for i = #spells + 1, #list.rows do list.rows[i]:Hide() end
    list.content:SetHeight(math.max(1, #spells * ROW_H))
    list.empty:SetShown(#spells == 0)
end

-- New spells learned or cast while the window is open show up straight away.
ns.OnTrackedChanged = RefreshList

local function SetAllSpells(on)
    for _, s in pairs(ns.tracked) do ns.SetIgnored(s, not on) end
    RefreshList()
end

-- The window -------------------------------------------------------------------
local function RefreshAll()
    for _, c in ipairs(controls) do c:Refresh() end
    if frame.moveButton then
        frame.moveButton:SetText(ns.IsUnlocked() and "Lock position" or "Unlock position")
    end
    RefreshList()
end

local function Build()
    frame = CreateFrame("Frame", "GWCooldownPulseConfig", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(WIDTH, HEIGHT)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetScript("OnShow", RefreshAll)
    frame:Hide()
    tinsert(UISpecialFrames, "GWCooldownPulseConfig")   -- Escape closes it

    local title = frame.TitleText
    if not title then
        title = Label(frame, "", "GameFontHighlight")
        title:SetPoint("TOP", 0, -5)
    end
    title:SetText("GW Cooldown Pulse")

    -- Left column: look and behaviour (y = offset from the window's top)
    local X = 24
    local function At(w, y, dx) w:SetPoint("TOPLEFT", frame, "TOPLEFT", X + (dx or 0), y) end
    local function Pct(v) return string.format("%d%%", v * 100 + 0.5) end

    At(Label(frame, "Appearance", "GameFontNormalLarge"), -34)
    At(Slider(frame, "Icon size", 24, 160, 4,
        function(v) return string.format("%d px (grows to %d)", v, v * 5) end,
        "size", function() ns.ApplyLayout(); ns.Preview() end), -76)
    At(Slider(frame, "Opacity", 0.1, 1, 0.05, Pct, "alpha", ns.Preview), -122)
    At(Slider(frame, "Halo glow", 0, 1, 0.05,
        function(v) return v == 0 and "off" or Pct(v) end, "halo", ns.Preview), -168)
    At(Slider(frame, "Animation length", 1.5, 5, 0.25,
        function(v) return string.format("%.2fs", v) end, "duration", ns.Preview), -214)

    At(Label(frame, "When to pulse", "GameFontNormalLarge"), -250)
    At(Slider(frame, "Ignore cooldowns shorter than", 0, 30, 0.5,
        function(v) return string.format("%gs", v) end, "minCD"), -292)
    At(Check(frame, "Only while in combat", "combatOnly"), -316, -4)
    At(Check(frame, "Include trinkets", "trinkets", ns.Rebuild), -342, -4)

    -- Buttons along the bottom
    local test = Button(frame, "Test", 80, ns.Test)
    test:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 20, 16)
    frame.moveButton = Button(frame, "Unlock position", 120, function(self)
        ns.SetUnlocked(not ns.IsUnlocked())
        self:SetText(ns.IsUnlocked() and "Lock position" or "Unlock position")
    end)
    frame.moveButton:SetPoint("LEFT", test, "RIGHT", 6, 0)
    local reset = Button(frame, "Defaults", 90, function()
        ns.ResetSettings()
        RefreshAll()
        ns.Print("Settings and position reset (spell choices kept).")
    end)
    reset:SetPoint("LEFT", frame.moveButton, "RIGHT", 6, 0)

    -- Right column: spell list
    local lx = WIDTH - LIST_W - 46
    local header3 = Label(frame, "Spells that pulse", "GameFontNormalLarge")
    header3:SetPoint("TOPLEFT", frame, "TOPLEFT", lx, -34)

    local box = CreateFrame("Frame", nil, frame)
    box:SetPoint("TOPLEFT", frame, "TOPLEFT", lx - 4, -56)
    box:SetSize(LIST_W + 28, HEIGHT - 56 - 76)
    local bg = box:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.35)

    local scroll = CreateFrame("ScrollFrame", nil, box, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 4, -4)
    scroll:SetPoint("BOTTOMRIGHT", -26, 4)
    list.content = CreateFrame("Frame", nil, scroll)
    list.content:SetSize(LIST_W, 1)
    scroll:SetScrollChild(list.content)

    list.empty = Label(box, "No spells with cooldowns yet.\nThey appear as you learn or cast them.", "GameFontDisableSmall")
    list.empty:SetPoint("TOP", 0, -20)
    list.empty:SetJustifyH("CENTER")

    local allOn = Button(frame, "All on", 70, function() SetAllSpells(true) end)
    allOn:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 0, -6)
    local allOff = Button(frame, "All off", 70, function() SetAllSpells(false) end)
    allOff:SetPoint("LEFT", allOn, "RIGHT", 6, 0)

    local hint = Label(frame, "Untick to silence", "GameFontDisableSmall")
    hint:SetPoint("LEFT", allOff, "RIGHT", 8, 0)
end

function ns.ToggleConfig()
    if not frame then Build() end
    frame:SetShown(not frame:IsShown())
end

-- Entry in the game's Options > AddOns list, with a button that opens the window.
local function RegisterOptionsPanel()
    local panel = CreateFrame("Frame")
    panel.name = "GW Cooldown Pulse"
    local t = Label(panel, "GW Cooldown Pulse", "GameFontNormalLarge")
    t:SetPoint("TOPLEFT", 16, -16)
    local d = Label(panel, "All settings are in the GW Cooldown Pulse window (also /cdpulse).", "GameFontHighlight")
    d:SetPoint("TOPLEFT", t, "BOTTOMLEFT", 0, -8)
    local open = Button(panel, "Open settings", 140, function()
        if SettingsPanel and SettingsPanel:IsShown() then HideUIPanel(SettingsPanel) end
        if InterfaceOptionsFrame and InterfaceOptionsFrame:IsShown() then HideUIPanel(InterfaceOptionsFrame) end
        if not frame then Build() end
        frame:Show()
    end)
    open:SetPoint("TOPLEFT", d, "BOTTOMLEFT", 0, -12)

    if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
        local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
        Settings.RegisterAddOnCategory(category)
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
    end
end

-- If the options list API differs on this client, the window still works.
local ok, err = pcall(RegisterOptionsPanel)
if not ok then ns.optionsPanelError = err end
