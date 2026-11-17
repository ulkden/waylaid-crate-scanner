local _, ns = ...

-- Sequential Auction House price scanner. For each item it sends one search query
-- (by item ID, like Blizzard's own UI) and records every listing's unit price and
-- quantity, so the cost of buying N units can be computed exactly.

local Scanner = {
  queue = {},
  index = 0,
  current = nil,
  running = false,
  token = 0,
}
ns.Scanner = Scanner

local RESULT_TIMEOUT = 8 -- seconds to wait for a search result before giving up on an item
local THROTTLE_POLL = 0.5

local SORTS = {
  { sortOrder = Enum.AuctionHouseSortOrder.Price, reverseSort = false },
}

function Scanner:IsRunning()
  return self.running
end

function Scanner:Progress()
  return self.index, #self.queue, self.current
end

--- itemSet: { [itemID] = true }
--- maxAge: items whose price is younger than this many seconds are skipped (nil = scan everything)
function Scanner:Start(itemSet, maxAge)
  if not ns.IsAHOpen() then
    ns.Print("open the Auction House to scan.")
    return
  end
  wipe(self.queue)
  local skipped, now = 0, time()
  for itemID in pairs(itemSet) do
    local rec = ns.Prices.Get(itemID)
    if maxAge and rec and (now - rec.t) < maxAge then
      skipped = skipped + 1
    else
      table.insert(self.queue, itemID)
    end
  end
  table.sort(self.queue)
  self.index = 0
  self.skipped = skipped
  self.running = true
  self.token = self.token + 1
  if skipped > 0 then
    ns.Print(
      string.format(
        "skipping %d item(s) priced in the last %d min (Shift-click Scan to rescan everything).",
        skipped,
        math.floor(maxAge / 60)
      )
    )
  end
  ns:Fire("SCAN_STARTED", #self.queue)
  self:Next()
end

-- Blizzard allows 100 search queries per minute; stay a little under it.
local MAX_PER_MINUTE = 90
local sendTimes = {}

local function RateLimitDelay()
  local now = GetTime()
  while sendTimes[1] and now - sendTimes[1] >= 60 do
    table.remove(sendTimes, 1)
  end
  if #sendTimes < MAX_PER_MINUTE then
    return 0
  end
  return 60 - (now - sendTimes[1]) + 0.1
end

function Scanner:Stop(reason)
  if not self.running then
    return
  end
  self.running = false
  self.current = nil
  self.token = self.token + 1
  ns:Fire("SCAN_FINISHED", reason)
end

function Scanner:Next()
  if not self.running then
    return
  end
  if not ns.IsAHOpen() then
    self:Stop("closed")
    return
  end
  self.index = self.index + 1
  local itemID = self.queue[self.index]
  if not itemID then
    self.current = nil
    self.running = false
    ns:Fire("SCAN_FINISHED", "done")
    return
  end
  self.current = itemID
  ns:Fire("SCAN_PROGRESS", self.index, #self.queue, itemID)
  self:Send()
end

function Scanner:Send()
  if not self.running or not self.current then
    return
  end
  if not C_AuctionHouse.IsThrottledMessageSystemReady() then
    self.waitingForThrottle = true
    local token = self.token
    C_Timer.After(THROTTLE_POLL, function()
      if token == self.token and self.waitingForThrottle then
        self.waitingForThrottle = false
        self:Send()
      end
    end)
    return
  end
  self.waitingForThrottle = false

  local delay = RateLimitDelay()
  if delay > 0 then
    self.rateLimitedUntil = GetTime() + delay
    ns:Fire("SCAN_PROGRESS", self.index, #self.queue, self.current)
    local token = self.token
    C_Timer.After(delay, function()
      if token == self.token then
        self.rateLimitedUntil = nil
        self:Send()
      end
    end)
    return
  end

  local itemID = self.current
  ns.Debug("searching", itemID, ns.ItemName(itemID))
  table.insert(sendTimes, GetTime())
  C_AuctionHouse.SendSearchQuery(C_AuctionHouse.MakeItemKey(itemID), SORTS, false)

  local token = self.token
  local idx = self.index
  C_Timer.After(RESULT_TIMEOUT, function()
    if token == self.token and self.running and self.index == idx and self.current == itemID then
      ns.Debug("timeout for", itemID, "- treating as no listings")
      ns.Prices.Store(itemID, {})
      self:Next()
    end
  end)
end

function Scanner:Finish(itemID, ladder)
  self.current = nil -- ignore any duplicate result events for this item
  ns.Prices.Store(itemID, ladder)
  ns:Fire("PRICES_UPDATED", itemID)
  -- Tiny delay keeps us well under the 100 searches/minute limit.
  local token = self.token
  C_Timer.After(0.05, function()
    if token == self.token then
      self:Next()
    end
  end)
end

ns:RegisterEvent("AUCTION_HOUSE_THROTTLED_SYSTEM_READY", function()
  if Scanner.waitingForThrottle then
    Scanner.waitingForThrottle = false
    Scanner:Send()
  end
end)

ns:RegisterEvent("COMMODITY_SEARCH_RESULTS_UPDATED", function(_, itemID)
  if not Scanner.running or itemID ~= Scanner.current then
    return
  end
  local ladder = {}
  local n = C_AuctionHouse.GetNumCommoditySearchResults(itemID) or 0
  for i = 1, n do
    local r = C_AuctionHouse.GetCommoditySearchResultInfo(itemID, i)
    if r and r.unitPrice and r.quantity and r.quantity > 0 then
      table.insert(ladder, { r.unitPrice, r.quantity })
    end
  end
  Scanner:Finish(itemID, ladder)
end)

ns:RegisterEvent("ITEM_SEARCH_RESULTS_UPDATED", function(_, itemKey)
  if not Scanner.running or not itemKey or itemKey.itemID ~= Scanner.current then
    return
  end
  local ladder = {}
  local n = C_AuctionHouse.GetNumItemSearchResults(itemKey) or 0
  for i = 1, n do
    local r = C_AuctionHouse.GetItemSearchResultInfo(itemKey, i)
    if r and r.buyoutAmount and r.quantity and r.quantity > 0 then
      table.insert(ladder, { r.buyoutAmount / r.quantity, r.quantity })
    end
  end
  Scanner:Finish(itemKey.itemID, ladder)
end)

ns:RegisterEvent("AUCTION_HOUSE_CLOSED", function()
  Scanner:Stop("closed")
end)
