# Contributing to Outgrown: Forever

This covers how the addon is put together, how to tune it and how to test changes. For what the addon does, see [README.md](README.md).

---

## Files

The `.toc` loads the files in this order. They share data through the addon's namespace table (`local _, ns = ...`); nothing is global.

| File           | Exposes      | Holds                                                                                     |
| -------------- | ------------ | ----------------------------------------------------------------------------------------- |
| `Strings.lua`  | `ns.L`       | Every piece of text shown to the player.                                                  |
| `Data.lua`     | `ns.Data`    | Every number used for grading. No logic.                                                  |
| `Grading.lua`  | `ns.Grading` | Reading items, spec detection, scoring, grades and upgrade checks. No UI.                 |
| `Outgrown.lua` |              | Glows, tooltip lines, the login message, hooks and events. Asks `ns.Grading` for answers. |

Keep it that way: text goes in `Strings.lua`, numbers in `Data.lua`, and `Grading.lua` never touches frames.

---

## How grading works

### Spec and weights

`Grading.RefreshRole()` finds the talent points spent per tree and takes the tree with the most, once at least `D.MIN_TALENT_POINTS` are spent. It tries three ways of reading talents, in order:

1. **Classic functions** (`GetNumTalentTabs`, `GetTalentInfo`, `GetTalentTabInfo`), for other clients. Forever has removed these.
2. **Specializations** (`C_SpecializationInfo.GetSpecializationInfo`, 7th return value = points spent). On Forever this currently returns a stub with no name and 0 points.
3. **The trait system** (`C_ClassTalents.GetActiveConfigID`, `C_Traits`), which is what Forever uses. All three Classic trees live in one trait tree, and `C_Traits.GetGroupDisplayInfoByTreeID` lists them as named display groups (`displayName` "Holy", `groupID`, `orderIndex`). Each talent node has a list of `groupIDs`; its first entry is a small sub-group, and the tree it belongs to appears further down the list. So a talent counts toward a tree when that tree's `groupID` appears anywhere in the node's `groupIDs`. Trees are matched to `D.CLASS_SPECS` by `displayName`, falling back to `orderIndex`. If no display groups are available, the code falls back to grouping by separate trees, first group, sub-tree, or horizontal position.

Set `D.DEBUG_SPEC = true` to log which method was used, the raw trait structure and how many points each group has. The log is kept in the saved variable `OutgrownForeverDB.log`, which the game writes to `WTF\Account\<account>\SavedVariables\Outgrown.lua` on `/reload` or logout. Repeat checks with the same result are only logged once.

Talent data can arrive after login, so the spec is re-checked on `PLAYER_ENTERING_WORLD`, `SPELLS_CHANGED`, talent events and whenever the character window opens. `D.CLASS_SPECS` maps each tree to a spec key (`PALADIN_RETRIBUTION`) and a role (`melee_str`). Before that, `D.DEFAULT_ROLE` is used.

The weights used for scoring are the role's `D.WEIGHTS`, with the spec's `D.SPEC_WEIGHTS` applied on top. Spec entries only list what differs from the role.

### Reading an item

`ParseItem` collects stat values from two sources, so nothing is counted twice:

- `GetItemStats` for base stats, armor and weapon DPS. These keys don't depend on the client's language.
- Tooltip lines starting with `Equip:`, matched against `D.EQUIP_PATTERNS`. An `Equip:` line that matches nothing, or any `Use:` or `Chance on hit:` line, marks the item as `unrated`.

Parsed items are cached by item link.

### Scoring an equipped item

- **Score:** each stat times its weight, summed. Weapon DPS is scaled by `D.DPS_SLOT_FACTOR` for the slot it's in.
- **Baseline:** what a typical green item for that slot would score at the player's level: `level × D.BUDGET_PER_LEVEL × slot budget × D.ROLE_EFFICIENCY`, plus expected weapon DPS where it counts, plus the armor expected from the best armor type the class can wear.
- **Grade:** `score / baseline` against `D.THRESHOLDS`. Once flagged, an item must climb `buffer` above the cut-off to clear, so grades don't flicker.

Special cases, in `GradeSlot`:

- Weapons the class can't use are always red.
- Below `D.GRACE_LEVEL`, and for items with no required level, nothing is graded.
- `unrated` items get the milder of the score grade and the required-level grade (`D.LEVEL_FALLBACK`).

### Upgrades

`Grading.IsUpgrade(link, levelAhead)` compares an item with what's equipped in the slot it would use. It must beat it by `D.UPGRADE_MARGIN`, be wearable (armor type, shields, relics, weapon type), and not require more than `levelAhead` levels above the player. With `D.UPGRADE_KEEP_ARMOR_TYPE` on, armor below the class's best type is never suggested, unless the equipped item in that slot is already below it (or the slot is empty); then anything at least as good as the equipped type counts. Cloaks are exempt.

Slot rules: rings and trinkets check both slots; a two-hander must beat main hand plus off-hand; nothing goes in the off hand next to a two-hander; one-handers only count for the off hand with dual wield; an `unrated` equipped item is never claimed to be beaten.

## Tuning

Everything lives in `Data.lua`.

| Symptom                             | Change                                                                                                                   |
| ----------------------------------- | ------------------------------------------------------------------------------------------------------------------------ |
| Grades too harsh or lenient overall | `D.THRESHOLDS`                                                                                                           |
| A spec values a stat wrongly        | its entry in `D.SPEC_WEIGHTS`                                                                                            |
| One slot type grades oddly          | that slot in `D.SLOT_BUDGET`                                                                                             |
| Weapons grade oddly                 | `D.EXPECTED_DPS`                                                                                                         |
| Wrong spec detected                 | turn on `D.DEBUG_SPEC` to see what was read; check tree order in `D.CLASS_SPECS`; or set `D.SPEC_OVERRIDE` while testing |
| Too many or too few upgrades        | `D.UPGRADE_MARGIN`                                                                                                       |
| An "Equip:" effect isn't recognised | add a pattern to `D.EQUIP_PATTERNS`, most specific first                                                                 |

`D.SHOW_DETAILS = true` shows the grey score line in tooltips, which is the quickest way to check a change.

## Common changes

- **New player-facing text:** add it to `Strings.lua` as `L.SOMETHING`, then use `L.SOMETHING` in `Outgrown.lua`.
- **A new stat:** add its key to the relevant `D.WEIGHTS` / `D.SPEC_WEIGHTS` entries, and either a `STAT_KEYS` entry in `Grading.lua` (from `GetItemStats`) or a pattern in `D.EQUIP_PATTERNS` (from the tooltip).
- **Translating:** copy `Strings.lua` and translate the values. On non-English clients, `D.EQUIP_PATTERNS` and the `Equip:` / `Use:` / `Chance on hit:` markers in `Grading.lua` need translating too.

## Client differences

Forever runs on the modern client, but the code is written to survive API differences:

- New APIs are tried first with the old global as a fallback, e.g. `C_Item.GetItemInfo` then `GetItemInfo`.
- Calls that may not exist or may error are wrapped in `pcall`, including `GetInventorySlotInfo` for slots like `RangedSlot`.
- Events that may not exist are registered with `pcall`.
- Bag code supports both the modern combined bag (`EnumerateValidItems`) and classic `ContainerFrameNItemM` buttons.
- Quest reward code checks each place reward buttons can live: `MapQuestInfoRewardsFrame` (the quest log in the world map, used by Forever), `QuestInfoRewardsFrame` (the quest giver window and pop-out quest log), and the older `QuestInfoItemN` / `QuestLogItemN` buttons. Each knows whether to read links with `GetQuestLogItemLink` or `GetQuestItemLink`.

Follow the same pattern for anything new.

## Testing

- Turn on Lua errors with `/console scriptErrors 1`, or use an error-catching addon like BugSack.
- Changes to `.lua` files load with `/reload`. Changes to the `.toc`, including new files, need a full game restart.
- If the addon shows as "Incompatible", set `## Interface:` in the `.toc` to the number printed by `/dump select(4, GetBuildInfo())`.
- Check grades on characters of different classes and specs, with `D.SHOW_DETAILS` on.
