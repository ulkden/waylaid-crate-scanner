local _, ns = ...

-- Crate detection: finds "Waylaid Crate: <Type>" items in your bags. If a crate's tooltip
-- lists a quantity for a material (e.g. "20 Copper Ore"), that quantity overrides the
-- built-in data, so changes to the crates in a patch are picked up automatically.

local CRATE_NAME_PATTERN = "^Waylaid Crate:%s*(.-)%s*$"

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

-- Returns a list of {itemID, lowerName} sorted longest name first, so that
-- "Bolt of Linen Cloth" wins over "Linen Cloth" on the same tooltip line.
local function GetMaterialNameList()
  local list = {}
  for _, itemID in ipairs(optionItemIDs) do
    table.insert(list, { itemID, ns.ItemName(itemID):lower() })
  end
  table.sort(list, function(a, b)
    return #a[2] > #b[2]
  end)
  return list
end

-- Parses tooltip lines into { [itemID] = quantity }. The largest number on a line that
-- names a material is taken as its quantity.
local function ParseTooltipQuantities(lines, nameList)
  local found = {}
  for _, line in ipairs(lines) do
    local lower = line:lower()
    for _, entry in ipairs(nameList) do
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

--- Maps a crate item name to its data key ("Waylaid Crate: Apprentice Ore" -> "Apprentice Ore").
--- Returns key, isKnown.
function ns.CrateKeyFromName(name)
  local suffix = name and name:match(CRATE_NAME_PATTERN)
  if not suffix then
    return nil
  end
  return suffix, ns.Crates[suffix] ~= nil
end

-- [crateItemID] = crate key, from the item IDs in Data.lua.
ns.CrateByItemID = {}
for key, def in pairs(ns.Crates) do
  if def.itemID then
    ns.CrateByItemID[def.itemID] = key
  end
end

local function IdentifyCrate(itemID, hyperlink)
  local key = ns.CrateByItemID[itemID]
  if key then
    return key, C_Item.GetItemNameByID(itemID) or ("Waylaid Crate: " .. key)
  end
  -- Fallback by name, for a crate type added after Data.lua was generated.
  local name = C_Item.GetItemNameByID(itemID) or (hyperlink and hyperlink:match("%[(.-)%]"))
  local nameKey, known = ns.CrateKeyFromName(name)
  if not nameKey then
    return nil
  end
  return known and nameKey or ("?" .. nameKey), name
end

local function LastBagIndex()
  return NUM_TOTAL_EQUIPPED_BAG_SLOTS or ((NUM_BAG_SLOTS or 4) + 1)
end

--- Scans bags. Returns a list of crate instances:
--- { key, name, itemID, count, options = { {itemID, qty}, ... } }
function ns.ScanBags()
  local result, bySignature = {}, {}
  local nameList
  for bag = 0, LastBagIndex() do
    local numSlots = C_Container.GetContainerNumSlots(bag) or 0
    for slot = 1, numSlots do
      local info = C_Container.GetContainerItemInfo(bag, slot)
      if info and info.itemID then
        local key, name = IdentifyCrate(info.itemID, info.hyperlink)
        if key then
          nameList = nameList or GetMaterialNameList()
          local parsed = ParseTooltipQuantities(GetTooltipLines(bag, slot), nameList)

          local options, used = {}, {}
          local def = ns.Crates[key]
          if def then
            for _, opt in ipairs(def.options) do
              table.insert(options, { opt[1], parsed[opt[1]] or opt[2] })
              used[opt[1]] = true
            end
          end
          -- Options found on the tooltip that our data doesn't know about.
          for optID, qty in pairs(parsed) do
            if not used[optID] then
              table.insert(options, { optID, qty })
            end
          end

          local sigParts = { key }
          for _, opt in ipairs(options) do
            table.insert(sigParts, opt[1] .. ":" .. opt[2])
          end
          local sig = table.concat(sigParts, "|")

          local count = info.stackCount or 1
          local inst = bySignature[sig]
          if inst then
            inst.count = inst.count + count
          else
            inst = {
              key = key,
              name = name or key,
              itemID = info.itemID,
              quality = (def and def.quality) or C_Item.GetItemQualityByID(info.itemID),
              count = count,
              options = options,
            }
            bySignature[sig] = inst
            table.insert(result, inst)
          end
          ns.Debug(
            string.format("crate %s (%d) bag %d slot %d, %d options", inst.name, info.itemID, bag, slot, #options)
          )
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
  for bag = 0, LastBagIndex() do
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
