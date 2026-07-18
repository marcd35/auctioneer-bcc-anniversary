# Auctioneer Ignore List Bug Analysis

## Summary

The ignore list is broken in two complementary ways after patch 2.5.6. The root cause is that **seller name resolution became significantly more deferred** in 2.5.6 (due to the WoW client's GUID-to-name resolution now being asynchronous), which exposed a pre-existing design flaw in how the filter is applied.

---

## How the Ignore Filter Is Supposed to Work

The ignore filter is implemented in [BasicFilter.lua](file:///c:/Coding/auctioneer/AuctioneerSuite-Crusade-2.6.7/Auc-Filter-Basic/BasicFilter.lua):

1. User adds a name to `IgnoreList` / `IgnoreLookup`
2. During each scan, `lib.AuctionFilter(operation, itemData)` is called for each auction
3. If `itemData.sellerName` is found in `IgnoreLookup`, the auction is marked filtered (`FLAG_FILTER`)
4. Filtered auctions are stored in scan data but excluded from statistical processing and display

---

## Bug #1 — The Core Regression (Post-2.5.6)

### The Filter Only Runs at "create" Time

In [CoreScan.lua L632](file:///c:/Coding/auctioneer/AuctioneerSuite-Crusade-2.6.7/Auc-Advanced/CoreScan.lua#L632-L655):

```lua
if (operation == "create" and processors.Filter) then
    -- ... filter runs here
end
```

The `AuctionFilter` is **only evaluated when an auction is seen for the first time** (`operation == "create"`). Existing auctions use `"update"` or `"leave"` — the filter is never re-checked.

### Seller Names Are Now Frequently `""` on First Scan

`GetAuctionItemInfo()` returns `owner` (position 14) — the seller's name. Per the WoW API documentation:

> The "owner" field can be *nil*. This happens because the auction listing internally contains player GUIDs rather than names, and the WoW client does not query the server for names until `GetAuctionItemInfo()` is actually called for the item, and the result takes one RTT to arrive.

In patch **2.5.6**, the shared UI code update made this GUID-to-name resolution **fully asynchronous**, meaning `owner` returns `nil` far more consistently than before. As a result:

- `GetAuctionItem()` sets `itemData[Const.SELLER] = nil` (L2066 in CoreScan.lua)
- `GetAuctionItemFillIn()` replaces `nil` with `""` at L1975
- The scan does NOT retry for seller name resolution — only `CLASSID` is retried

### The Consequence: Ignored Sellers Pass Through Unfiltered

First scan after 2.5.6:
- Auction from "Badguy" → `owner = nil` → `SELLER = ""` → filter checks `IgnoreLookup[""]` → **no match** → stored in scan data as new ("create"), UNFILTERED

Subsequent scans:
- Same auction → `owner = "Badguy"` → but code path is "update", not "create" → **filter never runs**

At [CoreScan.lua L1413-1415](file:///c:/Coding/auctioneer/AuctioneerSuite-Crusade-2.6.7/Auc-Advanced/CoreScan.lua#L1413):
```lua
if data[Const.SELLER] == "" then -- unknown seller name in new data; copy the old name if it exists
    data[Const.SELLER] = oldItem[Const.SELLER]
end
```

Ironically, this code would *copy* an already-resolved name forward — but it never triggers the filter.

---

## Bug #2 — Pre-Existing Secondary Issue

Even before 2.5.6, the filter had a subtler weakness: once an ignored seller's auction is stored in the scan image (even without `FLAG_FILTER`), it persists until it expires. This is by design, but the combination with Bug #1 means ignored sellers' auctions are now permanently visible until they naturally expire (up to 48 hours).

---

## The Fix

### Fix Location: [BasicFilter.lua](file:///c:/Coding/auctioneer/AuctioneerSuite-Crusade-2.6.7/Auc-Filter-Basic/BasicFilter.lua)

The `AuctionFilter` function needs to also run on `"update"` and `"leave"` operations when the seller name is known:

```lua
function lib.AuctionFilter(operation, itemData)
    if not get("filter.basic.activated") then return end

    if itemData.quality < get("filter.basic.minquality") then
        return true
    end
    if itemData.itemLevel < get("filter.basic.minlevel") then
        return true
    end
    local seller = itemData.sellerName
    if seller and seller ~= "" then  -- only check seller if name is resolved
        if get("filter.basic.ignoreself") and seller == PLAYER_NAME then
            return true
        end
        if lib.IsPlayerIgnored(seller) then
            return true
        end
    end
end
```

**BUT** — `AuctionFilter` is only called by the scan engine for `operation == "create"`. So we also need to fix the scan engine to call filter modules on `"update"` and `"leave"` when the seller name has just been resolved. That is a bigger change in CoreScan.lua.

### Simpler Fix: Re-filter on Seller Name Resolution (CoreScan.lua Stage 3)

In [CoreScan.lua L1413-1415](file:///c:/Coding/auctioneer/AuctioneerSuite-Crusade-2.6.7/Auc-Advanced/CoreScan.lua#L1413), after copying the seller name from the old item, check if the newly-resolved seller should be filtered:

```lua
if data[Const.SELLER] == "" then
    data[Const.SELLER] = oldItem[Const.SELLER]
end
-- NEW: if seller was just resolved, re-run filter check
if data[Const.SELLER] ~= "" and bitand(data[Const.FLAG], Const.FLAG_FILTER) == 0 then
    -- Re-run the AuctionFilter for this existing auction with now-known seller
    -- (this mirrors the filter logic from processStats for "create")
    ...
end
```

### Recommended Fix: Two-Part Patch

**Part 1** — In `BasicFilter.lua`, extend `AuctionFilter` to also handle `"update"` and `"leave"` operations (not just `"create"`). This is the cleanest approach since the filter's own logic is self-contained.

**Part 2** — In `CoreScan.lua`, remove the restriction that limits filter execution to `"create"` only, OR add a specific re-filter call when seller name transitions from `""` to a real name.

---

## Files to Modify

| File | Change |
|------|--------|
| [BasicFilter.lua](file:///c:/Coding/auctioneer/AuctioneerSuite-Crusade-2.6.7/Auc-Filter-Basic/BasicFilter.lua) | Extend `AuctionFilter` to handle `"update"`/`"leave"` ops |
| [CoreScan.lua](file:///c:/Coding/auctioneer/AuctioneerSuite-Crusade-2.6.7/Auc-Advanced/CoreScan.lua) | Add re-filter logic when seller name resolves from `""` |

---

## Bug #3 — The SearchUI Defect

Even with the scan data correctly filtering out ignored sellers, the `SearchUI` module (`SearchMain.lua`) still showed ignored sellers in its search results. 

### Why this happened
When a user clicks "Search" in SearchUI, the addon queries the snapshot via `lib.SearchItem`. This function explicitly checks if the item belongs to the current player (`item[Const.SELLER] == UnitName("player")`), and it runs the item through SearchUI's local filters (ItemPrice, ItemQuality, etc.). However, **it lacked a check against the global BasicFilter ignore list**. So if a scan happened to store an ignored seller's auction before it was filtered (or if the user added the seller to the ignore list *after* the scan completed), SearchUI would display the item.

### The Fix
The fix adds a seller ignore check at the top of `lib.SearchItem` in `SearchMain.lua`, directly mirroring the pattern used in `Appraiser` and `CompactUI`.

```lua
if AucAdvanced.Modules.Filter and AucAdvanced.Modules.Filter.Basic and AucAdvanced.Modules.Filter.Basic.IsPlayerIgnored then
    if AucAdvanced.Modules.Filter.Basic.IsPlayerIgnored(item[Const.SELLER]) then
        return false, "Blocked: Seller is on ignore list"
    end
end
```

## Updated Files to Modify

| File | Change |
|------|--------|
| [BasicFilter.lua](file:///c:/Coding/auctioneer/AuctioneerSuite-Crusade-2.6.7/Auc-Filter-Basic/BasicFilter.lua) | Extend `AuctionFilter` to handle `"update"`/`"leave"` ops |
| [CoreScan.lua](file:///c:/Coding/auctioneer/AuctioneerSuite-Crusade-2.6.7/Auc-Advanced/CoreScan.lua) | Add re-filter logic when seller name resolves from `""` |
| [SearchMain.lua](file:///c:/Coding/auctioneer/AuctioneerSuite-Crusade-2.6.7/Auc-Advanced/Modules/Auc-Util-SearchUI/SearchMain.lua) | Add seller ignore check in `lib.SearchItem` to prevent ignored sellers from appearing in SearchUI results |
