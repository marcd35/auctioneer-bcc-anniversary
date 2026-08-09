# Burning Crusade Classic (BCC) Anniversary — Addon Development Reference

Blizzard builds Classic Anniversary expansions on top of the modern, upgraded retail engine (The War Within framework). This means the API landscape has been completely altered from original legacy TBC and includes modern features and restrictions.

---

## BCC Patch 2.5.6 — Critical Gotchas

Patch 2.5.6 (Anniversary season, ~July 2026) rebased the BCC client onto the modern retail engine. This silently broke a large number of addons and changed several fundamental assumptions. The most impactful issues:

### 1. `SetNormalTexture(nil)` Is Now a Hard Error

**Previously:** Passing `nil` to `SetNormalTexture()` (and similar frame API calls) was silently ignored.
**Now:** The modern C++ binding requires a non-nil string or file ID asset. Passing `nil` throws a Lua error immediately.

```lua
-- Before (broken in 2.5.6)
frame:SetNormalTexture(nil)

-- After (safe)
frame:SetNormalTexture("")
```

Affected subsystems include any addon that dynamically clears button icons or textures — e.g., `SlideBar`, `AutoMagic`, `SearchUI`, `SimpleAuction`, `Enchantrix`, `Configator`.

> Reference: [Blizzard 2.5.6 UI/API changes — Official Forums](https://us.forums.blizzard.com/en/wow/c/classic-wow/burning-crusade-classic/1032)

---

### 2. Seller Name Resolution Is Now Asynchronous (GUID Race Condition)

**Previously:** When an auction was created in the scan data, the seller name was typically available synchronously.
**Now:** GUID-to-name resolution is deferred. On the first scan pass, the seller field is frequently `""` (empty string). The real name may only resolve on a subsequent scan when the client has had time to look it up.

**Consequence:** Any ignore-list or seller-based filter that only runs at auction *creation* time will miss ignored sellers whose names haven't resolved yet.

**Fix:** Re-evaluate seller filters when the name resolves on a subsequent scan commit, and also check at query time (e.g., inside SearchUI results rendering) rather than only at scan ingestion.

> See: [`docs/Ignore_List_Bug_Analysis.md`](Ignore_List_Bug_Analysis.md) for the full root cause breakdown.

---

### 3. `CASTING_BAR_ALPHA_STEP` Global Was Removed

**Previously:** `Blizzard_AuctionUI.lua`'s `AuctionProgressFrame` fade-out relied on a global `CASTING_BAR_ALPHA_STEP` being present.
**Now:** This global no longer exists in the 2.5.6 environment. When posting multiple auction stacks, Blizzard's native `OnUpdate` script immediately hits:

```
attempt to perform arithmetic on global 'CASTING_BAR_ALPHA_STEP' (a nil value)
```

Because the alpha never reaches `0`, the frame never hides and the error fires on every game frame — an infinite loop with no user-visible way to stop it short of `/reload`.

**Fix:** Define the missing global as a fallback at the very top of your addon's earliest-loaded file, *outside* any event hooks or load handlers — before `Blizzard_AuctionUI` ever gets a chance to run:

```lua
CASTING_BAR_ALPHA_STEP = CASTING_BAR_ALPHA_STEP or 0.05
```

> See: [`docs/Multisell_Bug_Analysis.md`](Multisell_Bug_Analysis.md) for three attempted approaches and why only the early-global injection worked.

---

### 4. Stricter Per-Frame Execution Limits

The modern engine enforces tighter CPU limits per frame. Complex addons that previously completed large loops in a single `OnUpdate` (e.g., bulk scan commits) may now be killed mid-operation by the script watchdog.

**Symptom:** Silent data truncation or incomplete scan commits with no visible Lua error — the operation just silently stops partway through.

**Fix:** Yield across frames using `C_Timer.After(0, callback)` or Auctioneer's existing coroutine-based commit scheduler rather than unbounded `for` loops within a single frame.

---

### 5. Nameplate & Unit Frame API Overhaul

Nameplates and raid frames were replaced wholesale with modern retail equivalents. Any addon hooking into the old nameplate system (ThreatPlates, older ElvUI for Classic, etc.) will silently do nothing or throw errors.

This does **not** affect Auctioneer directly, but is worth knowing if debugging a cross-addon interaction or testing in an environment with many addons loaded.

> Reference: [r/classicwow — 2.5.6 addon breakage megathread](https://www.reddit.com/r/classicwow/)

---

## General Development Resources

### 1. Extract the Live Blizzard Interface Code

The single most accurate reference is the Blizzard Interface Code pulled directly from your own game client. Websites can fall behind, but extracted code tells you exactly what functions exist in your specific patch.

```
/console ExportInterfaceFiles code
```

A `BlizzardInterfaceCode` folder will appear in your main game directory containing the exact Lua and XML source Blizzard ships. Search it with VS Code to inspect function signatures, event payloads, and frame hierarchies.

### 2. In-Game API Explorer

Blizzard built a live API explorer into the modern engine client:

```
/api help
/api search <keyword>
```

Example: `/api search AuctionHouse` lists every registered function and table for that system on your current build.

### 3. Warcraft Wiki — API Portal

**Link:** [warcraft.wiki.gg/wiki/World_of_Warcraft_API](https://warcraft.wiki.gg/wiki/World_of_Warcraft_API)

When looking up functions, pay close attention to version tags. Avoid anything labeled "Legacy" or "Vanilla Archive". If a function has diverging Retail and Classic behavior, the wiki documents both.

**TOC format reference:** [warcraft.wiki.gg/wiki/TOC_format](https://warcraft.wiki.gg/wiki/TOC_format)

### 4. Lua 5.1 Reference Manual

**Link:** [lua.org/manual/5.1/](https://www.lua.org/manual/5.1/)

The BCC addon sandbox is restricted to Lua 5.1 behavior. No `goto`, use `unpack()` not `table.unpack()`, use the `bit` library for bitwise ops. See `.agents/AGENTS.md` for the full mandatory rule set.

### 5. Enable Script Errors While Testing

Script errors are off by default in modern clients. Enable them to catch syntax and argument mismatches while developing:

```
/console scriptErrors 1
```

### 6. Developer Communities

| Community | Link |
|-----------|------|
| Warcraft AddOn Development Discord | Primary hub for ElvUI, WeakAuras, etc. authors |
| Reddit | [r/wowaddondev](https://www.reddit.com/r/wowaddondev/) |
| Blizzard Forums | [UI & Macro — Classic](https://us.forums.blizzard.com/en/wow/c/classic-wow/ui-and-macro/251) |
