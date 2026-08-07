# Relearn Moves

Lets any POKéMON relearn moves from its species movelist (level-up learnset
plus level-1 moves) once it has reached the required level.

## How to try it

1. Open the party menu (START > POKéMON) outside of battle.
2. Select a POKéMON, then pick **RELEARN** — it sits at the bottom of the
   list, after SWITCH (SWITCH keeps the second slot).
3. Choose a move. A free moveset slot learns it right away; a full moveset
   asks which move to forget (HM moves can't be forgotten, same as the
   level-up flow — unless the QoL Toggles mod's **FORGETTABLE HMs** toggle
   is on, which unlocks them here too).

The option never appears in battle. A mon with nothing left to relearn at
its current level reads "No moves to relearn." instead of hiding the row.

If the QoL Toggles mod (`qol_toggles`) is installed, its **FORGETTABLE HMs**
toggle is honored by the forget list: OFF keeps HM moves locked (the
default when QoL Toggles isn't installed), ON lets them be replaced like
any other move.

## Development

1. `POKEPORT_DEV=1 love .` once, leave it running
2. edit, press F5 to hot-reload, backtick for the dev console
3. `python3 tools/modkit.py validate relearn_moves` before sharing
4. `python3 tools/modkit.py pack mods/relearn_moves` to ship
