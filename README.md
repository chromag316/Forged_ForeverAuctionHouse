# Forged Forever Auction House

There is no separate window. Everything is added to Blizzard's auction house UI,
one feature at a time.

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
  - The commodity and item auction lists on the Sell view (the auctions of the item
    you're posting) show it the same way.
  - Nothing is shown for items without a market value yet.

- **Sell view: % of value**: right of the Unit Price input on Blizzard's sell form
  (`SellInfo.lua`), the price you entered as a % of the item's market value (colored
  like the lists). Nothing is added to Blizzard's form itself (it posts auctions, a
  restricted call): the text is on the addon's own frame and only reads the form.
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
  - **Checked prices**: a scan's prices get old fast (cheap listings, vendor deals
    especially, are bought within minutes). When you open an item in Blizzard's buy view
    (from the Deals list or anywhere), its exact lowest price and quantity replace the
    scan's until the next scan sees the item; a deal that's gone drops off the lists.
    The sales, trend and volatility figures still come from scans only.
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
    when opened and after each scan (the refresh button recalculates from stored data;
    it doesn't ask the server). A row's tooltip says how old its price is ("Price from
    scan 6 min ago" or "Price checked just now"). Item names are stored with the market data; an
    item the client hasn't loaded yet shows as a gray `item:ID` until its name arrives,
    then the row updates by itself. Names are shown as in Blizzard's Buy list: items
    with a random suffix have their full name ("Birchwood Maul of the Eagle"), gear has
    its level, so each variant is its own row with its own name. Click a column header to sort by it (once
    ascending, again descending, with Blizzard's sort arrow); rows without a value go
    last, and each list (Resale, Vendor, …) keeps its own sort until you reload. The
    lists start in the strategy engine's ranking. The list looks like Blizzard's auction lists (same
    border, background, column header buttons, row stripes and highlight).
    - The tab is added the way LibAHTab (used by Auctionator) does it, which avoids
      taint: it isn't added to Blizzard's tab list. With Auctionator installed, it's
      created through LibAHTab so the tabs line up.
  - `/fah strategy` prints the top 5 of each in chat; `/fah strategy
    resale|vendor|disenchant|sell` one kind.
- **Market tab**: a "Market" tab after Deals, laid out like Blizzard's Sell view (its
  panels, backgrounds and borders sit exactly on the Sell view's). Search for an item
  with the search box, which is where the Buy view has its own (the only way to pick
  one; with several matches, click one in the list).
  - Left panel (where the Sell view has its item and price inputs): the item, then rows
    in four groups: price (lowest now and how many are listed, market value, today's
    lowest, volatility, the 24-hour trend), demand (below), the order book and the
    competition (below).
  - **Demand**:
    - Sales: estimated sold per day. "Sold" means listings that disappeared between
      scans, which includes auctions that expired or were cancelled, so it's an upper
      bound.
    - Sell-through: that as a share of what's listed now ("54% per day").
    - Days of supply: how long what's listed would last at that pace ("1.9 days"),
      marked green "(fast)" under 2 days and red "(slow)" over 14.
    - Data: what the figures rest on: completed scans since the item was first seen
      (scan times are kept for 3 days) and days of data ("6 scans, 2.0 days").
  - Right panel (where the Sell view lists auctions, same background): a 30-day graph
    of the daily lowest price (gold), daily highest (gray), the market value (blue)
    and estimated sales per day (gray bars), with price and day labels. The refresh
    button above it asks the server for the item's listings again.
  - **Order book**: when an item is shown, the tab asks the server for its listings
    (the same search Blizzard's buy view sends; waits for the rate limit, not while a
    scan runs) and shows:
    - how many are listed below market value and what buying them all costs;
    - the wall: the first price with at least 10% (and 20+) of the listed quantity,
      where a new listing would end up;
    - how old the order book is (bottom left).
    Opening the item in Blizzard's buy view updates it too. Gear: the item level the
    lists use. Kept for the session only.
  - **Competition** (from the same search):
    - Sellers, you included: for stackable items "4 to 23 at 17 prices" (the server
      sends one row per price, which says how many sellers it has but names only some,
      so it's a range: at least the most sellers in one row, at most all rows' sellers
      added up; one number when it's exact), for other items "4 (17 auctions)";
    - Your listings: how many you have at your lowest price, and whether that's the
      cheapest (green; a tie counts) or undercut (red) by how many of others' units;
    - Supply: the quantity listed now vs. the average over the last 7 days, with the
      difference in %. The average is time-weighted (a quantity counts for as long as it
      was listed) and uses daily averages for days older than 3; with less than 7
      days of data it covers what there is (the Sales row shows how many days).
  - **Timing** (the right panel's "Timing" header; "Price History" switches back):
    - 7-day and 30-day average of the daily lowest price, with today's price vs. it
      ("50c (now +20%)"; "over 3 days" while there's less data than the period).
    - The lowest price by time of day (3-hour blocks, your local time) and by day of
      week, as bars around the item's usual level: green below it (a time to buy),
      red above (a time to sell); faint with fewer than 2 scans behind them. Below:
      when it's cheapest and when the most is listed.
    - Collected by every scan (starting with the version that added it): the price relative to the market
      value (so a trend doesn't look like a time pattern) and the quantity, per item.
      Older scans count less (half every 10 days); nothing older than 30 days.
  - **Profit after costs** (under the graph):
    - Flip margin: buying at the lowest price and reselling at market value, after the
      5% cut, per unit and in % of the buy price (green a profit, red a loss).
    - Deposit: per unit, from the client's own calculation for the duration Blizzard's
      sell view has selected. Stackable items by item; other items only while you
      have one in your bags. With sales data, the expected loss: the deposit is
      refunded on a sale, so what's lost is the deposit times the chance the auction
      doesn't sell within the duration (from the sell-through rate).
    - Break-even buy: the most you can pay to resell at market value, after the cut
      and the expected deposit loss.
    - Vendor: what a vendor pays for it (a floor) and sells it for (a ceiling; learned
      at merchants).
    - Disenchant: the expected value of the materials, for disenchantable gear.
  - **Ledger tab**: a "Ledger" tab after Market, built like the Deals list, with your
    own results (for all your characters on the realm and faction; kept 90 days):
    - Sales: sold for (after the 5% cut), cost and profit. The cost is first in, first
      out: a sale uses up your oldest purchases of the item made before it; units with
      no purchase behind them (farmed, crafted, bought before the Ledger) have no cost
      or profit (the tooltip says how many).
    - Purchases: paid each and in all, and how many are still unsold.
    - Unsold stock: what you bought and haven't sold, its cost and what it's worth at
      today's market value after the cut. Purchases unsold after 90 days are dropped.
    - Expired: expired and cancelled auctions, with an estimate of the deposit lost
      (the deposit for the sell view's selected duration).
    - The bottom bar: the last 30 days' sales, profit and spending, and the unsold
      stock's cost. Click a row to open the item in Blizzard's buy view.
    - Recorded: purchases when they go through in Blizzard's buy views (stackable items
      when the server confirms, other items when a buyout completes; bids aren't
      purchases); sales from the "Auction successful" mails and expired or cancelled
      auctions from their mails, read when you open your mailbox (a sale whose mail you
      never open isn't seen). Nothing is bought, posted or taken from the mail.
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
- **Tests** (`tests/`, needs Node.js): `cd tests`, `npm install` once, then `npm test`.
  It checks that every file in the .toc parses (Lua 5.1, well-formed XML) and uses
  no unknown globals (the allowed WoW globals are listed in `tests/check.js`; add new
  ones there), then runs the specs in `tests/spec/` in a Lua 5.1 interpreter
  (fengari) with stubs for the client. `npm test history tabs` runs only those
  specs. The tests can't replace checking in game: layout, taint and the real
  server aren't covered. The `tests` folder isn't needed in the installed addon.
- Blizzard's Forever UI source: [Gethe/wow-ui-source, branch `forever`](https://github.com/Gethe/wow-ui-source/tree/forever/Interface/AddOns/Blizzard_AuctionHouseUI).

## Credits

Based on [aux](https://github.com/shirsig/aux-addon) by shirsig and the Turtle WoW fork
[OldManAlpha/aux-addon](https://github.com/OldManAlpha/aux-addon), via Forged Auction House.
