# TODO

## 1. Scanning

1. ~~**Auto scan when the auction house opens.**~~ Done (`FullScan.lua`, on by default;
   the checkbox comes with item 4). Start a scan when Blizzard's window
   opens, but only while you're idle on the Buy view: no search of your own showing,
   not in an item, Sell or Auctions view. Pause there and resume when you come back
   to the Buy view (a scan replaces Blizzard's results list and shares the server's
   rate limit with Blizzard's own requests).
2. ~~**Move the scan status text** to the left of where it is now.~~ Done: it now starts
   right after Blizzard's money display, left-aligned, with room left of the Full Scan
   button for the checkbox.
3. ~~**Status text:**~~ Done.
   - Before the first query, while the rate limit isn't ready:
     `Rate limited. Waiting before starting...`; after it's sent:
     `Waiting for server response...`.
   - Progress: `Scanning... (1,180 of ~1,830 items)`. The total is an estimate: the server
     doesn't say how many items a search will return, so use the item count of the
     last completed scan, saved per realm and faction. If a scan finds more items
     than the estimate, raise the estimate with it.
   - With no completed scan yet: `Scanning... (1,180 items)`.
   - End messages (item counts with thousands separators, time in seconds):
     1. `Scan complete: 4,210 items (95s)`: an auto scan finished.
     2. `Full scan complete: 4,210 items (95s)`: a scan started with the
        Full Scan button finished.
     3. `Stopped by user: 1,180 items (30s)`: Stop was clicked.
     4. `Stopped: New search started`: you searched, opened favorites or picked a
        category.
     5. `Stopped: Server timeout`: no page arrived for 20 seconds.
     6. `Stopped: Server error`: the server reported a browse failure.
   - A completed scan's count becomes the next estimate.
   - A Full Scan stopped because you opened an item or changed tabs:
     `Stopped: Left the Buy view`. An auto scan pauses there without a message.
4. ~~**"Auto scan" checkbox**~~ Done: at the bottom of the Buy view, left of the Full
   Scan button (Blizzard checkbox template). It turns item 1 on or off; the setting is
   saved. Turning it on takes effect the next time the auction house opens; turning it
   off also stops a running auto scan (a Full Scan keeps going).
5. **The button keeps its "Full Scan" label.**

## 2. Strategy engine and sales proposals

1. ~~**Strategy engine**~~ Done (`Market.lua`, `Strategy.lua`; `/fah strategy` until the
   tab exists). Decided: all four suggestion types; detail kept 3 days, daily
   summaries 30 days. Based on the history data from the scans.
   - Needs more than today's one lowest price per item per day: store per-scan
     snapshots (time, lowest price, quantity available per item) to get price
     trends, estimated sales (quantity disappearing between scans) and volatility.
   - To decide: a retention rule (e.g. detail for a few days, then daily summaries),
     and which suggestions count as "profitable": resale (buy below market value,
     relist at market value after the 5% auction cut and deposit), vendor (buy below
     vendor sell price), disenchant (buy below expected disenchant value), and what
     to sell from your bags.
2. ~~**New tab**~~ Done (`StrategyTab.lua`, added the way LibAHTab does it), named
   **Deals**. In Blizzard's auction house window, next to Buy, Sell and Auctions.
   Its panel shows market statistics and suggests the most profitable buy and sell
   orders for the current market.
   - First check how Auctionator adds tabs to this window on Forever: adding a tab
     and display mode to Blizzard's frame can block buying ("Interface action failed
     because of an AddOn") if done the wrong way.

3. ~~**Market tab**~~ Done (`MarketTab.lua`; tabs shared via `Tabs.lua`): another tab in
   Blizzard's auction house window, after Deals. For one
   item it shows:
   - the 30-day price history, preferably as a graph (daily lowest and highest price
     from Market.lua's daily summaries, plus the last 3 days of scan snapshots in
     detail);
   - volatility;
   - sales velocity (estimated sales per day).
   - Data: Market.lua already keeps daily summaries for 30 days and snapshots for 3
     days; the market value line can come from the price history.
   - Graph: drawn with the client's own line/texture widgets (no library), in the
     default look.
   - The item is picked with a search box in the tab (only).

4. ~~**Deals list: click an item to buy it.**~~ Done and confirmed in game (buying works).
   `StrategyTab.OpenInBuyView` calls `AuctionHouseFrame:SelectBrowseResult`; Sell from bags
   rows open Blizzard's sell view instead (`OpenInSellView`, `AuctionHouseFrame:SetPostItem`).
   Clicking a row takes you to Blizzard's buy panel for that item (the commodity or item
   buy view, as if you'd clicked it in Blizzard's browse results).

## 3. Deals list improvements

1. ~~**Sort by clicking the column headers**~~ Done (`StrategyTab.SortBy`). Rows
   without a value go last; ties keep the engine's ranking; each list keeps its own
   sort for the session. Sort by clicking the column headers in the Deals lists (Item, Buy at, Sell at /
   Vendor pays / Disenchant, Profit, Return, Sold/day, …): click once for ascending,
   again for descending, with Blizzard's sort arrow on the header. The headers are
   Blizzard's AuctionHouseTableHeaderStringTemplate buttons, currently display only.

## 4. Market tab: trader stats

What a trader wants on top of today's lowest price, value, volatility, sales/day,
trend and graph: what it really costs to buy, how fast it really sells, and what's
left after costs. In order; 1-4 mostly use data already collected.

1. ~~**Order book**~~ Done (`OrderBook.lua`; two lines in the Market tab; the tab
   sends the item's search itself). From the item's commodity/item search:
   - cost to buy N (e.g. 20 / 100 / 200): total and average unit price;
   - units listed below market value, and what buying all of them costs;
   - the "wall": the first price level with a large quantity (where your own
     listing would sit).
2. **Competition:**
   - number of sellers and auctions (search results carry the owners);
   - your own listings: count, price, cheapest or undercut and by how much
     (search results flag your own items);
   - supply now vs. the 7-day average (low supply: sell; a flood: buy).
3. **Demand you can trust:**
   - sell-through (estimated sold / listed per day);
   - days of supply (listed / sales per day; under ~2 fast, over ~14 slow);
   - confidence: number of scans and days behind the figures, and the price's age.
     Note that a disappeared listing may have expired or been cancelled, not sold.
4. **Profit after costs:**
   - flip margin: lowest price to market value, minus the 5% cut;
   - deposit (from the client's deposit calculation) and the expected deposit loss
     from the sell-through rate;
   - break-even buy price;
   - floor and ceiling: vendor sell price, vendor buy price, disenchant value.
5. **Timing** (needs new data: hourly / weekday averages kept for 30 days, today
   only 3 days of detail):
   - price and supply by time of day and day of week: when to buy, when to sell;
   - 7-day and 30-day averages next to today's price.
6. **Your own results** (biggest new piece: track purchases, sale mails and own
   auctions): what you paid, what you sold for, realized profit, unsold stock.

Forever-specific:
- Random-suffix gear ("of the Eagle" vs. "of the Monkey") sells at very different
  prices: show one variant, ideally with a comparison of the item's variants.
- Progression-style content unlocks swing prices: a long-term trend or before/after
  view helps.
- Many items have little history: showing data confidence matters.
