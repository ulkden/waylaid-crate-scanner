local _, ns = ...

-- "Buy materials" window: pick how many crates to fill and which option, see the shopping list
-- (what to buy after using what's already in your bags), and buy each line from the Auction House.

local Prices, Purchase = ns.Prices, ns.Purchase

local BuyUI = {}
ns.BuyUI = BuyUI

local WIDTH = 700
local ROW_H = 22
local OPTION_H = 18
local MAX_OPTIONS = 6
local MAX_ROWS = 16

local COLOR_GREY = "|cff808080"
local COLOR_GREEN = "|cff40ff40"
local COLOR_ORANGE = "|cffff9933"
local COLOR_RED = "|cffff4040"

local function IsAHOpen()
  return AuctionHouseFrame and AuctionHouseFrame:IsShown()
end

local function MakeButton(parent, text, width, height)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(width, height or 22)
  b:SetText(text)
  return b
end

local function MakeLabel(parent, font, text)
  local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
  if text then
    fs:SetText(text)
  end
  return fs
end

local function MakeNumberBox(parent, width, onChanged)
  local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
  box:SetSize(width, 20)
  box:SetAutoFocus(false)
  box:SetNumeric(true)
  box:SetMaxLetters(5)
  box:SetJustifyH("CENTER")
  box:SetScript("OnTextChanged", function(self, userInput)
    if userInput then
      onChanged(self, tonumber(self:GetText()))
    end
  end)
  box:SetScript("OnEnterPressed", function(self)
    self:ClearFocus()
  end)
  box:SetScript("OnEscapePressed", function(self)
    self:ClearFocus()
  end)
  return box
end

---------------------------------------------------------------------------
-- Window construction
---------------------------------------------------------------------------
local function BuildOptionRow(parent, index)
  local row = CreateFrame("Button", nil, parent)
  row:SetHeight(OPTION_H)
  row.Radio = row:CreateTexture(nil, "ARTWORK")
  row.Radio:SetSize(14, 14)
  row.Radio:SetPoint("LEFT", 2, 0)
  row.Radio:SetTexture("Interface\\Buttons\\UI-RadioButton")
  row.Icon = row:CreateTexture(nil, "ARTWORK")
  row.Icon:SetSize(16, 16)
  row.Icon:SetPoint("LEFT", row.Radio, "RIGHT", 4, 0)
  row.Text = MakeLabel(row)
  row.Text:SetPoint("LEFT", row.Icon, "RIGHT", 4, 0)
  row.Cost = MakeLabel(row)
  row.Cost:SetPoint("RIGHT", -4, 0)
  local hl = row:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints()
  hl:SetColorTexture(1, 1, 1, 0.08)
  row:SetScript("OnClick", function(self)
    BuyUI.optionIndex = self.index
    BuyUI.qtyOverrides = {}
    BuyUI:Refresh()
  end)
  row.index = index
  return row
end

local function BuildItemRow(parent)
  local row = CreateFrame("Frame", nil, parent)
  row:SetHeight(ROW_H)
  row.Bg = row:CreateTexture(nil, "BACKGROUND")
  row.Bg:SetAllPoints()
  row.Icon = row:CreateTexture(nil, "ARTWORK")
  row.Icon:SetSize(18, 18)
  row.Icon:SetPoint("LEFT", 4, 0)
  row.Icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

  row.BuyButton = MakeButton(row, "Buy", 130, 20)
  row.BuyButton:SetPoint("RIGHT", -24, 0)
  row.BuyButton:SetMotionScriptsWhileDisabled(true)
  row.CancelButton = CreateFrame("Button", nil, row, "UIPanelCloseButton")
  row.CancelButton:SetSize(22, 22)
  row.CancelButton:SetPoint("LEFT", row.BuyButton, "RIGHT", 0, 0)
  row.CancelButton:SetScript("OnClick", function()
    Purchase.Cancel()
  end)
  row.CancelButton:Hide()

  row.Est = MakeLabel(row)
  row.Est:SetWidth(105)
  row.Est:SetJustifyH("RIGHT")
  row.Est:SetPoint("RIGHT", row.BuyButton, "LEFT", -8, 0)
  row.Qty = MakeNumberBox(row, 44, function(_, value)
    if row.itemID then
      BuyUI.qtyOverrides[row.itemID] = value or 0
      BuyUI:UpdateRows()
    end
  end)
  row.Qty:SetPoint("RIGHT", row.Est, "LEFT", -10, 0)
  row.Have = MakeLabel(row)
  row.Have:SetWidth(44)
  row.Have:SetJustifyH("RIGHT")
  row.Have:SetPoint("RIGHT", row.Qty, "LEFT", -12, 0)
  row.Need = MakeLabel(row)
  row.Need:SetWidth(44)
  row.Need:SetJustifyH("RIGHT")
  row.Need:SetPoint("RIGHT", row.Have, "LEFT", -4, 0)
  row.Name = MakeLabel(row)
  row.Name:SetJustifyH("LEFT")
  row.Name:SetWordWrap(false)
  row.Name:SetPoint("LEFT", row.Icon, "RIGHT", 6, 0)
  row.Name:SetPoint("RIGHT", row.Need, "LEFT", -6, 0)

  row.BuyButton:SetScript("OnClick", function()
    BuyUI:OnBuyClick(row)
  end)
  row.BuyButton:SetScript("OnEnter", function(self)
    BuyUI:ShowBuyTooltip(self, row)
  end)
  row.BuyButton:SetScript("OnLeave", GameTooltip_Hide)

  -- Item tooltip on the icon/name area.
  local hover = CreateFrame("Frame", nil, row)
  hover:SetPoint("TOPLEFT", row, "TOPLEFT")
  hover:SetPoint("BOTTOMRIGHT", row.Need, "BOTTOMLEFT")
  hover:EnableMouse(true)
  hover:SetScript("OnEnter", function(self)
    if row.itemID then
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetItemByID(row.itemID)
      GameTooltip:Show()
    end
  end)
  hover:SetScript("OnLeave", GameTooltip_Hide)
  return row
end

function BuyUI:Create()
  if self.frame then
    return self.frame
  end
  local f = CreateFrame("Frame", "WaylaidCrateScannerBuyWindow", UIParent, "PortraitFrameTemplate")
  f:SetSize(WIDTH, 400)
  f:SetToplevel(true)
  f:SetFrameStrata("HIGH")
  f:SetMovable(true)
  f:SetClampedToScreen(true)
  f:EnableMouse(true)
  if f.SetTitle then
    f:SetTitle("Buy Crate Materials")
  end
  if f.SetPortraitToAsset then
    f:SetPortraitToAsset(ns.ICON)
  end
  if not f.Bg then
    local bg = f:CreateTexture(nil, "BACKGROUND", nil, -8)
    bg:SetPoint("TOPLEFT", 2, -2)
    bg:SetPoint("BOTTOMRIGHT", -2, 2)
    bg:SetColorTexture(0.06, 0.06, 0.06, 0.95)
  end
  f:Hide()
  table.insert(UISpecialFrames, "WaylaidCrateScannerBuyWindow")
  self.frame = f

  local drag = CreateFrame("Frame", nil, f)
  drag:SetPoint("TOPLEFT", f, "TOPLEFT", 60, 0)
  drag:SetPoint("TOPRIGHT", f, "TOPRIGHT", -28, 0)
  drag:SetHeight(22)
  drag:EnableMouse(true)
  drag:RegisterForDrag("LeftButton")
  drag:SetScript("OnDragStart", function()
    f:StartMoving()
  end)
  drag:SetScript("OnDragStop", function()
    f:StopMovingOrSizing()
  end)

  -- Crate + quantity ------------------------------------------------------
  local crateIcon = f:CreateTexture(nil, "ARTWORK")
  crateIcon:SetSize(24, 24)
  crateIcon:SetPoint("TOPLEFT", f, "TOPLEFT", 64, -30)
  self.crateIcon = crateIcon
  local crateName = MakeLabel(f, "GameFontNormal")
  crateName:SetPoint("LEFT", crateIcon, "RIGHT", 6, 0)
  self.crateName = crateName

  local qtyLabel = MakeLabel(f, "GameFontHighlight", "Crates to fill:")
  qtyLabel:SetPoint("TOPLEFT", crateIcon, "BOTTOMLEFT", 0, -10)
  local minus = MakeButton(f, "-", 24, 20)
  minus:SetPoint("LEFT", qtyLabel, "RIGHT", 8, 0)
  local crateBox = MakeNumberBox(f, 40, function(_, value)
    BuyUI.crates = math.max(0, value or 0)
    BuyUI.qtyOverrides = {}
    BuyUI:Refresh()
  end)
  crateBox:SetPoint("LEFT", minus, "RIGHT", 8, 0)
  self.crateBox = crateBox
  local plus = MakeButton(f, "+", 24, 20)
  plus:SetPoint("LEFT", crateBox, "RIGHT", 4, 0)
  minus:SetScript("OnClick", function()
    BuyUI.crates = math.max(1, BuyUI.crates - 1)
    BuyUI.qtyOverrides = {}
    BuyUI:Refresh()
  end)
  plus:SetScript("OnClick", function()
    BuyUI.crates = BuyUI.crates + 1
    BuyUI.qtyOverrides = {}
    BuyUI:Refresh()
  end)

  local includeCrates = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
  includeCrates:SetSize(24, 24)
  includeCrates:SetPoint("LEFT", plus, "RIGHT", 20, 0)
  local includeLabel = MakeLabel(f, "GameFontHighlightSmall", "Also buy the crates")
  includeLabel:SetPoint("LEFT", includeCrates, "RIGHT", 2, 0)
  includeCrates:SetScript("OnClick", function(b)
    BuyUI.includeCrates = b:GetChecked() and true or false
    BuyUI:Refresh()
  end)
  self.includeCrates = includeCrates

  local craft = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
  craft:SetSize(24, 24)
  craft:SetPoint("LEFT", includeLabel, "RIGHT", 16, 0)
  local craftLabel = MakeLabel(f, "GameFontHighlightSmall", "Craft where cheaper")
  craftLabel:SetPoint("LEFT", craft, "RIGHT", 2, 0)
  craft:SetScript("OnClick", function(b)
    BuyUI.craft = b:GetChecked() and true or false
    BuyUI.qtyOverrides = {}
    BuyUI:Refresh()
  end)
  craft:SetScript("OnEnter", function(b)
    GameTooltip:SetOwner(b, "ANCHOR_TOP")
    GameTooltip:SetText("Craft where cheaper")
    GameTooltip:AddLine(
      "On: buy reagents and craft intermediate items wherever that is cheaper than buying them.\nOff: buy the fill materials outright.",
      1,
      1,
      1,
      true
    )
    GameTooltip:Show()
  end)
  craft:SetScript("OnLeave", GameTooltip_Hide)
  self.craftCheck = craft

  -- Options ---------------------------------------------------------------
  local optLabel = MakeLabel(f, "GameFontNormalSmall", "Fill with:")
  optLabel:SetPoint("TOPLEFT", qtyLabel, "BOTTOMLEFT", -50, -16)
  self.optLabel = optLabel
  local optCost = MakeLabel(f, "GameFontNormalSmall", "est. cost per crate")
  optCost:SetPoint("TOPRIGHT", f, "TOPRIGHT", -16, 0)
  optCost:SetPoint("BOTTOM", optLabel, "BOTTOM")
  self.optionRows = {}
  for i = 1, MAX_OPTIONS do
    local row = BuildOptionRow(f, i)
    row:SetPoint("LEFT", f, "LEFT", 14, 0)
    row:SetPoint("RIGHT", f, "RIGHT", -12, 0)
    if i == 1 then
      row:SetPoint("TOP", optLabel, "BOTTOM", 0, -4)
    else
      row:SetPoint("TOP", self.optionRows[i - 1], "BOTTOM", 0, 0)
    end
    self.optionRows[i] = row
  end

  -- Shopping list -------------------------------------------------------
  local header = CreateFrame("Frame", nil, f)
  header:SetHeight(18)
  header:SetPoint("LEFT", f, "LEFT", 10, 0)
  header:SetPoint("RIGHT", f, "RIGHT", -10, 0)
  self.listHeader = header
  local hbg = header:CreateTexture(nil, "BACKGROUND")
  hbg:SetAllPoints()
  hbg:SetColorTexture(0, 0, 0, 0.35)

  self.rows = {}
  for i = 1, MAX_ROWS do
    local row = BuildItemRow(f)
    row:SetPoint("LEFT", f, "LEFT", 10, 0)
    row:SetPoint("RIGHT", f, "RIGHT", -10, 0)
    if i == 1 then
      row:SetPoint("TOP", header, "BOTTOM", 0, -2)
    else
      row:SetPoint("TOP", self.rows[i - 1], "BOTTOM", 0, 0)
    end
    self.rows[i] = row
  end

  -- Header labels aligned with row 1's columns.
  local r1 = self.rows[1]
  local function HeaderOver(region, text, justify)
    local fs = MakeLabel(header, "GameFontNormalSmall", text)
    fs:SetJustifyH(justify or "RIGHT")
    fs:SetPoint("LEFT", region, "LEFT")
    fs:SetPoint("RIGHT", region, "RIGHT")
    fs:SetPoint("TOP", header, "TOP")
    fs:SetPoint("BOTTOM", header, "BOTTOM")
  end
  HeaderOver(r1.Name, "Shopping list", "LEFT")
  HeaderOver(r1.Need, "Need")
  HeaderOver(r1.Have, "Have")
  HeaderOver(r1.Qty, "Buy", "CENTER")
  HeaderOver(r1.Est, "Est. cost")

  local craftText = MakeLabel(f, "GameFontHighlightSmall")
  craftText:SetJustifyH("LEFT")
  craftText:SetPoint("LEFT", f, "LEFT", 16, 0)
  craftText:SetPoint("RIGHT", f, "RIGHT", -16, 0)
  self.craftText = craftText

  local total = MakeLabel(f, "GameFontNormal")
  total:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 16, 12)
  self.totalText = total
  local status = MakeLabel(f, "GameFontHighlightSmall")
  status:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -16, 14)
  status:SetJustifyH("RIGHT")
  self.statusText = status

  -- Expire quotes that the player doesn't confirm in time.
  local elapsed = 0
  f:SetScript("OnUpdate", function(_, dt)
    elapsed = elapsed + dt
    if elapsed < 0.5 then
      return
    end
    elapsed = 0
    local left = Purchase.QuoteSecondsLeft()
    if left then
      if left <= 0 then
        Purchase.Cancel()
        ns.Print("the price quote expired; click Buy again.")
      else
        BuyUI:UpdateRows()
      end
    end
  end)
  f:SetScript("OnHide", function()
    if Purchase.IsBusy() then
      Purchase.Cancel()
    end
  end)
  return f
end

---------------------------------------------------------------------------
-- Open / refresh
---------------------------------------------------------------------------

--- inst: crate instance ({ key, name, itemID, quality, count, options = { {itemID, qty}, ... } })
--- optionItemID: preselect this option (nil = cheapest). fromMarket: default to buying the crates too.
function BuyUI:Open(inst, optionItemID, fromMarket)
  self:Create()
  self.inst = inst
  self.crates = math.max(1, (not fromMarket and inst.count) or 1)
  self.includeCrates = fromMarket and inst.itemID ~= nil
  self.craft = true
  self.qtyOverrides = {}
  self.optionIndex = nil
  for i, opt in ipairs(inst.options) do
    if opt[1] == optionItemID then
      self.optionIndex = i
    end
  end

  local f = self.frame
  if not f:IsShown() then
    f:ClearAllPoints()
    local main = ns.UI.window
    if main and main:IsShown() then
      f:SetPoint("TOPLEFT", main, "TOPLEFT", 120, -40)
    else
      f:SetPoint("CENTER")
    end
  end
  f:Show()
  f:Raise()
  self:Refresh()
end

-- Cheapest option for one crate (used when no option was picked).
local function OptionCosts(inst)
  local costs, best = {}, nil
  for i, opt in ipairs(inst.options) do
    local node = ns.Tree.PriceMaterial(opt[1], opt[2])
    costs[i] = node.best
    if node.best and (not best or node.best < costs[best]) then
      best = i
    end
  end
  return costs, best
end

function BuyUI:Refresh()
  local f = self.frame
  if not (f and f:IsShown() and self.inst) then
    return
  end
  local inst = self.inst

  self.crateIcon:SetTexture((inst.itemID and C_Item.GetItemIconByID(inst.itemID)) or ns.ICON)
  self.crateName:SetText(inst.name)
  if not self.crateBox:HasFocus() then
    self.crateBox:SetText(tostring(self.crates))
  end
  self.includeCrates = self.includeCrates and inst.itemID ~= nil
  self.includeCrates:SetChecked(self.includeCrates)
  self.includeCrates:SetEnabled(inst.itemID ~= nil)
  self.craftCheck:SetChecked(self.craft)

  -- Options
  local costs, cheapest = OptionCosts(inst)
  self.optionIndex = self.optionIndex or cheapest or 1
  for i, row in ipairs(self.optionRows) do
    local opt = inst.options[i]
    if opt then
      row.Radio:SetTexCoord(i == self.optionIndex and 0.25 or 0, i == self.optionIndex and 0.5 or 0.25, 0, 1)
      row.Icon:SetTexture(ns.ItemIcon(opt[1]))
      local label = opt[2] .. " x " .. ns.ItemColorHex(opt[1]) .. ns.ItemName(opt[1]) .. "|r"
      if i == cheapest then
        label = label .. COLOR_GREEN .. "  (cheapest)|r"
      end
      row.Text:SetText(label)
      row.Cost:SetText(costs[i] and ns.FormatMoney(costs[i]) or (COLOR_GREY .. "not priced|r"))
      row:Show()
    else
      row:Hide()
    end
  end

  -- Plan
  local opt = inst.options[self.optionIndex]
  self.plan = Purchase.BuildPlan({
    crates = self.crates,
    optionItemID = opt[1],
    optionQty = opt[2],
    craft = self.craft,
    crateItemID = self.includeCrates and inst.itemID or nil,
  })

  -- Layout: list header below the last visible option.
  local lastOption = self.optionRows[math.min(#inst.options, MAX_OPTIONS)]
  self.listHeader:ClearAllPoints()
  self.listHeader:SetPoint("LEFT", f, "LEFT", 10, 0)
  self.listHeader:SetPoint("RIGHT", f, "RIGHT", -10, 0)
  self.listHeader:SetPoint("TOP", lastOption, "BOTTOM", 0, -12)

  local shopping = self.plan.shopping
  for i, row in ipairs(self.rows) do
    local item = shopping[i]
    row.item = item
    row.itemID = item and item.itemID
    row:SetShown(item ~= nil)
  end
  local shown = math.min(#shopping, MAX_ROWS)
  if #shopping > MAX_ROWS then
    ns.Print("shopping list truncated to " .. MAX_ROWS .. " items.")
  end

  -- Crafting steps
  local lines = {}
  for _, c in ipairs(self.plan.crafts) do
    local spellName = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(c.spell)
    local text = string.format("%dx %s", c.crafts, spellName or ns.ItemName(c.itemID))
    if c.made ~= c.crafts then
      text = text .. string.format(" (makes %d)", c.made)
    end
    table.insert(lines, text)
  end
  self.craftText:ClearAllPoints()
  self.craftText:SetPoint("LEFT", f, "LEFT", 16, 0)
  self.craftText:SetPoint("RIGHT", f, "RIGHT", -16, 0)
  self.craftText:SetPoint("TOP", shown > 0 and self.rows[shown] or self.listHeader, "BOTTOM", 0, -10)
  if #lines > 0 then
    self.craftText:SetText("|cffffd100Then craft, in this order:|r  " .. table.concat(lines, "  >  "))
  else
    self.craftText:SetText(COLOR_GREY .. "No crafting needed." .. "|r")
  end

  self:UpdateRows()

  -- Size the window to its content (positions resolve on the next frame).
  C_Timer.After(0, function()
    local top, bottom = f:GetTop(), self.craftText:GetBottom()
    if top and bottom then
      f:SetHeight(math.max(260, top - bottom + 44))
    end
  end)
end

local function RowQty(row)
  local override = BuyUI.qtyOverrides[row.itemID]
  if override ~= nil then
    return override
  end
  return row.item.toBuy
end

function BuyUI:UpdateRows()
  if not (self.frame and self.frame:IsShown() and self.plan) then
    return
  end
  local pending = Purchase.pending
  local ahOpen = IsAHOpen()
  local total, allPriced = 0, true

  for i, row in ipairs(self.rows) do
    local item = row.item
    if item then
      row.Bg:SetColorTexture(1, 1, 1, i % 2 == 0 and 0.03 or 0)
      row.Icon:SetTexture(ns.ItemIcon(item.itemID))
      local name = ns.ItemColorHex(item.itemID) .. ns.ItemName(item.itemID) .. "|r"
      if item.isCrate then
        name = name .. COLOR_GREY .. "  (crate)|r"
      end
      row.Name:SetText(name)
      row.Need:SetText(item.need)
      row.Have:SetText(item.have > 0 and (COLOR_GREEN .. item.have .. "|r") or (COLOR_GREY .. "0|r"))
      local qty = RowQty(row)
      if not row.Qty:HasFocus() then
        row.Qty:SetText(tostring(qty))
      end

      local cost, status = Prices.BuyCost(item.itemID, qty)
      if qty <= 0 then
        row.Est:SetText(COLOR_GREY .. "—|r")
      elseif cost then
        local note = ""
        if status == Prices.VENDOR then
          note = COLOR_GREY .. " vendor|r"
        elseif status == Prices.PARTIAL then
          note = COLOR_ORANGE .. "*|r"
        end
        row.Est:SetText(ns.FormatMoney(cost) .. note)
        total = total + cost
      else
        allPriced = false
        row.Est:SetText(status == Prices.NONE and (COLOR_RED .. "none listed|r") or (COLOR_GREY .. "not scanned|r"))
      end

      -- Buy button state
      local btn = row.BuyButton
      local mine = pending and pending.itemID == item.itemID
      row.CancelButton:SetShown(mine and pending.state == "quoted" or false)
      if mine and pending.state == "quoting" then
        btn:SetText("Getting price...")
        btn:Disable()
      elseif mine and pending.state == "quoted" then
        local left = Purchase.QuoteSecondsLeft()
        btn:SetText("Confirm " .. ns.FormatMoney(pending.totalPrice) .. (left and string.format(" (%ds)", left) or ""))
        btn:Enable()
      elseif mine and pending.state == "buying" then
        btn:SetText("Buying...")
        btn:Disable()
      else
        btn:SetText("Buy " .. qty)
        btn:SetEnabled(ahOpen and not pending and qty > 0)
      end
    end
  end

  self.totalText:SetText(
    "Estimated total: "
      .. ns.FormatMoney(total)
      .. (allPriced and "" or (COLOR_ORANGE .. "  (some items not priced)|r"))
  )
  if not ahOpen then
    self.statusText:SetText(COLOR_GREY .. "Open the Auction House to buy.|r")
  elseif pending and pending.state == "quoted" then
    self.statusText:SetText(COLOR_GREEN .. "Price received. Click Confirm to buy.|r")
  else
    self.statusText:SetText(COLOR_GREY .. "Buy asks the AH for a price quote, then you confirm.|r")
  end
end

function BuyUI:OnBuyClick(row)
  local pending = Purchase.pending
  if pending and pending.itemID == row.itemID and pending.state == "quoted" then
    Purchase.Confirm()
    return
  end
  Purchase.Start(row.itemID, RowQty(row))
end

function BuyUI:ShowBuyTooltip(button, row)
  if not row.item then
    return
  end
  GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
  local pending = Purchase.pending
  if pending and pending.itemID == row.itemID and pending.state == "quoted" then
    GameTooltip:SetText("Confirm purchase")
    GameTooltip:AddDoubleLine("Quantity", pending.qty, 1, 0.82, 0, 1, 1, 1)
    GameTooltip:AddDoubleLine("Unit price", ns.FormatMoney(pending.unitPrice, true), 1, 0.82, 0, 1, 1, 1)
    GameTooltip:AddDoubleLine("Total", ns.FormatMoney(pending.totalPrice, true), 1, 0.82, 0, 1, 1, 1)
    local est = Prices.BuyCost(row.itemID, pending.qty)
    if est and pending.totalPrice > est * 1.05 then
      GameTooltip:AddLine(
        string.format(
          "%d%% above the scanned estimate (%s).",
          (pending.totalPrice / est - 1) * 100,
          ns.FormatMoney(est)
        ),
        1,
        0.6,
        0.2,
        true
      )
    end
    GameTooltip:AddLine("Click the X to cancel.", 0.6, 0.6, 0.6)
  else
    GameTooltip:SetText("Buy from the Auction House")
    GameTooltip:AddLine(
      "Gets a live price quote for the quantity in the box; you then click Confirm to buy.",
      1,
      1,
      1,
      true
    )
    if ns.VendorPrices[row.itemID] then
      GameTooltip:AddLine(
        "Also sold by trade-supply vendors for " .. ns.FormatMoney(ns.VendorPrices[row.itemID], true) .. " each.",
        0.6,
        0.8,
        1,
        true
      )
    end
  end
  GameTooltip:Show()
end

---------------------------------------------------------------------------
-- Wiring
---------------------------------------------------------------------------
local function Shown()
  return BuyUI.frame and BuyUI.frame:IsShown()
end

ns:Listen("PURCHASE_UPDATED", function(p, result)
  if result == "succeeded" and p and BuyUI.qtyOverrides then
    BuyUI.qtyOverrides[p.itemID] = nil
  end
  if Shown() then
    BuyUI:UpdateRows()
  end
end)

local pending = false
local function QueueRefresh()
  if pending or not Shown() then
    return
  end
  pending = true
  C_Timer.After(0.3, function()
    pending = false
    if Shown() and not Purchase.IsBusy() then
      BuyUI:Refresh()
    end
  end)
end

ns:RegisterEvent("BAG_UPDATE_DELAYED", QueueRefresh)
ns:Listen("PRICES_UPDATED", QueueRefresh)
ns:Listen("ITEM_DATA_UPDATED", QueueRefresh)
ns:RegisterEvent("AUCTION_HOUSE_SHOW", function()
  C_Timer.After(0, function()
    if Shown() then
      BuyUI:UpdateRows()
    end
  end)
end)
ns:RegisterEvent("AUCTION_HOUSE_CLOSED", function()
  C_Timer.After(0, function()
    if Shown() then
      BuyUI:UpdateRows()
    end
  end)
end)
