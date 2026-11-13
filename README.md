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
  show up in Blizzard's results list as they arrive. Progress is shown at the bottom,
  right after your money, and the end message is also printed in chat.
  - While starting: `Rate limited. Waiting before starting...` (the server's rate
    limit isn't ready yet), then `Waiting for server response...` until the first page.
  - Progress: `Scanning... (1,180 of ~1,830 items)`. The total is an estimate from the
    last completed scan on this realm and faction (the server doesn't say how many items
    a search returns); before the first completed scan it shows
    `Scanning... (1,180 items)`.
  - End messages: `Scan complete: 4,210 items (95s)` (auto scan),
    `Full scan complete: 4,210 items (95s)`, `Stopped by user: 1,180 items (30s)`,
    `Stopped: New search started`, `Stopped: Left the Buy view`,
    `Stopped: Server timeout`, `Stopped: Server error`.
  - It stops when the list is complete, when you click **Stop Scan**, open an item,
    start your own search or change tabs, or when the auction house closes.
  - **Auto scan**: a scan also starts by itself shortly after the auction house opens
    on the Buy view. Opening an item or going to Sell or Auctions pauses it, and it
    starts over when you're back on the Buy view (prices already recorded are kept).
    Your own search, Stop, a server error or timeout, or one completed auto scan end
    auto scanning until you open the auction house again.
  - The **Auto scan** checkbox left of the Full Scan button turns it on or off (on by
    default, saved). Turning it on takes effect the next time you open the auction
    house; turning it off also stops a running auto scan.
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

- **Strategy engine**: market statistics and profitable suggestions from your scans.
  - Every scan stores, per item, the lowest price and quantity available (only when
    something changed). After a completed scan, items that disappeared get quantity 0.
    Detail is kept for 3 days, then folded into daily summaries kept for 30 days.
  - Per item it works out the current price and quantity, the market value, estimated
    sales per day (quantity drops between scans; at least 6 hours of data), the price
    trend (last 24 hours vs. the two days before) and volatility.
  - Suggestions, all after the 5% auction house cut (the deposit is refunded when an
    auction sells, so it's only a cost for listings that don't):
    - **Resale**: listed at least 10% below what relisting at market value earns, and
      selling at least every two days; ranked by expected profit per day.
    - **Vendor**: listed below what a vendor pays.
    - **Disenchant**: gear listed below its expected disenchant value.
    - **Sell from bags**: your items with a price just under the lowest listing (or the
      market value), expected proceeds, and whether the market is high or rising.
  - **Deals tab**: a "Deals" tab after Blizzard's Buy/Sell/Auctions tabs. A market summary
    (items tracked, listed, with sales data, time of the last full scan) shows in the
    window's bottom bar, and the panel shows the suggestions as a list: pick Resale, Vendor, Disenchant or Sell from
    bags with the tabs above the list (styled and placed like Blizzard's Auctions/Bids tabs); hover a row for the item tooltip, click it to open the item in Blizzard's buy view
    (Sell from bags rows open Blizzard's sell view with the item in it). All suggestions are in one scrolling list
    with a scroll bar, like Blizzard's Buy list (mouse wheel or drag the bar). It refreshes
    when opened and after each scan. The list looks like Blizzard's auction lists (same
    border, background, column header buttons, row stripes and highlight).
    - The tab is added the way LibAHTab (used by Auctionator) does it, which avoids
      taint: it isn't added to Blizzard's tab list. With Auctionator installed, it's
      created through LibAHTab so the tabs line up.
  - `/fah strategy` prints the top 5 of each in chat; `/fah strategy
    resale|vendor|disenchant|sell` one kind.
- **Market tab**: a "Market" tab after Deals. Search for an item (the search box is the
  only way to pick one; with several matches, click one in the list). It shows:
  - the lowest price now and how many are listed, the market value and today's lowest;
  - volatility, sales velocity (estimated sold per day), the 24-hour trend and how many
    days of data there are;
  - a 30-day graph: daily lowest price (gold), daily highest (gray), the market value
    (blue) and estimated sales per day (gray bars), with price and day labels.
  - Only items a scan has seen can be found. The graph uses the daily summaries for
    older days and the scan detail for the last 3; between changes the last price
    carries over.
  - Added the same taint-free way as the Deals tab (`Tabs.lua`).

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
