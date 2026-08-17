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
- **Random Enchantment Item Fix**: Fixed failed bid errors on random enchantment items
- **SetNormalTexture C++ API Binding Fix**: Fixed `bad argument #2 to '?' (Usage: self:SetNormalTexture(asset))` errors when setting or clearing button icons. Modern WoW API C++ bindings require a non-nil string or file ID asset parameter, whereas legacy Lua allowed `nil` or omitted parameters. Updated `SetNormalTexture` calls across `StatHistogram`, `SlideBar`, `AutoMagic`, `SearchUI`, `SimpleAuction`, `Enchantrix`, and `Configator` to pass non-nil fallback values.
- **CompactUI Icon Display Fix**: Fixed an issue in `CompactUI` where each auction item icon displayed a smaller inner square border (`UI-Quickslot2`) and disappeared when hovered. Removed the redundant normal texture border overlay and prevented the icon texture from un-anchoring and moving off-screen during `OnEnter`/`OnLeave`.

### New Features

- **SearchUI Ignore Seller Button**: Added an "Ignore Seller" button directly into the SearchUI interface, allowing users to easily ignore sellers without having to manually add their names to the ignore list in the addon configuration.
- **SearchUI Identify Seller Buttons**: Added `? Row` and `? All` buttons to the SearchUI interface. These buttons perform live Auction House queries for items with blank seller names (a common occurrence due to asynchronous name resolution in BCC). `? Row` queries the currently selected auction, while `? All` automatically queues and scans through all missing sellers in the search results sequentially. Both buttons intelligently handle server throttling and multi-page query results.
- **Buy/Bid Delta Filter**: Added a new filter and column (`Δ Pct`) to the SearchUI results grid. This allows users to view the percentage difference between the buyout price and current bid price, and optionally filter out auctions based on a minimum and/or maximum delta threshold. This feature is particularly useful for identifying arbitrage opportunities where a low bid on a high-value buyout item can yield significant profit.
- **SearchUI TimeLeft Filter Refactor**: Improved the TimeLeft filter to allow more granular control. Replaced the "Filter if more than" dropdown with two separate dropdowns: a qualifier (Less than, Less than and equal to, Equal to, Greater than, Greater than and equal to) and a time option (30min, 2hr, 12hr, 48hr).
- **Vendor Max Buyout Price**: Added new "Max Buyout Price" input box to Vendor tab which filters out auctions exceeding the input price.
- **Data Maintenance and DataPruner**: Reorganized Auctioneer's settings with a dedicated **Data Maintenance** parent category containing the existing ScanData controls and the new DataPruner utility. DataPruner can preview Stat-Simple price outliers in a non-destructive dry run, report results in chat, and prune matching historical records after confirmation. It also supports targeted item pruning or complete history removal through an item drop slot or Alt-click workflow. Back up your SavedVariables before permanently pruning or wiping data.

---

## For Developers

### Attribution Chain

This repository sits at the end of a chain of contributors. When making changes, it is important that original authorship is preserved and that your own contributions are attributed correctly.

| Role | Name |
|------|------|
| Original Author | [Norganna's AddOns](http://auctioneeraddon.com/) |
| Crusade Fork | [crediar](https://www.curseforge.com/wow/addons/auctioneer-crusade) |
| BCC Anniversary Fork | [marcd35](https://github.com/marcd35/auctioneer-bcc-anniversary) |

### Header & Version Rules

- **Do not change `## Author:`** — this always reflects the original upstream author (`Norganna's AddOns`).
- **Use `## X-Maintainer:` for fork attribution** — add or update this field in the relevant `.toc` file(s) with your username. Do not embed your name inside the `## Version:` string.
- **Version strings must be plain numbers only** — strings like `2.6.8 (marcd35)` are non-standard. Use `2.6.8` only.
- **Only bump versions for modules you actually changed** — don't sweep-update unmodified modules.

For the full versioning policy (when to bump patch vs. minor, which files to update, etc.) see [`docs/Versioning_Guide.md`](docs/Versioning_Guide.md).

For the official `.toc` metadata field specification, see the **WoW TOC Format reference** on the community wiki:
https://warcraft.wiki.gg/wiki/TOC_format
