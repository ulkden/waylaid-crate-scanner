local _, ns = ...

-- Merchant's Favor awarded for turning in a filled crate, by crate tier and quality.
-- Quality comes from Data.lua: 1 = Common (white, gathering crates), 2 = Uncommon (green, crafting crates).
--
-- Apprentice and Journeyman are confirmed in-game. Expert comes from player reports and Artisan is
-- extrapolated from the pattern (+5 per tier, Uncommon pays double), so both are flagged unconfirmed.
-- Correct any value in-game with:  /wcs favor <tier> <common|uncommon> <amount>
ns.FavorTable = {
  Apprentice = { [1] = 5, [2] = 10, confirmed = true },
  Journeyman = { [1] = 10, [2] = 20, confirmed = true },
  Expert = { [1] = 15, [2] = 30, confirmed = false },
  Artisan = { [1] = 20, [2] = 40, confirmed = false },
}

ns.QualityNames = { [1] = "common", [2] = "uncommon", [3] = "rare" }

function ns.CrateTier(key)
  if not key then
    return nil
  end
  for _, tier in ipairs({ "Apprentice", "Journeyman", "Expert", "Artisan" }) do
    if key:find(tier, 1, true) then
      return tier
    end
  end
end

--- Returns favor, confirmed (both nil if unknown).
function ns.GetFavor(key, quality)
  local tier = ns.CrateTier(key)
  if not tier or not quality then
    return nil
  end
  local override = ns.db and ns.db.favorOverrides and ns.db.favorOverrides[tier .. ":" .. quality]
  if override then
    return override, true
  end
  local row = ns.FavorTable[tier]
  local favor = row and row[quality]
  if not favor then
    return nil
  end
  return favor, row.confirmed
end

--- /wcs favor <tier> <common|uncommon> <amount>   (amount "clear" removes the override)
function ns.SetFavorOverride(args)
  local tier, qualityName, amount = args:match("^(%a+)%s+(%a+)%s+(%S+)$")
  if tier then
    tier = tier:sub(1, 1):upper() .. tier:sub(2):lower()
  end
  local quality
  for q, name in pairs(ns.QualityNames) do
    if qualityName and name == qualityName:lower() then
      quality = q
    end
  end
  if not (tier and ns.FavorTable[tier] and quality) then
    ns.Print("usage: /wcs favor <apprentice|journeyman|expert|artisan> <common|uncommon> <amount|clear>")
    for _, t in ipairs({ "Apprentice", "Journeyman", "Expert", "Artisan" }) do
      local c = ns.GetFavor(t, 1)
      local u = ns.GetFavor(t, 2)
      local row = ns.FavorTable[t]
      ns.Print(
        string.format(
          "  %s: common %s, uncommon %s%s",
          t,
          tostring(c),
          tostring(u),
          row.confirmed and "" or " (unconfirmed unless overridden)"
        )
      )
    end
    return
  end
  ns.db.favorOverrides = ns.db.favorOverrides or {}
  local k = tier .. ":" .. quality
  if amount == "clear" then
    ns.db.favorOverrides[k] = nil
    ns.Print(string.format("%s %s crates: back to default favor.", tier, qualityName))
  else
    local n = tonumber(amount)
    if not n then
      ns.Print("amount must be a number or 'clear'.")
      return
    end
    ns.db.favorOverrides[k] = n
    ns.Print(string.format("%s %s crates now award %d Merchant's Favor.", tier, qualityName, n))
  end
  ns:Fire("PRICES_UPDATED")
end
