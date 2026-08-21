# Copilot instructions — relearn_moves

Lua mod for the Pokémon Gen 1/Gen 2 Recompilation (gen1recomp), a LÖVE2D port
of Pokémon Red/Blue/Yellow and Gold. It adds a **RELEARN** option to the field
party-menu submenu so a mon can relearn any move from its species movelist it
has reached the level for. See `README.md` for the feature, `CHANGELOG.md` for
history.

## Build, test, and lint

There is no test framework — the headless suite is a plain Lua script using
the `tests.modkit` SDK (`T.eq`, `T.check`, `T.finish`). All commands run from
the **engine checkout** (`~/dev/gen1recomp`), because they require the
engine's `src/` tree and `tools/modkit.py`.

```sh
# Run the headless test suite (the only test file — this IS the single test):
# from the engine checkout, with POKEPORT_DATA_DIR set so no ROM is needed.
POKEPORT_DATA_DIR=tests/fixture_data luajit mods/relearn_moves/tests/relearn_moves_test.lua
# If this repository is not installed under engine/mods, pass its relative
# path instead; the test derives the mod path from its own filename.
POKEPORT_DATA_DIR=tests/fixture_data luajit ../../Downloads/relearn_moves-main/tests/relearn_moves_test.lua

# Validate the mod through the real loader (ROM-free fixture base):
python3 tools/modkit.py validate mods/relearn_moves --base fixture
#   MK103 ("could not check ids") is expected with --base fixture — the
#   fixture only carries FIX_* content; ids resolve against real data in-game.

# Lint (no ROM-derived bytes in the shipped mod):
python3 tools/modkit.py lint mods/relearn_moves

# Pack an installable zip (tests/ excluded via .modkitignore):
python3 tools/modkit.py pack mods/relearn_moves
```

Dev game loop (from README): `POKEPORT_DEV=1 love .`, edit + F5 hot-reload,
backtick for the dev console.

**Source-of-truth gotcha:** tests and validation resolve `mods/relearn_moves`
relative to the engine checkout's CWD. Keep this repository canonical; either
sync it into that path or invoke the headless test with this repository's
relative path as shown above.

## Architecture

- **Entry point:** `main.lua` returns `function(mod) ... end`, invoked by the
  engine loader (`src/mods/Loader.lua`) at boot. The mod object gives access
  to `mod.hooks:wrap`, `mod.content.<registry>` (registries freeze after
  load — no runtime patching), and `mod.exports` (observable by tests).
  Requires `"permissions": ["engine_internals"]` in `manifest.json` (already
  set) for the shared string/sound helpers; drawing uses the public `mod.ui`
  facade.
- **Submenu injection:** the `ui.party.submenu` hook receives the vanilla item
  list after it is built on both generations. Hook-injected entries carry an
  `onSelect` callback instead of an action id, so the vanilla update loop
  handles them. RELEARN is appended after SWITCH, guarded by `ctx.battle`
  (battle submenu stays vanilla), and is always present out of battle for
  discoverability.
- **The learn flow** is a screen (`MoveRelearn`) registered via
  `mod.content.screens:register("MoveRelearn", { new = ... })`, pushed over
  the still-open party menu with `mod.ui.push(game, "MoveRelearn", selMon)`.
  `mod.ui.TextBox`, `mod.ui.Font`, and `mod.ui.Theme` provide the shared UI
  facade. It pops itself with `game.stack:pop()` and pushes a `TextBox` message.
- **Pure logic layer** is exported via `mod.exports` so the headless suite can
  exercise it without a live game: `buildRelearnable` (Gen 1's level-1 moves
  plus `learnset`, or Gold's ordered `levelMoves`, at or below level, deduped,
  minus known moves), `applyMove` (learn into an open slot or replace slot
  1-4, full base PP), `injectSubmenu`, `tickerOffset` (marquee pacing), and
  the generation-specific HM sets.
- **Data model:** Gen 1 carries `level1Moves` plus `learnset`; Gold carries
  ordered `levelMoves` rows (`{level, move}`), including level-1 moves. Moves
  live in `game.data.moves[id]` with `name` and `pp`. A mon's moves are
  `{id, pp}` slots; Gold also tracks `maxPp`, which relearned moves receive.

## Conventions

- **Pure functions first:** put testable logic in module-level functions
  exported via `mod.exports`; keep screen `update`/`draw` thin and
  side-effect-free where possible.
- **Screen contract:** `new(game, ...)` returns a metatabled instance with
  `update(dt)` and `draw()`. Only the top stack state updates — push a
  `TextBox`/`ChoiceBox` to block input rather than polling underneath. Poll
  input via `game.input:wasPressed(...)` only inside `update` (edges promote
  at the fixed step; a press in `new` is not visible until the next frame).
- **Coordinates:** everything draws on a 160×144 GB-pixel canvas (20×18 grid
  of 8px tiles). `Font.draw` takes **pixel** coords; `Font.drawBox` takes
  **tile** coords — mixing them is the classic bug. Measure text with
  `Font.width(text)`, never `#text * 8`.
- **Draw hygiene:** opaque screens fill 160×144 white first, then
  `setColor(0, 0, 0, 1)` for text, and restore `setColor(1, 1, 1, 1)` at the
  end of `draw` (every engine widget does).
- **Ticker (marquee):** the learned-at level prefix stays fixed at the row's
  left edge; an overflowing move name scrolls inside its own clip window via
  `love.graphics.setScissor`. Pacing is `TICKER_HOLD = 1.6`s and
  `TICKER_SPEED = 16`px/s, cycling hold → scroll out → hold → scroll back;
  `tickerOffset(t, overflow)` is the pure implementation.
- **HM moves** (CUT, FLY, SURF, STRENGTH, FLASH, plus Gold's WATERFALL and
  WHIRLPOOL) can't be forgotten — the same gate the engine's level-up flow
  applies (IsMoveHM).
- **Localizable text:** use `Strings("...")` for player-facing strings, not
  raw literals.
- **Testing style:** seed real move/species records into `Data.moves` /
  `Data.pokemon` *before* `T.sdk.loadMod(...)` — the fixture only carries
  FIX_* content. Drive screens with a stub `game.input.wasPressed` returning
  a scripted key sequence (one key consumed per `update` call, polled in
  up/down/b/a order). Assert against exported pure functions for logic, and
  through the registered screen for flows.
- **Versioning:** cutting a release = bump `manifest.json` `version` and the
  matching `CHANGELOG.md` heading, then push to `main` — the workflow in
  `.github/workflows/release.yml` publishes the zip. Version resolution
  order: workflow_dispatch input → `[release X.Y.Z]` in the commit message →
  manifest ahead of tags → patch bump. `.md` and `.github/**` pushes are
  skipped by `paths-ignore`, so a docs-only push won't ship.
