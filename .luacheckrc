-- luacheck configuration for a World of Warcraft (WoW: Forever / retail API) addon.
-- Run: luacheck .        (or: make lint)

std = "lua51"
-- Line width is enforced by StyLua (stylua.toml, column_width = 120). StyLua cannot wrap long string
-- literals such as tooltip text, so luacheck does not check line length on top of it.
max_line_length = false
codes = true

exclude_files = {
  "WaylaidCrateScanner/Libs/**", -- vendored third-party libraries
  ".luacheckcache",
}

ignore = {
  "212/self", -- unused `self` in methods is normal for mixin-style code
  "212/_.*", -- unused args prefixed with _
  "211/_.*", -- unused locals prefixed with _
}

-- Globals this addon creates.
globals = {
  "WaylaidCrateScanner",
  "WaylaidCrateScannerDB",
  "SLASH_WAYLAIDCRATESCANNER1",
  "SLASH_WAYLAIDCRATESCANNER2",
  "SlashCmdList",
  "UISpecialFrames",
  -- Minimap addon compartment callbacks (named in the .toc)
  "WaylaidCrateScanner_OnAddonCompartmentClick",
  "WaylaidCrateScanner_OnAddonCompartmentEnter",
  "WaylaidCrateScanner_OnAddonCompartmentLeave",
}

-- WoW API / FrameXML globals the addon reads. Add new ones here when you use them.
read_globals = {
  -- Lua extensions provided by WoW
  "strtrim",
  "wipe",
  "time",
  "date",

  -- Namespaced C APIs
  "C_AuctionHouse",
  "C_Container",
  "C_CurrencyInfo",
  "C_Item",
  "C_Spell",
  "C_Timer",
  "C_TooltipInfo",
  "Enum",

  -- Global API functions
  "BreakUpLargeNumbers",
  "CreateDataProvider",
  "CreateFrame",
  "CreateScrollBoxListLinearView",
  "GameTooltip_Hide",
  "GetTime",
  "IsControlKeyDown",
  "IsShiftKeyDown",
  "LibStub",

  -- Frames, mixins and constants from FrameXML
  "AuctionHouseFrame",
  "ChatEdit_InsertLink",
  "ChatFrameUtil",
  "GameTooltip",
  "ITEM_QUALITY_COLORS",
  "NUM_BAG_SLOTS",
  "NUM_TOTAL_EQUIPPED_BAG_SLOTS",
  "ScrollBoxConstants",
  "ScrollUtil",
  "UIParent",
}

-- The offline test harness stubs the WoW API, so it defines those globals itself.
files["tools/test_harness.lua"] = {
  std = "luajit",
  globals = {
    "AuctionHouseFrame",
    "C_AuctionHouse",
    "C_Container",
    "C_Item",
    "C_Timer",
    "C_TooltipInfo",
    "CreateFrame",
    "Enum",
    "GetTime",
    "NUM_TOTAL_EQUIPPED_BAG_SLOTS",
    "SlashCmdList",
    "strtrim",
    "time",
    "wipe",
  },
  ignore = { "131" }, -- unused global (stubs)
}
