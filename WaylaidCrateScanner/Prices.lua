local _, ns = ...

-- Price lookups built on the scanned listing "ladders" (lowest unit price first).
local Prices = {}
ns.Prices = Prices

-- Status values returned alongside costs.
Prices.OK = "ok" -- enough listings to cover the quantity
Prices.PARTIAL = "partial" -- not enough listed; shortfall priced at the highest seen unit price
Prices.NONE = "none" -- scanned, nothing listed
Prices.UNKNOWN = "unknown" -- never scanned
Prices.VENDOR = "vendor" -- vendor price used

function Prices.Get(itemID)
  return ns.db.prices[itemID]
end

--- listed (optional): total quantity on the AH, if the search reported more than the ladder holds.
function Prices.Store(itemID, ladder, listed)
  table.sort(ladder, function(a, b)
    return a[1] < b[1]
  end)
  -- Keep the cheapest ~1000 units (far more than any crate needs), but count everything listed.
  local trimmed, kept, total = {}, 0, 0
  for _, step in ipairs(ladder) do
    if kept < 1000 then
      trimmed[#trimmed + 1] = step
      kept = kept + step[2]
    end
    total = total + step[2]
  end
  ns.db.prices[itemID] = { t = time(), ladder = trimmed, listed = math.max(listed or 0, total) }
end

local function VendorPrice(itemID)
  if ns.db.useVendor then
    return ns.VendorPrices[itemID]
  end
end

--- Lowest unit price available (AH or vendor), or nil.
function Prices.MinUnit(itemID)
  local vendor = VendorPrice(itemID)
  local rec = ns.db.prices[itemID]
  local ah = rec and rec.ladder[1] and rec.ladder[1][1]
  if vendor and ah then
    return math.min(vendor, ah)
  end
  return vendor or ah
end

--- Total listed quantity on the AH (from the last scan), or nil if never scanned.
function Prices.Listed(itemID)
  local rec = ns.db.prices[itemID]
  return rec and rec.listed
end

--- Cost of buying `qty` units, walking up the listing ladder.
--- Returns cost (or nil), status.
function Prices.BuyCost(itemID, qty)
  if qty <= 0 then
    return 0, Prices.OK
  end
  local vendor = VendorPrice(itemID)
  local rec = ns.db.prices[itemID]

  local ahCost, status
  if not rec then
    status = Prices.UNKNOWN
  elseif #rec.ladder == 0 then
    status = Prices.NONE
  else
    local remaining, cost, lastUnit = qty, 0, 0
    for _, step in ipairs(rec.ladder) do
      local take = math.min(remaining, step[2])
      cost = cost + take * step[1]
      lastUnit = step[1]
      remaining = remaining - take
      if remaining <= 0 then
        break
      end
    end
    if remaining > 0 then
      cost = cost + remaining * lastUnit
      status = Prices.PARTIAL
    else
      status = Prices.OK
    end
    ahCost = cost
  end

  if vendor and (ahCost == nil or vendor * qty <= ahCost) then
    return vendor * qty, Prices.VENDOR
  end
  return ahCost, status
end

--- Seconds since the oldest price among itemIDs was scanned (nil if any missing).
function Prices.OldestAge(itemIDs)
  local oldest
  for itemID in pairs(itemIDs) do
    local rec = ns.db.prices[itemID]
    if not rec then
      return nil
    end
    if not oldest or rec.t < oldest then
      oldest = rec.t
    end
  end
  return oldest and (time() - oldest) or nil
end

--- Removes `qty` units from the cheapest end of the cached ladder (after we bought them).
function Prices.Consume(itemID, qty)
  local rec = ns.db.prices[itemID]
  if not rec then
    return
  end
  rec.listed = math.max(0, rec.listed - qty)
  while qty > 0 and rec.ladder[1] do
    local step = rec.ladder[1]
    if step[2] <= qty then
      qty = qty - step[2]
      table.remove(rec.ladder, 1)
    else
      step[2] = step[2] - qty
      qty = 0
    end
  end
end
