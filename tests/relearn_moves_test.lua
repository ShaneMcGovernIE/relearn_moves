-- relearn_moves headless test: run with
-- POKEPORT_DATA_DIR=tests/fixture_data luajit mods/relearn_moves/tests/relearn_moves_test.lua
package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local Runtime = require("src.mods.Runtime")
local Data = require("src.core.Data")
Data:load()

-- The engine reads the forget gate from constants.hmMoves (the fixture
-- only carries FIX_CUT); seed the real HM set the screen flow relies on.
Data.constants.hmMoves = { "CUT" }

-- Seed moves + a species with a real movelist (the fixture only carries
-- FIX_* content) so the level gate and dedupe can be observed.
Data.moves.FIX_TACKLE = { id = "FIX_TACKLE", name = "TACKLE", type = "NORMAL",
  power = 40, accuracy = 100, pp = 35, effect = "NO_ADDITIONAL_EFFECT" }
Data.moves.FIX_EMBERISH = { id = "FIX_EMBERISH", name = "EMBER", type = "FIRE",
  power = 40, accuracy = 100, pp = 25, effect = "BURN_SIDE_EFFECT1" }
Data.moves.FIX_THUNDER = { id = "FIX_THUNDER", name = "THUNDERBOLT",
  type = "ELECTRIC", power = 95, accuracy = 100, pp = 15, effect = "NO_ADDITIONAL_EFFECT" }
Data.moves.FIX_WATER_GUN = { id = "FIX_WATER_GUN", name = "WATER GUN",
  type = "WATER", power = 40, accuracy = 100, pp = 25, effect = "NO_ADDITIONAL_EFFECT" }
Data.moves.FIX_GROWL = { id = "FIX_GROWL", name = "GROWL", type = "NORMAL",
  power = 0, accuracy = 100, pp = 40, effect = "ATTACK_DOWN1_EFFECT" }
Data.moves.CUT = { id = "CUT", name = "CUT", type = "NORMAL",
  power = 50, accuracy = 95, pp = 30, effect = "NO_ADDITIONAL_EFFECT" }

Data.pokemon.FIXMON_REL = {
  id = "FIXMON_REL", index = 4, dex = 4, name = "FIXMON REL",
  types = { "GRASS" },
  baseStats = { hp = 45, attack = 49, defense = 49, speed = 45, special = 65 },
  catchRate = 45, baseExp = 64,
  level1Moves = { "FIX_TACKLE" },
  growthRate = "MEDIUM_SLOW",
  tmhm = { "FIX_CUT" },
  learnset = {
    { level = 1, move = "FIX_TACKLE" },   -- dup of level1, never listed twice
    { level = 7, move = "FIX_EMBERISH" },
    { level = 13, move = "FIX_THUNDER" },
    { level = 25, move = "FIX_WATER_GUN" },
    { level = 36, move = "FIX_GROWL" },
  },
  evolutions = {},
}

local run = T.sdk.loadMod("mods/relearn_moves", { data = Data })
T.eq(#run.errors, 0, "loads clean (" .. tostring(run.errors[1]) .. ")")
local ex = run.loader.exports.relearn_moves
T.neq(ex, nil, "exports reachable")

local function mon(level, moves)
  local m = { species = "FIXMON_REL", level = level, moves = moves or {} }
  return m
end

-- ------------------------------------------------------ buildRelearnable

T.eq(#ex.buildRelearnable(Data, Data.pokemon.FIXMON_REL,
                          mon(5, { { id = "FIX_TACKLE" } })), 0,
     "level 5 knows nothing learnable (EMBERISH is L7)")
local dedupe = ex.buildRelearnable(Data, Data.pokemon.FIXMON_REL,
                                   mon(1, {}))
T.eq(#dedupe, 1, "level1 move + same learnset entry dedupe to one")
T.eq(dedupe[1].move, "FIX_TACKLE", "the surviving entry is TACKLE")
local lv7 = ex.buildRelearnable(Data, Data.pokemon.FIXMON_REL,
                                mon(7, { { id = "FIX_TACKLE" } }))
T.eq(#lv7, 1, "level 7 opens EMBERISH")
T.eq(lv7[1].level, 7, "learn level carried")
T.eq(lv7[1].move, "FIX_EMBERISH", "learn id carried")
T.eq(lv7[1].name, "EMBER", "name resolved from data.moves")
T.eq(lv7[1].pp, 25, "learned PP carried from the move def")
local lv36 = ex.buildRelearnable(Data, Data.pokemon.FIXMON_REL,
  mon(36, { { id = "FIX_TACKLE" }, { id = "FIX_EMBERISH" },
            { id = "FIX_THUNDER" } }))
T.eq(#lv36, 2, "level 36 offers WATER GUN and GROWL only")
T.eq(lv36[1].move, "FIX_WATER_GUN", "movelist order kept")
T.eq(lv36[2].move, "FIX_GROWL", "level gate applied")
T.eq(lv36[2].level, 36, "level 36 gate exact")

-- --------------------------------------------------------------- applyMove

local m3 = mon(30, { { id = "FIX_TACKLE" }, { id = "FIX_EMBERISH" },
                     { id = "FIX_THUNDER" } })
T.eq(ex.applyMove(Data, m3, "FIX_WATER_GUN"), nil, "open slot learns, no drop")
T.eq(#m3.moves, 4, "moveset filled")
T.eq(m3.moves[4].id, "FIX_WATER_GUN", "new move appended")
T.eq(m3.moves[4].pp, 25, "PP set from the move def")
T.eq(ex.applyMove(Data, m3, "FIX_WATER_GUN"), nil, "already known is a no-op")
T.eq(#m3.moves, 4, "no-op keeps the moveset")

local m4 = mon(40, { { id = "FIX_TACKLE" }, { id = "FIX_EMBERISH" },
                     { id = "FIX_THUNDER" }, { id = "FIX_WATER_GUN" } })
local dropped = ex.applyMove(Data, m4, "FIX_GROWL", 3)
T.eq(dropped, "FIX_THUNDER", "replacement reports the dropped move")
T.eq(m4.moves[3].id, "FIX_GROWL", "slot 3 now holds the relearned move")
T.eq(m4.moves[3].pp, 40, "relearned move gets full base PP")
local untouched = ex.applyMove(Data, m4, "FIX_EMBERISH", nil)
T.eq(untouched, nil, "full set without a slot is a no-op")
T.eq(m4.moves[2].id, "FIX_EMBERISH", "nothing shifted without a slot")

-- ----------------------------------------------------------- injectSubmenu

local function fieldItems()
  return { { label = "STATS" }, { label = "SWITCH" } }
end
local game = { data = Data }

-- relearnable mon: RELEARN lands at the bottom, after SWITCH
local items = ex.injectSubmenu(Data, fieldItems(),
                               mon(20, { { id = "FIX_TACKLE" } }),
                               { battle = false })
T.eq(#items, 3, "RELEARN inserted")
T.eq(items[1].label, "STATS", "STATS stays first")
T.eq(items[2].label, "SWITCH", "SWITCH keeps the second slot")
T.eq(items[3].label, "RELEARN", "RELEARN sits at the bottom")
T.eq(type(items[3].onSelect), "function", "entry carries an onSelect callback")
T.eq(items[3].relearn, true, "entry carries the idempotency marker")
local again = ex.injectSubmenu(Data, items, mon(20, { { id = "FIX_TACKLE" } }),
                               { battle = false })
T.eq(again, items, "injecting twice is a no-op")

-- battle: vanilla list untouched
local battle = { { label = "SWITCH" }, { label = "STATS" } }
T.eq(ex.injectSubmenu(Data, battle, mon(50, {}), { battle = true }), battle,
     "battle submenu never gains RELEARN")

-- the entry is unconditional out of battle (discoverability): even a mon
-- with nothing left to learn gets the RELEARN row; battle keeps vanilla
local noneItems = fieldItems()
local none = ex.injectSubmenu(Data, noneItems, mon(5, { { id = "FIX_TACKLE" } }),
                              { battle = false })
T.eq(#none, 3, "mon with nothing to relearn still gets RELEARN")
T.eq(none[3].label, "RELEARN", "the empty-list entry is RELEARN")
local nilDataItems = fieldItems()
T.eq(ex.injectSubmenu(nil, nilDataItems, mon(50, {}), { battle = false })[3].label,
     "RELEARN", "missing data still injects the entry")
local nilMonItems = fieldItems()
T.eq(ex.injectSubmenu(Data, nilMonItems, nil, { battle = false })[3].label,
     "RELEARN", "missing mon still injects the entry")

-- ------------------------------------------------------- hook wiring (real)

local hooked = Runtime.call("ui.party.submenu",
                            function(_, items) return items end,
                            game, fieldItems(),
                            mon(20, { { id = "FIX_TACKLE" } }),
                            { battle = false })
T.eq(#hooked, 3, "ui.party.submenu hook injects through the runtime")
T.eq(hooked[3].label, "RELEARN", "hook-injected entry is RELEARN")
local hookedBattle = Runtime.call("ui.party.submenu",
                                  function(_, items) return items end,
                                  game, battle, mon(50, {}),
                                  { battle = true })
T.eq(hookedBattle, battle, "runtime hook leaves battle alone")

-- ---------------------------------------------------------------- ticker

-- TICKER_HOLD = 1.6s, TICKER_SPEED = 16px/s; overflow 40 -> scroll 2.5s
local T_HOLD = 1.6
local T_SCROLL = 40 / 16
local T_CYCLE = 2 * T_HOLD + 2 * T_SCROLL
T.eq(ex.tickerOffset(0, 40), 0, "ticker starts at the label head")
T.eq(ex.tickerOffset(0.5, 40), 0, "start hold keeps the label still")
T.eq(ex.tickerOffset(T_HOLD + 0.5, 40), -8, "scroll out at 16px/s")
T.check(math.abs(ex.tickerOffset(T_HOLD + T_SCROLL, 40) + 40) < 1e-9,
        "scroll out reaches the tail")
T.eq(ex.tickerOffset(T_HOLD + T_SCROLL + 0.6, 40), -40,
     "end hold shows the tail")
T.check(math.abs(ex.tickerOffset(T_HOLD + T_SCROLL + T_HOLD + 0.25, 40) + 36) < 1e-9,
        "scroll back retraces")
T.eq(ex.tickerOffset(T_CYCLE + 0.1, 40), 0, "the cycle wraps to a new hold")
T.eq(ex.tickerOffset(5, 0), 0, "a fitting label never scrolls")
T.eq(ex.tickerOffset(5, nil), 0, "nil overflow never scrolls")
T.eq(ex.tickerOffset(0, 40), ex.tickerOffset(T_CYCLE, 40),
     "cycle boundary matches the start")

-- ------------------------------------------------------ data-driven HM gate

T.eq(ex.isHM(Data, "CUT"), true, "constants.hmMoves gates CUT")
T.eq(ex.isHM(Data, "FIX_GROWL"), false, "non-HM moves stay forgettable")
T.eq(ex.isHM(nil, "SURF"), true, "vanilla fallback when data is absent")
T.eq(ex.isHM(nil, "TACKLE"), false, "fallback rejects non-HM ids")

-- ---------------------------------------------------- the learn-flow screen

local stack = { list = {} }
function stack:push(s) self.list[#self.list + 1] = s end
function stack:pop() return table.remove(self.list) end
-- one entry per wasPressed call; update() polls up/down/b/a in order
-- (colon calls pass the input table as the first argument)
local function pressed(...)
  local seq = { ... }
  local i = 0
  return function(_, key)
    i = i + 1
    return seq[i] == key
  end
end
local function screenGame()
  return { data = Data, stack = stack, input = { wasPressed = pressed() } }
end

T.neq(Data.screens["MoveRelearn"], nil, "screen registered into data.screens")
local Screens = require("src.ui.Screens")
local mk = Screens.get(screenGame(), "MoveRelearn")
T.neq(mk, nil, "screens registry resolves the MoveRelearn factory")

-- ---------------------------------------------- qol_toggles HM-gate interop

-- a fake loader shaped like the real one (Game.mods): mods / modOptions /
-- exports keyed by mod id, with QoL Toggles' exported defaultFor
local function qolLoader(forgettable, opts)
  opts = opts or {}
  local bucket = {}
  if forgettable ~= nil then bucket.forgettable_hms = forgettable end
  return {
    mods = {
      qol_toggles = {
        enabled = opts.enabled ~= false,
        failed = opts.failed == true,
      },
    },
    modOptions = { qol_toggles = bucket },
    exports = {
      qol_toggles = {
        defaultFor = function(key) return key == "forgettable_hms" end,
      },
    },
  }
end
local function qolGame(forgettable, opts)
  local g = screenGame()
  g.mods = qolLoader(forgettable, opts)
  return g
end

T.eq(ex.hmForgettable(screenGame()), false,
     "no mods loader keeps the HM lock")
T.eq(ex.hmForgettable({}), false, "missing game keeps the HM lock")
T.eq(ex.hmForgettable(qolGame(nil)), true,
     "toggle untouched (default ON) unlocks HMs with QoL Toggles present")
T.eq(ex.hmForgettable(qolGame(true)), true, "FORGETTABLE HMs ON unlocks HMs")
T.eq(ex.hmForgettable(qolGame(false)), false, "FORGETTABLE HMs OFF keeps the lock")
do
  local g = qolGame(nil)
  g.mods.mods.qol_toggles.enabled = false
  T.eq(ex.hmForgettable(g), false, "a disabled QoL Toggles keeps the lock")
end
do
  local g = qolGame(nil)
  g.mods.mods.qol_toggles.failed = true
  T.eq(ex.hmForgettable(g), false, "a failed QoL Toggles keeps the lock")
end

-- the submenu entry's onSelect pushes the screen with the selected mon
do
  stack.list = {}
  local g = screenGame()
  local entry = ex.injectSubmenu(Data, fieldItems(),
                                 mon(20, { { id = "FIX_TACKLE" } }),
                                 { battle = false })[3]
  local target = mon(20, { { id = "FIX_TACKLE" } })
  entry.onSelect(target, g)
  T.eq(#g.stack.list, 1, "onSelect pushes one screen")
  local pushed = g.stack.list[1]
  T.eq(pushed.mon, target, "the pushed screen carries the selected mon")
  T.eq(pushed.list[1].move, "FIX_EMBERISH",
       "the pushed screen built its relearn list")
end

-- monName: nickname wins, species name falls back
do
  local g = screenGame()
  local scr = mk.new(g, { species = "FIXMON_REL", level = 5, moves = {},
                          nickname = "SPARKY" })
  T.eq(scr:monName(), "SPARKY", "nickname wins over species name")
  local plain = mk.new(g, mon(5, {}))
  T.eq(plain:monName(), "FIXMON REL", "species name fallback")
end

-- learn into an open slot: A on the first relearnable move
do
  stack.list = {}
  local g = screenGame()
  g.input.wasPressed = pressed(nil, nil, nil, "a")
  local target = mon(20, { { id = "FIX_TACKLE" } }) -- knows only TACKLE
  local scr = mk.new(g, target)
  scr:update(0)
  T.eq(#target.moves, 2, "open-slot learn adds the move")
  T.eq(target.moves[2].id, "FIX_EMBERISH", "first relearnable move added")
  T.eq(target.moves[2].pp, 25, "PP set through the screen flow")
  T.eq(#g.stack.list, 1, "screen popped, message box pushed")
  T.eq(type(g.stack.list[1].pages), "table", "message is a TextBox")
end

-- full moveset: A opens the forget list, B cancels back to the list
do
  stack.list = {}
  local g = screenGame()
  g.input.wasPressed = pressed(nil, nil, nil, "a") -- first update: enters forget mode
  local target = mon(40, { { id = "FIX_TACKLE" }, { id = "FIX_EMBERISH" },
                           { id = "FIX_THUNDER" }, { id = "FIX_WATER_GUN" } })
  local scr = mk.new(g, target)
  scr:update(0)
  T.neq(scr.forgetting, nil, "full moveset enters the forget list")
  T.eq(scr.forgetting.move, "FIX_GROWL", "chosen move remembered")
  g.input.wasPressed = pressed(nil, nil, "b", nil) -- second update: B cancels
  scr:update(0)
  T.eq(scr.forgetting, nil, "B cancels the forget list")
  T.eq(#target.moves, 4, "no move was replaced on cancel")
end

-- full moveset: pick a slot to replace, poof text, move swapped
do
  stack.list = {}
  local g = screenGame()
  local seq = pressed(nil, nil, nil, "a",   -- list: A
                      nil, nil, nil, "a")   -- forget: A on slot 1
  g.input.wasPressed = seq
  local target = mon(40, { { id = "FIX_TACKLE" }, { id = "FIX_EMBERISH" },
                           { id = "FIX_THUNDER" }, { id = "FIX_WATER_GUN" } })
  local scr = mk.new(g, target)
  scr:update(0)
  T.neq(scr.forgetting, nil, "forget list open")
  scr:update(0)
  T.eq(scr.forgetting, nil, "forget list closed after the swap")
  T.eq(target.moves[1].id, "FIX_GROWL", "slot 1 now holds GROWL")
  T.eq(target.moves[1].pp, 40, "relearned move PP set")
  T.eq(#g.stack.list, 1, "screen popped, message box pushed")
end

-- full moveset: HM moves can't be deleted
do
  stack.list = {}
  local g = screenGame()
  local seq = pressed(nil, nil, nil, "a",   -- list: A
                      nil, nil, nil, "a")   -- forget: A on CUT (HM)
  g.input.wasPressed = seq
  local target = mon(40, { { id = "CUT" }, { id = "FIX_EMBERISH" },
                           { id = "FIX_THUNDER" }, { id = "FIX_WATER_GUN" } })
  local scr = mk.new(g, target)
  scr:update(0)
  scr:update(0)
  T.neq(scr.forgetting, nil, "forget list stays open after an HM pick")
  T.eq(target.moves[1].id, "CUT", "the HM move was not replaced")
  T.eq(#g.stack.list, 1, "only the HM-can't-delete box is on the stack")
end

-- full moveset: QoL Toggles FORGETTABLE HMs ON lets an HM be replaced
do
  stack.list = {}
  local g = qolGame(true)
  local seq = pressed(nil, nil, nil, "a",   -- list: A
                      nil, nil, nil, "a")   -- forget: A on CUT (HM)
  g.input.wasPressed = seq
  local target = mon(40, { { id = "CUT" }, { id = "FIX_EMBERISH" },
                           { id = "FIX_THUNDER" }, { id = "FIX_WATER_GUN" } })
  local scr = mk.new(g, target)
  scr:update(0)
  scr:update(0)
  T.eq(scr.forgetting, nil, "forget list closes after the HM swap")
  T.eq(target.moves[1].id, "FIX_TACKLE", "the HM slot now holds the relearned move")
  T.eq(#g.stack.list, 1, "screen popped, message box pushed")
end

-- B pops straight back to the party menu
do
  stack.list = {}
  local g = screenGame()
  g.input.wasPressed = pressed(nil, nil, "b", nil)
  local scr = mk.new(g, mon(40, {}))
  scr:update(0)
  T.eq(#g.stack.list, 0, "B pops the relearn screen")
end

-- hold-to-scroll: the navRepeat branch needs input.isDown (the headless
-- screenGame() stub only has wasPressed, so the repeat path was never
-- exercised -- regression for REPEAT_DELAY/REPEAT_RATE being declared
-- after navRepeat, which made them nil globals in the real game)
do
  stack.list = {}
  local held = { down = true }
  local g = screenGame()
  g.input.isDown = function(_, key) return held[key] == true end
  local scr = mk.new(g, mon(40, {})) -- empty moveset: all 5 learnable rows
  T.check(#scr.list >= 5, "relearn list has enough rows to scroll")
  local start = scr.index
  for _ = 1, 5 do scr:update(16 / 60) end -- five 16-frame ticks holding down
  T.check(scr.index > start, "holding down scrolls past the first row")
  T.eq(scr.index, math.min(#scr.list, start + 5),
       "cursor stepped once per REPEAT_DELAY interval")
end

run.release()
T.finish("relearn_moves")
