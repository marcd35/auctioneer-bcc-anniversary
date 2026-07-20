# Multisell Bug Analysis (CASTING_BAR_ALPHA_STEP)

## The Issue

When posting multiple stacks of an auction using Auctioneer's Appraiser, users encountered an infinitely repeating Lua error:
`attempt to perform arithmetic on global 'CASTING_BAR_ALPHA_STEP' (a nil value)`
This error would increment indefinitely and prevent the user from performing other UI actions without reloading the UI.

## Root Cause

The root cause lies in how the Burning Crusade Classic (BCC) client implements the native multiple-auction posting UI (`Blizzard_AuctionUI`).
When posting multiple auctions natively, Blizzard uses a progress bar frame called `AuctionProgressFrame`.
When the final auction is posted, the frame attempts to fade out by setting `self.fadeOut = true`.
In its `OnUpdate` handler, the Blizzard code expects to decrement the frame's alpha value by `CASTING_BAR_ALPHA_STEP`:

```lua
-- Paraphrased Blizzard_AuctionUI.lua code
if self.fadeOut then
    local alpha = self:GetAlpha() - CASTING_BAR_ALPHA_STEP;
    self:SetAlpha(alpha);
end
```

However, in the BCC client (which runs on a modern client backend), the global variable `CASTING_BAR_ALPHA_STEP` was either removed or inadvertently excluded from the UI environment. As a result, the arithmetic operation fails because `CASTING_BAR_ALPHA_STEP` is `nil`. Because the alpha never reaches `0`, the frame never hides itself, causing the `OnUpdate` script to run continuously and generate the error on every frame.

## The Fix

### Attempt 1: Early Global Injection

Our initial fix attempted to inject the missing global variable into the environment when Auctioneer hooked into the `Blizzard_AuctionUI` addon via `Stubby.RegisterAddOnHook` in `CoreMain.lua`.

**Why it failed:**
The timing of the `HookAH` execution and Blizzard's taint sandbox prevented the global assignment from taking effect within the execution context of Blizzard's `AuctionProgressFrame:OnUpdate` script.

### Attempt 2: Coordinated Interception (Failed)
To ensure the fix ran in the correct context, we attempted a three-layer fix intercepting `AUCTION_MULTISELL_UPDATE` and hooking `AuctionProgressFrame:HookScript("OnUpdate", ...)` when `blizzard_auctionui` loads.

**Why it failed:**
The error originates within Blizzard's secure `Blizzard_AuctionUI.lua` code. Using `HookScript` from an addon only attaches *additional* code to run alongside or after the original script. It cannot prevent Blizzard's native `OnUpdate` script from executing and crashing when it hits the nil arithmetic, regardless of how we attempt to catch it dynamically.

### Attempt 3: Earliest Global Fallback (Successful)
The only way to definitively prevent the native Blizzard code from crashing is to ensure the global variable exists in the environment *before* the Blizzard UI ever has a chance to execute. 

The fix was applied by defining the missing global at the very top of `Auc-Advanced\CoreMain.lua`, entirely outside of any event hooks or load handlers:
```lua
CASTING_BAR_ALPHA_STEP = CASTING_BAR_ALPHA_STEP or 0.05
```
Because `Auc-Advanced` is loaded by the client during the initial login sequence (before the user opens the Auction House and triggers the load-on-demand `Blizzard_AuctionUI`), this guarantees the global variable is securely initialized and available for Blizzard's native scripts.
