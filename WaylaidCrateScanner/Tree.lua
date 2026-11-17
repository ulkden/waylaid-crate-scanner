local _, ns = ...

-- Builds the cost tree:
--   crate (root)                      children are ALTERNATIVES: any one option fills the crate
--     option material  x need         children are REAGENTS of its recipe (all required)
--       reagent        x need ...     and so on, recursively
--
-- Every material node is priced two ways where possible: buying `need` units from the AH,
-- or crafting it from its reagents. The cheaper one becomes the node's `best` cost.

local Tree = {}
ns.Tree = Tree

local MAX_DEPTH = 8
local NONE = {}

local function MakeMaterial(itemID, need, perCraft, path, ancestors, depth)
  local node = {
    kind = "mat",
    itemID = itemID,
    need = need, -- units needed for this crate along this branch
    perCraft = perCraft, -- units of this reagent used by ONE craft of the parent (nil for crate options)
    path = path,
  }
  local recipe = ns.Recipes[itemID]
  if recipe and not ancestors[itemID] and depth < MAX_DEPTH then
    node.recipe = recipe
    node.crafts = math.ceil(need / recipe.yield)
    node.children = {}
    ancestors[itemID] = true
    for i, reagent in ipairs(recipe.reagents) do
      local reagentID, count = reagent[1], reagent[2]
      node.children[i] =
        MakeMaterial(reagentID, node.crafts * count, count, path .. ">" .. reagentID, ancestors, depth + 1)
    end
    ancestors[itemID] = nil
  end
  return node
end

--- inst = { key, name, itemID, count, options = { {itemID, qty}, ... } }
function Tree.BuildRoot(inst, path)
  -- key is copied onto the root so the UI can sort roots by plain field name (as with price, best...).
  local root = { kind = "crate", inst = inst, key = inst.key, path = path }
  local children = {}
  for i, opt in ipairs(inst.options) do
    local itemID, qty = opt[1], opt[2]
    local child = MakeMaterial(itemID, qty, nil, path .. ">" .. itemID, {}, 0)
    child.optionQty = qty
    child.crate = root -- option rows link back to their crate (used by the Buy button)
    child.order = i
    children[i] = child
  end
  -- Every node's children is either nil or non-empty, so `if node.children` means "expandable".
  root.children = children[1] and children or nil
  return root
end

--- crates: output of ns.ScanBags(). Crates in your bags start expanded.
function Tree.Build(crates)
  local roots, seenKeys = {}, {}
  for _, inst in ipairs(crates) do
    seenKeys[inst.key] = (seenKeys[inst.key] or 0) + 1
    local root = Tree.BuildRoot(inst, "crate:" .. inst.key .. "#" .. seenKeys[inst.key])
    root.defaultExpanded = true
    table.insert(roots, root)
  end
  return roots
end

-- One root per crate type, for AH Market mode. A tree's shape depends only on Data.lua, so these
-- are built once; Tree.Market refreshes each crate's own price and Tree.Compute its costs.
local marketRoots
local function MarketRoots()
  if not marketRoots then
    marketRoots = {}
    for key, def in pairs(ns.Crates) do
      local inst = {
        key = key,
        name = "Waylaid Crate: " .. key,
        itemID = def.itemID,
        quality = def.quality,
        count = 1,
        options = def.options,
      }
      table.insert(marketRoots, Tree.BuildRoot(inst, "market:" .. key))
    end
  end
  return marketRoots
end

--- Market roots with each crate's own AH price and listed quantity refreshed.
--- onlyListed = true keeps just the crate types currently listed on the AH (from the last scan).
function Tree.Market(onlyListed)
  local roots = {}
  for _, root in ipairs(MarketRoots()) do
    local itemID = root.inst.itemID
    root.listed = itemID and ns.Prices.Listed(itemID)
    root.price = itemID and ns.Prices.BuyCost(itemID, 1) or nil
    if not onlyListed or (root.listed and root.listed > 0) then
      table.insert(roots, root)
    end
  end
  return roots
end

--- Every item ID the market scan needs: all crate items plus all of their materials.
--- Depends only on Data.lua, so it is built once. Callers must not modify it.
local marketItems
function Tree.MarketScanItems()
  if not marketItems then
    marketItems = Tree.CollectItems(MarketRoots())
    for _, def in pairs(ns.Crates) do
      if def.itemID then
        marketItems[def.itemID] = true
      end
    end
  end
  return marketItems
end

--- Collects every item ID in the trees into a set (what needs scanning).
function Tree.CollectItems(roots, set)
  set = set or {}
  local function walk(node)
    if node.itemID then
      set[node.itemID] = true
    end
    if node.children then
      for _, child in ipairs(node.children) do
        walk(child)
      end
    end
  end
  for _, root in ipairs(roots) do
    walk(root)
  end
  return set
end

local function ComputeMaterial(node)
  local P = ns.Prices
  node.unit = P.MinUnit(node.itemID)
  node.buyCost, node.buyStatus = P.BuyCost(node.itemID, node.need)

  if node.children then
    local craftCost, perCraft, complete = 0, 0, true
    for _, child in ipairs(node.children) do
      ComputeMaterial(child)
      if child.best == nil then
        complete = false
      else
        craftCost = craftCost + child.best
        local childUnit = child.bestUnit
        if childUnit then
          perCraft = perCraft + childUnit * child.perCraft
        else
          complete = false
        end
      end
    end
    node.craftCost = complete and craftCost or nil
    node.perCraftCost = complete and perCraft or nil
  end

  local buy, craft = node.buyCost, node.craftCost
  if buy and craft then
    if craft < buy then
      node.best, node.method = craft, "craft"
    else
      node.best, node.method = buy, "buy"
    end
  elseif craft then
    node.best, node.method = craft, "craft"
  elseif buy then
    node.best, node.method = buy, "buy"
  else
    node.best, node.method = nil, nil
  end

  -- Effective cost of one unit, used by the parent's per-craft sum.
  if node.best and node.need > 0 then
    node.bestUnit = node.best / node.need
  else
    local craftUnit = node.perCraftCost and node.recipe and (node.perCraftCost / node.recipe.yield)
    if node.unit and craftUnit then
      node.bestUnit = math.min(node.unit, craftUnit)
    else
      node.bestUnit = node.unit or craftUnit
    end
  end
end

local function CompareOptions(a, b)
  if a.best and b.best then
    if a.best ~= b.best then
      return a.best < b.best
    end
  elseif a.best then
    return true
  elseif b.best then
    return false
  end
  return a.order < b.order
end

--- Prices every root in one pass. Each crate root gets:
---   best / bestChild           cheapest option, crafting allowed
---   buyBest / buyBestChild     cheapest option bought outright from the AH
---   craftBest / craftBestChild cheapest option crafted yourself (nil if nothing is craftable)
---   total                      crate's own AH price + best (market only; price set by Tree.Market)
---   favor / favorConfirmed / perFavor, and isBestValue on the root with the lowest perFavor
--- Returns a summary:
---   best      = total of the cheapest fills (crafting allowed) across all crates
---   buyOnly   = total of the cheapest purely-purchased fills (no crafting at all)
---   allPriced / allBuyPriced = false if some crate couldn't be priced that way
---   crates    = number of crates; favor = total favor; bestValue = the best-value root (or nil)
function Tree.Compute(roots)
  local summary = { crates = 0, best = 0, buyOnly = 0, allPriced = true, allBuyPriced = true }
  for _, root in ipairs(roots) do
    local inst = root.inst
    -- Merchant's Favor: cost per favor = (crate price, if bought on the AH) + fill cost, / favor.
    local favor, confirmed = ns.GetFavor(inst.key, inst.quality)
    local divisor = favor and favor > 0 and favor
    local base = root.price or 0

    local best, bestChild, buyBest, buyBestChild, craftBest, craftBestChild
    for _, child in ipairs(root.children or NONE) do
      ComputeMaterial(child)
      local cost = child.best
      child.isCheapest = false
      child.perFavor = cost and divisor and (base + cost) / divisor or nil
      if cost and (not best or cost < best) then
        best, bestChild = cost, child
      end
      if child.buyCost and (not buyBest or child.buyCost < buyBest) then
        buyBest, buyBestChild = child.buyCost, child
      end
      if child.craftCost and (not craftBest or child.craftCost < craftBest) then
        craftBest, craftBestChild = child.craftCost, child
      end
    end
    if bestChild then
      bestChild.isCheapest = true
    end
    if root.children then
      table.sort(root.children, CompareOptions)
    end

    root.best, root.bestChild = best, bestChild
    root.buyBest, root.buyBestChild = buyBest, buyBestChild
    root.craftBest, root.craftBestChild = craftBest, craftBestChild
    root.total = root.price and best and (root.price + best) or nil
    root.favor, root.favorConfirmed = favor, confirmed
    root.perFavor = best and divisor and (base + best) / divisor or nil
    root.isBestValue = false
    if root.perFavor and (not summary.bestValue or root.perFavor < summary.bestValue.perFavor) then
      summary.bestValue = root
    end

    local count = inst.count
    summary.crates = summary.crates + count
    if favor then
      summary.favor = (summary.favor or 0) + favor * count
    end
    if best then
      summary.best = summary.best + best * count
    else
      summary.allPriced = false
    end
    if buyBest then
      summary.buyOnly = summary.buyOnly + buyBest * count
    else
      summary.allBuyPriced = false
    end
  end
  if summary.bestValue then
    summary.bestValue.isBestValue = true
  end
  return summary
end

--- Default: crates in your bags expanded; market crates and materials collapsed.
function Tree.IsExpanded(node)
  local v = ns.db.expanded[node.path]
  if v == nil then
    return node.defaultExpanded == true
  end
  return v
end

function Tree.SetExpanded(node, value)
  ns.db.expanded[node.path] = value
end

--- Visible rows: { node = node, depth = n }
function Tree.Flatten(roots)
  local rows = {}
  local function add(node, depth)
    table.insert(rows, { node = node, depth = depth })
    if node.children and Tree.IsExpanded(node) then
      for _, child in ipairs(node.children) do
        add(child, depth + 1)
      end
    end
  end
  for _, root in ipairs(roots) do
    add(root, 0)
  end
  return rows
end

function Tree.SetAllExpanded(roots, value)
  local function walk(node)
    if node.children then
      Tree.SetExpanded(node, value)
      for _, child in ipairs(node.children) do
        walk(child)
      end
    end
  end
  for _, root in ipairs(roots) do
    walk(root)
  end
end

--- Prices `qty` of one item on its own (buy vs craft, recursively), for the purchase planner.
function Tree.PriceMaterial(itemID, qty)
  local node = MakeMaterial(itemID, qty, nil, "plan>" .. itemID, {}, 0)
  ComputeMaterial(node)
  return node
end
