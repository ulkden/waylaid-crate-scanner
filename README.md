<p align="center"><img src="media/waylaid_crate_logo.svg" alt="Waylaid Crate Scanner logo" width="160"></p>

# Waylaid Crate Scanner (WoW: Forever)

Finds the cheapest way to fill Waylaid Crates and the cheapest **gold per Merchant's Favor**, then builds a shopping list you can buy straight from the Auction House.

- **My Crates** prices the crates in your bags.
- **AH Market** compares every crate type listed on the Auction House: the crate's price, the cost to fill it, and the total.

Each crate expands into its fill options, and crafted materials expand into their reagents, all the way down (Copper Modulator → Handful of Copper Bolts → Copper Bar → Copper Ore). Every material is priced both ways, bought or crafted, and the cheaper one is used at each step. So the cheapest fill can mix the two, for example crafting modulators from bought bolts and bars you smelt yourself.

## Install
Copy the `WaylaidCrateScanner` folder into `World of Warcraft/_forever_/Interface/AddOns/` and restart the game. From a clone: `make install WOW_ADDONS="<path to that AddOns folder>"`.

## Usage
1. **Open the window.** Use the **Crates** tab on the Auction House (it sits alongside Auctionator and other LibAHTab tabs), the minimap addon menu, or `/wcs`.
   - The first time, it opens beside the AH. After that it opens where you left it. Move it by the title bar and resize it from the bottom-right corner. Escape closes it.
   - Opened from the AH tab, it closes with the AH. Opened with `/wcs`, it stays open.
2. **Pick a mode** (**My Crates** or **AH Market**) and click **Scan Prices** / **Scan Market**. Scanning needs the AH open.
   - Items priced in the last 5 minutes are skipped. **Shift-click** to rescan everything.
   - A market scan searches 30 crates and 113 materials. The addon stays under Blizzard's limit of 100 AH searches per minute, so it pauses partway and takes about 2 minutes. The status line shows a countdown.
   - Prices last for the session. They survive a `/reload` and are cleared when you log in. With the AH closed, the window shows the last scan.

### My Crates columns
| Column | Material rows | Crate rows |
|---|---|---|
| Need | Units needed for this crate along this branch | |
| AH unit | Lowest listed unit price | |
| Per craft | Cost of the reagents for **one** craft (`/2` = one craft makes 2) | |
| Buy all | Buy all Need units, walking up the real listings (`*` = not enough listed) | Cheapest option bought outright |
| Craft all | Craft them, each reagent bought or crafted, whichever is cheaper | Cheapest option crafted the same way |
| Craft saves | Buy all minus Craft all (green `+` = crafting is cheaper, red `-` = buying is cheaper) | Same, for the crate |
| Favor | | Merchant's Favor the crate awards (`~` = estimated) |
| Gold / favor | On option rows: cost per favor using that option | Cheapest fill ÷ favor |

The footer totals your crates: cost buying only, cost with crafting, total favor and gold per favor.

### AH Market columns
| Column | Crate rows | Material rows |
|---|---|---|
| Qty | Crates listed on the AH | Units needed |
| Crate / unit | The crate's lowest AH price | Lowest unit price |
| Buy fill / Craft fill | Cheapest fill bought outright / crafted | Buy all / Craft all |
| Total | **Crate price + cheapest fill** | Cheaper of buy and craft |
| Favor | Merchant's Favor the crate awards | |
| Gold / favor | **(Crate price + cheapest fill) ÷ favor** | Same, using that option |

### Reading the table
- Both modes sort by **Gold / favor**, cheapest first. Click the name header or a sortable column header (Buy, Craft, Crate / unit, Total, Favor, Gold / favor) to sort by it. The active sort is green.
- The best-value crate is highlighted green and named in the footer. On each crate, green marks the cheapest option. Of buy and craft, the cheaper is bright and the other is dimmed.
- Click a row to expand or collapse it. Right-click or Ctrl-click expands or collapses everything below it. Shift-click links the item.
- Hover over a row for details: savings %, listed quantity, how many you have in your bags, the recipe, and how old the price is.

### Merchant's Favor
Favor depends on the crate's tier and quality. Gathering crates (ore, herbs, textiles, curiosities) are Common. Crafting crates (ingots, parts, fabrics) are Uncommon.

| Tier | Common | Uncommon | Source |
|---|---|---|---|
| Apprentice | 5 | 10 | confirmed |
| Journeyman | 10 | 20 | confirmed |
| Expert | 15 | 30 | player reports (shown with `~`) |
| Artisan | 20 | 40 | estimate from the pattern (shown with `~`) |

When you turn one in and see the real number, set it with `/wcs favor <tier> <common|uncommon> <amount>`, for example `/wcs favor artisan uncommon 40`. Use `clear` instead of a number to undo it. `/wcs favor` alone lists the current values.

### Buying materials
Each crate row and each of its option rows has a **Buy** button. It opens a shopping list:

- **Crates to fill**: how many crates to buy for. Defaults to how many you carry (My Crates) or 1 (AH Market).
- **Fill with**: the option to use. The cheapest is preselected, or the one whose row you clicked.
- **Craft where cheaper**: on = buy reagents and craft wherever that is cheaper, with the crafting steps listed in order (smelt bars, then bolts, then modulators). Off = buy the fill items outright.
- **Also buy the crates**: adds the crate itself to the list. On by default in AH Market mode.
- Each line shows **Need**, what you **Have**, and an editable **Buy** quantity with its estimated cost. Have counts your bags plus anything you bought on the AH that is still in your mailbox, so nothing is bought twice.

Click **Buy N** to get a live price quote. The button becomes **Confirm &lt;price&gt;**: click it to buy, or the X to cancel. The tooltip warns if the quote is more than 5% above the scanned estimate. Quotes expire after a short time, as in Blizzard's buy dialog. Purchases arrive in your mailbox. If the AH never answers a confirmed purchase, the addon gives up after 15 seconds and asks you to check your mailbox before buying again.

### Slash commands
| Command | What it does |
|---|---|
| `/wcs` or `/cratescanner` | Open or close the window |
| `/wcs favor …` | Show or correct Merchant's Favor values (see above) |
| `/wcs crates` | List the crates in your bags |
| `/wcs tooltip` | Print the tooltip lines of the crates in your bags |
| `/wcs reset` | Clear scanned prices |
| `/wcs debug` | Toggle debug messages |
| `/wcs help` | List the commands |

## Data
`Data.lua` is generated from Wowhead's WoW: Forever database. The generator looks up each crate by name to get its item ID, required level and the fill options on its tooltip. It then follows every material's "created by" recipe, using the real Forever yields (e.g. Smelt Bronze makes 2).

Regenerate it after a patch with `make data` (see [CONTRIBUTING.md](CONTRIBUTING.md#when-the-game-adds-or-changes-crates)). The generator reports crates whose options changed. In game, if a crate in your bags lists different quantities on its tooltip, the tooltip wins.

Vendor prices are used only for unlimited-stock reagents (Weak Flux, Salt, Coal), when they are cheaper than the AH or the item isn't listed. Turn this off with the **Vendor reagents** checkbox.

## Contributing
See [CONTRIBUTING.md](CONTRIBUTING.md) for setup, `make check` (lint, format check, tests) and the code layout.

## License
Copyright (C) 2026 ulkden. Licensed under the GNU General Public License v3.0; see [LICENSE](LICENSE).

Bundled third-party libraries in `WaylaidCrateScanner/Libs/` keep their own licenses: [LibAHTab](https://github.com/Auctionator/LibAHTab) (MIT, © plusmouse; see `Libs/LibAHTab/LICENSE`) and LibStub (public domain).
