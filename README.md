# Auctioneer Suite - Crusade

This repository is a fork of [MentalPower's original Auctioneer addon](https://www.curseforge.com/wow/addons/auctioneer), which has amassed over 33 million downloads. It uses crediar's ["Crusade" version](https://www.curseforge.com/wow/addons/auctioneer-crusade) as a starting point.

## Fixes & Updates

This fork specifically addresses bugs introduced with the World of Warcraft Burning Crusade Classic 2.5.6 patch changes.

### Fixed Bugs

- **Cancel Button** - Fixed cancel button in SearchUI below "Clear" button
- **Cancel Button Queue Status Text** - Fixed a UI layout issue where the queued quantity and cost text was incorrectly placed outside of the "Cancel" button, it now appropriately replaces the "Cancel" text.
- **SearchUI Stale Data** - Fixed a bug where clicking the "Rescan" button would return stale auctions (auctions that were no longer on the AH). The UI now properly filters out auctions flagged as unseen by the scan engine.
- **Single Item Posting** - Fixed bug where posting a BoE item with a base + suffix would sometimes return an error "you do not have enough items to do that"
- **Stale Queries** - Attempting to perform a refresh query via SearchUI now properly discards any stale/suspended search results.
- **Posting Multiple Stacks Error**: Fixed an infinite loop error (`attempt to perform arithmetic on global 'CASTING_BAR_ALPHA_STEP'`) when posting multiple stacks of an item. This was caused by a missing global variable in the Burning Crusade Classic (BCC) Auction UI, which has now been properly injected. For a detailed technical breakdown, please see the [Multisell Bug Analysis](docs/Multisell_Bug_Analysis.md) document.
- **CoreScan Image Count Discrepancy**: Fixed a race condition where actively removing an auction via the UI (e.g., buying or canceling an auction) while a background scan commit was in progress would cause auctions to be skipped and permanently dropped from the database, resulting in a count discrepancy error.
- **Ignore List Filtering**: Fixed issues where the seller ignore list failed to hide auctions from ignored players. In patch 2.5.6, seller name (GUID-to-name) resolution became asynchronous, meaning the first time an auction is scanned, the seller name is often empty. Because the ignore filter previously only ran during the initial creation of an auction in the scan data, ignored sellers were slipping through unfiltered. The filter now correctly re-evaluates auctions when the seller name is resolved on subsequent scans. Additionally, SearchUI was updated to actively check the ignore list during search queries, ensuring previously cached auctions from newly-ignored sellers are not displayed. For a detailed technical breakdown, please see the [Ignore List Bug Analysis](docs/Ignore_List_Bug_Analysis.md) document.
- **SearchUI Purchase Column Index Regression**: Fixed a bug where adding the `Δ Pct` column to the results grid shifted all subsequent column indices, causing incorrect data (e.g., the item stack count) to be read as the bid price. This produced a "Price cannot be less than the minimum bid" error on any purchase attempt. All hardcoded column index references and the `OnClickSheet` column modulo were corrected.
- **Stale Bid Price Silent Failure**: Fixed a bug where a queued bid attempt would fail silently if another player had outbid the queued price between the last scan and the purchase attempt. The error message now includes both the queued bid amount and the current minimum required, and the Vendor searcher is automatically re-run to refresh results.

### New Features

- **SearchUI Ignore Seller Button**: Added an "Ignore Seller" button directly into the SearchUI interface, allowing users to easily ignore sellers without having to manually add their names to the ignore list in the addon configuration.
- **SearchUI Identify Seller Buttons**: Added `? Row` and `? All` buttons to the SearchUI interface. These buttons perform live Auction House queries for items with blank seller names (a common occurrence due to asynchronous name resolution in BCC). `? Row` queries the currently selected auction, while `? All` automatically queues and scans through all missing sellers in the search results sequentially. Both buttons intelligently handle server throttling and multi-page query results.
- **Buy/Bid Delta Filter**: Added a new filter and column (`Δ Pct`) to the SearchUI results grid. This allows users to view the percentage difference between the buyout price and current bid price, and optionally filter out auctions based on a minimum and/or maximum delta threshold. This feature is particularly useful for identifying arbitrage opportunities where a low bid on a high-value buyout item can yield significant profit.
