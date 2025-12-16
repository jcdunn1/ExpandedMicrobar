-- ExpandedMicrobar.lua
-- Patch 11.2.7
--
-- Stable version (syntax-clean):
--   * Custom Spellbook microbutton with correct chrome
--   * Talents microbutton stays Talents-only
--   * Opening Spellbook no longer forces Talents button into "down/selected"
--   * Extra far-right Customer Support / Web Ticket "?" is hidden
--   * Hover highlight works for stock buttons

local SPACING = -5

----------------------------------------------------------------------
-- Layout order (left -> right)
----------------------------------------------------------------------
local ORDER = {
  "CharacterMicroButton",
  "ExpandedMicrobarSpellbookButton",
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

local function AtlasExists(name)
  return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name) ~= nil
end

local function GetBlizzardMicroContainer()
  local bar = _G.MicroButtonAndBagsBar
  if bar and bar.MicroMenu then return bar.MicroMenu end
  return _G.MicroMenu
end

----------------------------------------------------------------------
-- Disable Blizzard micro layout
----------------------------------------------------------------------
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
  _G.ExpandedMicrobarTicketTicker = C_Timer.NewTicker(0.25, HideWebTicketOnce, 80)
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
    if type(tt) == "string" and tt:lower():find(tabNameLower, 1, true) then
      return true
    end
    return false
  end

  local function scan(root, depth)
    if depth > 7 then return nil end
    for _, c in ipairs({ root:GetChildren() }) do
      if c and c.IsObjectType then
        if c:IsObjectType("Button") and matches(c) then
          return c
        end
        local found = scan(c, depth + 1)
        if found then return found end
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
-- Prevent Talents button from showing selected when Spellbook is used
----------------------------------------------------------------------
local function ClearTalentsSelectedVisual()
  local ps = _G.PlayerSpellsMicroButton
  if not ps then return end
  if ps._ExpandedMicrobar_SuppressClear then return end
  ps._ExpandedMicrobar_SuppressClear = true

  if ps.SetChecked then
    ps:SetChecked(false)
  end
  if ps.SetButtonState then
    ps:SetButtonState("NORMAL", false)
  end

  local ht = ps.GetHighlightTexture and ps:GetHighlightTexture()
  if ht then ht:Hide() end

  local n = ps.GetNormalTexture and ps:GetNormalTexture()
  if n then n:SetAlpha(1); n:Show() end

  if ps.PushedBackground then ps.PushedBackground:Hide() end

  ps._ExpandedMicrobar_SuppressClear = false
end

----------------------------------------------------------------------
-- Spellbook button (robust: atlas if available, else clone chrome + overlay)
----------------------------------------------------------------------
local function EnsureOverlayIcon(btn, ref)
  if btn._ExpandedMicrobar_OverlayIcon then return btn._ExpandedMicrobar_OverlayIcon end

  local icon = btn:CreateTexture(nil, "OVERLAY", nil, 7)
  icon:SetSize(18, 18)
  icon:SetPoint("CENTER", btn, "CENTER", 0, -2)

  if ref and ref.Icon and ref.Icon.IsObjectType and ref.Icon:IsObjectType("Texture") then
    local w, h = ref.Icon:GetSize()
    if w and h and w > 0 and h > 0 then icon:SetSize(w, h) end

    icon:ClearAllPoints()
    local n = ref.Icon:GetNumPoints() or 0
    if n > 0 then
      for i = 1, n do
        local p, rel, rp, x, y = ref.Icon:GetPoint(i)
        if p and rel and rp then icon:SetPoint(p, rel, rp, x or 0, y or 0) end
      end
    else
      icon:SetPoint("CENTER", btn, "CENTER", 0, -2)
    end
  end

  btn._ExpandedMicrobar_OverlayIcon = icon
  return icon
end

local function StripBakedGlyphLayers(btn)
  local n = btn.GetNormalTexture and btn:GetNormalTexture()
  local p = btn.GetPushedTexture and btn:GetPushedTexture()
  local d = btn.GetDisabledTexture and btn:GetDisabledTexture()
  if n then n:SetAlpha(0) end
  if p then p:SetAlpha(0) end
  if d then d:SetAlpha(0) end
end

local function SetSpellbookPressedVisual(btn, pressed)
  if not btn or not btn._ExpandedMicrobar_UseChromeSwap then return end
  if pressed then
    if btn.Background then btn.Background:Hide() end
    if btn.PushedBackground then btn.PushedBackground:Show() end
  else
    if btn.PushedBackground then btn.PushedBackground:Hide() end
    if btn.Background then btn.Background:Show() end
  end
end

local function CreateSpellbookButton(parent)
  if _G.ExpandedMicrobarSpellbookButton then
    return _G.ExpandedMicrobarSpellbookButton
  end

  local ref = _G.PlayerSpellsMicroButton
  if not ref then return nil end

  local objectType = (ref.GetObjectType and ref:GetObjectType()) or "Button"
  local b = CreateFrame(objectType, "ExpandedMicrobarSpellbookButton", parent)
  b:SetSize(ref:GetSize())
  b:SetFrameStrata(ref:GetFrameStrata())
  b:SetFrameLevel(ref:GetFrameLevel())
  b:RegisterForClicks("AnyUp")

  local upCandidates = {
    "UI-HUD-MicroMenu-Spellbook-Up",
    "UI-HUD-MicroMenu-SpellBook-Up",
    "UI-HUD-MicroMenu-Spellbook",
    "UI-HUD-MicroMenu-SpellBook",
  }
  local downCandidates = {
    "UI-HUD-MicroMenu-Spellbook-Down",
    "UI-HUD-MicroMenu-SpellBook-Down",
  }

  local chosenUp
  for _, a in ipairs(upCandidates) do
    if AtlasExists(a) then chosenUp = a break end
  end

  if chosenUp then
    local chosenDown
    for _, a in ipairs(downCandidates) do
      if AtlasExists(a) then chosenDown = a break end
    end

    b:SetNormalAtlas(chosenUp, true)
    b:SetPushedAtlas(chosenDown or chosenUp, true)
    b:SetDisabledAtlas(chosenUp, true)
    b:SetHighlightAtlas("UI-HUD-MicroMenu-Highlight", "ADD")

    for _, getter in ipairs({"GetNormalTexture", "GetPushedTexture", "GetDisabledTexture", "GetHighlightTexture"}) do
      local t = b[getter] and b[getter](b)
      if t then
        t:ClearAllPoints()
        t:SetAllPoints(b)
        t:SetAlpha(1)
      end
    end

    b._ExpandedMicrobar_UseChromeSwap = false
  else
    -- Fallback: clone talents chrome and overlay book icon.
    b:SetNormalAtlas("UI-HUD-MicroMenu-SpecTalents-Up", true)
    b:SetPushedAtlas("UI-HUD-MicroMenu-SpecTalents-Down", true)
    b:SetDisabledAtlas("UI-HUD-MicroMenu-SpecTalents-Up", true)
    b:SetHighlightAtlas("UI-HUD-MicroMenu-Highlight", "ADD")

    local function copy(dst, src)
      if not (dst and src) then return end
      if src.GetAtlas and dst.SetAtlas then
        local a = src:GetAtlas()
        if a then dst:SetAtlas(a, true) return end
      end
      if src.GetTexture and dst.SetTexture then
        local t = src:GetTexture()
        if t then dst:SetTexture(t) end
      end
    end

    copy(b:GetNormalTexture(), ref:GetNormalTexture())
    copy(b:GetPushedTexture(), ref:GetPushedTexture())
    copy(b:GetDisabledTexture(), ref:GetDisabledTexture())
    copy(b:GetHighlightTexture(), ref:GetHighlightTexture())

    for _, getter in ipairs({"GetNormalTexture", "GetPushedTexture", "GetDisabledTexture", "GetHighlightTexture"}) do
      local t = b[getter] and b[getter](b)
      if t then
        t:ClearAllPoints(); t:SetAllPoints(b); t:SetAlpha(1)
      end
    end

    local function cloneRegion(key)
      local src = ref[key]
      if not (src and src.IsObjectType and src:IsObjectType("Texture")) then return end
      local layer, sub = src:GetDrawLayer()
      local dst = b:CreateTexture(nil, layer, nil, sub)
      b[key] = dst
      copy(dst, src)
      dst:ClearAllPoints(); dst:SetAllPoints(b); dst:SetAlpha(1); dst:Show()
    end

    cloneRegion("Background")
    cloneRegion("PushedBackground")

    b._ExpandedMicrobar_UseChromeSwap = true
    StripBakedGlyphLayers(b)

    -- Replace highlight with safe overlay (cloned highlight can contain talents glyph)
    local builtinHT = b.GetHighlightTexture and b:GetHighlightTexture()
    if builtinHT then builtinHT:Hide(); builtinHT:SetAlpha(0) end

    local hh = b:CreateTexture(nil, "HIGHLIGHT")
    hh:SetAllPoints(b)
    hh:SetColorTexture(1, 1, 1, 0.2)
    hh:Hide()
    b._ExpandedMicrobar_HoverHighlight = hh

    local icon = EnsureOverlayIcon(b, ref)
    icon:SetTexture("Interface/Icons/INV_Misc_Book_09")
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    icon:SetAlpha(1)
    icon:Show()

    b:SetScript("OnMouseDown", function(self) SetSpellbookPressedVisual(self, true) end)
    b:SetScript("OnMouseUp", function(self) SetSpellbookPressedVisual(self, false) end)
  end

  b:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText("Spellbook |cffffff00(P)|r", 1, 1, 1)
    GameTooltip:Show()
    if self._ExpandedMicrobar_HoverHighlight then self._ExpandedMicrobar_HoverHighlight:Show() end
  end)

  b:SetScript("OnLeave", function(self)
    GameTooltip_Hide()
    if self._ExpandedMicrobar_HoverHighlight then self._ExpandedMicrobar_HoverHighlight:Hide() end
    SetSpellbookPressedVisual(self, false)
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
-- Patch PlayerSpellsMicroButton to be Talents-only
----------------------------------------------------------------------
local function PatchPlayerSpellsButton()
  local b = _G.PlayerSpellsMicroButton
  if not b or b._ExpandedMicrobar_Patched then return end
  b._ExpandedMicrobar_Patched = true

  _G.ExpandedMicrobar_LastSpellsMode = _G.ExpandedMicrobar_LastSpellsMode or "talents"
  b._ExpandedMicrobar_AllowChecked = false

  b.tooltipText = "Talents |cffffff00(N)|r"

  b:HookScript("OnEnter", function(self)
    local ht = self.GetHighlightTexture and self:GetHighlightTexture()
    if ht then ht:SetAlpha(1); ht:Show() end
    local n = self.GetNormalTexture and self:GetNormalTexture()
    if n then n:SetAlpha(1) end

    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText(self.tooltipText, 1, 1, 1)
    GameTooltip:Show()
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
-- Our replacement bar + layout
----------------------------------------------------------------------
local OurBar
local ButtonsForLayout = {}
local LayoutQueued = false

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
    if name == "ExpandedMicrobarSpellbookButton" then
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

  DisableBlizzardMicroContainerLayout()
  HideBlizzardMicroContainer()
  StartWebTicketHider()

  PatchPlayerSpellsButton()

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
f:SetScript("OnEvent", function()
  Apply()
  C_Timer.After(0.2, Apply)
  C_Timer.After(0.8, Apply)
end)
