local _, ns = ...

-- Shopping-list planning and Auction House commodity purchasing.
--
-- Plan: for N crates filled with one option, walk the recipe tree. Use what is already in your bags
-- first, then buy or craft the rest (craft only where it is cheaper, if crafting is enabled).
--
-- Purchase: Blizzard's two-step commodity flow. Both steps must come from a mouse click:
--   1. Start(itemID, qty)  -> C_AuctionHouse.StartCommoditiesPurchase -> server quotes the real price
--   2. Confirm()           -> C_AuctionHouse.ConfirmCommoditiesPurchase (only after the quote arrives)

local Purchase = {}
ns.Purchase = Purchase

local MAX_PLAN_DEPTH = 10
local QUOTE_TIMEOUT = 10 -- seconds to wait for the server's price quote
local BUY_TIMEOUT = 15 -- seconds to wait for the result of a confirmed purchase

---------------------------------------------------------------------------
-- Purchases waiting in the mailbox
---------------------------------------------------------------------------
-- AH purchases arrive by mail, not in your bags, so the planner would otherwise offer to buy
-- them again. Each purchase adds to ns.charDB.inMail; whenever your bags gain that item, the
-- gain is taken as mail being collected and comes off the mail count. (Crafting with it only
-- shrinks your bags, so it doesn't touch the mail count.)

--- Units of itemID bought on the AH and not yet collected from the mailbox.
function Purchase.InMail(itemID)
  return ns.charDB.inMail[itemID] or 0
end

local function AddToMail(itemID, qty)
  local inMail = ns.charDB.inMail
  if not inMail[itemID] then
    ns.charDB.lastBags[itemID] = ns.CountInBags(itemID)
  end
  inMail[itemID] = (inMail[itemID] or 0) + qty
end

ns:RegisterEvent("BAG_UPDATE_DELAYED", function()
  local inMail, lastBags = ns.charDB.inMail, ns.charDB.lastBags
  for itemID, qty in pairs(inMail) do
    local bags = ns.CountInBags(itemID)
    local arrived = bags - (lastBags[itemID] or bags)
    if arrived > 0 then
      qty = qty - arrived
    end
    if qty > 0 then
      inMail[itemID], lastBags[itemID] = qty, bags
    else
      inMail[itemID], lastBags[itemID] = nil, nil
    end
  end
end)

---------------------------------------------------------------------------
-- Planning
---------------------------------------------------------------------------

--- opts = { crates = n, optionItemID = id, optionQty = qty per crate, craft = bool,
---         crateItemID = id or nil (include the crate itself in the list) }
--- Returns {
---   shopping = { { itemID, need, have, toBuy, isCrate }, ... }   (sorted: crate first, then by name)
---   crafts   = { { itemID, crafts, made, fromBags, depth, spell }, ... } (deepest first = craft order)
--- }
function Purchase.BuildPlan(opts)
  local available = {}
  local function take(itemID, qty)
    if available[itemID] == nil then
      available[itemID] = ns.CountInBags(itemID) + Purchase.InMail(itemID)
    end
    local used = math.min(available[itemID], qty)
    available[itemID] = available[itemID] - used
    return qty - used, used
  end

  local shoppingByID, shopping = {}, {}
  local craftsByID, crafts = {}, {}

  local function addShopping(itemID, need, have, isCrate)
    local s = shoppingByID[itemID]
    if not s then
      s = { itemID = itemID, name = ns.ItemName(itemID), need = 0, have = 0, isCrate = isCrate }
      shoppingByID[itemID] = s
      table.insert(shopping, s)
    end
    s.need = s.need + need
    s.have = s.have + have
  end

  local function visit(itemID, qty, depth)
    if qty <= 0 then
      return
    end
    local remaining, used = take(itemID, qty)
    local node = remaining > 0 and ns.Tree.PriceMaterial(itemID, remaining) or nil
    local craft = node and opts.craft and node.recipe and node.method == "craft" and depth < MAX_PLAN_DEPTH
    if not craft then
      addShopping(itemID, qty, used)
      return
    end
    local c = craftsByID[itemID]
    if not c then
      c = { itemID = itemID, name = ns.ItemName(itemID), crafts = 0, made = 0, fromBags = 0, depth = depth }
      c.spell = node.recipe.spell
      craftsByID[itemID] = c
      table.insert(crafts, c)
    end
    local n = math.ceil(remaining / node.recipe.yield)
    c.crafts = c.crafts + n
    c.made = c.made + n * node.recipe.yield
    c.fromBags = c.fromBags + used
    c.depth = math.max(c.depth, depth)
    for _, reagent in ipairs(node.recipe.reagents) do
      visit(reagent[1], n * reagent[2], depth + 1)
    end
  end

  local crates = math.max(0, math.floor(opts.crates or 0))
  if opts.crateItemID and crates > 0 then
    local _, used = take(opts.crateItemID, crates)
    addShopping(opts.crateItemID, crates, used, true)
  end
  visit(opts.optionItemID, opts.optionQty * crates, 0)

  for _, s in ipairs(shopping) do
    s.toBuy = math.max(0, s.need - s.have)
  end
  table.sort(shopping, function(a, b)
    if a.isCrate ~= b.isCrate then
      return a.isCrate and true or false
    end
    return a.name < b.name
  end)
  table.sort(crafts, function(a, b)
    if a.depth ~= b.depth then
      return a.depth > b.depth
    end
    return a.name < b.name
  end)
  return { shopping = shopping, crafts = crafts }
end

---------------------------------------------------------------------------
-- Purchasing (one purchase at a time, like Blizzard's buy dialog)
---------------------------------------------------------------------------
-- Purchase.pending = { itemID, qty, state = "quoting" | "quoted" | "buying", unitPrice, totalPrice }
--
-- The COMMODITY_* events don't say which item they are about, so a purchase made at the same
-- moment through Blizzard's Buy tab (or another addon) can be mistaken for ours.

-- A confirmed purchase whose result never arrived (it timed out, or the AH closed). If the
-- server reports success afterwards, it is still recorded so the shopping list counts it.
local unresolved

function Purchase.IsBusy()
  return Purchase.pending ~= nil
end

local function Finish(result, message)
  local p = Purchase.pending
  Purchase.pending = nil
  if message then
    ns.Print(message)
  end
  ns:Fire("PURCHASE_UPDATED", p, result)
end

--- Step 1 (call from a button click): ask the server for a price quote.
function Purchase.Start(itemID, qty)
  if Purchase.pending then
    ns.Print("finish or cancel the current purchase first.")
    return
  end
  if not ns.IsAHOpen() then
    ns.Print("open the Auction House to buy.")
    return
  end
  qty = math.floor(tonumber(qty) or 0)
  if qty <= 0 then
    return
  end
  unresolved = nil -- a late result from now on belongs to this purchase
  Purchase.pending = { itemID = itemID, qty = qty, state = "quoting" }
  C_AuctionHouse.StartCommoditiesPurchase(itemID, qty)
  ns:Fire("PURCHASE_UPDATED", Purchase.pending)

  local pending = Purchase.pending
  C_Timer.After(QUOTE_TIMEOUT, function()
    if Purchase.pending == pending and pending.state == "quoting" then
      C_AuctionHouse.CancelCommoditiesPurchase()
      Finish("failed", "no price quote from the Auction House; try again.")
    end
  end)
end

--- Seconds left on the current quote (nil if none).
function Purchase.QuoteSecondsLeft()
  local p = Purchase.pending
  if p and p.state == "quoted" and C_AuctionHouse.GetQuoteDurationRemaining then
    return C_AuctionHouse.GetQuoteDurationRemaining()
  end
end

--- Cancels a quote. A confirmed purchase ("buying") can't be cancelled; its result is awaited.
function Purchase.Cancel()
  local p = Purchase.pending
  if not p or p.state == "buying" then
    return
  end
  C_AuctionHouse.CancelCommoditiesPurchase()
  Finish("cancelled")
end

-- Cancels the quote if it has run out. Returns true if it had.
local function ExpireQuote()
  local left = Purchase.QuoteSecondsLeft()
  if left and left <= 0 then
    Purchase.Cancel()
    ns.Print("the price quote expired; click Buy again.")
    return true
  end
end

--- Step 2 (call from a button click): buy at the quoted price.
function Purchase.Confirm()
  local p = Purchase.pending
  if not p or p.state ~= "quoted" or ExpireQuote() then
    return
  end
  p.state = "buying"
  C_AuctionHouse.ConfirmCommoditiesPurchase(p.itemID, p.qty)
  ns:Fire("PURCHASE_UPDATED", p)
  C_Timer.After(BUY_TIMEOUT, function()
    if Purchase.pending == p and p.state == "buying" then
      unresolved = p
      Finish("failed", "no answer from the Auction House; check your mailbox before buying again.")
    end
  end)
end

-- While a quote is open, tick twice a second: update the countdown and expire the quote on time.
local function WatchQuote(p)
  C_Timer.After(0.5, function()
    if Purchase.pending ~= p or p.state ~= "quoted" or ExpireQuote() then
      return
    end
    ns:Fire("PURCHASE_UPDATED", p)
    WatchQuote(p)
  end)
end

ns:RegisterEvent("COMMODITY_PRICE_UPDATED", function(_, unitPrice, totalPrice)
  local p = Purchase.pending
  if p and p.state == "quoting" then
    p.state = "quoted"
    p.unitPrice, p.totalPrice = unitPrice, totalPrice
    ns:Fire("PURCHASE_UPDATED", p)
    WatchQuote(p)
  end
end)

ns:RegisterEvent("COMMODITY_PRICE_UNAVAILABLE", function()
  if Purchase.pending then
    local name = ns.ItemName(Purchase.pending.itemID)
    Finish("failed", "not enough " .. name .. " listed at a buyable price (or it isn't a stackable commodity).")
  end
end)

local function RecordPurchase(p)
  ns.Print(string.format("bought %d x %s for %s.", p.qty, ns.ItemName(p.itemID), ns.FormatMoney(p.totalPrice, true)))
  -- Those listings are gone now: remove them from the cached price ladder.
  ns.Prices.Consume(p.itemID, p.qty)
  AddToMail(p.itemID, p.qty)
end

ns:RegisterEvent("COMMODITY_PURCHASE_SUCCEEDED", function()
  local p = Purchase.pending
  if p and p.state == "buying" then
    RecordPurchase(p)
    Finish("succeeded")
  elseif unresolved then
    p, unresolved = unresolved, nil
    RecordPurchase(p)
    ns:Fire("PURCHASE_UPDATED", p, "succeeded")
  end
end)

ns:RegisterEvent("COMMODITY_PURCHASE_FAILED", function()
  unresolved = nil
  if Purchase.pending then
    Finish("failed", "purchase failed (prices may have changed); click Buy to get a new quote.")
  end
end)

ns:RegisterEvent("AUCTION_HOUSE_CLOSED", function()
  local p = Purchase.pending
  if p then
    if p.state == "buying" then
      unresolved = p
    end
    Purchase.pending = nil
    ns:Fire("PURCHASE_UPDATED", nil, "cancelled")
  end
end)
