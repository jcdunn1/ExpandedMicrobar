-- ExpandedMicrobar.lua
-- Patch 11.2.7
--
-- Goals:
--   1) Add a real Spellbook button to the micro menu.
--   2) Retarget Blizzard PlayerSpellsMicroButton so it behaves as Talents-only.
--   3) Non-ElvUI: replace Blizzard micro container layout (we do our own).
--   4) Hide the far-right Customer Support/Web Ticket "?" button.
--
-- ElvUI support:
--   - If ElvUI_MicroBar exists, we DO NOT replace layout.
--   - We create a unique button name (ExpandedMicrobarSpellbookButton)
--     and insert it into _G.MICRO_BUTTONS for ElvUI positioning.
--   - We let ElvUI skin the button, but we provide our OWN overlay icon
--     (prevents sheet-coords conflicts and professions being replaced).
--   - IMPORTANT: We do NOT run a repeating ticker (avoids recursion/stack overflow).

local SPACING = -5
local ELVUI_BUTTON_NAME = "ExpandedMicrobarSpellbookButton" -- never use SpellbookMicroButton

-- Non-ElvUI layout order (left -> right)
local ORDER = {
  "CharacterMicroButton",
  ELVUI_BUTTON_NAME,
  "PlayerSpellsMicroButton", -- Talents-only
  "HousingMicroButton",
  "ProfessionMicroButton",
  "AchievementMicroButton",
  "GuildMicroButton",
  "LFDMicroButton",
  "CollectionsMicroButton",
  "EJMicroButton",
  "StoreMicroButton",
  "MainMenuMicroButton",
}

----------------------------------------------------------------------
-- Utilities
----------------------------------------------------------------------
local function InCombat()
  return InCombatLockdown and InCombatLockdown()
end

local function IsElvUIMicrobarActive()
  return _G.ElvUI_MicroBar ~= nil
end

local function GetBlizzardMicroContainer()
  local bar = _G.MicroButtonAndBagsBar
  if bar and bar.MicroMenu then return bar.MicroMenu end
  return _G.MicroMenu
end

----------------------------------------------------------------------
-- Hide Web Ticket / Customer Support "?"
----------------------------------------------------------------------
local function FindWebTicketFrame()
  return _G.HelpOpenWebTicketButton
      or _G.HelpOpenTicketButton
      or _G.HelpOpenWebTicket
      or _G.HelpOpenTicket
end

local function HideWebTicketOnce()
  local t = FindWebTicketFrame()
  if not t then return end

  if not t._ExpandedMicrobar_HideHooked and t.HookScript then
    t._ExpandedMicrobar_HideHooked = true
    t:HookScript("OnShow", function(self)
      self:Hide()
      if self.SetAlpha then self:SetAlpha(0) end
    end)
  end

  t:Hide()
  if t.SetAlpha then t:SetAlpha(0) end
  if t.EnableMouse then t:EnableMouse(false) end
end

local function StartWebTicketHider()
  HideWebTicketOnce()
  if _G.ExpandedMicrobarTicketTicker then return end
  _G.ExpandedMicrobarTicketTicker = C_Timer.NewTicker(0.25, HideWebTicketOnce, 80) -- ~20s
end

----------------------------------------------------------------------
-- PlayerSpellsFrame helpers
----------------------------------------------------------------------
local function ClickPlayerSpellsTab(tabNameLower)
  local frame = _G.PlayerSpellsFrame
  if not frame then return end

  local function matches(btn)
    local fs = btn.GetFontString and btn:GetFontString()
    if fs then
      local tx = fs:GetText()
      if tx and tx:lower() == tabNameLower then return true end
    end
    local tt = btn.tooltipText or btn.tooltipTitle
    if type(tt) == "string" and tt:lower():find(tabNameLower, 1, true) then return true end
    return false
  end

  local function scan(root, depth)
    if depth > 7 then return nil end
    for _, c in ipairs({ root:GetChildren() }) do
      if c and c.IsObjectType then
        if c:IsObjectType("Button") and matches(c) then return c end
        local f = scan(c, depth + 1)
        if f then return f end
      end
    end
    return nil
  end

  local tab = scan(frame, 0)
  if tab and tab.Click then tab:Click() end
end

local function TogglePlayerSpellsThen(fn)
  if PlayerSpellsUtil and PlayerSpellsUtil.TogglePlayerSpellsFrame then
    PlayerSpellsUtil.TogglePlayerSpellsFrame()
    C_Timer.After(0, fn)
  end
end

local function ForceSpellbookTab()
  ClickPlayerSpellsTab((SPELLBOOK and SPELLBOOK:lower()) or "spellbook")
end

local function ForceTalentsTab()
  ClickPlayerSpellsTab((TALENTS and TALENTS:lower()) or "talents")
end

----------------------------------------------------------------------
-- Talents button state: keep hover highlight; prevent selected when opening Spellbook
----------------------------------------------------------------------
local function RestoreMicroButtonChrome(btn)
  if not btn then return end

  local n = btn.GetNormalTexture and btn:GetNormalTexture()
  local p = btn.GetPushedTexture and btn:GetPushedTexture()
  local d = btn.GetDisabledTexture and btn:GetDisabledTexture()
  local ht = btn.GetHighlightTexture and btn:GetHighlightTexture()

  if n then n:SetAlpha(1); n:Show() end
  if p then p:SetAlpha(1); p:Hide() end
  if d then d:SetAlpha(1); d:Hide() end
  if ht then ht:SetAlpha(1) end

  if btn.Background then btn.Background:SetAlpha(1); btn.Background:Show() end
  if btn.PushedBackground then btn.PushedBackground:SetAlpha(1); btn.PushedBackground:Hide() end

  if btn.FlashBorder then btn.FlashBorder:Hide() end
  if btn.FlashContent then btn.FlashContent:Hide() end
  if btn.QuickKeybindHighlightTexture then btn.QuickKeybindHighlightTexture:Hide() end
end

local function ClearTalentsSelectedVisual()
  local ps = _G.PlayerSpellsMicroButton
  if not ps then return end

  if ps._ExpandedMicrobar_SuppressClear then return end
  ps._ExpandedMicrobar_SuppressClear = true

  if ps.SetChecked then ps:SetChecked(false) end
  if ps.SetButtonState then ps:SetButtonState("NORMAL", false) end

  if ps.PushedBackground then ps.PushedBackground:Hide() end

  local ht = ps.GetHighlightTexture and ps:GetHighlightTexture()
  if ht then
    ht:SetAlpha(1)
    -- do NOT permanently hide; hover should work
    ht:Hide()
  end

  RestoreMicroButtonChrome(ps)

  ps._ExpandedMicrobar_SuppressClear = false
end

local function PatchPlayerSpellsButton()
  local b = _G.PlayerSpellsMicroButton
  if not b or b._ExpandedMicrobar_Patched then return end
  b._ExpandedMicrobar_Patched = true

  _G.ExpandedMicrobar_LastSpellsMode = _G.ExpandedMicrobar_LastSpellsMode or "talents"
  b._ExpandedMicrobar_AllowChecked = false

  b.tooltipText = "Talents |cffffff00(N)|r"

  b:HookScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText(self.tooltipText, 1, 1, 1)
    GameTooltip:Show()

    local ht = self.GetHighlightTexture and self:GetHighlightTexture()
    if ht then ht:SetAlpha(1); ht:Show() end

    local n = self.GetNormalTexture and self:GetNormalTexture()
    if n then n:SetAlpha(1) end
  end)

  b:HookScript("OnLeave", function(self)
    GameTooltip_Hide()
    local ht = self.GetHighlightTexture and self:GetHighlightTexture()
    if ht then ht:Hide() end
  end)

  b:HookScript("OnClick", function(self)
    _G.ExpandedMicrobar_LastSpellsMode = "talents"
    self._ExpandedMicrobar_AllowChecked = true
    C_Timer.After(0, function()
      ForceTalentsTab()
      C_Timer.After(0.2, function() self._ExpandedMicrobar_AllowChecked = false end)
    end)
  end)

  if type(b.SetChecked) == "function" and not b._ExpandedMicrobar_SetCheckedHooked then
    b._ExpandedMicrobar_SetCheckedHooked = true
    hooksecurefunc(b, "SetChecked", function(self, checked)
      if self._ExpandedMicrobar_SuppressClear then return end
      if checked and (not self._ExpandedMicrobar_AllowChecked) and _G.ExpandedMicrobar_LastSpellsMode ~= "talents" then
        C_Timer.After(0, ClearTalentsSelectedVisual)
        C_Timer.After(0.15, ClearTalentsSelectedVisual)
      end
    end)
  end
end

----------------------------------------------------------------------
-- Spellbook button helpers
----------------------------------------------------------------------
local function CopyAtlasOrTexture(dst, src)
  if not (dst and src) then return end

  if src.GetAtlas and dst.SetAtlas then
    local a = src:GetAtlas()
    if a then dst:SetAtlas(a, true) return end
  end

  if src.GetTexture and dst.SetTexture then
    local t = src:GetTexture()
    if t then dst:SetTexture(t) end
  end

  if src.GetTexCoord and dst.SetTexCoord then
    local l, r, t, b = src:GetTexCoord()
    if l then dst:SetTexCoord(l, r, t, b) end
  end

  if src.GetVertexColor and dst.SetVertexColor then
    local r, g, b, a = src:GetVertexColor()
    if r then dst:SetVertexColor(r, g, b, a) end
  end

  if src.GetBlendMode and dst.SetBlendMode then
    local bm = src:GetBlendMode()
    if bm then dst:SetBlendMode(bm) end
  end

  if src.GetAlpha and dst.SetAlpha then
    dst:SetAlpha(src:GetAlpha() or 1)
  end
end

local function CloneTextureRegion(dstBtn, key, srcBtn)
  local src = srcBtn and srcBtn[key]
  if not (src and src.IsObjectType and src:IsObjectType("Texture")) then return end

  local layer, subLevel = src:GetDrawLayer()
  local dst = dstBtn[key]
  if not dst then
    dst = dstBtn:CreateTexture(nil, layer, nil, subLevel)
    dstBtn[key] = dst
  end

  CopyAtlasOrTexture(dst, src)

  local w, h = src:GetSize()
  if w and h and w > 0 and h > 0 then dst:SetSize(w, h) end

  dst:ClearAllPoints()
  local n = src:GetNumPoints() or 0
  for i = 1, n do
    local p, rel, rp, x, y = src:GetPoint(i)
    if p and rel and rp then
      dst:SetPoint(p, rel, rp, x or 0, y or 0)
    end
  end
  dst:Show()
end

local function EnsureIconOnlyHighlight(self, anchor)
  if self._ExpandedMicrobar_IconHighlight then return self._ExpandedMicrobar_IconHighlight end

  local hl = self:CreateTexture(nil, "OVERLAY", nil, 7)
  local a = anchor or self

  local w, h
  if a and a.GetSize then w, h = a:GetSize() end
  w = (w and w > 0) and w or 18
  h = (h and h > 0) and h or 18

  hl:ClearAllPoints()
  hl:SetPoint("CENTER", a, "CENTER", 0, 0)
  hl:SetSize(w + 10, h + 10)
  hl:SetTexture("Interface/Buttons/ButtonHilight-Square")
  hl:SetBlendMode("ADD")
  hl:SetAlpha(0.45)
  hl:Hide()

  self._ExpandedMicrobar_IconHighlight = hl
  return hl
end

local function ApplyElvUIOverlayIcon(btn)
  if not btn or btn._ExpandedMicrobar_ElvUIIconApplied then return end
  btn._ExpandedMicrobar_ElvUIIconApplied = true

  -- Hide ElvUI-assigned sheet textures on OUR custom button only.
  local n = btn.GetNormalTexture and btn:GetNormalTexture()
  local p = btn.GetPushedTexture and btn:GetPushedTexture()
  local d = btn.GetDisabledTexture and btn:GetDisabledTexture()
  if n then n:SetAlpha(0); n:Hide() end
  if p then p:SetAlpha(0); p:Hide() end
  if d then d:SetAlpha(0); d:Hide() end

  local icon = btn:CreateTexture(nil, "OVERLAY", nil, 7)
  icon:SetSize(18, 18)
  icon:SetPoint("CENTER", btn, "CENTER", 0, -2)
  icon:SetTexture("Interface/Icons/INV_Misc_Book_09")
  icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  btn._ExpandedMicrobar_OverlayIcon = icon

  btn:HookScript("OnMouseDown", function(self)
    if self._ExpandedMicrobar_OverlayIcon then self._ExpandedMicrobar_OverlayIcon:SetAlpha(0.75) end
  end)
  btn:HookScript("OnMouseUp", function(self)
    if self._ExpandedMicrobar_OverlayIcon then self._ExpandedMicrobar_OverlayIcon:SetAlpha(1) end
  end)
end

local function CreateSpellbookButton(parent)
  if _G[ELVUI_BUTTON_NAME] then
    local existing = _G[ELVUI_BUTTON_NAME]
    if existing.SetParent then existing:SetParent(parent) end
    return existing
  end

  local ref = _G.PlayerSpellsMicroButton
  if not ref then return nil end

  local b = CreateFrame("Button", ELVUI_BUTTON_NAME, parent)
  b:SetSize(ref:GetSize())
  b:SetFrameStrata(ref:GetFrameStrata())
  b:SetFrameLevel(ref:GetFrameLevel())
  b:EnableMouse(true)
  b:RegisterForClicks("AnyUp")

  local elvuiMode = IsElvUIMicrobarActive()

  -- ElvUI needs placeholder textures to exist
  if elvuiMode then
    if not (b.GetNormalTexture and b:GetNormalTexture()) then
      b:SetNormalTexture(b:CreateTexture(nil, "ARTWORK"))
    end
    if not (b.GetPushedTexture and b:GetPushedTexture()) then
      b:SetPushedTexture(b:CreateTexture(nil, "ARTWORK"))
    end
    if not (b.GetDisabledTexture and b:GetDisabledTexture()) then
      b:SetDisabledTexture(b:CreateTexture(nil, "ARTWORK"))
    end
  end

  if not elvuiMode then
    -- Clone full micro chrome from talents button.
    b:SetNormalAtlas("UI-HUD-MicroMenu-SpecTalents-Up", true)
    b:SetPushedAtlas("UI-HUD-MicroMenu-SpecTalents-Down", true)
    b:SetDisabledAtlas("UI-HUD-MicroMenu-SpecTalents-Up", true)
    b:SetHighlightAtlas("UI-HUD-MicroMenu-Highlight", "ADD")

    CopyAtlasOrTexture(b:GetNormalTexture(),    ref:GetNormalTexture())
    CopyAtlasOrTexture(b:GetPushedTexture(),    ref:GetPushedTexture())
    CopyAtlasOrTexture(b:GetDisabledTexture(),  ref:GetDisabledTexture())
    CopyAtlasOrTexture(b:GetHighlightTexture(), ref:GetHighlightTexture())

    for _, getter in ipairs({"GetNormalTexture", "GetPushedTexture", "GetDisabledTexture", "GetHighlightTexture"}) do
      local t = b[getter] and b[getter](b)
      if t then
        t:ClearAllPoints(); t:SetAllPoints(b)
        if getter == "GetHighlightTexture" then t:SetAlpha(0); t:Hide() else t:SetAlpha(1) end
      end
    end

    CloneTextureRegion(b, "Background", ref)
    CloneTextureRegion(b, "PushedBackground", ref)
    CloneTextureRegion(b, "FlashBorder", ref)
    CloneTextureRegion(b, "FlashContent", ref)
    CloneTextureRegion(b, "QuickKeybindHighlightTexture", ref)

    if b.Background then b.Background:ClearAllPoints(); b.Background:SetAllPoints(b); b.Background:Show(); b.Background:SetAlpha(1) end
    if b.PushedBackground then b.PushedBackground:ClearAllPoints(); b.PushedBackground:SetAllPoints(b); b.PushedBackground:Hide(); b.PushedBackground:SetAlpha(1) end
    if b.FlashBorder then b.FlashBorder:Hide() end
    if b.FlashContent then b.FlashContent:Hide() end
    if b.QuickKeybindHighlightTexture then b.QuickKeybindHighlightTexture:Hide() end

    -- Strip baked glyphs from base textures.
    local n = b.GetNormalTexture and b:GetNormalTexture()
    local p = b.GetPushedTexture and b:GetPushedTexture()
    local d = b.GetDisabledTexture and b:GetDisabledTexture()
    if n then n:SetAlpha(0) end
    if p then p:SetAlpha(0) end
    if d then d:SetAlpha(0) end

    -- Overlay book icon.
    local icon = b:CreateTexture(nil, "OVERLAY", nil, 7)
    icon:SetSize(18, 18)
    icon:SetPoint("CENTER", b, "CENTER", 0, -2)
    icon:SetTexture("Interface/Icons/INV_Misc_Book_09")
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    b._ExpandedMicrobar_OverlayIcon = icon

    -- Pressed feedback swaps chrome.
    b:SetScript("OnMouseDown", function(self)
      if self.Background and self.PushedBackground then
        self.Background:Hide(); self.PushedBackground:Show()
      end
    end)
    b:SetScript("OnMouseUp", function(self)
      if self.Background and self.PushedBackground then
        self.PushedBackground:Hide(); self.Background:Show()
      end
    end)
  end

  -- Tooltip + icon-only highlight (both modes)
  b:HookScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText("Spellbook |cffffff00(P)|r", 1, 1, 1)
    GameTooltip:Show()

    local anchor = self._ExpandedMicrobar_OverlayIcon or (self.GetNormalTexture and self:GetNormalTexture())
    local hl = EnsureIconOnlyHighlight(self, anchor)
    if hl then hl:Show() end
  end)

  b:HookScript("OnLeave", function(self)
    GameTooltip_Hide()
    local hl = self._ExpandedMicrobar_IconHighlight
    if hl then hl:Hide() end
  end)

  b:SetScript("OnClick", function()
    _G.ExpandedMicrobar_LastSpellsMode = "spellbook"
    TogglePlayerSpellsThen(function()
      ForceSpellbookTab()
      C_Timer.After(0, ClearTalentsSelectedVisual)
      C_Timer.After(0.15, ClearTalentsSelectedVisual)
    end)
  end)

  return b
end

----------------------------------------------------------------------
-- ElvUI integration (no ticker)
----------------------------------------------------------------------
local function InsertIntoMicroButtonsList()
  if type(_G.MICRO_BUTTONS) ~= "table" then
    _G.MICRO_BUTTONS = {}
  end

  local list = _G.MICRO_BUTTONS
  for _, v in ipairs(list) do
    if v == ELVUI_BUTTON_NAME then return end
  end

  for i, v in ipairs(list) do
    if v == "CharacterMicroButton" then
      table.insert(list, i + 1, ELVUI_BUTTON_NAME)
      return
    end
  end

  table.insert(list, 1, ELVUI_BUTTON_NAME)
end

local function TryElvUISkinSpellbook(btn)
  if not btn then return end
  if not _G.ElvUI or type(unpack) ~= "function" then return end

  local ok, E = pcall(unpack, _G.ElvUI)
  if not ok or not E or type(E.GetModule) ~= "function" then return end

  local ok2, AB = pcall(function() return E:GetModule("ActionBars") end)
  if not ok2 or not AB then return end

  if AB.MICRO_OFFSETS and not AB.MICRO_OFFSETS[ELVUI_BUTTON_NAME] then
    AB.MICRO_OFFSETS[ELVUI_BUTTON_NAME] = AB.MICRO_OFFSETS.SpellbookMicroButton
      or AB.MICRO_OFFSETS.ProfessionMicroButton
      or (1.05 / 12.125)
  end

  if type(AB.HandleMicroButton) == "function" then
    pcall(function() AB:HandleMicroButton(btn, ELVUI_BUTTON_NAME) end)
  end
  if type(AB.UpdateMicroButtonTexture) == "function" then
    pcall(function() AB:UpdateMicroButtonTexture(ELVUI_BUTTON_NAME) end)
  end

  -- Force our own icon overlay so we don't conflict with ElvUI micro-sheet coords.
  ApplyElvUIOverlayIcon(btn)
end

local function EnsureElvUISpellbookButton()
  if not IsElvUIMicrobarActive() then return end

  local btn = CreateSpellbookButton(_G.ElvUI_MicroBar)
  InsertIntoMicroButtonsList()

  -- Skin now, then retry once after ElvUI finishes its own microbar update.
  TryElvUISkinSpellbook(btn)
  C_Timer.After(0.5, function()
    TryElvUISkinSpellbook(btn)
  end)
end

----------------------------------------------------------------------
-- Non-ElvUI: replacement bar + layout
----------------------------------------------------------------------
local OurBar
local ButtonsForLayout = {}
local LayoutQueued = false

local function DisableBlizzardMicroContainerLayout()
  local c = GetBlizzardMicroContainer()
  if not c or c._ExpandedMicrobar_Disabled then return end
  c._ExpandedMicrobar_Disabled = true
  c.Layout = function() end
  c.UpdateHelpTicketButtonAnchor = function() end
end

local function HideBlizzardMicroContainer()
  local c = GetBlizzardMicroContainer()
  if c then
    c:Hide()
    c:SetAlpha(0)
    c:EnableMouse(false)
  end
end

local function CreateOurBar()
  if OurBar then return OurBar end

  OurBar = CreateFrame("Frame", "ExpandedMicrobarBar", UIParent)
  OurBar:SetSize(1, 1)
  OurBar:SetFrameStrata("MEDIUM")
  OurBar:SetFrameLevel(10)

  local blizz = GetBlizzardMicroContainer()
  if blizz and blizz.GetPoint then
    local p, rel, rp, x, y = blizz:GetPoint(1)
    if p and rel and rp then
      OurBar:SetPoint(p, rel, rp, x or 0, y or 0)
    else
      OurBar:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -14, 44)
    end
  else
    OurBar:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -14, 44)
  end

  return OurBar
end

local function QueueLayout()
  if LayoutQueued then return end
  LayoutQueued = true

  C_Timer.After(0, function()
    LayoutQueued = false
    if InCombat() then return end

    local prev
    local maxH = 0
    local totalW = 0

    for _, b in ipairs(ButtonsForLayout) do
      if b and b.Show then
        b:ClearAllPoints()
        b:SetParent(OurBar)
        b:Show()
        if b.SetAlpha then b:SetAlpha(1) end

        local w = b:GetWidth() or 0
        local h = b:GetHeight() or 0
        if h > maxH then maxH = h end

        if not prev then
          b:SetPoint("TOPLEFT", OurBar, "TOPLEFT", 0, 0)
          totalW = w
        else
          b:SetPoint("TOPLEFT", prev, "TOPRIGHT", SPACING, 0)
          totalW = totalW + w + SPACING
        end

        prev = b
      end
    end

    if totalW < 1 then totalW = 1 end
    if maxH < 1 then maxH = 1 end
    OurBar:SetSize(totalW, maxH)
  end)
end

local function HookRelayoutOnShowHide(b)
  if not b or b._ExpandedMicrobar_ShowHideHooked then return end
  b._ExpandedMicrobar_ShowHideHooked = true
  b:HookScript("OnShow", QueueLayout)
  b:HookScript("OnHide", QueueLayout)
end

local function CollectButtons()
  ButtonsForLayout = {}

  for _, name in ipairs(ORDER) do
    local b = _G[name]
    if name == ELVUI_BUTTON_NAME then
      b = CreateSpellbookButton(OurBar)
    end

    if b and b.Show then
      table.insert(ButtonsForLayout, b)
      HookRelayoutOnShowHide(b)
    end
  end
end

----------------------------------------------------------------------
-- Apply
----------------------------------------------------------------------
local function Apply()
  if InCombat() then return end

  StartWebTicketHider()
  PatchPlayerSpellsButton()

  if IsElvUIMicrobarActive() then
    EnsureElvUISpellbookButton()
    return
  end

  DisableBlizzardMicroContainerLayout()
  HideBlizzardMicroContainer()

  CreateOurBar()
  CollectButtons()
  QueueLayout()

  C_Timer.After(0.8, function()
    if InCombat() then return end
    StartWebTicketHider()
    QueueLayout()
  end)
end

----------------------------------------------------------------------
-- Bootstrap
----------------------------------------------------------------------
local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("PLAYER_REGEN_ENABLED")
f:RegisterEvent("ADDON_LOADED")

f:SetScript("OnEvent", function(_, event, addonName)
  -- Only react to ADDON_LOADED for ElvUI itself. Other load-on-demand Blizzard addons
  -- (like Blizzard_MapCanvas) should not trigger our Apply(), to avoid unintended interactions.
  if event == "ADDON_LOADED" then
    if addonName == "ElvUI" then
      C_Timer.After(0, Apply)
      C_Timer.After(0.2, Apply)
    end
    return
  end

  Apply()
  C_Timer.After(0.2, Apply)
  C_Timer.After(0.8, Apply)
end)
