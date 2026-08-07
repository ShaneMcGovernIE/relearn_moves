-- Move Relearn: adds a RELEARN entry to the bottom of the field party-menu
-- submenu (after SWITCH) that lets a mon relearn any move from its species
-- movelist it has reached the level for.  A full moveset opens a forget
-- list (HM moves stay locked unless the QoL Toggles mod's FORGETTABLE HMs
-- toggle is on); an empty slot learns the move straight away.  Battle
-- never sees the option.
--
-- Wiring: the ui.party.submenu hook (src/ui/PartyMenu.lua:620) receives
-- the vanilla item list after it is built; hook-injected entries carry an
-- onSelect callback instead of an action id (PartyMenu.lua:332-334), so
-- the vanilla update handles the rest.  The learn flow is a screen
-- registered in the screens registry, pushed over the still-open party
-- menu with Screens.push.

local Font = require("src.render.Font")
local Strings = require("src.core.Strings")
local Screens = require("src.ui.Screens")
local Sound = require("src.core.Sound")
local Theme = require("src.ui.Theme")

-- Vanilla HM set (data/moves/hm_moves.asm, IsMoveHM); the runtime gate is
-- data-driven off constants.hmMoves (Data.lua:31) and falls back here when
-- data is absent (headless fixtures without the registry).
local HM_MOVES = {
  CUT = true, FLY = true, SURF = true, STRENGTH = true, FLASH = true,
}

-- Pure (mod.exports.isHM for headless tests): the engine's forget gate
-- (the same set MoveLearnMenu applies via IsMoveHM).  Reads the live
-- constants.hmMoves list -- so a mod or imported dataset that extends the
-- HM set gates here too -- and falls back to the vanilla five.
local function isHM(data, moveId)
  local hm = data and data.constants and data.constants.hmMoves
  if hm then
    for _, id in ipairs(hm) do
      if id == moveId then return true end
    end
    return false
  end
  return HM_MOVES[moveId] == true
end

-- Pure (mod.exports.hmForgettable for headless tests): whether an HM move
-- may be forgotten from the relearn forget list.  The vanilla lock stays
-- unless the QoL Toggles mod (optional dependency) is loaded, enabled and
-- not failed, and its FORGETTABLE HMs toggle reads ON.  The toggle lives
-- in the same options.lua bucket QoL Toggles writes (Game.mods.modOptions
-- .qol_toggles); when the user has never flipped it the bucket has no
-- entry, so we fall back to QoL Toggles' exported default for the toggle
-- (default ON) -- the exact fallback its own get() applies, keeping the
-- two forget flows consistent.  A fresh install with the toggle untouched
-- therefore unlocks HMs here too.
local function hmForgettable(game)
  local loader = game and game.mods
  local other = loader and loader.mods and loader.mods.qol_toggles
  if not other or not other.enabled or other.failed then return false end
  local bucket = loader.modOptions and loader.modOptions.qol_toggles
  local stored = bucket and bucket.forgettable_hms
  if stored ~= nil then return stored == true end
  local exports = loader.exports and loader.exports.qol_toggles
  if exports and exports.defaultFor then
    return exports.defaultFor("forgettable_hms") == true
  end
  return false
end

-- Pure (mod.exports.buildRelearnable for headless tests): the moves a mon
-- may relearn -- level-1 moves plus learnset entries at or below its
-- level, in movelist order, deduped, minus what it already knows.
-- Returns { level, move, name }.
local function buildRelearnable(data, def, mon)
  local out, seen, known = {}, {}, {}
  for _, mv in ipairs(mon.moves or {}) do known[mv.id] = true end
  local function add(level, move)
    if known[move] or seen[move] then return end
    seen[move] = true
    local mdef = data and data.moves and data.moves[move]
    out[#out + 1] = {
      level = level,
      move = move,
      name = (mdef and mdef.name) or move,
      pp = (mdef and mdef.pp) or 0,
    }
  end
  for _, id in ipairs(def.level1Moves or {}) do add(1, id) end
  for _, entry in ipairs(def.learnset or {}) do
    if entry.level <= mon.level then add(entry.level, entry.move) end
  end
  return out
end

-- Pure (mod.exports.applyMove for headless tests): add a move with full
-- base PP.  A full moveset replaces slot `replace` (1-4) and returns the
-- dropped move id; otherwise returns nil.  No-op when already known.
local function applyMove(data, mon, moveId, replace)
  for _, mv in ipairs(mon.moves or {}) do
    if mv.id == moveId then return nil end
  end
  local mdef = data and data.moves and data.moves[moveId]
  local slot = { id = moveId, pp = (mdef and mdef.pp) or 0 }
  mon.moves = mon.moves or {}
  if #mon.moves < 4 then
    mon.moves[#mon.moves + 1] = slot
    return nil
  end
  if not replace then return nil end
  local old = mon.moves[replace]
  mon.moves[replace] = slot
  return old and old.id
end

-- Pure (mod.exports.injectSubmenu for headless tests): append the RELEARN
-- entry at the bottom of the field party submenu, after SWITCH.  Battle
-- keeps the vanilla list.  The entry is always present out of battle so
-- the feature is discoverable; a mon with nothing left to learn reads "No
-- moves to relearn." in the flow screen instead of hiding the option.
local function injectSubmenu(data, items, mon, ctx)
  if ctx and ctx.battle then return items end
  for _, e in ipairs(items) do
    if e.relearn then return items end
  end
  local entry = {
    label = Strings("RELEARN"),
    relearn = true,
    onSelect = function(selMon, game)
      Screens.push(game, "MoveRelearn", selMon)
    end,
  }
  -- RELEARN goes at the bottom of the list, after SWITCH (SWITCH keeps the
  -- second slot).  Appending is independent of any engine row ordering, so
  -- the entry can never land between other options.
  items[#items + 1] = entry
  return items
end

-- ---------- the learn flow screen (over the still-open party menu) ----------

local MoveRelearn = {}
MoveRelearn.__index = MoveRelearn

local CURSOR = 0xED
local ROWS = 5 -- forget-list geometry from MoveLearnMenu: 4 moves + CANCEL
-- Hold-to-scroll pacing in seconds (the ListMenu keyRepeat: REPEAT_DELAY
-- 16 / REPEAT_RATE 4 fixed frames at 60fps).  Declared before navRepeat so
-- the function closes over the locals (a later local is invisible to it).
local REPEAT_DELAY = 16 / 60
local REPEAT_RATE = 4 / 60

function MoveRelearn.new(game, mon)
  local self = setmetatable({}, MoveRelearn)
  self.game = game
  self.mon = mon
  local def = game.data and game.data.pokemon[mon.species]
  self.list = def and buildRelearnable(game.data, def, mon) or {}
  self.index = 1
  self.scroll = 0
  self.tick = 0
  self.hold = { up = 0, down = 0 } -- hold-to-scroll timers (navRepeat)
  -- nil, or { move, index } while choosing a slot to replace
  self.forgetting = nil
  return self
end

function MoveRelearn:monName()
  return self.mon.nickname or self.game.data.pokemon[self.mon.species].name
end

function MoveRelearn:finish(message)
  -- pop the screen first, then the message reads over the party menu
  self.game.stack:pop()
  local TextBox = require("src.render.TextBox")
  self.game.stack:push(TextBox.new(self.game, message))
end

-- Hold-to-scroll (the ListMenu keyRepeat pacing: REPEAT_DELAY 16 fixed
-- frames, then REPEAT_RATE 4, at 60fps).  One step on the press edge,
-- then repeat while the key stays down.  `step` moves the cursor one row
-- (closures below own the wrap-around).
function MoveRelearn:navRepeat(dt, dir, step)
  local input = self.game.input
  if input:wasPressed(dir) then
    self.hold[dir] = 0
    step()
    return
  end
  if input.isDown and input:isDown(dir) then
    self.hold[dir] = self.hold[dir] + (dt or 0)
    while self.hold[dir] >= REPEAT_DELAY do
      step()
      self.hold[dir] = self.hold[dir] - REPEAT_RATE
    end
  else
    self.hold[dir] = 0
  end
end

-- Cursor/A-accept are the engine's Press_AB click; a successful learn ends
-- with the Get_Item2 chime.  Headless (no love) is a safe no-op.
local function beep(game, id)
  if game and game.data then
    Sound.play(game.data, id or "Press_AB")
  end
end

function MoveRelearn:update(dt)
  self.tick = (self.tick or 0) + (dt or 0)
  local input = self.game.input
  if self.forgetting then
    local n = #self.mon.moves + 1 -- moves + CANCEL
    self:navRepeat(dt, "up", function()
      self.forgetting.index = self.forgetting.index > 1
        and self.forgetting.index - 1 or n
    end)
    self:navRepeat(dt, "down", function()
      self.forgetting.index = self.forgetting.index < n
        and self.forgetting.index + 1 or 1
    end)
    if input:wasPressed("b") then
      beep(self.game)
      self.forgetting = nil
    elseif input:wasPressed("a") then
      beep(self.game)
      if self.forgetting.index > #self.mon.moves then
        self.forgetting = nil -- CANCEL back to the relearn list
        return
      end
      local old = self.mon.moves[self.forgetting.index]
      if isHM(self.game.data, old.id) and not hmForgettable(self.game) then
        -- HMCantDeleteText, then back to the forget list
        local TextBox = require("src.render.TextBox")
        self.game.stack:push(TextBox.new(self.game,
          Strings("HM techniques\ncan't be deleted!")))
        return
      end
      local move = self.forgetting.move
      local slot = self.forgetting.index
      local mdef = self.game.data.moves[move]
      local name = self:monName()
      self.forgetting = nil
      applyMove(self.game.data, self.mon, move, slot)
      beep(self.game, "Get_Item2")
      self:finish(Strings(
        "1, 2 and... Poof!\f%s forgot\n%s!\fAnd...\f%s learned\n%s!",
        name, self.game.data.moves[old.id].name, name, mdef.name))
    end
    return
  end
  local n = #self.list
  if n == 0 then
    -- The RELEARN entry is always injected out of battle, so an empty list
    -- here is rare (a mon with nothing left to learn after a move was
    -- removed from its learnset).  It reads "No moves to relearn." in the
    -- dialogue box below (no move list box); any button exits cleanly.
    if input:wasPressed("a") or input:wasPressed("b") then
      beep(self.game)
      self.game.stack:pop()
    end
    return
  end
  self:navRepeat(dt, "up", function() self.index = math.max(1, self.index - 1) end)
  self:navRepeat(dt, "down", function() self.index = math.min(n, self.index + 1) end)
  if input:wasPressed("b") then
    beep(self.game)
    self.game.stack:pop()
  elseif input:wasPressed("a") then
    beep(self.game)
    local entry = self.list[self.index]
    if #self.mon.moves < 4 then
      applyMove(self.game.data, self.mon, entry.move)
      beep(self.game, "Get_Item2")
      self:finish(Strings("%s learned\n%s!", self:monName(), entry.name))
    else
      self.forgetting = { move = entry.move, index = 1 }
    end
  end
  -- keep the cursor inside the visible window
  if n > ROWS then
    if self.index < self.scroll + 1 then self.scroll = self.index - 1 end
    if self.index > self.scroll + ROWS then self.scroll = self.index - ROWS end
  end
end

-- Box is 18 tiles at (2,5), two tiles wider than MoveLearnMenu's forget
-- list so each row has room for a PP column.  The engine's text
-- convention pads 8px inside the box, so text clips at the inner right
-- edge: 152.  The GB font is a flat 8px/glyph.
--
-- Each relearn row is three zones: the learned-at level ("LV" + digits,
-- the number left-aligned against "LV" like the engine's PrintLevel,
-- no padding) at the row's left, the move name starting right after the
-- level digits (a name wider than the window scrolls as a ticker; the
-- level never moves), and the learned PP ("PP%2d", 4 glyphs)
-- right-aligned, which never scrolls.  A fixed gap separates the level
-- from the name, and the name window from the PP column.
local BOX_TX, BOX_TY, BOX_TW, BOX_TH = 2, 5, 18, 7
local CLIP_X = 24 -- 8px in from the widened box's inner edge (16)
local NAME_GAP = 8 -- gap between the level digits and the move name
local PP_GAP = 8 -- gap between the name window and the right-aligned PP
local PP_W = 32 -- "PP%2d" = 4 glyphs at 8px
local PP_X = 152 - PP_W

-- Ticker hold/scroll pacing: hold at each end so the player can read the
-- whole name, scroll at 16px/s (half a second per glyph).
local TICKER_HOLD = 1.6
local TICKER_SPEED = 16

-- Pure (mod.exports.tickerOffset for headless tests): horizontal offset
-- for an overflowing label at time t (seconds).  Cycle: hold at 0, scroll
-- out to -overflow, hold, scroll back to 0.  Labels that fit (overflow <=
-- 0) are static.
function MoveRelearn.tickerOffset(t, overflow)
  if not (overflow and overflow > 0) then return 0 end
  local scroll = overflow / TICKER_SPEED
  local cycle = 2 * TICKER_HOLD + 2 * scroll
  local p = t % cycle
  if p < TICKER_HOLD then return 0 end
  p = p - TICKER_HOLD
  if p < scroll then return -p * TICKER_SPEED end
  p = p - scroll
  if p < TICKER_HOLD then return -overflow end
  p = p - TICKER_HOLD
  return -overflow + p * TICKER_SPEED
end

-- Draw one row: the level prefix fixed at the left, the learned PP
-- right-aligned, then the move name starting right after the level
-- digits, tickering when the NAME alone overflows its window (which
-- stops a fixed gap before the PP column).  The love.graphics.setScissor
-- bounds the marquee so text never bleeds over the box border or under
-- the PP; the clip is cleared per row.
local function drawRowLabel(game, prefix, name, pp, row, tick)
  local y = (5 + row) * 8
  Font.draw(prefix, CLIP_X, y)
  Font.draw(("PP%2d"):format(pp), PP_X, y)
  local x = CLIP_X + Font.width(prefix) + NAME_GAP
  local clipW = PP_X - x - PP_GAP
  local w = Font.width(name)
  if w <= clipW then
    Font.draw(name, x, y)
    return
  end
  if love and love.graphics and love.graphics.setScissor then
    love.graphics.setScissor(x, y, clipW, 8)
  end
  Font.draw(name, x + MoveRelearn.tickerOffset(tick or 0, w - clipW), y)
  if love and love.graphics and love.graphics.setScissor then
    love.graphics.setScissor()
  end
end

function MoveRelearn:draw()
  if self.forgetting or #self.list > 0 then
    Font.drawBox(BOX_TX, BOX_TY, BOX_TW, BOX_TH)
  end
  love.graphics.setColor(0, 0, 0, 1)
  if self.forgetting then
    for i, mv in ipairs(self.mon.moves) do
      Font.draw(self.game.data.moves[mv.id].name, CLIP_X, (5 + i) * 8)
      Font.draw(("PP%2d"):format(mv.pp or 0), PP_X, (5 + i) * 8)
    end
    Font.draw(Strings("CANCEL"), CLIP_X, (6 + #self.mon.moves) * 8)
    Font.drawCode(CURSOR, CLIP_X - 8, (5 + self.forgetting.index) * 8)
    Font.drawBox(0, 12, 20, 6)
    Font.draw(Strings("Which move should"), 8, 14 * 8)
    Font.draw(Strings("be forgotten?"), 8, 16 * 8)
  elseif #self.list == 0 then
    -- No move list box: just the message in the dialogue box below (any
    -- button exits, handled in update).
    Font.drawBox(0, 12, 20, 6)
    Font.draw(Strings("No moves to\nrelearn."), 8, 14 * 8)
  else
    local last = math.min(#self.list, self.scroll + ROWS)
    for i = self.scroll + 1, last do
      local e = self.list[i]
      drawRowLabel(self.game, ("LV%d"):format(e.level), e.name, e.pp,
                   i - self.scroll, self.tick)
    end
    Font.drawCode(CURSOR, CLIP_X - 8, (5 + self.index - self.scroll) * 8)
    -- moreArrow ($EE): more moves below the visible window, sitting on the
    -- box's bottom border (the Menu/ListMenu pattern)
    if #self.list > ROWS and self.scroll + ROWS < #self.list then
      Font.drawCode(Theme.moreArrow,
        (BOX_TX + BOX_TW - 2) * 8, (BOX_TY + BOX_TH - 1) * 8)
    end
    Font.drawBox(0, 12, 20, 6)
    Font.draw(Strings("Relearn which"), 8, 14 * 8)
    Font.draw(Strings("move?"), 8, 16 * 8)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

return function(mod)
  mod.exports.buildRelearnable = buildRelearnable
  mod.exports.applyMove = applyMove
  mod.exports.injectSubmenu = injectSubmenu
  mod.exports.tickerOffset = MoveRelearn.tickerOffset
  mod.exports.HM_MOVES = HM_MOVES
  mod.exports.isHM = isHM
  mod.exports.hmForgettable = hmForgettable

  mod.content.screens:register("MoveRelearn", { new = MoveRelearn.new })

  mod.hooks:wrap("ui.party.submenu", function(next, game, items, mon, ctx)
    items = next(game, items)
    return injectSubmenu(game and game.data, items, mon, ctx)
  end)
end
