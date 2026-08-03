# Changelog

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
