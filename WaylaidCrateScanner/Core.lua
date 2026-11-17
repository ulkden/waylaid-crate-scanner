local addonName, ns = ...
_G.WaylaidCrateScanner = ns

ns.addonName = addonName
ns.TAB_ID = "WaylaidCrateScanner"
-- Addon icon (64x64 TGA; WoW resolves the extension). Also set as ## IconTexture in the .toc.
ns.ICON = "Interface\\AddOns\\" .. addonName .. "\\Media\\waylaid_crate_icon_64"

---------------------------------------------------------------------------
-- Minimap addon compartment entry (names referenced from the .toc)
---------------------------------------------------------------------------
function WaylaidCrateScanner_OnAddonCompartmentClick()
  ns.UI:ToggleWindow()
end

-- Called by the compartment menu as (addonName, menuButton).
function WaylaidCrateScanner_OnAddonCompartmentEnter(_, menuButton)
  if not menuButton then
    return
  end
  GameTooltip:SetOwner(menuButton, "ANCHOR_LEFT")
  GameTooltip:SetText("Waylaid Crate Scanner")
  GameTooltip:AddLine("Click to open the scanner window.", 1, 1, 1)
  GameTooltip:AddLine("Scanning needs the Auction House open.", 0.6, 0.6, 0.6)
  GameTooltip:Show()
end

function WaylaidCrateScanner_OnAddonCompartmentLeave()
  GameTooltip:Hide()
end

local DEFAULTS = {
  prices = {}, -- [itemID] = { t = time(), listed = n, ladder = { {unitPrice, quantity}, ... } }; cleared at login
  expanded = {}, -- [nodePath] = true/false
  useVendor = true, -- use vendor price for Weak Flux / Salt / Coal when cheaper
  mode = "bags", -- "bags" (crates in your bags) or "market" (every crate listed on the AH)
  sort = {}, -- [mode] = sort key (see UI.lua SORTS); defaults: bags "name", market "perFavor"
  favorOverrides = {}, -- ["Tier:quality"] = favor, set with /wcs favor
  window = {}, -- saved window position / size
  debug = false,
}

---------------------------------------------------------------------------
-- Events + a tiny internal message bus
---------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
local eventHandlers = {}

function ns:RegisterEvent(event, fn)
  if not eventHandlers[event] then
    eventHandlers[event] = {}
    eventFrame:RegisterEvent(event)
  end
  table.insert(eventHandlers[event], fn)
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
  local list = eventHandlers[event]
  if not list then
    return
  end
  for i = 1, #list do
    list[i](event, ...)
  end
end)

local listeners = {}
function ns:Listen(msg, fn)
  listeners[msg] = listeners[msg] or {}
  table.insert(listeners[msg], fn)
end

function ns:Fire(msg, ...)
  local list = listeners[msg]
  if not list then
    return
  end
  for i = 1, #list do
    list[i](...)
  end
end

--- Returns a function that, however often it is called, runs fn once `delay` seconds after the
--- first call of a burst. Used to coalesce noisy events (bag updates, price updates, item data).
function ns.Debounce(delay, fn)
  local queued = false
  local function run()
    queued = false
    fn()
  end
  return function()
    if not queued then
      queued = true
      C_Timer.After(delay, run)
    end
  end
end

function ns.IsAHOpen()
  return AuctionHouseFrame ~= nil and AuctionHouseFrame:IsShown()
end

---------------------------------------------------------------------------
-- Printing / debug
---------------------------------------------------------------------------
function ns.Print(...)
  print("|cff33ccffCrate Scanner:|r", ...)
end

function ns.Debug(...)
  if ns.db and ns.db.debug then
    print("|cff888888[WCS]|r", ...)
  end
end

---------------------------------------------------------------------------
-- Item helpers
---------------------------------------------------------------------------
ns.AllItemIDs = {}
for itemID in pairs(ns.FallbackNames) do
  table.insert(ns.AllItemIDs, itemID)
end

-- An item's name, icon and quality never change once the client knows them, so each is looked
-- up once and cached. Until then the lookups are retried (and names use Data.lua's fallbacks).
local nameCache, iconCache, qualityCache, qualityHex = {}, {}, {}, {}

--- Returns name, isFallback (true while the client hasn't loaded the item yet).
function ns.ItemName(itemID)
  local name = nameCache[itemID] or C_Item.GetItemNameByID(itemID)
  if name then
    nameCache[itemID] = name
    return name
  end
  C_Item.RequestLoadItemDataByID(itemID)
  return ns.FallbackNames[itemID] or ("item:" .. itemID), true
end

function ns.ItemIcon(itemID)
  local icon = iconCache[itemID] or C_Item.GetItemIconByID(itemID)
  iconCache[itemID] = icon
  return icon or 134400 -- question mark
end

function ns.ItemQuality(itemID)
  local quality = qualityCache[itemID] or C_Item.GetItemQualityByID(itemID)
  qualityCache[itemID] = quality
  return quality
end

--- "|cffrrggbb" for an item quality (nil if unknown). Each quality is looked up once.
function ns.QualityHex(quality)
  if not quality then
    return nil
  end
  local hex = qualityHex[quality]
  if not hex then
    if C_Item.GetItemQualityColor then
      local _, _, _, h = C_Item.GetItemQualityColor(quality)
      hex = h and ("|c" .. h)
    end
    hex = hex or (ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality] and ITEM_QUALITY_COLORS[quality].hex)
    qualityHex[quality] = hex
  end
  return hex
end

function ns.ItemColorHex(itemID)
  return ns.QualityHex(ns.ItemQuality(itemID)) or "|cffffffff"
end

local GetItemCount = C_Item.GetItemCount
function ns.CountInBags(itemID)
  return GetItemCount and GetItemCount(itemID, false, false, true) or 0
end

---------------------------------------------------------------------------
-- Money formatting (compact, coin icons, skips leading zero denominations)
---------------------------------------------------------------------------
local GOLD = "|TInterface\\MoneyFrame\\UI-GoldIcon:12:12:2:0|t"
local SILVER = "|TInterface\\MoneyFrame\\UI-SilverIcon:12:12:2:0|t"
local COPPER = "|TInterface\\MoneyFrame\\UI-CopperIcon:12:12:2:0|t"

--- full = true always shows copper; otherwise copper is dropped once the amount
--- reaches 1 gold, which keeps the table columns narrow.
function ns.FormatMoney(copper, full)
  if copper == nil then
    return nil
  end
  copper = math.floor(copper + 0.5)
  local g = math.floor(copper / 10000)
  local s = math.floor((copper % 10000) / 100)
  local c = copper % 100
  if g > 0 then
    local gold = BreakUpLargeNumbers and BreakUpLargeNumbers(g) or g
    if not full then
      return string.format("%s%s %02d%s", gold, GOLD, s, SILVER)
    end
    return string.format("%s%s %02d%s %02d%s", gold, GOLD, s, SILVER, c, COPPER)
  elseif s > 0 then
    return string.format("%d%s %02d%s", s, SILVER, c, COPPER)
  end
  return string.format("%d%s", c, COPPER)
end

---------------------------------------------------------------------------
-- Init
---------------------------------------------------------------------------
ns:RegisterEvent("ADDON_LOADED", function(_, name)
  if name ~= addonName then
    return
  end
  WaylaidCrateScannerDB = WaylaidCrateScannerDB or {}
  for k, v in pairs(DEFAULTS) do
    if WaylaidCrateScannerDB[k] == nil then
      WaylaidCrateScannerDB[k] = type(v) == "table" and {} or v
    end
  end
  ns.db = WaylaidCrateScannerDB
  ns.db.learnedCrates = nil -- obsolete: crate item IDs now ship in Data.lua
  ns.db.marketSort = nil -- obsolete: replaced by ns.db.sort
end)

-- Prices are only good for the current session: keep them through /reload, drop them at login.
ns:RegisterEvent("PLAYER_ENTERING_WORLD", function(_, isInitialLogin)
  if isInitialLogin then
    wipe(ns.db.prices)
  end
end)

ns:RegisterEvent("PLAYER_LOGIN", function()
  -- Warm the item cache so names/icons and tooltip matching work immediately.
  for _, itemID in ipairs(ns.AllItemIDs) do
    C_Item.RequestLoadItemDataByID(itemID)
  end
end)

ns:RegisterEvent(
  "GET_ITEM_INFO_RECEIVED",
  ns.Debounce(0.3, function()
    ns:Fire("ITEM_DATA_UPDATED")
  end)
)

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
SLASH_WAYLAIDCRATESCANNER1 = "/wcs"
SLASH_WAYLAIDCRATESCANNER2 = "/cratescanner"
SlashCmdList.WAYLAIDCRATESCANNER = function(msg)
  msg = strtrim((msg or ""):lower())
  if msg == "" then
    ns.UI:ToggleWindow()
  elseif msg:sub(1, 5) == "favor" then
    ns.SetFavorOverride(strtrim(msg:sub(6)))
  elseif msg == "help" then
    ns.Print("/wcs — toggle the scanner window (scanning needs the Auction House open)")
    ns.Print("/wcs crates | tooltip | debug | reset")
    ns.Print("/wcs favor <tier> <common|uncommon> <amount|clear> — correct a Merchant's Favor value")
  elseif msg == "debug" then
    ns.db.debug = not ns.db.debug
    ns.Print("debug", ns.db.debug and "ON" or "OFF")
  elseif msg == "tooltip" then
    ns.DumpCrateTooltips()
  elseif msg == "reset" then
    wipe(ns.db.prices)
    ns.Print("cached prices cleared.")
    ns:Fire("PRICES_UPDATED")
  elseif msg == "crates" then
    local crates = ns.ScanBags()
    if #crates == 0 then
      ns.Print("no Waylaid Crates found in your bags.")
    end
    for _, inst in ipairs(crates) do
      local favor = ns.GetFavor(inst.key, inst.quality)
      ns.Print(string.format("%s x%d (%s favor each)", inst.name, inst.count, favor and tostring(favor) or "?"))
    end
  else
    ns.Print("unknown command. /wcs help")
  end
end
