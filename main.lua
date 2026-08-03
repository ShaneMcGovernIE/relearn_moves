-- Move Relearn: adds a RELEARN entry to the field party-menu submenu
-- (between STATS and SWITCH) that lets a mon relearn any move from its
-- species movelist it has reached the level for.  A full moveset opens a
-- forget list (HM moves stay locked, like MoveLearnMenu); an empty slot
-- learns the move straight away.  Battle never sees the option.
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

-- data/moves/hm_moves.asm (IsMoveHM): the same gate MoveLearnMenu applies
local HM_MOVES = {
  CUT = true, FLY = true, SURF = true, STRENGTH = true, FLASH = true,
}

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

-- Pure (mod.exports.injectSubmenu for headless tests): insert the RELEARN
-- entry between STATS and SWITCH in the field party submenu.  Battle keeps
-- the vanilla list.  The entry is always present out of battle so the
-- feature is discoverable; a mon with nothing left to learn reads "No
-- moves to relearn." in the flow screen instead of hiding the option.
local function injectSubmenu(data, items, mon, ctx)
  if ctx and ctx.battle then return items end
  for _, e in ipairs(items) do
    if e.relearn then return items end
  end
  local out = {}
  for i, e in ipairs(items) do
    if i == 2 then
      out[#out + 1] = {
        label = Strings("RELEARN"),
        relearn = true,
        onSelect = function(selMon, game)
          Screens.push(game, "MoveRelearn", selMon)
        end,
      }
    end
    out[#out + 1] = e
  end
  return out
end

-- ---------- the learn flow screen (over the still-open party menu) ----------

local MoveRelearn = {}
MoveRelearn.__index = MoveRelearn

local CURSOR = 0xED
local ROWS = 5 -- forget-list geometry from MoveLearnMenu: 4 moves + CANCEL

function MoveRelearn.new(game, mon)
  local self = setmetatable({}, MoveRelearn)
  self.game = game
  self.mon = mon
  local def = game.data and game.data.pokemon[mon.species]
  self.list = def and buildRelearnable(game.data, def, mon) or {}
  self.index = 1
  self.scroll = 0
  self.tick = 0
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

function MoveRelearn:update(dt)
  self.tick = (self.tick or 0) + (dt or 0)
  local input = self.game.input
  if self.forgetting then
    local n = #self.mon.moves + 1 -- moves + CANCEL
    if input:wasPressed("up") then
      self.forgetting.index = self.forgetting.index > 1
        and self.forgetting.index - 1 or n
    elseif input:wasPressed("down") then
      self.forgetting.index = self.forgetting.index < n
        and self.forgetting.index + 1 or 1
    elseif input:wasPressed("b") then
      self.forgetting = nil
    elseif input:wasPressed("a") then
      if self.forgetting.index > #self.mon.moves then
        self.forgetting = nil -- CANCEL back to the relearn list
        return
      end
      local old = self.mon.moves[self.forgetting.index]
      if HM_MOVES[old.id] then
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
      self:finish(Strings(
        "1, 2 and... Poof!\f%s forgot\n%s!\fAnd...\f%s learned\n%s!",
        name, self.game.data.moves[old.id].name, name, mdef.name))
    end
    return
  end
  local n = #self.list
  if n == 0 then
    -- nothing to relearn (the RELEARN entry is only injected when non-empty,
    -- so this is just a belt-and-braces exit)
    if input:wasPressed("a") or input:wasPressed("b") then
      self.game.stack:pop()
    end
    return
  end
  if input:wasPressed("up") then
    self.index = math.max(1, self.index - 1)
  elseif input:wasPressed("down") then
    self.index = math.min(n, self.index + 1)
  elseif input:wasPressed("b") then
    self.game.stack:pop()
  elseif input:wasPressed("a") then
    local entry = self.list[self.index]
    if #self.mon.moves < 4 then
      applyMove(self.game.data, self.mon, entry.move)
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

-- Box is 16 tiles at (4,5) (TextBoxBorder 4,7, MoveLearnMenu's geometry);
-- names start at x=48, one glyph in from the box's left border.  The
-- engine's own text convention pads 8px inside the box, so text clips at
-- the inner right edge: 152.  The GB font is a flat 8px/glyph.
--
-- Each row is two zones: the learned-at level ("LV%3d", 5 glyphs) stays
-- fixed at the row's left, and the move name sits after it in its own
-- clip window.  A name wider than that window scrolls as a ticker; the
-- level never moves.
local CLIP_X = 48
local LEVEL_W = 40 -- "LV%3d" = 5 glyphs at 8px
local NAME_X = CLIP_X + LEVEL_W + 8
local NAME_CLIP_W = 152 - NAME_X -- 56px = 7 glyphs

-- Ticker hold/scroll pacing: hold at each end so the player can read the
-- whole name, scroll at 24px/s (about a glyph every 1/3s).
local TICKER_HOLD = 1.2
local TICKER_SPEED = 24

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

-- Draw one row: the level prefix fixed, then the move name, tickering
-- when the NAME alone overflows its window.  love.graphics.setScissor
-- bounds the marquee to the name's window so the text never bleeds over
-- the box border; the clip is cleared per row.
local function drawRowLabel(game, prefix, name, row, tick)
  local y = (5 + row) * 8
  Font.draw(prefix, CLIP_X, y)
  local w = Font.width(name)
  if w <= NAME_CLIP_W then
    Font.draw(name, NAME_X, y)
    return
  end
  if love and love.graphics and love.graphics.setScissor then
    love.graphics.setScissor(NAME_X, y, NAME_CLIP_W, 8)
  end
  Font.draw(name, NAME_X + MoveRelearn.tickerOffset(tick or 0, w - NAME_CLIP_W), y)
  if love and love.graphics and love.graphics.setScissor then
    love.graphics.setScissor()
  end
end

function MoveRelearn:draw()
  -- same box geometry as MoveLearnMenu's forget list (TextBoxBorder 4,7)
  Font.drawBox(4, 5, 16, 7)
  love.graphics.setColor(0, 0, 0, 1)
  if self.forgetting then
    for i, mv in ipairs(self.mon.moves) do
      Font.draw(self.game.data.moves[mv.id].name, 48, (5 + i) * 8)
    end
    Font.draw(Strings("CANCEL"), 48, (6 + #self.mon.moves) * 8)
    Font.drawCode(CURSOR, 40, (5 + self.forgetting.index) * 8)
    Font.drawBox(0, 12, 20, 6)
    Font.draw(Strings("Which move should"), 8, 14 * 8)
    Font.draw(Strings("be forgotten?"), 8, 16 * 8)
  elseif #self.list == 0 then
    Font.draw(Strings("No moves to\nrelearn."), 48, 48)
    Font.drawBox(0, 12, 20, 6)
    Font.draw(Strings("Nothing to\nrelearn."), 8, 14 * 8)
  else
    local last = math.min(#self.list, self.scroll + ROWS)
    for i = self.scroll + 1, last do
      local e = self.list[i]
      drawRowLabel(self.game, ("LV%3d"):format(e.level), e.name,
                   i - self.scroll, self.tick)
    end
    Font.drawCode(CURSOR, 40, (5 + self.index - self.scroll) * 8)
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

  mod.content.screens:register("MoveRelearn", { new = MoveRelearn.new })

  mod.hooks:wrap("ui.party.submenu", function(next, game, items, mon, ctx)
    items = next(game, items)
    return injectSubmenu(game and game.data, items, mon, ctx)
  end)
end
