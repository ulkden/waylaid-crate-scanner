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
  -- key/price are copied onto the root so the UI can sort roots by plain field name.
  local root = { kind = "crate", inst = inst, key = inst.key, price = inst.price, path = path }
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

--- crates: output of ns.ScanBags().
function Tree.Build(crates)
  local roots, seenKeys = {}, {}
  for _, inst in ipairs(crates) do
    seenKeys[inst.key] = (seenKeys[inst.key] or 0) + 1
    table.insert(roots, Tree.BuildRoot(inst, "crate:" .. inst.key .. "#" .. seenKeys[inst.key]))
  end
  return roots
end

--- One root per crate type (used by the market scan).
--- onlyListed = true keeps just the crate types currently listed on the AH (from the last scan).
function Tree.BuildMarket(onlyListed)
  local roots = {}
  for key, def in pairs(ns.Crates) do
    local listed = def.itemID and ns.Prices.Listed(def.itemID)
    if not onlyListed or (listed and listed > 0) then
      local inst = {
        key = key,
        name = "Waylaid Crate: " .. key,
        itemID = def.itemID,
        quality = def.quality,
        count = 1,
        options = def.options,
        price = def.itemID and ns.Prices.BuyCost(def.itemID, 1) or nil,
        listed = listed,
      }
      table.insert(roots, Tree.BuildRoot(inst, "market:" .. key))
    end
  end
  return roots
end

--- Every item ID the market scan needs: all crate items plus all of their materials.
--- Depends only on Data.lua, so it is built once. Callers must not modify it.
local marketItems
function Tree.MarketScanItems()
  if not marketItems then
    marketItems = Tree.CollectItems(Tree.BuildMarket(false))
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

--- Returns a summary table:
---   best      = total of the cheapest fills (crafting allowed) across all crates
---   buyOnly   = total of the cheapest purely-purchased fills (no crafting at all)
---   allPriced / allBuyPriced = false if some crate couldn't be priced that way
---
--- Each crate root gets:
---   best / bestChild           cheapest option, crafting allowed
---   buyBest / buyBestChild     cheapest option bought outright from the AH
---   craftBest / craftBestChild cheapest option crafted yourself (nil if nothing is craftable)
---   total                      crate's own AH price + best (market scan only)
function Tree.Compute(roots)
  local summary = { best = 0, buyOnly = 0, allPriced = true, allBuyPriced = true }
  for _, root in ipairs(roots) do
    root.best, root.bestChild = nil, nil
    root.buyBest, root.buyBestChild = nil, nil
    root.craftBest, root.craftBestChild = nil, nil
    for _, child in ipairs(root.children or NONE) do
      ComputeMaterial(child)
      child.isCheapest, child.isCheapestBuy = false, false
      if child.best and (root.best == nil or child.best < root.best) then
        root.best, root.bestChild = child.best, child
      end
      if child.buyCost and (root.buyBest == nil or child.buyCost < root.buyBest) then
        root.buyBest, root.buyBestChild = child.buyCost, child
      end
      if child.craftCost and (root.craftBest == nil or child.craftCost < root.craftBest) then
        root.craftBest, root.craftBestChild = child.craftCost, child
      end
    end
    local price = root.inst.price
    root.total = (price and root.best) and (price + root.best) or nil

    -- Merchant's Favor: cost per favor = (crate price, if bought on the AH) + fill cost, / favor.
    local favor, confirmed = ns.GetFavor(root.inst.key, root.inst.quality)
    root.favor, root.favorConfirmed = favor, confirmed
    local base = price or 0
    root.perFavor = (favor and favor > 0 and root.best) and (base + root.best) / favor or nil
    for _, child in ipairs(root.children or NONE) do
      child.perFavor = (favor and favor > 0 and child.best) and (base + child.best) / favor or nil
    end
    if favor then
      summary.favor = (summary.favor or 0) + favor * root.inst.count
    end
    if root.bestChild then
      root.bestChild.isCheapest = true
    end
    if root.buyBestChild then
      root.buyBestChild.isCheapestBuy = true
    end
    if root.children then
      table.sort(root.children, CompareOptions)
    end

    local count = root.inst.count
    if root.best then
      summary.best = summary.best + root.best * count
    else
      summary.allPriced = false
    end
    if root.buyBest then
      summary.buyOnly = summary.buyOnly + root.buyBest * count
    else
      summary.allBuyPriced = false
    end
  end
  return summary
end

--- Default: crates in your bags expanded; market crates and materials collapsed.
function Tree.IsExpanded(node)
  local v = ns.db.expanded[node.path]
  if v == nil then
    return node.kind == "crate" and node.path:sub(1, 6) == "crate:"
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
