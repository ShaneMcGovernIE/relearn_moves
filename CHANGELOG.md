# Changelog

## [1.4.0] - 2026-08-07

### Added

- The forget list now honors the QoL Toggles mod's **FORGETTABLE HMs**
  toggle (new optional dependency). When that toggle is ON, HM moves can be
  forgotten from the relearn screen just like any other move; OFF (or the
  mod absent) keeps them locked. The toggle is read the same way QoL
  Toggles itself reads it, so a fresh install with the toggle untouched
  (default ON) matches its level-up forget flow.

## [1.3.0] - 2026-08-07

### Changed

- RELEARN moves to the bottom of the field party-menu submenu, after
  SWITCH. SWITCH keeps the second slot; RELEARN is appended regardless of
  the engine's row ordering.

## [1.2.0] - 2026-08-06

### Added

- Sound effects on the relearn screens: a Press_AB click for cursor moves
  and accept, plus the Get_Item2 chime on a successful relearn, matching
  the vanilla party-menu feel.
- PP display: learned PP right-aligned in the relearn list, and current PP
  beside each move in the forget list (the box widened two tiles to fit).
- A more-arrow (▼) on the relearn list's bottom border when moves scroll
  below the visible window.
- Hold-to-scroll on Up/Down in both the relearn and forget lists (16-frame
  delay, then repeat every 4 frames at 60 fps).
- The HM forget-gate is now data-driven off `constants.hmMoves`, falling
  back to the vanilla five when data is absent.

### Changed

- The RELEARN submenu entry anchors on the STATS row instead of a fixed
  index, so it stays between STATS and SWITCH even if the engine reorders
  rows.
- Relearn rows follow the engine's layout: "LV" + digits with no gap, the
  move name right after the level, and a gap before the right-aligned PP
  so ticking names never run into it.

### Fixed

- Hold-to-scroll crashed in-game ("attempt to compare nil with number"):
  the key-repeat pacing constants were declared after the function that
  used them, so they resolved as nil globals. They are now declared before
  use, with a regression test covering the hold path.

## [1.1.2] - 2026-08-03

### Changed

- The name ticker is slower: scroll speed 24 to 16 px/s, and each end
  hold 1.2 to 1.6 seconds.

## [1.1.1] - 2026-08-03

### Fixed

- The relearn-list ticker scrolls only the move name now. The learned-at
  level stays fixed at the row's left edge; the name ticks inside its own
  clip window.

## [1.1.0] - 2026-08-03

### Added

- Move names that overflow the relearn list box now scroll as a ticker:
  hold at the start, scroll to the end, hold, scroll back. The marquee is
  clipped to the row so it never bleeds over the box border; short names
  draw statically.

## [1.0.1] - 2026-08-03

### Fixed

- RELEARN now always shows in the field party-menu submenu. It was gated
  on having a relearnable move, so a mon that had never forgotten a move
  hid the entry entirely (reported as "not showing"); such a mon now reads
  "No moves to relearn." in the flow screen.

## [1.0.0] - 2026-08-03

### Added

- RELEARN entry in the field party-menu submenu, between STATS and SWITCH.
- Relearn flow: a mon can learn any move from its species movelist at or
  below its current level, minus what it already knows.
- Open-slot learning (move added with full base PP) and a forget list for
  full movesets (HM moves stay locked, matching the level-up flow).
- Battle never offers RELEARN; the battle submenu is untouched.
