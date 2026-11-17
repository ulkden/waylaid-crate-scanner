local _, ns = ...

-- Crate detection: finds "Waylaid Crate: <Type>" items in your bags. If a crate's tooltip
-- lists a quantity for a material (e.g. "20 Copper Ore"), that quantity overrides the
-- built-in data, so changes to the crates in a patch are picked up automatically.

local CRATE_NAME_PATTERN = "^Waylaid Crate:%s*(.-)%s*$"
local LAST_BAG = NUM_TOTAL_EQUIPPED_BAG_SLOTS or ((NUM_BAG_SLOTS or 4) + 1)

-- Every material that appears as a crate option (used for tooltip matching).
local optionItemIDs = {}
do
  local seen = {}
  for _, def in pairs(ns.Crates) do
    for _, opt in ipairs(def.options) do
      if not seen[opt[1]] then
        seen[opt[1]] = true
        table.insert(optionItemIDs, opt[1])
      end
    end
  end
end

-- [crateItemID] = crate key, from the item IDs in Data.lua.
ns.CrateByItemID = {}
for key, def in pairs(ns.Crates) do
  if def.itemID then
    ns.CrateByItemID[def.itemID] = key
  end
end

local function CleanText(text)
  if not text then
    return nil
  end
  text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", ""):gsub("|A.-|a", "")
  return text
end

local function GetTooltipLines(bag, slot)
  local lines = {}
  if not (C_TooltipInfo and C_TooltipInfo.GetBagItem) then
    return lines
  end
  local ok, data = pcall(C_TooltipInfo.GetBagItem, bag, slot)
  if not ok or not data or not data.lines then
    return lines
  end
  for _, line in ipairs(data.lines) do
    local left = CleanText(line.leftText)
    local right = CleanText(line.rightText)
    local text = left or ""
    if right and right ~= "" then
      text = text .. " " .. right
    end
    if text ~= "" then
      table.insert(lines, text)
    end
  end
  return lines
end

-- { {itemID, lowerName}, ... } sorted longest name first, so that "Bolt of Linen Cloth" wins over
-- "Linen Cloth" on the same tooltip line. Built once; rebuilt only while some names are still the
-- English fallbacks (the client hasn't loaded them yet).
local nameList, nameListComplete
local function MaterialNames()
  if not nameList then
    nameList, nameListComplete = {}, true
    for _, itemID in ipairs(optionItemIDs) do
      local name, isFallback = ns.ItemName(itemID)
      if isFallback then
        nameListComplete = false
      end
      table.insert(nameList, { itemID, name:lower() })
    end
    table.sort(nameList, function(a, b)
      return #a[2] > #b[2]
    end)
  end
  return nameList
end
ns:Listen("ITEM_DATA_UPDATED", function()
  if not nameListComplete then
    nameList = nil
  end
end)

-- Parses tooltip lines into { [itemID] = quantity }. The largest number on a line that
-- names a material is taken as its quantity.
local function ParseTooltipQuantities(lines, names)
  local found = {}
  for _, line in ipairs(lines) do
    local lower = line:lower()
    for _, entry in ipairs(names) do
      local s, e = lower:find(entry[2], 1, true)
      if s then
        local rest = lower:sub(1, s - 1) .. " " .. lower:sub(e + 1)
        local qty
        for num in rest:gmatch("%d+") do
          num = tonumber(num)
          if not qty or num > qty then
            qty = num
          end
        end
        if qty and qty > 0 then
          found[entry[1]] = qty
        end
        break
      end
    end
  end
  return found
end

-- A crate's fill options: Data.lua's, with quantities from its tooltip where the tooltip lists
-- them, plus any tooltip material our data doesn't know about.
local function ReadOptions(key, bag, slot)
  local parsed = ParseTooltipQuantities(GetTooltipLines(bag, slot), MaterialNames())
  local options = {}
  local def = ns.Crates[key]
  if def then
    for _, opt in ipairs(def.options) do
      table.insert(options, { opt[1], parsed[opt[1]] or opt[2] })
      parsed[opt[1]] = nil
    end
  end
  for optID, qty in pairs(parsed) do
    table.insert(options, { optID, qty })
  end
  return options
end

--- Maps a crate item name to its data key ("Waylaid Crate: Apprentice Ore" -> "Apprentice Ore").
--- Returns key, isKnown.
function ns.CrateKeyFromName(name)
  local suffix = name and name:match(CRATE_NAME_PATTERN)
  if not suffix then
    return nil
  end
  return suffix, ns.Crates[suffix] ~= nil
end

-- Item IDs whose name is known and isn't a Waylaid Crate, so they're skipped on later scans.
local notCrate = {}

local function IdentifyCrate(itemID, hyperlink)
  local key = ns.CrateByItemID[itemID]
  if key then
    return key, ns.ItemName(itemID)
  end
  if notCrate[itemID] then
    return nil
  end
  -- Fallback by name, for a crate type added after Data.lua was generated.
  local name = C_Item.GetItemNameByID(itemID) or (hyperlink and hyperlink:match("%[(.-)%]"))
  local nameKey, known = ns.CrateKeyFromName(name)
  if not nameKey then
    if name then
      notCrate[itemID] = true
    end
    return nil
  end
  return known and nameKey or ("?" .. nameKey), name
end

--- Scans bags. Returns a list of crate instances, one per crate item ID (stacks are merged):
--- { key, name, itemID, quality, count, options = { {itemID, qty}, ... } }
--- Stacks of the same item ID share a tooltip, so each crate type's tooltip is read only once.
function ns.ScanBags()
  local result, byItemID = {}, {}
  for bag = 0, LAST_BAG do
    for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
      local info = C_Container.GetContainerItemInfo(bag, slot)
      local itemID = info and info.itemID
      local inst = itemID and byItemID[itemID]
      if inst then
        inst.count = inst.count + (info.stackCount or 1)
      elseif itemID then
        local key, name = IdentifyCrate(itemID, info.hyperlink)
        if key then
          local def = ns.Crates[key]
          inst = {
            key = key,
            name = name or key,
            itemID = itemID,
            quality = (def and def.quality) or ns.ItemQuality(itemID),
            count = info.stackCount or 1,
            options = ReadOptions(key, bag, slot),
          }
          byItemID[itemID] = inst
          table.insert(result, inst)
          if ns.db.debug then
            ns.Debug(
              string.format("crate %s (%d) bag %d slot %d, %d options", inst.name, itemID, bag, slot, #inst.options)
            )
          end
        end
      end
    end
  end
  table.sort(result, function(a, b)
    return a.name < b.name
  end)
  return result
end

function ns.DumpCrateTooltips()
  local any = false
  for bag = 0, LAST_BAG do
    for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
      local info = C_Container.GetContainerItemInfo(bag, slot)
      if info and info.itemID and IdentifyCrate(info.itemID, info.hyperlink) then
        any = true
        ns.Print(string.format("item %d (bag %d slot %d):", info.itemID, bag, slot))
        for i, line in ipairs(GetTooltipLines(bag, slot)) do
          print("   " .. i .. ": " .. line)
        end
      end
    end
  end
  if not any then
    ns.Print("no Waylaid Crates found in your bags.")
  end
end
