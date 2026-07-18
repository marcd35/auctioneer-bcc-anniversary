# Auctioneer Suite - Crusade

This repository is a fork of [MentalPower's original Auctioneer addon](https://www.curseforge.com/wow/addons/auctioneer), which has amassed over 33 million downloads. It uses crediar's ["Crusade" version](https://www.curseforge.com/wow/addons/auctioneer-crusade) as a starting point.

## Fixes & Updates

This fork specifically addresses bugs introduced with the World of Warcraft Burning Crusade Classic 2.5.6 patch changes.

### Fixed Bugs

- **Ignore List Filtering**: Fixed issues where the seller ignore list failed to hide auctions from ignored players. In patch 2.5.6, seller name (GUID-to-name) resolution became asynchronous, meaning the first time an auction is scanned, the seller name is often empty. Because the ignore filter previously only ran during the initial creation of an auction in the scan data, ignored sellers were slipping through unfiltered. The filter now correctly re-evaluates auctions when the seller name is resolved on subsequent scans. Additionally, SearchUI was updated to actively check the ignore list during search queries, ensuring previously cached auctions from newly-ignored sellers are not displayed. For a detailed technical breakdown, please see the [Ignore List Bug Analysis](docs/Ignore_List_Bug_Analysis.md) document.

### New Features

- **SearchUI Ignore Seller Button**: Added an "Ignore Seller" button directly into the SearchUI interface, allowing users to easily ignore sellers without having to manually add their names to the ignore list in the addon configuration.
- **SearchUI Identify Seller Buttons**: Added `? Row` and `? All` buttons to the SearchUI interface. These buttons perform live Auction House queries for items with blank seller names (a common occurrence due to asynchronous name resolution in BCC). `? Row` queries the currently selected auction, while `? All` automatically queues and scans through all missing sellers in the search results sequentially. Both buttons intelligently handle server throttling and multi-page query results.
