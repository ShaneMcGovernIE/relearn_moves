# Changelog

## [Unreleased]

### Fixed

- Key-repeat (hold-to-scroll) crashed with "attempt to compare nil with
  number" in the real game: `REPEAT_DELAY`/`REPEAT_RATE` were declared
  after `navRepeat`, so the function read them as nil globals.  They are
  now declared before the function.  Headless stubs never hit this path,
  so a regression test now drives the `input.isDown` branch directly.

### Added

- Sound effects: cursor/A-accept click (Press_AB), the Get_Item2 chime on a
  successful relearn, matching the vanilla party-menu feel.
- The relearn list shows each move's learned PP ("PP%2d", right-aligned);
  the forget list shows the current moves' PP too.
- A more-arrow (▼) on the relearn list's bottom border when there are moves
  below the visible window.
- Hold-to-scroll on Up/Down in both the relearn list and the forget list
  (ListMenu key-repeat pacing: 16-frame delay, then every 4 frames).
- The HM forget-gate is now data-driven off `constants.hmMoves`, so a mod
  or imported dataset that extends the HM set gates here too. Falls back to
  the vanilla five when data is absent.

### Changed

- The RELEARN submenu entry now anchors on the STATS row instead of a fixed
  index, so it stays between STATS and SWITCH even if the engine reorders
  rows (a missing anchor appends at the end).
- The forget-list box is two tiles wider to make room for the PP column;
  the relearn name clip window narrows to 6 glyphs accordingly.

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
