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
  prices = {}, -- [itemID] = { t = time(), ladder = { {unitPrice, quantity}, ... } }
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

function ns.ItemName(itemID)
  local name = C_Item.GetItemNameByID(itemID)
  if name then
    return name
  end
  C_Item.RequestLoadItemDataByID(itemID)
  return ns.FallbackNames[itemID] or ("item:" .. itemID)
end

function ns.ItemIcon(itemID)
  return C_Item.GetItemIconByID(itemID) or 134400 -- question mark
end

function ns.ItemColorHex(itemID)
  local quality = C_Item.GetItemQualityByID(itemID)
  if quality and C_Item.GetItemQualityColor then
    local _, _, _, hex = C_Item.GetItemQualityColor(quality)
    if hex then
      return "|c" .. hex
    end
  end
  if quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality] then
    return ITEM_QUALITY_COLORS[quality].hex
  end
  return "|cffffffff"
end

function ns.CountInBags(itemID)
  if C_Item.GetItemCount then
    return C_Item.GetItemCount(itemID, false, false, true) or 0
  end
  return 0
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

ns:RegisterEvent("PLAYER_LOGIN", function()
  -- Warm the item cache so names/icons and tooltip matching work immediately.
  for _, itemID in ipairs(ns.AllItemIDs) do
    C_Item.RequestLoadItemDataByID(itemID)
  end
end)

local itemInfoPending = false
ns:RegisterEvent("GET_ITEM_INFO_RECEIVED", function()
  if itemInfoPending then
    return
  end
  itemInfoPending = true
  C_Timer.After(0.3, function()
    itemInfoPending = false
    ns:Fire("ITEM_DATA_UPDATED")
  end)
end)

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
