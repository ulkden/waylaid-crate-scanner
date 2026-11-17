-- Offline test harness: stubs the WoW API and exercises Crates/Prices/Scanner/Tree logic.
-- Usage: luajit tools/test_harness.lua WaylaidCrateScanner
local ADDON = arg[1]
local ns = {}

-- ---- WoW API stubs -------------------------------------------------------
local frames = {}

-- Generic widget stub. Known methods keep simple state (shown, text, checked, scripts) so tests can
-- inspect what the UI rendered; any other method or field is a harmless no-op ("Any").
local Any
Any = setmetatable({}, {
  __index = function()
    return Any
  end,
  __call = function()
    return nil
  end,
})
local Widget = {}
local WidgetMT = {
  -- Capitalized keys are WoW methods or child regions (no-op stand-ins); lowercase keys are the
  -- addon's own fields and stay nil until set, exactly like on a real frame.
  __index = function(_, k)
    if Widget[k] then
      return Widget[k]
    end
    if type(k) == "string" and k:match("^%u") then
      return Any
    end
    return nil
  end,
}
local function NewWidget()
  local w = setmetatable({ events = {}, scripts = {}, shown = true, text = "", checked = false }, WidgetMT)
  table.insert(frames, w)
  return w
end
function Widget:RegisterEvent(e)
  self.events[e] = true
end
function Widget:SetScript(name, fn)
  self.scripts[name] = fn
  if name == "OnEvent" then
    self.onEvent = fn
  end
end
function Widget:Show()
  local was = self.shown
  self.shown = true
  if not was and self.scripts.OnShow then
    self.scripts.OnShow(self)
  end
end
function Widget:Hide()
  local was = self.shown
  self.shown = false
  if was and self.scripts.OnHide then
    self.scripts.OnHide(self)
  end
end
function Widget:SetShown(v)
  if v then
    self:Show()
  else
    self:Hide()
  end
end
function Widget:IsShown()
  return self.shown
end
function Widget:SetText(t)
  self.text = t
end
function Widget:GetText()
  return self.text
end
function Widget:SetChecked(v)
  self.checked = v and true or false
end
function Widget:GetChecked()
  return self.checked
end
function Widget:HasFocus()
  return false
end
function Widget:CreateTexture()
  return NewWidget()
end
function Widget:CreateFontString()
  return NewWidget()
end
function Widget:GetTop()
  return 600
end
function Widget:GetBottom()
  return 100
end
function Widget:GetRight()
  return 800
end
function Widget:GetWidth()
  return 1000
end
function Widget:GetHeight()
  return 600
end
function Widget:GetEffectiveScale()
  return 1
end
function Widget:GetFrameLevel()
  return 1
end
function Widget:GetPoint()
  return "CENTER", nil, "CENTER", 0, 0
end
function Widget:IsObjectType()
  return true
end
-- Scroll lists: render every element through the view's initializer, like the real ScrollBox.
function Widget:SetElementInitializer(_, fn)
  self.initializer = fn
end
function Widget:SetDataProvider(dp)
  self.renderedRows = {}
  local view = self.view
  for _, elementData in ipairs(dp.items) do
    local row = NewWidget()
    if view and view.initializer then
      view.initializer(row, elementData)
    end
    table.insert(self.renderedRows, row)
  end
end

function CreateFrame()
  local w = NewWidget()
  w.shown = true
  return w
end
UIParent = NewWidget()
GameTooltip = NewWidget()
UISpecialFrames = {}
GameTooltip_Hide = function() end
ScrollBoxConstants = { RetainScrollPosition = true }
CreateScrollBoxListLinearView = function()
  return NewWidget()
end
CreateDataProvider = function(items)
  return { items = items or {} }
end
ScrollUtil = {
  InitScrollBoxListWithScrollBar = function(scrollBox, _, view)
    scrollBox.view = view
  end,
}
IsShiftKeyDown = function()
  return false
end
IsControlKeyDown = function()
  return false
end
local function fire(event, ...)
  for _, f in ipairs(frames) do
    if f.events[event] and f.onEvent then
      f.onEvent(f, event, ...)
    end
  end
end
local timers = {}
C_Timer = {
  After = function(_, fn)
    table.insert(timers, fn)
  end,
}
local function runTimers()
  while #timers > 0 do
    table.remove(timers, 1)()
  end
end
time = os.time
GetTime = os.clock
wipe = function(t)
  for k in pairs(t) do
    t[k] = nil
  end
  return t
end
strtrim = function(s)
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end
SlashCmdList = {}
NUM_TOTAL_EQUIPPED_BAG_SLOTS = 5
AuctionHouseFrame = NewWidget() -- shown: the Auction House is open

local names
local bagCounts = {} -- [itemID] = count, for C_Item.GetItemCount
C_Item = {
  GetItemNameByID = function(id)
    return names[id]
  end,
  RequestLoadItemDataByID = function() end,
  GetItemIconByID = function()
    return 1
  end,
  GetItemQualityByID = function()
    return 1
  end,
  GetItemCount = function(id)
    return bagCounts[id] or 0
  end,
}

-- Bag 0: Apprentice Parts, Apprentice Ore, Journeyman Fabrics x2 (two stacks), plus junk.
local bag0 = {
  { itemID = 248704, stackCount = 1 },
  { itemID = 248683, stackCount = 1 },
  { itemID = 248705, stackCount = 2 },
  { itemID = 248705, stackCount = 1 },
  { itemID = 2589, stackCount = 20 },
}
local tooltips = {
  -- tooltip overrides the Copper Ore quantity (data says 20)
  [2] = {
    "Waylaid Crate: Apprentice Ore",
    "Use: Fill the crate with any bundle from the following list:",
    "- 25 Copper Ore",
    "- 20 Tin Ore",
  },
}
C_Container = {
  GetContainerNumSlots = function(bag)
    return bag == 0 and #bag0 or 0
  end,
  GetContainerItemInfo = function(bag, slot)
    return bag == 0 and bag0[slot] or nil
  end,
}
C_TooltipInfo = {
  GetBagItem = function(_, slot)
    local lines = {}
    for i, s in ipairs(tooltips[slot] or {}) do
      lines[i] = { leftText = s }
    end
    return { lines = lines }
  end,
}
local sent = {}
local purchaseCalls = {}
C_AuctionHouse = {
  IsThrottledMessageSystemReady = function()
    return true
  end,
  MakeItemKey = function(id)
    return { itemID = id }
  end,
  SendSearchQuery = function(key)
    table.insert(sent, key.itemID)
  end,
  GetNumCommoditySearchResults = function()
    return 0
  end,
  StartCommoditiesPurchase = function(id, qty)
    table.insert(purchaseCalls, "start:" .. id .. "x" .. qty)
  end,
  ConfirmCommoditiesPurchase = function(id, qty)
    table.insert(purchaseCalls, "confirm:" .. id .. "x" .. qty)
  end,
  CancelCommoditiesPurchase = function()
    table.insert(purchaseCalls, "cancel")
  end,
  GetQuoteDurationRemaining = function()
    return 20
  end,
}
Enum = { AuctionHouseSortOrder = { Price = 0 } }

-- ---- load addon files ----------------------------------------------------
local function load(file)
  local chunk = assert(loadfile(ADDON .. "/" .. file))
  chunk("WaylaidCrateScanner", ns)
end
load("Data.lua")
names = {}
for id, n in pairs(ns.FallbackNames) do
  names[id] = n
end
for _, f in ipairs({
  "Core.lua",
  "Favor.lua",
  "Crates.lua",
  "Prices.lua",
  "Scanner.lua",
  "Tree.lua",
  "Purchase.lua",
  "Widgets.lua",
  "UI.lua",
  "BuyUI.lua",
}) do
  load(f)
end
fire("ADDON_LOADED", "WaylaidCrateScanner")

local failures = 0
local function check(cond, msg)
  print((cond and "PASS " or "FAIL ") .. msg)
  if not cond then
    failures = failures + 1
  end
end

-- ---- prices --------------------------------------------------------------
local P = ns.Prices
P.Store(2840, { { 30, 5 }, { 40, 100 } }) -- Copper Bar
P.Store(2770, { { 10, 200 } }) -- Copper Ore
P.Store(2771, { { 12, 200 } }) -- Tin Ore
P.Store(4359, { { 500, 3 } }) -- Handful of Copper Bolts: only 3 listed
P.Store(4361, {}) -- Copper Tube: none listed
P.Store(4363, { { 2000, 10 } }) -- Copper Modulator
P.Store(2589, { { 5, 500 } }) -- Linen Cloth
P.Store(2997, { { 400, 20 } }) -- Bolt of Woolen Cloth
P.Store(2592, { { 100, 100 } }) -- Wool Cloth (3 per bolt = 300 < 400)
-- crate prices for market mode
P.Store(248683, { { 1000, 2 } }) -- Apprentice Ore crate
P.Store(248704, { { 50, 1 } }) -- Apprentice Parts crate
P.Store(248705, { { 5000, 1 } }) -- Journeyman Fabrics crate
P.Store(248702, {}) -- Apprentice Fabrics: scanned, none listed

-- ---- bags ----------------------------------------------------------------
local crates = ns.ScanBags()
check(#crates == 3, "3 distinct crate types found in bags")
local byKey = {}
for _, c in ipairs(crates) do
  byKey[c.key] = c
end
check(
  byKey["Journeyman Fabrics"] and byKey["Journeyman Fabrics"].count == 3,
  "two Journeyman Fabrics stacks merged (x3)"
)
check(byKey["Apprentice Ore"].options[1][2] == 25, "tooltip quantity overrides data (25 Copper Ore)")
check(byKey["Apprentice Parts"].name == "Waylaid Crate: Apprentice Parts", "crate identified by item ID")

local roots = ns.Tree.Build(crates)
local sum = ns.Tree.Compute(roots)
local rootByKey = {}
for _, r in ipairs(roots) do
  rootByKey[r.inst.key] = r
end
local parts = rootByKey["Apprentice Parts"]
check(parts.buyBest == 8000 and parts.craftBest == 160, "Apprentice Parts: buy-only 8000, crafted 160")
check(
  rootByKey["Apprentice Ore"].best == 240 and rootByKey["Apprentice Ore"].bestChild.itemID == 2771,
  "Apprentice Ore best = 20 Tin Ore (240) beats 25 Copper Ore (250)"
)
check(rootByKey["Apprentice Ore"].craftBest == nil, "raw-material crate has no craft route")
check(sum.best == 240 + 160 + 1800 * 3, "summary multiplies by crate count")

-- ---- market --------------------------------------------------------------
local market = ns.Tree.BuildMarket(true)
ns.Tree.Compute(market)
check(#market == 3, "market lists only crate types with listings (3)")
local mByKey = {}
for _, r in ipairs(market) do
  mByKey[r.inst.key] = r
end
check(
  mByKey["Apprentice Parts"].inst.price == 50 and mByKey["Apprentice Parts"].total == 210,
  "market total = crate price + cheapest fill"
)
check(mByKey["Apprentice Ore"].inst.listed == 2, "market crate listed quantity")

local scanItems = ns.Tree.MarketScanItems()
local nScan, crateIDs = 0, 0
for id in pairs(scanItems) do
  nScan = nScan + 1
  if ns.CrateByItemID[id] then
    crateIDs = crateIDs + 1
  end
end
check(crateIDs == 30, "market scan includes all 30 crate item IDs")
print("     market scan size: " .. nScan .. " items")

-- ---- merchant's favor --------------------------------------------------
check(ns.GetFavor("Apprentice Ore", 1) == 5 and ns.GetFavor("Apprentice Parts", 2) == 10, "apprentice favor 5 / 10")
check(ns.GetFavor("Journeyman Fabrics", 2) == 20, "journeyman uncommon favor 20")
local _, confirmed = ns.GetFavor("Flowering Artisan Herbs", 1)
check(
  ns.GetFavor("Flowering Artisan Herbs", 1) == 20 and confirmed == false,
  "artisan herbs favor 20, flagged unconfirmed"
)
check(byKey["Apprentice Parts"].quality == 2 and byKey["Apprentice Ore"].quality == 1, "crate quality from data")
-- bags: per favor = fill cost / favor (crate already owned)
check(parts.favor == 10 and parts.perFavor == 16, "bag Apprentice Parts: 160 fill / 10 favor = 16 per favor")
check(rootByKey["Apprentice Ore"].perFavor == 48, "bag Apprentice Ore: 240 / 5 = 48 per favor")
check(sum.favor == 5 + 10 + 20 * 3, "summary favor counts crate stacks")
-- market: per favor includes the crate's own price
check(mByKey["Apprentice Parts"].perFavor == 21, "market Apprentice Parts: (50 + 160) / 10 = 21 per favor")
local cheapOpt = mByKey["Apprentice Parts"].bestChild
check(cheapOpt.perFavor == 21, "option row per favor = (crate + this option) / favor")
-- override
ns.SetFavorOverride("artisan common 25")
check(
  ns.GetFavor("Artisan Ore", 1) == 25 and select(2, ns.GetFavor("Artisan Ore", 1)) == true,
  "/wcs favor override applies and counts as confirmed"
)
ns.SetFavorOverride("artisan common clear")
check(ns.GetFavor("Artisan Ore", 1) == 20, "/wcs favor clear restores default")

-- ---- purchase planning --------------------------------------------------
local function byItem(list)
  local t = {}
  for _, e in ipairs(list) do
    t[e.itemID] = e
  end
  return t
end
bagCounts[2589] = 20 -- 20 Linen Cloth already in bags
local plan = ns.Purchase.BuildPlan({ crates = 2, optionItemID = 4363, optionQty = 4, craft = true })
local shop, crafts = byItem(plan.shopping), byItem(plan.crafts)
check(crafts[4363] and crafts[4363].crafts == 8, "plan: craft 8 Copper Modulators for 2 crates")
check(crafts[4359] and crafts[4359].crafts == 16, "plan: craft 16 Handful of Copper Bolts")
check(crafts[2840] and crafts[2840].crafts == 24, "plan: smelt 24 Copper Bars (16 for bolts + 8 for modulators)")
check(plan.crafts[1].itemID == 2840, "plan: craft steps ordered deepest first (bars before bolts)")
check(shop[2770] and shop[2770].toBuy == 24, "plan: buy 24 Copper Ore")
check(
  shop[2589] and shop[2589].need == 16 and shop[2589].have == 16 and shop[2589].toBuy == 0,
  "plan: Linen Cloth covered by bags (need 16, have 16, buy 0)"
)
local buyOnly = ns.Purchase.BuildPlan({ crates = 2, optionItemID = 4363, optionQty = 4, craft = false })
check(
  #buyOnly.shopping == 1 and buyOnly.shopping[1].toBuy == 8 and #buyOnly.crafts == 0,
  "plan without crafting: buy 8 Copper Modulators outright"
)
bagCounts[248704] = 1
local withCrates = ns.Purchase.BuildPlan({
  crates = 3,
  optionItemID = 4363,
  optionQty = 4,
  craft = false,
  crateItemID = 248704,
})
check(withCrates.shopping[1].isCrate and withCrates.shopping[1].toBuy == 2, "plan: crate line first, buys 3 - 1 owned")
bagCounts[248704] = nil

-- ---- purchase state machine ----------------------------------------------
local P2 = ns.Purchase
P.Store(2770, { { 10, 200 } })
P2.Start(2770, 24)
check(
  P2.pending and P2.pending.state == "quoting" and purchaseCalls[#purchaseCalls] == "start:2770x24",
  "purchase: Start asks for a quote"
)
P2.Confirm()
check(purchaseCalls[#purchaseCalls] == "start:2770x24", "purchase: Confirm does nothing before the quote arrives")
fire("COMMODITY_PRICE_UPDATED", 11, 264)
check(P2.pending.state == "quoted" and P2.pending.totalPrice == 264, "purchase: quote received")
P2.Confirm()
check(P2.pending.state == "buying" and purchaseCalls[#purchaseCalls] == "confirm:2770x24", "purchase: Confirm buys")
fire("COMMODITY_PURCHASE_SUCCEEDED")
check(
  P2.pending == nil and P.Listed(2770) == 176,
  "purchase: success clears state and consumes 24 from the cached ladder"
)
P2.Start(2770, 5)
fire("COMMODITY_PRICE_UNAVAILABLE")
check(P2.pending == nil, "purchase: price unavailable ends the purchase")
P2.Start(2770, 5)
fire("COMMODITY_PRICE_UPDATED", 10, 50)
P2.Cancel()
check(P2.pending == nil and purchaseCalls[#purchaseCalls] == "cancel", "purchase: Cancel releases the quote")
runTimers()

-- ---- UI smoke tests (stubbed widgets) ------------------------------------
-- Builds the real windows and renders them, so errors in UI code (nil/boolean indexing, bad
-- arguments to our own functions) fail here instead of silently in game.
local UI, BuyUI = ns.UI, ns.BuyUI
local okUI, errUI = pcall(function()
  ns.db.mode = "bags"
  UI:ShowWindow(false)
  UI:Recompute()
end)
check(okUI, "UI: scanner window builds and renders in My Crates mode" .. (okUI and "" or (": " .. tostring(errUI))))
check(UI.scrollBox.renderedRows and #UI.scrollBox.renderedRows > 0, "UI: My Crates list renders rows")
local okMarket, errMarket = pcall(function()
  UI:SetMode("market")
end)
check(okMarket, "UI: AH Market mode renders" .. (okMarket and "" or (": " .. tostring(errMarket))))
check(#UI.roots == 3, "UI: AH Market shows the 3 listed crate types")

local marketInst
for _, r in ipairs(UI.roots) do
  if r.inst.key == "Apprentice Parts" then
    marketInst = r.inst
  end
end
local okBuy, errBuy = pcall(function()
  BuyUI:Open(marketInst, nil, true)
  runTimers()
end)
check(okBuy, "BuyUI: opens and refreshes" .. (okBuy and "" or (": " .. tostring(errBuy))))
if okBuy then
  check(BuyUI.includeCratesCheck.checked == true, "BuyUI: market default ticks 'Also buy the crates'")
  check(BuyUI.craftCheck.checked == true, "BuyUI: 'Craft where cheaper' on by default")
  check(BuyUI.crateBox.text == "1", "BuyUI: market default is 1 crate")
  local shownOptions = 0
  for _, row in ipairs(BuyUI.optionRows) do
    if row.shown then
      shownOptions = shownOptions + 1
      check(row.Text.text ~= "", "BuyUI: option row " .. row.index .. " has text")
    end
  end
  check(shownOptions == #marketInst.options, "BuyUI: one option row per fill option (" .. shownOptions .. ")")
  local selected = BuyUI.optionRows[BuyUI.optionIndex]
  check(selected and selected.Text.text:find("cheapest", 1, true) ~= nil, "BuyUI: cheapest option preselected")
  local shownRows = 0
  for _, row in ipairs(BuyUI.rows) do
    if row.shown then
      shownRows = shownRows + 1
      check(row.Name.text ~= "" and row.Qty.text ~= "", "BuyUI: shopping row " .. shownRows .. " has name and quantity")
      check(row.BuyButton.text:find("^Buy") ~= nil, "BuyUI: shopping row " .. shownRows .. " has a Buy button")
    end
  end
  check(shownRows == #BuyUI.plan.shopping and shownRows > 0, "BuyUI: only plan rows are shown (" .. shownRows .. ")")
  check(BuyUI.plan.shopping[1].isCrate, "BuyUI: crate line listed first")

  -- Buy -> quote -> Confirm button flow on the first shopping row.
  local row1 = BuyUI.rows[1]
  BuyUI:OnBuyClick(row1)
  check(row1.BuyButton.text == "Getting price...", "BuyUI: Buy click shows 'Getting price...'")
  fire("COMMODITY_PRICE_UPDATED", 55, 55)
  check(row1.BuyButton.text:find("^Confirm") ~= nil, "BuyUI: quote turns the button into Confirm <price>")
  BuyUI:OnBuyClick(row1)
  check(ns.Purchase.pending and ns.Purchase.pending.state == "buying", "BuyUI: Confirm click buys")
  fire("COMMODITY_PURCHASE_SUCCEEDED")
  check(row1.BuyButton.text:find("^Buy") ~= nil, "BuyUI: button resets to Buy after the purchase")
end

-- ---- scanner skip-fresh --------------------------------------------------
ns.Scanner:Start({ [2840] = true, [2771] = true, [99999] = true }, 300)
check(#ns.Scanner.queue == 1 and ns.Scanner.queue[1] == 99999, "scanner skips items priced in the last 5 minutes")
ns.Scanner:Stop()
runTimers()

-- ---- session prices -----------------------------------------------------
P.Store(2770, { { 10, 200 } })
fire("PLAYER_ENTERING_WORLD", false, true)
check(P.Get(2770) ~= nil, "prices survive /reload")
fire("PLAYER_ENTERING_WORLD", true, false)
check(next(ns.db.prices) == nil, "prices are cleared at login")

print(failures == 0 and "ALL PASSED" or (failures .. " FAILED"))
os.exit(failures == 0 and 0 or 1)
