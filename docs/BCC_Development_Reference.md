# Burning Crusade Classic (BCC) Anniversary Addon Development Reference

Blizzard builds Classic Anniversary expansions on top of the modern, upgraded retail engine (The War Within framework). This means the API landscape has been completely altered from original legacy TBC and includes modern features and restrictions.

Here is a curated list of the most up-to-date and reliable resources for BCC Anniversary addon development:

## 1. The Living Source: Extracting the Code Locally
The single most accurate reference is the Blizzard Interface Code pulled directly from your own game client. Websites can fall behind, but the extracted code tells you exactly what functions exist in your specific patch version.

*   Fire up BCC Anniversary, open your chat box, and run this command:
    `/console ExportInterfaceFiles code`
*   Check your main game directory (usually `_classic_era_` or `_classic_`). A new folder named `BlizzardInterfaceCode` will appear containing the exact Lua and XML source files Blizzard uses for the base UI. Search these files using VS Code to see how functions work or what arguments frame events pass.

## 2. In-Game API Documentation Tool
Blizzard built an official, live API explorer directly into the modern engine client. You can use it in-game to query functions, namespaces, and tables:
*   `/api help`
*   `/api search <keyword>` (e.g., `/api search Nameplate` will list every API function and table registered to the system live on your current build).

## 3. Warcraft Wiki (Fandom/Wiki.gg)
**Link:** [Warcraft Wiki API Portal](https://warcraft.wiki.gg/wiki/World_of_Warcraft_API)
When looking up functions, pay close attention to the version tags.
*   **Avoid** any documentation labeled "Legacy" or "Vanilla Archive".
*   Look for functions mapped to the modern or Classic portal. If a function has modern Retail behavior and a Classic behavior, the wiki explicitly documents the differences.

## 4. Lua 5.1 Reference Manual
**Link:** [Lua 5.1 Reference Manual](https://www.lua.org/manual/5.1/)
While the engine uses a custom hybrid Lua environment under the hood, the addon sandbox is heavily restricted to mimic **Lua 5.1** behavior to preserve legacy logic. Always reference the 5.1 manual for standard library functions (no `goto`, use `unpack()`, use the `bit` library for bitwise operations).

## 5. Debugging Tip: Enable Script Errors
When testing code, remember that `scriptErrors` are turned off by default in modern clients. Enable them globally in your chat frame so you can actively catch syntax or argument mismatches:
`/console scriptErrors 1`

## 6. Developer Communities
Because the modern engine moves quickly, documentation can sometimes lag. The most active groups tracking live changes are:
*   **Discord:** The Warcraft AddOn Development Discord (hub for creators of ElvUI, WeakAuras, etc.)
*   **Reddit:** [r/wowaddondev](https://www.reddit.com/r/wowaddondev/)
*   **Blizzard Forums:** Official UI & Macro Forums
