# Contributing

Thanks for helping out! This is a WoW: Forever addon (retail/Mainline API, interface `16001`).

## Setup

You need `luacheck`, `stylua` and `luajit` (and `python3` + `curl` to regenerate data).

```sh
# macOS
brew install luacheck stylua luajit
# Debian/Ubuntu
sudo apt-get install luajit lua-check   # StyLua: download from github.com/JohnnyMorganz/StyLua/releases

make hooks   # optional: run `make check` before every commit
```

## Everyday commands

| Command | What it does |
|---|---|
| `make check` | Everything CI runs: lint, format check and offline tests |
| `make format` | Reformat Lua with StyLua (do this before committing) |
| `make lint` | luacheck |
| `make test` | Offline logic tests with a stubbed WoW API (`tools/test_harness.lua`) |
| `make install` | Copy the addon into your Forever AddOns folder (set `WOW_ADDONS=...` if it isn't the macOS default) |
| `make data` | Regenerate `Data.lua` from Wowhead's WoW: Forever database |

CI (GitHub Actions) runs `luacheck`, `stylua --check` and the tests on every push and pull request.

## Branching

During initial development, changes go straight to `main`. Once the addon is ready for a general audience we'll switch to GitHub Flow (short-lived feature branches + pull requests).

## Code layout

```
WaylaidCrateScanner/
  WaylaidCrateScanner.toc  load order
  README.md     CurseForge project description (player-facing; paste into the CurseForge page)
  Data.lua      GENERATED: crates (item ID, level, quality, fill options), recipes, vendor prices
  Core.lua      namespace, events, message bus, saved variables, money formatting, slash commands
  Favor.lua     Merchant's Favor per crate tier/quality (hand-maintained) + /wcs favor overrides
  Crates.lua    finds crates in your bags (by item ID) and reads quantities from their tooltips
  Prices.lua    price "ladders" per item; cost of buying N units walking up the listings
  Scanner.lua   sequential AH search queue (C_AuctionHouse.SendSearchQuery), rate limited
  Tree.lua      builds crate -> option -> reagent trees and computes buy/craft/best costs, gold per favor
  Purchase.lua  shopping-list planner (bags first, buy vs craft) + two-step commodity purchase state machine
  Widgets.lua   shared UI building blocks: colors, buttons, tooltips, the portrait window shell
  UI.lua        scanner window, AH tab launcher (via LibAHTab), rows, tooltips, sorting
  BuyUI.lua     "Buy Crate Materials" window: crate count, option choice, shopping list with Buy/Confirm buttons
  Media/        in-game textures (waylaid_crate_icon_64.tga: addon list / compartment / window icon)
  Libs/         vendored LibStub + LibAHTab (do not edit; not linted or formatted)
media/          logo source art (SVG + 512px PNG) for the README and CurseForge; not shipped in-game
tools/
  crates.py         crate names + material name->ID hints (input to gen.py)
  gen.py            builds Data.lua from Wowhead Forever (crate tooltips + "created by" recipes)
  test_harness.lua  offline tests
```

Shared helpers live in `Core.lua` (`ns.Debounce`, `ns.IsAHOpen`, item/money helpers) and `Widgets.lua`;
use them rather than writing a local copy.

Modules communicate through `ns:Fire(msg)` / `ns:Listen(msg, fn)`. Messages: `SCAN_STARTED`, `SCAN_PROGRESS`, `SCAN_FINISHED`, `PRICES_UPDATED`, `ITEM_DATA_UPDATED`, `PURCHASE_UPDATED`.

Purchases must start from a real mouse click: `C_AuctionHouse.StartCommoditiesPurchase` is hardware-event restricted, and `ConfirmCommoditiesPurchase` is only called from the Confirm click after the server's quote arrives. Never call either one from timers or events.

## When the game adds or changes crates

1. Add the new crate to `tools/crates.py` (the name after `Waylaid Crate: `, plus each material's name and item ID if you know it; otherwise gen.py looks it up by name).
2. Run `make data`. It looks up each crate on Wowhead Forever by name, records its item ID, level and quality, takes the fill options from the crate's tooltip, and follows every material's recipes. It prints a `PROBLEM:` line for anything that doesn't match. Delete `.cache/wowhead` first to force fresh data after a patch.
3. If the crate belongs to a new tier, or favor rewards change, update `ns.FavorTable` in `Favor.lua`, and add the tier to `ns.CrateTier`'s list.
4. If a new crate category name doesn't end in Ore/Ingots/Herbs/Parts/Textiles/Fabrics/Curiosities, add it to `order` in `gen.py` (it only controls ordering in Data.lua).
5. `make check`, then `make install` and test in game (`/wcs crates`, `/wcs tooltip`).

## Using new WoW API functions

luacheck only allows globals listed in `.luacheckrc`. When you call a WoW API or FrameXML global the addon hasn't used before, add it to `read_globals` there. Check that it exists in Forever first: the client's UI source is mirrored in the `forever` branch of [Gethe/wow-ui-source](https://github.com/Gethe/wow-ui-source/tree/forever).

## Textures

In-game textures must be TGA (uncompressed or RLE, with alpha) or BLP, with power-of-two dimensions (e.g. 64x64).
Reference them without the extension: `Interface\AddOns\WaylaidCrateScanner\Media\<name>` (double the backslashes inside Lua strings). WoW only finds new
texture files after a full client restart, not `/reload`.

## Style

- StyLua decides formatting (`stylua.toml`: 2 spaces, 120 columns, double quotes).
- Keep `Data.lua` generated; never hand-edit it.
- Prefer `C_*` namespaced APIs; guard anything that may not exist on older clients.
- Keep the offline tests passing, and add a test to `tools/test_harness.lua` for new cost or detection logic.
- UI code is covered by smoke tests that build the real windows against stub widgets: they record text,
  shown state and checkbox state; any other capitalized method or child region is a no-op; scroll lists
  render every row. They catch Lua errors that WoW would otherwise swallow silently (with Lua errors
  hidden, a half-drawn window is the only symptom). When you add UI, extend the smoke test to open it.
- Don't give a frame and a plain value the same field name (e.g. `self.includeCrates` for both a checkbox
  and its boolean). Suffix widgets: `includeCratesCheck`, `crateBox`, `scanButton`.
