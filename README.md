# Forged Forever Auction House

Adds features from [Forged Auction House](../Forged_AuctionHouse) (a fork of aux for
1.12) to Blizzard's own auction house window in **World of Warcraft: Forever**
(interface 16001).

There is no separate window. Everything is added to Blizzard's auction house UI,
one feature at a time. See [TODO.md](TODO.md) for the features still to come.

## Install

Copy the `Forged_ForeverAuctionHouse` folder to
`World of Warcraft\_forever_\Interface\AddOns\`. Restart the client (a new addon
folder needs a full restart) and enable the addon at character select.

## Status

Features so far:

- **Price history**: while you use Blizzard's auction house, the lowest unit buyout of
  every item that appears in a search is recorded for the day. That covers browse
  results, and the individual auctions when you open an item. At midnight the day's
  minimum becomes a data point (up to 11 are kept). An item's **value** is the weighted
  median of those points, newer days weighing more (as in aux). Data is kept per realm
  and faction.
  - `/fah value <item>`: shift-click an item (or give an item ID) to see its value,
    today's minimum and days of history.
  - `/fah history`: how many items are recorded; `/fah history clear` clears them.
- **Full Scan**: a button at the bottom right of Blizzard's Buy view. It searches the
  whole auction house (an empty search) and loads every page as fast as the server's
  rate limit allows. Price history records every item's lowest price, and the pages
  show up in Blizzard's results list as they arrive. Progress is shown next to the
  button, and a summary is printed in chat when it ends.
  - It stops when the list is complete, when you click **Stop Scan**, open an item,
    start your own search or change tabs, or when the auction house closes.
  - A scan only gives the lowest price per item, not every auction. Forever's
    `ReplicateItems` ("get all") does nothing, so a paged search is the only way.
- **Tooltip lines**: price lines on every item tooltip: label on the left, price on
  the right, in the tooltip's standard font and Blizzard's coins. Prices are for one
  item, also when the tooltip is for a stack.
  - **Vendor**: Blizzard's own "Sell Price:" line, relabeled "Vendor:" with one
    item's sell price on the right (on by default).
  - **Market**: historical value from price history (on by default).
  - **Today**: today's lowest price and its % of the market value.
  - **Vendor Buy**: vendor buy price, learned when you open a merchant window
    ("limited" if the merchant's stock is limited).
  - **Disenchant**: expected disenchant value, from the outcome chances and the
    dusts', essences' and shards' prices.
  - **Disenchants into**: the possible outcomes with chances and amounts.
  - `/fah tooltip` lists the lines with their on/off state; `/fah tooltip <line>`
    toggles one (`sell price` for the Vendor relabel, `market`, `daily`,
    `vendor buy`, `disenchant value`, `disenchant distribution`).

- **% of market value in Blizzard's lists**: each price in the auction house lists also
  shows its percentage of the item's market value (price history), colored as in aux:
  blue under 50%, green under 80%, yellow under 110%, orange under 135%, red above.
  - Browse results: the lowest price, shown in the left part of the Price column.
  - Commodity auctions: the unit price, shown right after the price, right-aligned so
    the numbers line up, in the same font as the quantity numbers.
  - Item auctions: the buyout per item, shown the same way right after the buyout price.
  - Nothing is shown for items without a market value yet.
  - `/fah percent` turns it on or off.
  - **Experimental: sortable % column.** `/fah percent column` (then `/reload`) adds a
    "%" column right after Price in the browse results. Click its header to sort by %
    (low to high, high to low, back to the server's order). Pages that arrive later are
    sorted in; a new search or a click on one of Blizzard's headers ends the % sort.
    Off by default: it writes into Blizzard's own table and results, which can make the
    client block buying ("Interface action failed because of an AddOn"). If buying
    fails, turn it off again with `/fah percent column` and `/reload`.

## Development notes

- Forever uses the modern `C_AuctionHouse` API and Lua 5.1, not the 1.12 API.
- Blizzard's UI (`Blizzard_AuctionHouseUI`) is load-on-demand. Features hook it on
  the `AUCTION_UI_LOADED` message from `Core.lua`.
- Hook Blizzard's frames with `hooksecurefunc` / `HookScript` only. Replacing its
  functions, or showing and hiding its panels from addon code, taints them.
- Buying, bidding, posting and cancelling are restricted calls and must come from
  a click.
- Use the client's default look: Blizzard templates and font objects, no custom themes.
- Blizzard's Forever UI source: [Gethe/wow-ui-source, branch `forever`](https://github.com/Gethe/wow-ui-source/tree/forever/Interface/AddOns/Blizzard_AuctionHouseUI).

## Credits

Based on [aux](https://github.com/shirsig/aux-addon) by shirsig and the Turtle WoW fork
[OldManAlpha/aux-addon](https://github.com/OldManAlpha/aux-addon), via Forged Auction House.
