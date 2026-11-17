local _, ns = ...

local Tree, Prices, Scanner = ns.Tree, ns.Prices, ns.Scanner

-- The scanner lives in its own resizable window. The "Crates" tab on the Auction House is just
-- a launcher: selecting it opens the window beside the AH. Scanning works while the AH is open;
-- with the AH closed the window still shows the last scanned prices.

local UI = {}
ns.UI = UI

local ROW_HEIGHT = 20
local INDENT = 16
local RIGHT_PAD = 6
local FRESH_SECONDS = 300 -- Scan skips items priced within this window (Shift-click to force)
local DEFAULT_W, DEFAULT_H = 1100, 600
local MIN_W, MIN_H = 960, 360

local C = ns.COLOR
local COLOR_CRATE, COLOR_GREY, COLOR_DIM, COLOR_RED = C.CRATE, C.GREY, C.DIM, C.RED
local COLOR_ORANGE, COLOR_GREEN, COLOR_CRAFT, COLOR_FAVOR = C.ORANGE, C.GREEN, C.CRAFT, C.FAVOR
local IsAHOpen, MakeButton, SimpleTooltip = ns.IsAHOpen, ns.MakeButton, ns.SimpleTooltip

local PLUS = "Interface\\Buttons\\UI-PlusButton-Up"
local MINUS = "Interface\\Buttons\\UI-MinusButton-Up"

---------------------------------------------------------------------------
-- Text helpers
---------------------------------------------------------------------------
local function Money(copper, color)
  local s = ns.FormatMoney(copper)
  if not s then
    return ""
  end
  return color and (color .. s .. "|r") or s
end

local function FormatAge(seconds)
  if not seconds then
    return nil
  end
  if seconds < 90 then
    return "just now"
  end
  if seconds < 3600 then
    return string.format("%d min ago", seconds / 60)
  end
  if seconds < 86400 then
    return string.format("%.1f h ago", seconds / 3600)
  end
  return string.format("%d days ago", seconds / 86400)
end

local function SavedText(buy, craft)
  if not buy or not craft then
    return ""
  end
  local diff = buy - craft
  if math.abs(diff) < 1 then
    return COLOR_GREY .. "—|r"
  end
  if diff > 0 then
    return COLOR_GREEN .. "+" .. ns.FormatMoney(diff) .. "|r"
  end
  return COLOR_RED .. "-" .. ns.FormatMoney(-diff) .. "|r"
end

local function SavedPercent(buy, craft)
  if not buy or not craft or buy <= 0 then
    return ""
  end
  return string.format(" (%d%%)", math.floor((buy - craft) / buy * 100 + 0.5))
end

-- Material rows ----------------------------------------------------------
-- The cheaper route is shown bright (green on the crate's cheapest option); the other is dimmed.
local function RouteColor(node, isChosen)
  if not isChosen then
    return COLOR_DIM
  end
  if node.isCheapest then
    return COLOR_GREEN
  end
  return nil
end

local function MatUnit(node)
  if node.unit then
    return Money(node.unit)
  end
  if node.buyStatus == Prices.NONE then
    return COLOR_RED .. "none listed|r"
  end
  return COLOR_GREY .. "?|r"
end

local function MatPerCraft(node)
  if not node.children then
    return ""
  end
  local s = node.perCraftCost and Money(node.perCraftCost) or (COLOR_GREY .. "?|r")
  if node.recipe and node.recipe.yield > 1 then
    s = s .. COLOR_GREY .. " /" .. node.recipe.yield .. "|r"
  end
  return s
end

local function MatBuy(node)
  if not node.buyCost then
    if node.buyStatus == Prices.UNKNOWN then
      return COLOR_GREY .. "not scanned|r"
    end
    return COLOR_RED .. "none listed|r"
  end
  local hasCraft = node.craftCost ~= nil
  local s = Money(node.buyCost, RouteColor(node, not hasCraft or node.method == "buy"))
  if node.buyStatus == Prices.PARTIAL then
    s = s .. COLOR_ORANGE .. "*|r"
  end
  return s
end

local function MatCraft(node)
  if not node.children then
    return ""
  end
  if not node.craftCost then
    return COLOR_GREY .. "?|r"
  end
  local color = RouteColor(node, node.method == "craft")
  if node.method == "craft" and not node.isCheapest then
    color = COLOR_CRAFT
  end
  return Money(node.craftCost, color)
end

local function MatSaved(node)
  return SavedText(node.buyCost, node.craftCost)
end

local function MatBest(node)
  if not node.best then
    return MatBuy(node)
  end
  return Money(node.best, node.isCheapest and COLOR_GREEN or nil)
end

-- Gold per favor on a crate's option rows: cost of completing the crate with this option.
local function MatPerFavor(node)
  if not node.perFavor then
    return ""
  end
  return Money(node.perFavor, node.isCheapest and COLOR_GREEN or COLOR_DIM)
end

-- Crate rows -------------------------------------------------------------
-- buyBest = cheapest option bought outright; craftBest = cheapest option crafted yourself.
local function CrateBuy(node)
  if not node.buyBest then
    return COLOR_GREY .. "—|r"
  end
  local craftCheaper = node.craftBest and node.craftBest < node.buyBest - 0.5
  return Money(node.buyBest, craftCheaper and COLOR_DIM or COLOR_GREEN)
end

local function CrateCraft(node)
  if not node.craftBest then
    return COLOR_GREY .. "—|r"
  end
  local craftCheaper = not node.buyBest or node.craftBest < node.buyBest - 0.5
  return Money(node.craftBest, craftCheaper and COLOR_GREEN or COLOR_DIM)
end

local function CrateSaved(node)
  return SavedText(node.buyBest, node.craftBest)
end

local function CratePrice(node)
  if node.price then
    return Money(node.price)
  end
  return COLOR_GREY .. "?|r"
end

local function CrateTotal(node)
  if not node.total then
    return COLOR_GREY .. "?|r"
  end
  return Money(node.total)
end

local function CrateFavor(node)
  if not node.favor then
    return COLOR_GREY .. "?|r"
  end
  if node.favorConfirmed then
    return COLOR_FAVOR .. node.favor .. "|r"
  end
  return COLOR_GREY .. "~|r" .. COLOR_FAVOR .. node.favor .. "|r"
end

local function CratePerFavor(node)
  if not node.perFavor then
    return COLOR_GREY .. "?|r"
  end
  local s = Money(node.perFavor, node.isBestValue and COLOR_GREEN or COLOR_FAVOR)
  if not node.favorConfirmed then
    s = COLOR_GREY .. "~|r" .. s
  end
  return s
end

local function Blank()
  return ""
end

-- Column widths, right to left from the name column. Both modes share them because the row
-- widgets are pooled and reused across modes.
local WIDTHS = { 50, 100, 100, 110, 110, 105, 55, 105 }
local NUM_COLS = #WIDTHS

-- Per-mode columns: header, value for crate rows, value for material rows, sort key.
local COLUMNS = {
  bags = {
    {
      header = "Need",
      crate = Blank,
      mat = function(n)
        return n.need
      end,
    },
    { header = "AH unit", crate = Blank, mat = MatUnit },
    { header = "Per craft", crate = Blank, mat = MatPerCraft },
    { header = "Buy all", sort = "buy", crate = CrateBuy, mat = MatBuy },
    { header = "Craft all", sort = "craft", crate = CrateCraft, mat = MatCraft },
    { header = "Craft saves", crate = CrateSaved, mat = MatSaved },
    { header = "Favor", sort = "favor", crate = CrateFavor, mat = Blank },
    { header = "Gold / favor", sort = "perFavor", crate = CratePerFavor, mat = MatPerFavor },
  },
  market = {
    {
      header = "Qty",
      crate = function(n)
        return n.listed or ""
      end,
      mat = function(n)
        return n.need
      end,
    },
    { header = "Crate / unit", sort = "price", crate = CratePrice, mat = MatUnit },
    { header = "Per craft", crate = Blank, mat = MatPerCraft },
    { header = "Buy fill", sort = "buy", crate = CrateBuy, mat = MatBuy },
    { header = "Craft fill", sort = "craft", crate = CrateCraft, mat = MatCraft },
    { header = "Total", sort = "total", crate = CrateTotal, mat = MatBest },
    { header = "Favor", sort = "favor", crate = CrateFavor, mat = Blank },
    { header = "Gold / favor", sort = "perFavor", crate = CratePerFavor, mat = MatPerFavor },
  },
}
assert(#COLUMNS.bags == NUM_COLS and #COLUMNS.market == NUM_COLS, "every mode needs one column per WIDTHS entry")

-- Sort keys -> the crate-root field they sort by. Missing values always sort last.
local SORTS = {
  name = "key",
  price = "price",
  buy = "buyBest",
  craft = "craftBest",
  total = "total",
  favor = "favor",
  perFavor = "perFavor",
}
local SORT_DESC = { favor = true }

local function Mode()
  return ns.db.mode == "market" and "market" or "bags"
end

local function SortKey()
  local key = ns.db.sort[Mode()] or "perFavor"
  return SORTS[key] and key or "perFavor"
end

local function SortRoots(roots)
  local key = SortKey()
  local field, desc = SORTS[key], SORT_DESC[key]
  table.sort(roots, function(a, b)
    local va, vb = a[field], b[field]
    if va ~= nil and vb ~= nil and va ~= vb then
      if desc then
        return va > vb
      end
      return va < vb
    end
    if va ~= nil and vb == nil then
      return true
    end
    if vb ~= nil and va == nil then
      return false
    end
    return a.key < b.key
  end)
end

---------------------------------------------------------------------------
-- Rows
---------------------------------------------------------------------------
local function BuildRow(button)
  button:SetHeight(ROW_HEIGHT)
  button:RegisterForClicks("LeftButtonUp", "RightButtonUp")

  button.Bg = button:CreateTexture(nil, "BACKGROUND")
  button.Bg:SetAllPoints()
  button.Bg:SetColorTexture(1, 1, 1, 0)

  local hl = button:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints()
  hl:SetColorTexture(1, 1, 1, 0.08)

  button.Toggle = button:CreateTexture(nil, "ARTWORK")
  button.Toggle:SetSize(14, 14)

  button.Icon = button:CreateTexture(nil, "ARTWORK")
  button.Icon:SetSize(16, 16)
  button.Icon:SetPoint("LEFT", button.Toggle, "RIGHT", 3, 0)
  button.Icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

  button.Cols = {}
  local anchor
  for i = NUM_COLS, 1, -1 do
    local fs = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetJustifyH("RIGHT")
    fs:SetWidth(WIDTHS[i])
    if anchor then
      fs:SetPoint("RIGHT", anchor, "LEFT", 0, 0)
    else
      fs:SetPoint("RIGHT", button, "RIGHT", -RIGHT_PAD, 0)
    end
    button.Cols[i] = fs
    anchor = fs
  end

  button.Name = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  button.Name:SetJustifyH("LEFT")
  button.Name:SetWordWrap(false)
  -- "Buy" opens the purchase window for this crate (option rows preselect that option).
  button.BuyButton = CreateFrame("Button", nil, button, "UIPanelButtonTemplate")
  button.BuyButton:SetSize(40, 18)
  button.BuyButton:SetText("Buy")
  button.BuyButton:SetPoint("RIGHT", button.Cols[1], "LEFT", -4, 0)
  button.BuyButton:SetScript("OnClick", function(self)
    UI:OpenBuyWindow(self:GetParent().row)
  end)
  SimpleTooltip(
    button.BuyButton,
    "Buy materials",
    "Open a shopping list for filling this crate, with Buy buttons for each item."
  )

  button.Name:SetPoint("LEFT", button.Icon, "RIGHT", 4, 0)
  button.Name:SetPoint("RIGHT", button.BuyButton, "LEFT", -6, 0)

  button:SetScript("OnClick", function(self, mouseButton)
    UI:OnRowClick(self, mouseButton)
  end)
  button:SetScript("OnEnter", function(self)
    UI:ShowRowTooltip(self)
  end)
  button:SetScript("OnLeave", function()
    GameTooltip:Hide()
  end)
  button.built = true
end

local function InitRow(button, row)
  if not button.built then
    BuildRow(button)
  end
  button.row = row
  local node = row.node
  local hasChildren = node.children ~= nil

  button.Toggle:ClearAllPoints()
  button.Toggle:SetPoint("LEFT", button, "LEFT", 4 + row.depth * INDENT, 0)
  if hasChildren then
    button.Toggle:SetTexture(Tree.IsExpanded(node) and MINUS or PLUS)
    button.Toggle:Show()
  else
    button.Toggle:SetTexture(nil)
    button.Toggle:Hide()
  end

  local columns = COLUMNS[Mode()]
  local isCrate = node.kind == "crate"

  if isCrate then
    local inst = node.inst
    if node.isBestValue then
      button.Bg:SetColorTexture(0.2, 1, 0.2, 0.12)
    else
      button.Bg:SetColorTexture(1, 0.82, 0, 0.10)
    end
    button.Icon:SetTexture(inst.itemID and ns.ItemIcon(inst.itemID) or 132594)
    local label = (ns.QualityHex(inst.quality) or COLOR_CRATE) .. inst.name .. "|r"
    if inst.count > 1 then
      label = label .. "  x" .. inst.count
    end
    button.Name:SetText(label)
  else
    if node.isCheapest then
      button.Bg:SetColorTexture(0.2, 1, 0.2, 0.10)
    elseif row.depth % 2 == 0 then
      button.Bg:SetColorTexture(1, 1, 1, 0.03)
    else
      button.Bg:SetColorTexture(0, 0, 0, 0)
    end
    button.Icon:SetTexture(ns.ItemIcon(node.itemID))
    button.Name:SetText(ns.ItemColorHex(node.itemID) .. ns.ItemName(node.itemID) .. "|r")
  end

  for i, col in ipairs(columns) do
    local fn = isCrate and col.crate or col.mat
    button.Cols[i]:SetText(fn(node) or "")
  end

  -- Buy button on crate rows and their fill-option rows.
  button.BuyButton:SetShown(isCrate or node.crate ~= nil)
end

function UI:OpenBuyWindow(row)
  local node = row and row.node
  if not node then
    return
  end
  local crateNode = node.kind == "crate" and node or node.crate
  if not crateNode then
    return
  end
  ns.BuyUI:Open(crateNode.inst, node.kind ~= "crate" and node.itemID or nil, Mode() == "market")
end

---------------------------------------------------------------------------
-- Interaction + tooltips
---------------------------------------------------------------------------
local function InsertLink(itemID)
  local _, link = C_Item.GetItemInfo(itemID)
  if not link then
    return
  end
  if ChatFrameUtil and ChatFrameUtil.InsertLink then
    ChatFrameUtil.InsertLink(link)
  elseif ChatEdit_InsertLink then
    ChatEdit_InsertLink(link)
  end
end

function UI:OnRowClick(button, mouseButton)
  local node = button.row and button.row.node
  if not node then
    return
  end
  local itemID = node.itemID or (node.inst and node.inst.itemID)
  if IsShiftKeyDown() and itemID then
    InsertLink(itemID)
    return
  end
  if node.children then
    if IsControlKeyDown() or mouseButton == "RightButton" then
      Tree.SetAllExpanded({ node }, not Tree.IsExpanded(node))
    else
      Tree.SetExpanded(node, not Tree.IsExpanded(node))
    end
    self:RefreshList()
  end
end

local function AddMoneyLine(label, copper, r, g, b)
  if copper then
    GameTooltip:AddDoubleLine(label, ns.FormatMoney(copper, true), r or 1, g or 0.82, b or 0, 1, 1, 1)
  end
end

-- "Crafting saves / costs extra" lines. mult scales the totals (crate count); the % stays per unit.
local function AddSavingsLines(buy, craft, mult)
  local diff = buy - craft
  if diff >= 1 then
    GameTooltip:AddDoubleLine(
      "Crafting saves",
      ns.FormatMoney(diff * mult, true) .. SavedPercent(buy, craft),
      0.25,
      1,
      0.25,
      0.25,
      1,
      0.25
    )
  elseif diff <= -1 then
    GameTooltip:AddDoubleLine("Crafting costs extra", ns.FormatMoney(-diff * mult, true), 1, 0.25, 0.25, 1, 0.25, 0.25)
  else
    GameTooltip:AddLine("Buying and crafting cost the same.", 0.8, 0.8, 0.8)
  end
end

function UI:ShowCrateTooltip(node)
  local inst = node.inst
  local count = inst.count
  GameTooltip:SetText(inst.name, 1, 0.82, 0)
  local qualityName = ns.QualityNames[inst.quality or 0]
  if node.favor then
    GameTooltip:AddDoubleLine(
      "Merchant's Favor",
      node.favor .. (node.favorConfirmed and "" or " (unconfirmed)"),
      1,
      0.82,
      0,
      0.9,
      0.8,
      0.5
    )
    if not node.favorConfirmed then
      GameTooltip:AddLine(
        string.format(
          "Estimated. Correct it with /wcs favor %s %s <amount>",
          (ns.CrateTier(inst.key) or "?"):lower(),
          qualityName or "?"
        ),
        0.6,
        0.6,
        0.6,
        true
      )
    end
  end
  if node.price then
    AddMoneyLine("Crate price on AH", node.price)
    if node.listed then
      GameTooltip:AddDoubleLine("Crates listed", node.listed, 1, 0.82, 0, 1, 1, 1)
    end
  end
  GameTooltip:AddLine(" ")
  GameTooltip:AddDoubleLine("Fill with ONE of:", "buy  /  craft", 1, 1, 1, 0.6, 0.6, 0.6)
  for _, child in ipairs(node.children or {}) do
    local right = child.buyCost and ns.FormatMoney(child.buyCost) or "—"
    if child.craftCost then
      right = right .. "  /  " .. ns.FormatMoney(child.craftCost)
    end
    local left = child.optionQty .. " x " .. ns.ItemName(child.itemID)
    if child.isCheapest then
      GameTooltip:AddDoubleLine(left, right, 0.25, 1, 0.25, 0.25, 1, 0.25)
    else
      GameTooltip:AddDoubleLine(left, right, 0.9, 0.9, 0.9, 0.9, 0.9, 0.9)
    end
  end
  GameTooltip:AddLine(" ")
  if node.buyBestChild then
    AddMoneyLine(
      "Cheapest bought: " .. node.buyBestChild.optionQty .. " x " .. ns.ItemName(node.buyBestChild.itemID),
      node.buyBest * count
    )
  end
  if node.craftBestChild then
    AddMoneyLine(
      "Cheapest crafted: " .. node.craftBestChild.optionQty .. " x " .. ns.ItemName(node.craftBestChild.itemID),
      node.craftBest * count
    )
  end
  if node.buyBest and node.craftBest then
    AddSavingsLines(node.buyBest, node.craftBest, count)
  end
  if node.total then
    AddMoneyLine("Total (crate + cheapest fill)", node.total, 0.25, 1, 0.25)
  end
  if node.perFavor then
    AddMoneyLine("Gold per Merchant's Favor", node.perFavor, 0.9, 0.8, 0.5)
  end
  if count > 1 then
    GameTooltip:AddLine("Fill totals are for all " .. count .. " crates; gold/favor is per crate.", 0.6, 0.6, 0.6)
  end
  GameTooltip:AddLine(" ")
  GameTooltip:AddLine("Click to expand/collapse. Right-click: expand/collapse everything below.", 0.5, 0.5, 0.5, true)
end

function UI:ShowMaterialTooltip(node)
  GameTooltip:SetItemByID(node.itemID)
  GameTooltip:AddLine(" ")
  GameTooltip:AddDoubleLine("Needed for crate", node.need, 1, 0.82, 0, 1, 1, 1)
  GameTooltip:AddDoubleLine("In your bags", ns.CountInBags(node.itemID), 1, 0.82, 0, 1, 1, 1)

  local rec = Prices.Get(node.itemID)
  if node.unit then
    AddMoneyLine("Lowest unit price", node.unit)
  end
  if rec then
    GameTooltip:AddDoubleLine("Listed on AH", Prices.Listed(node.itemID), 1, 0.82, 0, 1, 1, 1)
  end
  if node.buyCost then
    local note = ""
    if node.buyStatus == Prices.PARTIAL then
      note = " (not enough listed)"
    end
    if node.buyStatus == Prices.VENDOR then
      note = " (vendor)"
    end
    AddMoneyLine("Buy " .. node.need .. note, node.buyCost)
  elseif node.buyStatus == Prices.NONE then
    GameTooltip:AddDoubleLine("Buy " .. node.need, "none listed", 1, 0.82, 0, 1, 0.25, 0.25)
  end

  if node.recipe then
    local r = node.recipe
    local spellName = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(r.spell)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(
      "Recipe: " .. (spellName or ("spell " .. r.spell)) .. (r.yield > 1 and (" (makes " .. r.yield .. ")") or ""),
      0.4,
      0.8,
      1
    )
    for _, reagent in ipairs(r.reagents) do
      GameTooltip:AddLine("   " .. reagent[2] .. " x " .. ns.ItemName(reagent[1]), 0.9, 0.9, 0.9)
    end
    AddMoneyLine("Cost per craft", node.perCraftCost)
    AddMoneyLine("Craft " .. node.crafts .. "x (" .. node.crafts * r.yield .. " made)", node.craftCost)
    if node.buyCost and node.craftCost then
      AddSavingsLines(node.buyCost, node.craftCost, 1)
    elseif node.method then
      GameTooltip:AddLine(
        node.method == "craft" and "Can only be crafted (none listed)." or "Reagents not priced; buying only.",
        0.8,
        0.8,
        0.8
      )
    end
  end
  if node.perFavor then
    AddMoneyLine("Gold per favor with this option", node.perFavor, 0.9, 0.8, 0.5)
  end
  if rec then
    GameTooltip:AddLine("Price scanned " .. FormatAge(time() - rec.t), 0.5, 0.5, 0.5)
  end
  GameTooltip:AddLine("Shift-click to link.", 0.5, 0.5, 0.5)
end

function UI:ShowRowTooltip(button)
  local node = button.row and button.row.node
  if not node then
    return
  end
  GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
  if node.kind == "crate" then
    self:ShowCrateTooltip(node)
  else
    self:ShowMaterialTooltip(node)
  end
  GameTooltip:Show()
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------
function UI:SaveWindowGeometry()
  local f = self.window
  local point, _, relPoint, x, y = f:GetPoint(1)
  ns.db.window = { point = point, relPoint = relPoint, x = x, y = y, w = f:GetWidth(), h = f:GetHeight() }
end

function UI:PlaceWindow()
  local f, saved = self.window, ns.db.window
  f:ClearAllPoints()
  if saved and saved.point then
    f:SetSize(math.max(MIN_W, saved.w or DEFAULT_W), math.max(MIN_H, saved.h or DEFAULT_H))
    f:SetPoint(saved.point, UIParent, saved.relPoint, saved.x, saved.y)
    return
  end
  f:SetSize(DEFAULT_W, DEFAULT_H)
  -- First open: dock to the right of the Auction House if it fits on screen, else center.
  if IsAHOpen() then
    local scale = AuctionHouseFrame:GetEffectiveScale() / UIParent:GetEffectiveScale()
    local right, top = AuctionHouseFrame:GetRight() * scale, AuctionHouseFrame:GetTop() * scale
    if right + DEFAULT_W + 4 <= UIParent:GetWidth() then
      f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", right + 4, top)
      return
    end
  end
  f:SetPoint("CENTER")
end

function UI:CreateWindow()
  if self.window then
    return self.window
  end

  local f = ns.CreatePanelWindow("WaylaidCrateScannerWindow", "Waylaid Crate Scanner", function()
    UI:SaveWindowGeometry()
  end)
  f:SetResizable(true)
  if f.SetResizeBounds then
    f:SetResizeBounds(MIN_W, MIN_H)
  end
  self.window = f

  -- Resize grip.
  local grip = CreateFrame("Button", nil, f)
  grip:SetSize(16, 16)
  grip:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -4, 4)
  grip:SetFrameLevel(f:GetFrameLevel() + 10)
  grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
  grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
  grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
  grip:SetScript("OnMouseDown", function()
    f:StartSizing("BOTTOMRIGHT")
  end)
  grip:SetScript("OnMouseUp", function()
    f:StopMovingOrSizing()
    UI:SaveWindowGeometry()
  end)

  -- Toolbar ---------------------------------------------------------------
  local bagsMode = MakeButton(f, "My Crates", 96)
  bagsMode:SetPoint("TOPLEFT", f, "TOPLEFT", 64, -30)
  bagsMode:SetScript("OnClick", function()
    UI:SetMode("bags")
  end)
  SimpleTooltip(bagsMode, "My Crates", "Price the Waylaid Crates in your bags.")
  self.bagsModeButton = bagsMode

  local marketMode = MakeButton(f, "AH Market", 96)
  marketMode:SetPoint("LEFT", bagsMode, "RIGHT", 2, 0)
  marketMode:SetScript("OnClick", function()
    UI:SetMode("market")
  end)
  SimpleTooltip(
    marketMode,
    "AH Market",
    "Every Waylaid Crate type listed on the Auction House: the crate's own price, the cost to fill it by buying or crafting, and the gold per Merchant's Favor."
  )
  self.marketModeButton = marketMode

  local scan = MakeButton(f, "Scan Prices", 110)
  scan:SetPoint("LEFT", marketMode, "RIGHT", 10, 0)
  scan:SetScript("OnClick", function()
    UI:ToggleScan(IsShiftKeyDown())
  end)
  SimpleTooltip(scan, "Scan", function()
    if not IsAHOpen() then
      return "Open the Auction House to scan. Until then the window shows the last scanned prices."
    end
    return "Searches the Auction House for every material (and, in AH Market mode, every crate). Items priced in the last 5 minutes are skipped; Shift-click to rescan everything."
  end)
  scan:SetMotionScriptsWhileDisabled(true)
  self.scanButton = scan

  local expand = MakeButton(f, "+", 26)
  expand:SetPoint("LEFT", scan, "RIGHT", 10, 0)
  expand:SetScript("OnClick", function()
    Tree.SetAllExpanded(UI.roots or {}, true)
    UI:RefreshList()
  end)
  SimpleTooltip(expand, "Expand all")

  local collapse = MakeButton(f, "-", 26)
  collapse:SetPoint("LEFT", expand, "RIGHT", 2, 0)
  collapse:SetScript("OnClick", function()
    Tree.SetAllExpanded(UI.roots or {}, false)
    UI:RefreshList()
  end)
  SimpleTooltip(collapse, "Collapse all")

  local vendor = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
  vendor:SetSize(24, 24)
  vendor:SetPoint("LEFT", collapse, "RIGHT", 10, 0)
  local vendorLabel = vendor.Text or vendor.text or vendor:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  vendorLabel:ClearAllPoints()
  vendorLabel:SetPoint("LEFT", vendor, "RIGHT", 2, 0)
  vendorLabel:SetFontObject("GameFontHighlightSmall")
  vendorLabel:SetText("Vendor reagents")
  vendor:SetScript("OnShow", function(b)
    b:SetChecked(ns.db.useVendor)
  end)
  vendor:SetScript("OnClick", function(b)
    ns.db.useVendor = b:GetChecked() and true or false
    UI:Recompute()
  end)
  SimpleTooltip(
    vendor,
    "Vendor reagents",
    "Use vendor prices for Weak Flux, Salt and Coal when cheaper than the Auction House."
  )

  local status = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  status:SetPoint("RIGHT", f, "TOPRIGHT", -14, -41)
  status:SetPoint("LEFT", vendorLabel, "RIGHT", 12, 0)
  status:SetJustifyH("RIGHT")
  status:SetWordWrap(false)
  self.status = status

  -- List ------------------------------------------------------------------
  local inset = CreateFrame("Frame", nil, f, "InsetFrameTemplate")
  inset:SetPoint("TOPLEFT", f, "TOPLEFT", 6, -60)
  inset:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -6, 28)

  local header = CreateFrame("Frame", nil, inset)
  header:SetPoint("TOPLEFT", inset, "TOPLEFT", 4, -4)
  header:SetPoint("TOPRIGHT", inset, "TOPRIGHT", -24, -4)
  header:SetHeight(20)
  local hbg = header:CreateTexture(nil, "BACKGROUND")
  hbg:SetAllPoints()
  hbg:SetColorTexture(0, 0, 0, 0.35)

  local function MakeHeaderButton(justify)
    local h = CreateFrame("Button", nil, header)
    h:SetHeight(20)
    local fs = h:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetAllPoints()
    fs:SetJustifyH(justify)
    h.Text = fs
    local hl = h:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.06)
    h:SetScript("OnClick", function(btn)
      if btn.sortKey then
        ns.db.sort[Mode()] = btn.sortKey
        UI:Resort()
      end
    end)
    -- title/sortKey are set per mode by UpdateHeaders; only sortable headers show a tooltip.
    h:SetScript("OnEnter", function(btn)
      if btn.sortKey then
        GameTooltip:SetOwner(btn, "ANCHOR_TOP")
        GameTooltip:SetText(btn.title)
        GameTooltip:AddLine("Click to sort by this column.", 1, 1, 1, true)
        GameTooltip:Show()
      end
    end)
    h:SetScript("OnLeave", GameTooltip_Hide)
    return h
  end

  self.headers = {}
  local anchor
  for i = NUM_COLS, 1, -1 do
    local h = MakeHeaderButton("RIGHT")
    h:SetWidth(WIDTHS[i])
    if anchor then
      h:SetPoint("RIGHT", anchor, "LEFT", 0, 0)
    else
      h:SetPoint("RIGHT", header, "RIGHT", -RIGHT_PAD, 0)
    end
    self.headers[i] = h
    anchor = h
  end
  local nameHeader = MakeHeaderButton("LEFT")
  nameHeader:SetPoint("LEFT", header, "LEFT", 6, 0)
  nameHeader:SetPoint("RIGHT", anchor, "LEFT", -6, 0)
  nameHeader.sortKey = "name"
  self.nameHeader = nameHeader

  local scrollBox = CreateFrame("Frame", nil, inset, "WowScrollBoxList")
  scrollBox:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -2)
  scrollBox:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", -24, 4)

  local scrollBar = CreateFrame("EventFrame", nil, inset, "MinimalScrollBar")
  scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 6, 0)
  scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 6, 0)

  local view = CreateScrollBoxListLinearView()
  view:SetElementExtent(ROW_HEIGHT)
  view:SetElementInitializer("Button", InitRow)
  ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)
  self.scrollBox = scrollBox

  local empty = inset:CreateFontString(nil, "OVERLAY", "GameFontDisable")
  empty:SetPoint("CENTER", inset, "CENTER", 0, 20)
  empty:SetWidth(560)
  empty:SetJustifyH("CENTER")
  self.empty = empty

  local footer = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  footer:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 14, 9)
  footer:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -26, 9)
  footer:SetJustifyH("LEFT")
  footer:SetWordWrap(false)
  self.footer = footer

  f:SetScript("OnShow", function()
    UI:RefreshCrates()
  end)
  f:SetScript("OnHide", function()
    UI.openedByAH = false
    if UI.tabPanel and UI.tabPanel:IsShown() then
      UI:UpdateTabPanel()
    end
  end)

  self:PlaceWindow()
  return f
end

function UI:ShowWindow(fromAH)
  self:CreateWindow()
  if not self.window:IsShown() then
    self.openedByAH = fromAH and true or false
    self.window:Show()
  end
  self.window:Raise()
  self:UpdateTabPanel()
end

function UI:ToggleWindow()
  if self.window and self.window:IsShown() then
    self.window:Hide()
  else
    self:ShowWindow(false)
  end
end

---------------------------------------------------------------------------
-- Auction House tab: a launcher for the window
---------------------------------------------------------------------------
function UI:CreateTabPanel(parent)
  local panel = CreateFrame("Frame", "WaylaidCrateScannerTabPanel", parent)
  panel:SetPoint("TOPLEFT", parent, "TOPLEFT", 4, -26)
  panel:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -4, 28)

  local text = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  text:SetPoint("CENTER", panel, "CENTER", 0, 10)

  local icon = panel:CreateTexture(nil, "ARTWORK")
  icon:SetSize(64, 64)
  icon:SetTexture(ns.ICON)
  icon:SetPoint("BOTTOM", text, "TOP", 0, 16)
  text:SetWidth(520)
  text:SetJustifyH("CENTER")
  panel.Text = text

  local button = MakeButton(panel, "Open Crate Scanner", 180)
  button:SetPoint("TOP", text, "BOTTOM", 0, -16)
  button:SetScript("OnClick", function()
    UI:ToggleWindow()
  end)
  panel.Button = button

  panel:SetScript("OnShow", function()
    UI:ShowWindow(true)
    UI:UpdateTabPanel()
  end)
  self.tabPanel = panel
  return panel
end

function UI:UpdateTabPanel()
  local panel = self.tabPanel
  if not panel then
    return
  end
  local open = self.window and self.window:IsShown()
  panel.Text:SetText(
    open
        and "The Waylaid Crate Scanner window is open.\n\nYou can keep it open while you use the Buy tab;\nscans run as long as the Auction House is open."
      or "Waylaid Crate Scanner\n\nPrices every way to fill Waylaid Crates and finds the\ncheapest gold per Merchant's Favor."
  )
  panel.Button:SetText(open and "Close Crate Scanner" or "Open Crate Scanner")
end

---------------------------------------------------------------------------
-- Data refresh
---------------------------------------------------------------------------
function UI:SetMode(mode)
  if ns.db.mode == mode then
    return
  end
  ns.db.mode = mode
  if mode == "bags" then
    self:RefreshCrates()
  else
    self:Recompute()
  end
end

-- Header labels, active sort and mode buttons: they change only with the mode or the sort.
function UI:UpdateHeaders()
  local mode = Mode()
  local active = SortKey()
  for i, col in ipairs(COLUMNS[mode]) do
    local h = self.headers[i]
    h.sortKey, h.title = col.sort, col.header
    h.Text:SetText((col.sort and col.sort == active) and (COLOR_GREEN .. col.header .. "|r") or col.header)
  end
  local nameText = mode == "market" and "Crate type / material" or "Crate / material"
  self.nameHeader.title = nameText
  self.nameHeader.Text:SetText(active == "name" and (COLOR_GREEN .. nameText .. "|r") or nameText)

  if mode == "market" then
    self.marketModeButton:LockHighlight()
    self.bagsModeButton:UnlockHighlight()
  else
    self.bagsModeButton:LockHighlight()
    self.marketModeButton:UnlockHighlight()
  end
end

-- The Scan button follows the scanner and whether the AH is open.
function UI:UpdateScanButton()
  if Scanner:IsRunning() then
    self.scanButton:SetText("Stop")
    self.scanButton:Enable()
  else
    self.scanButton:SetText(Mode() == "market" and "Scan Market" or "Scan Prices")
    self.scanButton:SetEnabled(IsAHOpen())
  end
end

--- Rescans your bags and rebuilds their trees (My Crates mode), then reprices.
function UI:RefreshCrates()
  if not self.window then
    return
  end
  if Mode() == "bags" then
    self.bagRoots = Tree.Build(ns.ScanBags())
    self.bagItems = Tree.CollectItems(self.bagRoots)
  end
  self:Recompute()
end

--- Reprices the current trees (their shape is reused; only costs change) and redraws.
function UI:Recompute()
  if not self.window then
    return
  end
  if Mode() == "market" then
    self.roots = Tree.Market(true)
  else
    self.roots = self.bagRoots or {}
  end
  self.summary = Tree.Compute(self.roots)
  self:Resort()
  self:UpdateFooter()
  self:UpdateStatus()
end

--- Re-sorts and redraws without repricing (sort header clicks).
function UI:Resort()
  SortRoots(self.roots)
  self:UpdateHeaders()
  self:RefreshList()
end

function UI:RefreshList()
  if not self.scrollBox then
    return
  end
  local rows = Tree.Flatten(self.roots or {})
  self.scrollBox:SetDataProvider(CreateDataProvider(rows), ScrollBoxConstants.RetainScrollPosition)

  if #rows > 0 then
    self.empty:Hide()
    return
  end
  local text
  if Mode() == "market" then
    local anyScanned = false
    for _, def in pairs(ns.Crates) do
      if def.itemID and Prices.Get(def.itemID) then
        anyScanned = true
        break
      end
    end
    if anyScanned then
      text = "No Waylaid Crates are listed on the Auction House right now."
    else
      text =
        "Click Scan Market (with the Auction House open) to price every Waylaid Crate\nand all of their materials. It takes about 2 minutes."
    end
  else
    text =
      "No Waylaid Crates in your bags.\n\nSwitch to AH Market to compare every crate type listed on the Auction House."
  end
  self.empty:SetText(text)
  self.empty:Show()
end

-- Status line (scan progress or price age) and the Scan button.
function UI:UpdateStatus()
  if not self.window then
    return
  end
  local mode = Mode()

  if Scanner:IsRunning() then
    local i, n, itemID = Scanner:Progress()
    if Scanner.rateLimitedUntil then
      self.status:SetText(
        string.format(
          "%sAH search limit, resuming in %ds|r (%d/%d)",
          COLOR_ORANGE,
          math.max(0, math.ceil(Scanner.rateLimitedUntil - GetTime())),
          i,
          n
        )
      )
    else
      self.status:SetText(string.format("Scanning %d/%d: %s", i, n, itemID and ns.ItemName(itemID) or ""))
    end
  else
    local items = mode == "market" and Tree.MarketScanItems() or self.bagItems or {}
    local age = FormatAge(Prices.OldestAge(items))
    local s
    if mode == "bags" and not next(items) then
      s = ""
    elseif age then
      s = COLOR_GREY .. "Prices from " .. age .. "|r"
    else
      s = COLOR_ORANGE .. "Not all prices scanned yet|r"
    end
    if not IsAHOpen() then
      s = s .. (s ~= "" and "  " or "") .. COLOR_GREY .. "(open the Auction House to scan)|r"
    end
    self.status:SetText(s)
  end
  self:UpdateScanButton()
end

-- Footer totals and best value: they change only when prices are recomputed.
function UI:UpdateFooter()
  local roots = self.roots
  local sum = self.summary
  local best = sum.bestValue
  local bestText = ""
  if best then
    bestText = "   Best value: "
      .. COLOR_GREEN
      .. best.inst.key
      .. "|r "
      .. ns.FormatMoney(best.perFavor)
      .. " per favor"
      .. (best.favorConfirmed and "" or COLOR_GREY .. " (est.)|r")
  end

  if Mode() == "market" then
    self.footer:SetText(
      #roots > 0 and (#roots .. " crate type" .. (#roots == 1 and "" or "s") .. " listed" .. bestText) or ""
    )
    return
  end

  local numCrates = sum.crates
  if numCrates == 0 then
    self.footer:SetText("")
    return
  end
  local s = numCrates .. " crate" .. (numCrates == 1 and "" or "s") .. "   Buy only: "
  s = s .. (sum.buyOnly > 0 and ns.FormatMoney(sum.buyOnly) or "?")
  if not sum.allBuyPriced then
    s = s .. COLOR_ORANGE .. "*|r"
  end
  s = s .. "   With crafting: " .. (sum.best > 0 and ns.FormatMoney(sum.best) or "?")
  if not sum.allPriced then
    s = s .. COLOR_ORANGE .. "*|r"
  end
  if sum.allPriced and sum.allBuyPriced and sum.buyOnly - sum.best >= 1 then
    s = s .. "  " .. COLOR_GREEN .. "(saves " .. ns.FormatMoney(sum.buyOnly - sum.best) .. ")|r"
  end
  if (sum.favor or 0) > 0 then
    s = s .. "   " .. COLOR_FAVOR .. sum.favor .. " favor|r"
    if sum.allPriced and sum.best > 0 then
      s = s .. " @ " .. ns.FormatMoney(sum.best / sum.favor) .. " each"
    end
  end
  self.footer:SetText(s .. bestText)
end

function UI:ToggleScan(force)
  if Scanner:IsRunning() then
    Scanner:Stop("cancelled")
    return
  end
  local items
  if Mode() == "market" then
    items = Tree.MarketScanItems()
  else
    self:RefreshCrates()
    items = self.bagItems
    if not next(items) then
      ns.Print("no Waylaid Crates in your bags — nothing to scan. Try AH Market mode.")
      return
    end
  end
  Scanner:Start(items, (not force) and FRESH_SECONDS or nil)
end

---------------------------------------------------------------------------
-- Wiring
---------------------------------------------------------------------------
local function WindowShown()
  return UI.window and UI.window:IsShown()
end

local QueueRecompute = ns.Debounce(0.25, function()
  if WindowShown() then
    UI:Recompute()
  end
end)

-- While the scanner waits out the AH search limit, tick the countdown once a second.
local countdownTicking = false
local function TickCountdown()
  if not (WindowShown() and Scanner:IsRunning() and Scanner.rateLimitedUntil) then
    countdownTicking = false
    return
  end
  UI:UpdateStatus()
  C_Timer.After(1, TickCountdown)
end

ns:Listen("SCAN_STARTED", function()
  if WindowShown() then
    UI:UpdateStatus()
  end
end)
ns:Listen("SCAN_PROGRESS", function()
  if not WindowShown() then
    return
  end
  UI:UpdateStatus()
  if Scanner.rateLimitedUntil and not countdownTicking then
    countdownTicking = true
    C_Timer.After(1, TickCountdown)
  end
end)
ns:Listen("PRICES_UPDATED", QueueRecompute)
-- New item data only changes names and icons: redraw the rows, no repricing.
ns:Listen(
  "ITEM_DATA_UPDATED",
  ns.Debounce(0.25, function()
    if WindowShown() then
      UI:RefreshList()
    end
  end)
)
ns:Listen("SCAN_FINISHED", function(reason)
  if reason == "done" then
    ns.Print("price scan complete.")
  end
  if WindowShown() then
    UI:Recompute()
  end
end)

ns:RegisterEvent(
  "BAG_UPDATE_DELAYED",
  ns.Debounce(0.3, function()
    if Mode() == "bags" and WindowShown() then
      UI:RefreshCrates()
    end
  end)
)

ns:RegisterEvent("AUCTION_HOUSE_SHOW", function()
  C_Timer.After(0, function()
    if WindowShown() then
      UI:UpdateStatus()
    end
  end)
end)

ns:RegisterEvent("AUCTION_HOUSE_CLOSED", function()
  C_Timer.After(0, function()
    if not WindowShown() then
      return
    end
    -- Close with the AH only if the AH tab opened it; a /wcs-opened window stays.
    if UI.openedByAH then
      UI.window:Hide()
    else
      UI:UpdateStatus()
    end
  end)
end)

local function CreateTab()
  if UI.tabCreated or not AuctionHouseFrame then
    return
  end
  local LibAHTab = LibStub("LibAHTab-1-0", true)
  if not LibAHTab then
    ns.Print("LibAHTab missing — cannot add the Auction House tab. Use /wcs to open the window.")
    return
  end
  if LibAHTab:DoesIDExist(ns.TAB_ID) then
    UI.tabCreated = true
    return
  end
  LibAHTab:CreateTab(ns.TAB_ID, UI:CreateTabPanel(AuctionHouseFrame), "Crates", "Waylaid Crate Scanner")
  UI.tabCreated = true
end

ns:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", function(_, interactionType)
  if interactionType == Enum.PlayerInteractionType.Auctioneer then
    CreateTab()
  end
end)

ns:RegisterEvent("ADDON_LOADED", function(_, name)
  if name == "Blizzard_AuctionHouseUI" then
    C_Timer.After(0, CreateTab)
  end
end)
