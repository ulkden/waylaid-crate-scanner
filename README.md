<p align="center"><img src="media/waylaid_crate_logo.svg" alt="Waylaid Crate Scanner logo" width="160"></p>

# Waylaid Crate Scanner (WoW: Forever)

A resizable scanner window that finds the cheapest way to fill Waylaid Crates and the cheapest **gold per Merchant's Favor**. Open it from the Auction House **Crates** tab (it docks beside the AH and stays open while you use the Buy tab), from the minimap addon menu, or with `/wcs`. Scans run while the Auction House is open. With the AH closed, the window shows the prices scanned this session (they survive a `/reload` and are cleared when you log in).

Two modes:

- **My Crates**: prices the Waylaid Crates in your bags.
- **AH Market**: compares every Waylaid Crate type listed on the Auction House. It shows the crate's own price, the cost to fill it by buying or by crafting, and the total.

Every crate expands into a tree of fill options. Crafted materials expand further into their reagents, recursively (e.g. Copper Modulator → Handful of Copper Bolts → Copper Bar → Copper Ore).

## Install
Copy the `WaylaidCrateScanner` folder into `World of Warcraft/_forever_/Interface/AddOns/`, then `/reload`. (From a clone on macOS: `make install`.)

## Usage
1. Open the Auction House and click the **Crates** tab. It shares the tab strip with Auctionator and any other addon that uses LibAHTab. The scanner window opens beside the AH. You can move it by its title bar and resize it from the bottom-right corner; position and size are saved. Escape closes it.
2. Choose **My Crates** or **AH Market**, then click **Scan Prices** / **Scan Market**.
   - Items priced in the last 5 minutes are skipped. **Shift-click** to rescan everything.
   - A market scan searches 30 crates + 113 materials. Blizzard allows 100 AH searches per minute, so it pauses partway and takes about 2 minutes. The status line shows a countdown.

### My Crates columns
| Column | Material rows | Crate rows |
|---|---|---|
| Need | Units needed for this crate along this branch | |
| AH unit | Lowest listed unit price | |
| Per craft | Sum of the reagents for **one** craft (`/2` = one craft makes 2) | |
| Buy all | Buy all Need units from the AH, walking up the real listings (`*` = not enough listed) | Cheapest option bought outright |
| Craft all | Craft them, each reagent bought or crafted, whichever is cheaper | Cheapest option crafted yourself |
| Craft saves | Buy all minus Craft all (green `+` = crafting cheaper, red `-` = buying cheaper) | Same, for the crate |
| Favor | | Merchant's Favor the crate awards (`~` = estimated) |
| Gold / favor | On option rows: cost per favor using that option | Cheapest fill ÷ favor |

### AH Market columns
| Column | Crate rows | Material rows |
|---|---|---|
| Qty | Crates listed on the AH | Units needed |
| Crate / unit | The crate's own lowest AH price | Lowest unit price |
| Buy fill / Craft fill | Cheapest fill bought outright / crafted | Buy all / craft all |
| Total | **Crate price + cheapest fill** | Cheaper of buy/craft |
| Favor | Merchant's Favor the crate awards | |
| Gold / favor | **(crate price + cheapest fill) ÷ favor** | Same, using that option |

Both modes sort by **Gold / favor** (cheapest first) by default. Click a column header (or the name header) to sort by it; the active sort column is shown in green. The best-value crate is highlighted green and named in the footer.

### Merchant's Favor
Favor depends on crate tier and quality. Gathering crates (ore, herbs, textiles, curiosities) are Common; crafting crates (ingots, parts, fabrics) are Uncommon:

| Tier | Common | Uncommon | Source |
|---|---|---|---|
| Apprentice | 5 | 10 | confirmed |
| Journeyman | 10 | 20 | confirmed |
| Expert | 15 | 30 | player reports (shown with `~`) |
| Artisan | 20 | 40 | estimate from the pattern (shown with `~`) |

When you turn one in and see the real number, set it with `/wcs favor <tier> <common|uncommon> <amount>`, e.g. `/wcs favor artisan uncommon 40`. Undo with `clear` instead of a number. `/wcs favor` alone lists the current values.

Of the two routes, the cheaper one is shown bright and the other dimmed. Green marks the cheapest option. Click a row to expand or collapse it. Right-click expands or collapses everything below it. Shift-click links the item. Hover over a row for details: savings %, listed quantity, how many you have in your bags, and price age.

### Buying materials
Every crate row, and each of its fill-option rows, has a **Buy** button that opens a shopping list:

- **Crates to fill**: how many crates to buy materials for (defaults to how many you carry in My Crates mode, 1 in AH Market mode).
- **Fill with**: choose the option; the cheapest is preselected (or the one whose row you clicked).
- **Craft where cheaper**: on = buy reagents and craft intermediates wherever that's cheaper; off = buy the fill items outright. The crafting steps are listed in order (e.g. smelt bars, then bolts, then modulators).
- **Also buy the crates**: adds the crate itself to the list (on by default in AH Market mode).
- Each line shows Need, what you already **Have** in your bags (used first), and an editable **Buy** quantity with its estimated cost.

Click **Buy N** to get a live price quote from the Auction House. The button then becomes **Confirm &lt;price&gt;**: click it to purchase, or the X to cancel. If the quote is more than 5% above the scanned estimate, the tooltip warns you. Quotes expire after a short time, like Blizzard's own buy dialog. Only stackable (commodity) items can be bought this way, which covers crates and all fill materials.

### Slash commands
`/wcs` (toggle the window) · `/wcs favor …` · `/wcs crates` (list crates in your bags) · `/wcs tooltip` (print crate tooltip lines) · `/wcs debug` · `/wcs reset` (clear cached prices)

## Data
`Data.lua` is generated from Wowhead's WoW: Forever database. The generator looks up each crate by name to get its item ID, required level and the fill options on its tooltip. It then follows every material's "created by" recipes, using the real Forever yields (e.g. Smelt Bronze makes 2).

Regenerate after a patch with `make data` (see [CONTRIBUTING.md](CONTRIBUTING.md#when-the-game-adds-or-changes-crates)). It reports any crate whose options changed. In game, a crate in your bags whose tooltip shows different quantities overrides the data automatically.

Vendor prices are used only for unlimited-stock reagents (Weak Flux, Salt, Coal). You can toggle this with the "Vendor reagents" checkbox in the window.

## Contributing
See [CONTRIBUTING.md](CONTRIBUTING.md) for setup, `make check` (lint, format check, tests) and the code layout.

## License
Copyright (C) 2026 ulkden. Licensed under the GNU General Public License v3.0; see [LICENSE](LICENSE).

Bundled third-party libraries in `WaylaidCrateScanner/Libs/` keep their own licenses: [LibAHTab](https://github.com/Auctionator/LibAHTab) (MIT, © plusmouse; see `Libs/LibAHTab/LICENSE`) and LibStub (public domain).
