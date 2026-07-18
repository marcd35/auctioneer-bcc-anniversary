# Agent Rules for Auctioneer Crusade

<RULE[Lua_5_1_Compatibility]>
**CRITICAL**: World of Warcraft Burning Crusade Classic (BCC) uses a **hybrid/modified Lua environment** built on top of the modern retail engine. While it utilizes backported elements from newer Lua versions internally, Blizzard deliberately restricts the addon API to mimic **Lua 5.1** behavior to prevent breaking legacy logic.

You MUST ensure all standard code you write is treated as Lua 5.1 compatible.

Specifically:
- **NO `goto` statements**: `goto` and labels (`::label::`) are not supported in the addon sandbox and will cause immediate parsing errors. Use standard boolean flags and conditional logic instead.
- **NO `table.unpack()`**: Use `unpack()`.
- **NO native bitwise operators**: (`&`, `|`, `~`, `<<`, `>>`). WoW provides the `bit` library (`bit.band`, `bit.bor`, etc.) for bitwise operations.
- **NO `_ENV`**: The `_ENV` variable does not exist. Environments are manipulated via `setfenv` and `getfenv`.
- **"Taint" Sandbox**: Be aware of Blizzard's secure/insecure code execution environment, which heavily alters standard Lua behavior regarding global environments and function hooks.
</RULE[Lua_5_1_Compatibility]>
