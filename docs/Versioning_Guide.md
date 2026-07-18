# Versioning Guide for Auctioneer Crusade Fork

Since this repository is a fork of crediar's Auctioneer Crusade (which itself is based on MentalPower's original addon), it is important to establish a clear versioning strategy. This ensures users know they have our custom bug fixes, prevents conflicts with any official updates, and makes debugging easier.

## 1. The Addon Version Number (`## Version:`)

The base version we started with is **`2.6.7 (crediar)`**.

For this fork, we recommend **Semantic Versioning with a Fork Suffix**. This makes it immediately obvious to the user that they are using a community-maintained fork rather than the original author's release.

**Recommended Format:** `<Major>.<Minor>.<Patch>`

### When to bump:

- **Patch (+0.0.1):** When you apply bug fixes (like the 2.5.6 ignore list fix). _e.g., 2.6.8, 2.6.9_
- **Minor (+0.1.0):** When you add new features (e.g., a new scanning module or UI enhancement). _e.g., 2.7.0_
- **Major (+1.0.0):** Only if there is a massive overhaul of the architecture.

## 2. The Game Patch Number (`## Interface:`)

The `.toc` file contains an `Interface:` field (currently `20505`), which tells the WoW client which game patch the addon is built for.

- You should **only update this number** when Blizzard releases a new game patch (e.g., moving from 2.5.5 to 2.5.6) AND you have verified the addon works on that new patch.
- Updating this stops the game from marking the addon as "Out of Date."

## 3. How to Apply a Version Bump

When you are ready to release a new version of this fork, you need to update the version strings across the suite. Auctioneer is broken into many sub-modules, and they typically all share the version number.

### Files to Update:

1.  **`.toc` Files:** Search the repository for `## Version: 2.6.7 (crediar)` and replace it with your new version string (e.g., `## Version: 2.6.8 (anniversary)`).
    - _Key files: `Auc-Advanced\Auc-Advanced.toc`, `BeanCounter\BeanCounter.toc`, `Enchantrix\Enchantrix.toc`, etc._
2.  **Lua Core Files:** Some core files embed the version string for chat printouts.
    - _Check `Auc-Advanced\CoreMain.lua` (e.g., `Auctioneer loaded (version %s)`)._
3.  **`README.md`:** Update any references to the version number so users downloading the zip know what they are getting.

## Summary Checklist for a Release

- [ ] Determine the new version number (e.g., `2.6.8 (anniversary)`).
- [ ] Do a global find-and-replace in all `.toc` files for the old version string.
- [ ] Update the `## Interface:` number if the release coincides with a new WoW patch.
- [ ] Update the `README.md` and commit the changes with a tag (e.g., `git tag v2.6.8-anniversary`).
