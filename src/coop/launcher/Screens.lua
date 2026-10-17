-- The launcher's screens laid out (#38): Menu.lua's and CoopMenu.lua's
-- state turned into a page of plain nodes (Ui.lua) for a launcher of w x h
-- pixels.  No love.* here: Launcher.lua paints the page and tests read it.
--
-- Every page has the top bar (GEN1 CO·OP, the tabs), the screen's content
-- (scrolled when it is taller than the window) and the footer with the
-- controls and the credit line of upstream's licence, word for word.  A
-- message box sits over the content, never over the credit.
--
--   local page = Screens.build(menu, ui, { w = 480, h = 400, device = "keys" })
--
-- `ui` is the presentation's own state, kept by Launcher.lua between frames:
-- { focus = key, scroll = px }.  Focus keys: "row:<i>" (the active model's
-- row i), "tab:<name>", "back", "quit", "ok", "key:<r>:<c>" (text entry).

local Ui = require("src.coop.launcher.Ui")
local Games = require("src.coop.launcher.Games")
local CoopMenu = require("src.coop.launcher.CoopMenu")
local Text = require("src.coop.launcher.Text")
local L = Text.get

local Screens = {}

Screens.MARGIN = 12
Screens.MAX_WIDTH = 640
Screens.GAP = 8

local LINE = Ui.LINE
local width = Ui.width

local function Menu() return require("src.coop.launcher.Menu") end

-- ------------------------------------------------------------ pieces

-- a button: { key, act, label, sub?, style = "normal" | "primary" |
-- "quiet" | "selected", enabled, tag?, swatch?, detail? }
local function button(p, x, y, w, h, o)
  local enabled = o.enabled ~= false
  local style = o.style or "normal"
  local ink = "ink"
  if style == "primary" and enabled then
    p:rect(x, y, w, h, "accent")
    ink = "onAccent"
  elseif style == "quiet" then
    ink = enabled and "ink" or "muted"
  else
    p:rect(x, y, w, h, style == "selected" and "lcd" or (enabled and "paper" or "shell"))
    p:frame(x, y, w, h, style == "selected" and "accent" or "line", style == "selected" and 2 or 1)
    if not enabled then ink = "muted" end
  end
  local sub = o.sub and Ui.wrap(o.sub, w - 16)
  local lines = 1 + (sub and #sub or 0)
  local tx = x + 8 + (o.swatch and 8 or 0)
  local ty = y + math.floor((h - lines * LINE) / 2) + 1
  if o.swatch then p:add({ kind = "rect", x = x + 8, y = ty + 2, w = 4, h = 9, colour = o.swatch }) end
  local text = o.label
  local room = w - (tx - x) - 8
  if o.detail then room = room - width(o.detail) - 8 end
  if o.tag then room = room - width(o.tag) - 12 end
  p:text(tx, ty, Ui.fit(text, room), ink, 1, style == "quiet" and enabled)
  local after = tx + width(Ui.fit(text, room))
  if o.tag then
    local tw = width(o.tag) + 6
    p:frame(after + 6, ty, tw, LINE - 1, ink == "onAccent" and "onAccent" or "muted")
    p:text(after + 9, ty, o.tag, ink == "onAccent" and "onAccent" or "muted")
  end
  if o.detail then
    p:text(x + w - 8 - width(o.detail), ty, o.detail, ink == "ink" and "muted" or ink)
  end
  for i, line in ipairs(sub or {}) do
    if ty + i * LINE + LINE <= y + h + 2 then
      p:text(tx, ty + i * LINE, line, ink == "onAccent" and "onAccent" or "muted")
    end
  end
  if o.key then p:hit(x, y, w, h, o.key, o.act, enabled) end
end

-- a model row's button
local function rowButton(p, x, y, w, h, index, row, o)
  o = o or {}
  o.key = "row:" .. index
  o.act = { kind = "row", index = index }
  o.label = o.label or row.label
  if o.enabled == nil then o.enabled = row.enabled ~= false end
  button(p, x, y, w, h, o)
end

-- the width a button needs for its label
local function fitWidth(label, extra) return width(label) + 16 + (extra or 0) end

-- a section label in small muted capitals
local function sectionLabel(p, x, y, text) p:text(x, y, text, "muted") end

-- a panel's background: added first, sized when its content is known
local function panel(p, x, y, w)
  local fill = p:rect(x, y, w, 0, "lcd")
  local border = p:frame(x, y, w, 0, "line")
  return function(bottom)
    fill.h = bottom - fill.y + p.dy
    border.h = fill.h
  end
end

-- the rows of the model with id `id` (all, in order)
local function rowsWith(rows, id)
  local out = {}
  for i, r in ipairs(rows) do
    if r.id == id then out[#out + 1] = { index = i, row = r } end
  end
  return out
end

local function rowOf(rows, id)
  for i, r in ipairs(rows) do
    if r.id == id then return i, r end
  end
  return nil
end

-- co-op (#7): an import screen's CHOOSE FILE on a phone (the system's file
-- picker); its height, 0 without one
local function pickButton(p, c, rows, y)
  local i, row = rowOf(rows, "pick")
  if not i then return 0 end
  rowButton(p, c.x + 10, y, fitWidth(row.label), 24, i, row, { style = "primary" })
  return 32
end

-- a heading: title at twice the size, the subtitle, a BACK button
local function heading(p, c, y, title, subtitle, back)
  local backW = back and fitWidth(L("← BACK")) or 0
  local titleW = c.w - backW - 8
  local h = 0
  for _, line in ipairs(Ui.wrap(title, titleW, 2)) do
    p:text(c.x, y + h, line, "ink", 2)
    h = h + LINE * 2
  end
  if back then
    button(p, c.x + c.w - backW, y + 4, backW, 20,
      { key = "back", act = { kind = "back" }, label = L("← BACK") })
  end
  if subtitle and subtitle ~= "" then
    h = h + p:para(c.x, y + h + 2, titleW, subtitle, "muted") + 2
  end
  return h + 12
end

-- a row of buttons laid out right to left at the bottom of a screen
local function actionsRight(p, c, y, list)
  local x = c.x + c.w
  for i = #list, 1, -1 do
    local b = list[i]
    local w = b.w or fitWidth(b.label or b.row.label)
    x = x - w
    if b.index then
      rowButton(p, x, y, w, 24, b.index, b.row, b)
    else
      button(p, x, y, w, 24, b)
    end
    x = x - 8
  end
  return 24
end

-- pixel icons Launcher.lua draws (no check mark in the font)
local function icon(p, x, y, name, colour)
  return p:add({ kind = "icon", x = x, y = y, name = name, colour = colour or "ink" })
end

-- two columns side by side when the content is wide enough, else stacked
local function columns(c, ratio)
  if c.w >= 460 then
    local left = math.floor((c.w - 12) * (ratio or 0.55))
    return { x = c.x, w = left }, { x = c.x + left + 12, w = c.w - left - 12 }, true
  end
  return { x = c.x, w = c.w }, { x = c.x, w = c.w }, false
end

-- ------------------------------------------------------------ top and foot

local function topBar(p, menu, W, opts)
  local M = Screens.MARGIN
  local bar = p:rect(0, 0, W, 0, "shell")
  -- the mark: four squares, the second one paler
  for i = 0, 3 do
    local col, row = i % 2, math.floor(i / 2)
    p:rect(M + col * 7, 10 + row * 7, 5, 5, i == 1 and "line" or "accent")
  end
  p:text(M + 20, 6, Menu().TITLE, "ink", 2)
  p:text(M + 20, 6 + LINE * 2 - 4, L("UNOFFICIAL FORK"), "muted")
  local top = menu:isTop() and not menu:currentNotice()
  local tabs = {}
  local total = 0
  for _, t in ipairs(Menu().TABS) do
    local label = L(Menu().TAB_LABELS[t])
    tabs[#tabs + 1] = { tab = t, label = label, w = width(label) + 12 }
    total = total + width(label) + 12 + 2
  end
  if menu.canQuit then
    tabs[#tabs + 1] = { quit = true, label = L("QUIT"), w = width(L("QUIT")) + 12 }
    total = total + width(L("QUIT")) + 12 + 2
  end
  local brandW = M + 20 + width(Menu().TITLE, 2) + 16
  local x, y, h
  if brandW + total + M <= W then
    x, y, h = W - M - total, 12, 42
  else
    x, y, h = M, 44, 66
  end
  for _, t in ipairs(tabs) do
    local current = t.tab == menu.tab
    if current then
      p:rect(x, y, t.w, 20, "lcd")
      p:frame(x, y, t.w, 20, "line")
    end
    p:text(x + 6, y + 4, t.label, (top or current) and "ink" or "muted")
    if top then
      if t.quit then
        p:hit(x, y, t.w, 20, "quit", { kind = "quit" })
      else
        p:hit(x, y, t.w, 20, "tab:" .. t.tab, { kind = "tab", tab = t.tab })
      end
    end
    x = x + t.w + 2
  end
  bar.h = h
  p:rect(0, h, W, 1, "line")
  return h + 1
end

local HINTS = {
  keys = "ARROWS MOVE · ENTER OR Z CONFIRM · ESC OR X BACK",
  pad = "D-PAD MOVE · A CONFIRM · B BACK",
  mouse = "CLICK TO CHOOSE · RIGHT CLICK GOES BACK",
  touch = "TAP TO CHOOSE",
}

-- the footer's height for a width (the credit wraps)
local function footerHeight(W)
  local lines = Ui.wrap(Menu().CREDIT, W - 2 * Screens.MARGIN)
  return 8 + LINE + 4 + #lines * LINE + 6
end

local function footer(p, W, H, device)
  local M = Screens.MARGIN
  local fh = footerHeight(W)
  local y = H - fh
  p:rect(0, y, W, fh, "paper")
  p:rect(0, y, W, 1, "line")
  p:text(M, y + 8, Ui.fit(L(HINTS[device] or HINTS.keys), W - 2 * M), "muted")
  local ly = y + 8 + LINE + 4
  for _, line in ipairs(Ui.wrap(Menu().CREDIT, W - 2 * M)) do
    p:text(M, ly, line, "muted")
    ly = ly + LINE
  end
  return y
end

-- ------------------------------------------------------------ screens

local S = {}

function S.play(p, menu, c)
  local rows = menu:items()
  local y = c.y
  local version = menu.version
  local ready = menu.ready(version)
  -- caption
  p:rect(c.x, y + 4, 5, 5, "muted")
  p:text(c.x + 10, y, L("YOUR ADVENTURE HUB"), "muted")
  local right = L("Local saves · Direct connections")
  if width(L("YOUR ADVENTURE HUB")) + width(right) + 30 <= c.w then
    p:text(c.x + c.w - width(right), y, right, "muted")
  end
  y = y + LINE + 6
  -- the hero: the words, the paired 1 + 2 tiles
  local tiles = c.w >= 400
  local textW = tiles and math.floor(c.w * 0.58) or c.w - 24
  local close = panel(p, c.x, y, c.w)
  local hy = y + 12
  hy = hy + p:para(c.x + 12, hy, textW, L("THE SAME STORY. YOUR OWN TEAM."), "muted") + 4
  for _, line in ipairs({ L("One story."), L("Two journeys.") }) do
    hy = hy + p:para(c.x + 12, hy, textW, line, "ink", 2)
  end
  hy = hy + 4 + p:para(c.x + 12, hy + 4, textW,
    L("A shared campaign, from the first step to the final badge."), "muted")
  if tiles then
    local tw, th = 70, 70
    local tx = c.x + 12 + textW + math.floor((c.w - 24 - textW - 2 * tw - 22) / 2)
    for i, caption in ipairs({ L("YOUR TEAM"), L("THEIR TEAM") }) do
      local x = tx + (i - 1) * (tw + 22)
      local ty = y + 12 + (i - 1) * 10
      p:rect(x + 4, ty + 4, tw, th, "line")
      p:rect(x, ty, tw, th, "field")
      p:frame(x, ty, tw, th, "ink", 2)
      p:text(x + math.floor((tw - width(tostring(i), 4)) / 2), ty + 6, tostring(i), "ink", 4)
      local cap = Ui.fit(caption, tw - 4)
      p:text(x + math.floor((tw - width(cap)) / 2), ty + th - LINE - 4, cap, "ink")
    end
    p:text(tx + tw + 5, y + 12 + 26, "+", "ink", 2)
    hy = math.max(hy, y + 12 + 10 + th + 6)
  end
  hy = hy + 12
  close(hy)
  y = hy + 10
  -- the cartridges
  sectionLabel(p, c.x, y, L("YOUR CARTRIDGE"))
  local lang = L("%s · Verified imports", CoopMenu.languageName(version))
  if width(L("YOUR CARTRIDGE")) + width(lang) + 20 <= c.w then
    p:text(c.x + c.w - width(lang), y, lang, "muted")
  end
  y = y + LINE + 4
  local carts = rowsWith(rows, "cart")
  -- five in a row when the widest name or status fits, else three
  local need = 0
  for _, it in ipairs(carts) do
    need = math.max(need, width(it.row.label) + 8, width(it.row.detail or ""))
  end
  local perRow = (c.w - 4 * 6) / 5 >= need + 24 and 5 or 3
  local cw = math.floor((c.w - (perRow - 1) * 6) / perRow)
  for k, it in ipairs(carts) do
    local col, line = (k - 1) % perRow, math.floor((k - 1) / perRow)
    rowButton(p, c.x + col * (cw + 6), y + line * 40, cw, 34, it.index, it.row, {
      style = it.row.game == version and "selected" or "normal",
      swatch = "edition:" .. it.row.game, sub = it.row.detail,
    })
  end
  y = y + math.ceil(#carts / perRow) * 40 + 4
  -- what fits, PLAY SOLO
  local soloI, soloRow = rowOf(rows, "solo")
  local label = Games.label(version)
  local soloW = fitWidth(L("PLAY SOLO →"))
  -- which games play together (#9): Red with Blue, Yellow with Yellow
  p:para(c.x, y + 5, c.w - soloW - 8,
    L("%s plays with %s", label, CoopMenu.togetherText(version)), "muted", 1, 2)
  rowButton(p, c.x + c.w - soloW, y, soloW, 22, soloI, soloRow,
    { style = "quiet", label = L("PLAY SOLO →") })
  y = y + 30
  -- the three ways to play together
  local acts = {
    { id = "host", sub = L("Your save. Friends can join anytime."), style = "primary" },
    { id = "join", sub = L("Nearby games or a direct address.") },
    { id = "couch", sub = L("Two players. One screen. Comes later."), tag = L("PLANNED") },
  }
  local three = c.w >= 420
  local aw = three and math.floor((c.w - 12) / 3) or c.w
  local ah = 0
  for _, a in ipairs(acts) do
    ah = math.max(ah, (1 + #Ui.wrap(a.sub, aw - 16)) * LINE + 14)
  end
  for k, a in ipairs(acts) do
    local i, row = rowOf(rows, a.id)
    local x = three and c.x + (k - 1) * (aw + 6) or c.x
    local ay = three and y or y + (k - 1) * (ah + 6)
    rowButton(p, x, ay, aw, ah, i, row, { style = a.style, sub = a.sub, tag = a.tag })
  end
  y = y + (three and ah or 3 * (ah + 6) - 6) + 10
  -- no ROM for the selected cartridge
  if not ready then
    local i, row = rowOf(rows, "import")
    local bw = fitWidth(row.label)
    local closeN = panel(p, c.x, y, c.w)
    local th = p:para(c.x + 10, y + 9, c.w - bw - 30,
      L("%s has no imported cartridge on this device.", label), "ink")
    rowButton(p, c.x + c.w - bw - 8, y + 6, bw, 22, i, row, { style = "primary" })
    closeN(y + math.max(th + 12, 34))
    y = y + math.max(th + 12, 34) + 10
  end
  -- the last session
  local li, lrow = rowOf(rows, "last")
  if li then
    local last = menu:lastSession()
    p:rect(c.x, y, c.w, 1, "line")
    y = y + 8
    local bw = fitWidth(lrow.label .. " →")
    local textW2 = c.w - bw - 12
    local title = last.kind == "host" and last.campaign.title or (last.title or last.address)
    p:text(c.x, y, L("LAST SESSION"), "muted")
    p:text(c.x + width(L("LAST SESSION")) + 8, y,
      Ui.fit(title, textW2 - width(L("LAST SESSION")) - 8), "ink")
    local what
    if last.kind == "host" then
      local names = {}
      for _, pl in ipairs(last.campaign.players or {}) do names[#names + 1] = pl.name end
      what = L("%s · %s · Hosted on this device", Games.label(last.version),
        #names > 0 and table.concat(names, ", ") or L("no players yet"))
    else
      what = L("%s · Joined at %s", Games.label(last.version), tostring(last.address))
    end
    p:text(c.x, y + LINE, Ui.fit(what, textW2), "muted")
    rowButton(p, c.x + c.w - bw, y + 2, bw, 24, li, lrow, { label = lrow.label .. " →" })
    y = y + 2 * LINE + 6
  end
  return y
end

function S.solo(p, menu, c)
  local rows = menu:items()
  local label = Games.label(menu.version)
  local y = c.y + heading(p, c, c.y, L("Play %s solo", label),
    L("Your own save, apart from every campaign."), true)
  local info = menu.saveInfo(menu.version)
  for i, row in ipairs(rows) do
    if row.id ~= "back" then
      local sub
      if row.id == "continue" and info then
        sub = L("%s · BADGES %d · %s", info.name, info.badges, info.time)
      elseif row.id == "new" then
        sub = info and L("A new save slot. The old save stays on disk.")
          or L("The game starts from its title screen.")
      elseif row.id == "reimport" then
        sub = L("Import this cartridge's ROM again.")
      end
      rowButton(p, c.x, y, c.w, 40, i, row, { sub = sub, style = i == 1 and "primary" or nil })
      y = y + 46
    end
  end
  return y
end

function S.controls(p, menu, c)
  local rows = menu:items()
  local y = c.y + heading(p, c, c.y, L("Controls"),
    L("The game's buttons, and each player's device for couch co-op."), false)
  -- a capture under way: the prompt, and nothing else takes a press (#4)
  local prompt = menu:capturing()
  if prompt then
    local lines = Ui.wrap(prompt, c.w - 24)
    local h = #lines * LINE + 16
    p:rect(c.x, y, c.w, h, "lcd")
    p:frame(c.x, y, c.w, h, "accent", 2)
    for i, line in ipairs(lines) do p:text(c.x + 12, y + 8 + (i - 1) * LINE, line, "ink") end
    y = y + h + 10
  end
  local a, b, wide = columns(c, 0.55)
  -- the game's buttons
  local close = panel(p, a.x, y, a.w)
  local ly = y + 10
  sectionLabel(p, a.x + 10, ly, L("IN THE GAME"))
  ly = ly + LINE + 4
  for _, e in ipairs(rowsWith(rows, "bind")) do
    rowButton(p, a.x + 10, ly, a.w - 20, 22, e.index, e.row, { detail = e.row.detail })
    ly = ly + 26
  end
  local ri, rrow = rowOf(rows, "reset")
  if ri then
    rowButton(p, a.x + 10, ly + 2, fitWidth(rrow.label), 22, ri, rrow, { style = "quiet" })
    ly = ly + 28
  end
  ly = ly + p:para(a.x + 10, ly + 2, a.w - 20,
    L("A key and a pad button for each. The game's own CONTROLS menu shows the same."), "muted") + 4
  close(ly + 6)
  -- the players' devices
  local by = wide and y or ly + 18
  local close2 = panel(p, b.x, by, b.w)
  local ry = by + 10
  sectionLabel(p, b.x + 10, ry, L("PLAYER DEVICES"))
  ry = ry + LINE + 4
  for _, e in ipairs(rowsWith(rows, "seat")) do
    rowButton(p, b.x + 10, ry, b.w - 20, 22, e.index, e.row, { detail = e.row.detail })
    ry = ry + 26
  end
  local ci, crow = rowOf(rows, "clear")
  if ci then
    rowButton(p, b.x + 10, ry + 2, fitWidth(crow.label), 22, ci, crow, { style = "quiet" })
    ry = ry + 28
  end
  if menu.controls then
    sectionLabel(p, b.x + 10, ry + 4, L("CONNECTED PADS"))
    ry = ry + LINE + 6
    local pads = menu.controls:padList()
    if #pads == 0 then
      ry = ry + p:para(b.x + 10, ry, b.w - 20, L("No pad connected."), "muted") + 4
    end
    for _, e in ipairs(pads) do
      local tag = e.player and L("P%d", e.player)
      local room = b.w - 20 - (tag and width(tag) + 12 or 0)
      p:text(b.x + 10, ry, Ui.fit(e.name, room), "ink")
      if tag then
        local tx = b.x + 10 + width(Ui.fit(e.name, room)) + 6
        p:frame(tx, ry, width(tag) + 6, LINE - 1, "muted")
        p:text(tx + 3, ry, tag, "muted")
      end
      ry = ry + LINE + 2
    end
  end
  ry = ry + p:para(b.x + 10, ry + 4, b.w - 20,
    L("Couch co-op seats each player at the device claimed here, remembered by pad. Without a claim, player 1 uses any device, as in solo play."),
    "muted") + 4
  close2(ry + 8)
  -- the launcher itself
  y = math.max(ly + 6, ry + 8) + 12
  local close3 = panel(p, c.x, y, c.w)
  local ky = y + 10
  sectionLabel(p, c.x + 10, ky, L("IN THE LAUNCHER"))
  ky = ky + LINE + 4
  for _, pair in ipairs({
    { L("MOVE"), L("Arrows or WASD · D-pad or stick") },
    { L("CONFIRM"), L("Z, Enter or Space · A or START") },
    { L("BACK"), L("X, Esc or Backspace · B") },
    { L("MOUSE"), L("A click chooses, a right click goes back.") },
    { L("TOUCH"), L("A tap chooses.") },
  }) do
    p:text(c.x + 10, ky, pair[1], "ink")
    ky = ky + p:para(c.x + 100, ky, c.w - 110, pair[2], "muted") + 4
  end
  close3(ky + 6)
  return ky + 6
end

function S.settings(p, menu, c)
  local rows = menu:items()
  local y = c.y + heading(p, c, c.y, L("Settings"),
    L("The launcher's own settings, then the game's. A pressed value moves on; left and right step it."), false)
  local notes = {
    language = L("The language of the launcher. A game's text follows its cartridge."),
    theme = L("Light or dark colours for the launcher."),
    window = L("A window, or the whole screen."),
    scale = L("Draw the game at an exact multiple of its pixels; OFF fits the window."),
    music = L("0 to 7."),
    sound = L("0 to 7."),
    textSpeed = L("How fast text appears."),
    animations = L("Attack animations in battle."),
    battleStyle = L("SHIFT asks before the next Pokemon; SET does not."),
    mods = L("The mods installed on this device, each on or off for this game."),
  }
  local groups = {
    { "launcher", L("LAUNCHER") }, { "video", L("VIDEO") }, { "audio", L("AUDIO") }, { "game", L("GAME") },
    { "mods", L("MODS") },
  }
  for _, g in ipairs(groups) do
    local mine = {}
    for i, row in ipairs(rows) do
      if (row.group or "launcher") == g[1] then mine[#mine + 1] = { index = i, row = row } end
    end
    if #mine > 0 then
      local close = panel(p, c.x, y, c.w)
      local ry = y + 10
      sectionLabel(p, c.x + 10, ry, g[2])
      ry = ry + LINE + 4
      for _, e in ipairs(mine) do
        local row = e.row
        p:text(c.x + 10, ry + 5, row.label, "ink")
        p:para(c.x + 10, ry + 5 + LINE, c.w - 150, notes[row.id] or "", "muted", 1, 2)
        local bw = math.max(100, fitWidth(row.detail, 24))
        rowButton(p, c.x + c.w - bw - 10, ry + 4, bw, 22, e.index, row,
          { label = row.option and ("< " .. row.detail .. " >") or row.detail })
        ry = ry + 2 * LINE + 14
      end
      close(ry + 4)
      y = ry + 14
    end
  end
  if not menu.gameOptions then
    y = y + p:para(c.x + 10, y, c.w - 20,
      L("Video, sound and game options are in each game's own OPTIONS menu."), "muted") + 4
  else
    y = y + p:para(c.x + 10, y, c.w - 20,
      L("The game's options are the ones its own OPTIONS menu shows; a change here is a change there."), "muted") + 4
  end
  return y
end

function S.help(p, menu, c)
  local rows = menu:items()
  local y = c.y + heading(p, c, c.y, L("A little help before you go"),
    L("Co-op connects directly to the hosting device."), false)
  local a, b, wide = columns(c, 0.52)
  local close = panel(p, a.x, y, a.w)
  local ly = y + 10
  sectionLabel(p, a.x + 10, ly, L("CONNECTING"))
  ly = ly + LINE + 6
  for _, pair in ipairs({
    { L("At home"), L("Use Nearby or the host's home address. Both devices use the same network.") },
    { L("Over the internet"), L("Use a VPN address, or forward UDP 24680 on the hosting network.") },
    { L("Cartridges"), L("Both players need the same game, ROM and language. Red with Blue comes later.") },
  }) do
    p:text(a.x + 10, ly, pair[1], "ink")
    ly = ly + LINE + p:para(a.x + 10, ly + LINE, a.w - 20, pair[2], "muted") + 8
  end
  close(ly)
  local by = wide and y or ly + 12
  local close2 = panel(p, b.x, by, b.w)
  local ry = by + 10
  sectionLabel(p, b.x + 10, ry, L("SESSION LOGS"))
  ry = ry + LINE + 6
  local si, srow = rowOf(rows, "share")
  local bw = math.max(60, fitWidth(srow.detail))
  p:text(b.x + 10, ry + 5, srow.label, "ink")
  rowButton(p, b.x + b.w - bw - 10, ry, bw, 22, si, srow, { label = srow.detail })
  ry = ry + 28
  ry = ry + p:para(b.x + 10, ry, b.w - 20,
    L("Shared logs go to the players of a session. They hold trainer names and addresses: never post them."),
    "muted") + 8
  local oi, orow = rowOf(rows, "open")
  if oi then
    rowButton(p, b.x + 10, ry, fitWidth(orow.label), 22, oi, orow)
    ry = ry + 30
  end
  close2(ry)
  y = math.max(ly, ry) + 12
  local close3 = panel(p, c.x, y, c.w)
  local cy = y + 10
  sectionLabel(p, c.x + 10, cy, L("ABOUT"))
  cy = cy + LINE + 6
  for _, para in ipairs(Menu().credits()) do
    cy = cy + p:para(c.x + 10, cy, c.w - 20, para, "ink") + 6
  end
  close3(cy + 4)
  return cy + 4
end

-- the SAVES page (#6): the slots as cards, the questions, the import
local function savesList(p, saves, c)
  local rows = saves:items()
  local d = saves:details()
  local label = Games.label(saves.version)
  local y = c.y + heading(p, c, c.y, L("%s saves", label),
    L("Each slot is one adventure. The game continues the active one."), true)
  local byslot = {}
  for i, r in ipairs(rows) do
    if r.slot then
      byslot[r.slot] = byslot[r.slot] or {}
      byslot[r.slot][r.id] = i
    end
  end
  for _, slot in ipairs(d.slots) do
    local idx = byslot[slot.id] or {}
    local bws = { fitWidth(L("PLAY →")), fitWidth(L("EXPORT")), fitWidth(L("DELETE")), fitWidth(L("EDIT")) }
    local bw = (idx.play and bws[1] + 6 or 0) + (idx.edit and bws[4] + 6 or 0) + bws[2] + bws[3] + 6
    local inline = c.w - bw - 20 >= 180
    local ch = inline and 3 * LINE + 14 or 3 * LINE + 44
    p:rect(c.x, y, c.w, ch, slot.active and "lcd" or "paper")
    p:frame(c.x, y, c.w, ch, slot.active and "accent" or "line", slot.active and 2 or 1)
    local tw = inline and c.w - bw - 30 or c.w - 20
    local title = slot.name or L("Empty slot")
    if slot.active then title = title .. " · " .. L("ACTIVE") end
    p:text(c.x + 10, y + 7, Ui.fit(title, tw), "ink")
    local line2 = slot.exists and L("BADGES %d · POKéDEX %d · TIME %s", slot.badges, slot.dex, slot.time)
      or L("No save yet: the game starts from its title screen.")
    p:text(c.x + 10, y + 7 + LINE, Ui.fit(line2, tw), "muted")
    local line3 = slot.campaign and L("Campaign: %s (entered from CAMPAIGNS)", slot.campaign)
      or (slot.label and slot.label ~= "" and slot.label ~= slot.name and L("%s · %s", slot.id, slot.label) or slot.id)
    p:text(c.x + 10, y + 7 + 2 * LINE, Ui.fit(line3, tw), "muted")
    local bx = inline and c.x + c.w - bw - 10 or c.x + 10
    local by = inline and y + math.floor((ch - 22) / 2) or y + 3 * LINE + 14
    if idx.play then
      rowButton(p, bx, by, bws[1], 22, idx.play, rows[idx.play], { style = "primary" })
      bx = bx + bws[1] + 6
    end
    if idx.edit then
      rowButton(p, bx, by, bws[4], 22, idx.edit, rows[idx.edit])
      bx = bx + bws[4] + 6
    end
    rowButton(p, bx, by, bws[2], 22, idx.export, rows[idx.export])
    bx = bx + bws[2] + 6
    rowButton(p, bx, by, bws[3], 22, idx.delete, rows[idx.delete])
    y = y + ch + 6
  end
  if #d.slots == 0 then
    y = y + p:para(c.x, y, c.w, L("No saves for %s on this device yet.", label), "muted") + 6
  end
  y = y + 6
  local n = #d.slots
  p:text(c.x, y + 5, n == 1 and L("1 save slot") or L("%d save slots", n), "muted")
  local ni, nrow = rowOf(rows, "new")
  local ii, irow = rowOf(rows, "import")
  actionsRight(p, c, y, { { index = ii, row = irow }, { index = ni, row = nrow, style = "primary" } })
  y = y + 30
  y = y + p:para(c.x, y + 4, c.w,
    L("A .sav is the cartridge's own format, as an emulator or a cartridge reader writes it. Exports go to the exports folder of this device."),
    "muted") + 4
  return y
end

local function savesQuestion(p, saves, c, title)
  local rows = saves:items()
  local y = c.y + heading(p, c, c.y, title, nil, false)
  local close = panel(p, c.x, y, c.w)
  local py = y + 10 + p:para(c.x + 10, y + 10, c.w - 20, saves:prompt() or "", "ink")
  close(py + 10)
  y = py + 18
  local list = {}
  for i, row in ipairs(rows) do
    list[#list + 1] = { index = i, row = row, style = row.id == "confirm" and "primary" or nil }
  end
  actionsRight(p, c, y, list)
  return y + 30
end

local function savesImport(p, saves, c)
  local label = Games.label(saves.version)
  local y = c.y + heading(p, c, c.y, L("Import a save"),
    L("A .sav for %s becomes a new save slot. Nothing is uploaded.", label), true)
  local close = panel(p, c.x, y, c.w)
  local py = y + 10
  local help = saves.canType
    and L("Drop the .sav file on this window, or type its path and press ENTER.")
    or saves.canPick and L("Choose the .sav file; the system's file picker opens.")
    or L("Drop the .sav file on this window.")
  py = py + p:para(c.x + 10, py, c.w - 20, help, "ink") + 8
  py = py + pickButton(p, c, saves:items(), py)
  if saves.canType then
    p:rect(c.x + 10, py, c.w - 20, 22, "field")
    p:frame(c.x + 10, py, c.w - 20, 22, "line")
    local shown = saves.path
    while width(shown) > c.w - 40 do shown = shown:sub(2) end
    p:text(c.x + 16, py + 5, shown .. "_", "ink")
    py = py + 30
  end
  py = py + p:para(c.x + 10, py, c.w - 20,
    L("32 KB in the cartridge's format (.sav, .srm). The save's trainer, team, items and progress come along; the slot it lands in is made the active one."),
    "muted")
  close(py + 10)
  return py + 10
end

function S.saves(p, menu, c)
  local saves = menu.saves
  if not saves then return c.y end
  local s = saves.screen
  if s == "delete" then return savesQuestion(p, saves, c, L("Delete this save?")) end
  if s == "confirm" then return savesQuestion(p, saves, c, L("A bigger file than expected")) end
  if s == "import" then return savesImport(p, saves, c) end
  return savesList(p, saves, c)
end

-- the MODS page (#30): the installed mods as cards, the install and the
-- optional file screens
local function modsList(p, mods, c)
  local rows = mods:items()
  local label = Games.label(mods.version)
  local y = c.y + heading(p, c, c.y, L("Mods for %s", label),
    L("Mods installed on this device. A change takes effect when the game starts."), true)
  local byMod = {}
  for i, r in ipairs(rows) do
    if r.mod then
      byMod[r.mod] = byMod[r.mod] or { optional = {} }
      if r.id == "toggle" then byMod[r.mod].toggle = i end
      if r.id == "optional" then byMod[r.mod].optional[r.import] = i end
    end
  end
  for _, m in ipairs(mods.mods) do
    local idx = byMod[m.id] or { optional = {} }
    local bw = math.max(fitWidth(L("ON")), fitWidth(L("OFF"))) + 8
    local tw = c.w - bw - 30
    local lines = {}
    lines[#lines + 1] = { m.problem and L("Cannot load: %s", m.problem) or m.description, "muted" }
    local tags = {}
    if m.engine then tags[#tags + 1] = L("PATCHES ENGINE CODE") end
    if m.link then tags[#tags + 1] = L("CHANGES LINK PLAY") end
    if #tags > 0 then lines[#lines + 1] = { table.concat(tags, " · "), "muted" } end
    local ch = (1 + #lines) * LINE + 14
    local imports = {}
    for _, imp in ipairs(m.imports or {}) do
      imports[#imports + 1] = imp
      ch = ch + LINE + 14
    end
    p:rect(c.x, y, c.w, ch, m.enabled and "lcd" or "paper")
    p:frame(c.x, y, c.w, ch, m.enabled and "accent" or "line", m.enabled and 2 or 1)
    local title = m.version and L("%s · %s", m.name, m.version) or m.name
    p:text(c.x + 10, y + 7, Ui.fit(title, tw), "ink")
    local ly = y + 7 + LINE
    for _, line in ipairs(lines) do
      p:text(c.x + 10, ly, Ui.fit(line[1], tw), line[2])
      ly = ly + LINE
    end
    if idx.toggle then
      rowButton(p, c.x + c.w - bw - 10, y + 7, bw, 22, idx.toggle, rows[idx.toggle],
        { style = m.enabled and "primary" or nil })
    end
    for _, imp in ipairs(imports) do
      local ib = idx.optional[imp.id]
      local iw = fitWidth(L("IMPORT FILE"))
      local text = imp.present and L("Optional: %s · IMPORTED", imp.name)
        or L("Optional: %s · NOT IMPORTED", imp.name)
      p:text(c.x + 10, ly + 9, Ui.fit(text, c.w - iw - 30), "muted")
      if ib then rowButton(p, c.x + c.w - iw - 10, ly + 4, iw, 22, ib, rows[ib]) end
      ly = ly + LINE + 14
    end
    y = y + ch + 6
  end
  if #mods.mods == 0 then
    y = y + p:para(c.x, y, c.w, L("No mods on this device yet."), "muted") + 6
  end
  y = y + 6
  local n = #mods.mods
  p:text(c.x, y + 5, n == 1 and L("1 mod") or L("%d mods", n), "muted")
  local ii, irow = rowOf(rows, "install")
  actionsRight(p, c, y, { { index = ii, row = irow, style = "primary" } })
  y = y + 30
  y = y + p:para(c.x, y + 4, c.w,
    L("A mod's code runs in the game with the game's rights. Install mods you trust. A mod that changes link play needs the same mod on every partner's device."),
    "muted") + 4
  return y
end

local function modsPath(p, mods, c, title, subtitle, help, foot)
  local y = c.y + heading(p, c, c.y, title, subtitle, true)
  local close = panel(p, c.x, y, c.w)
  local py = y + 10
  py = py + p:para(c.x + 10, py, c.w - 20, help, "ink") + 8
  py = py + pickButton(p, c, mods:items(), py)
  if mods.canType then
    p:rect(c.x + 10, py, c.w - 20, 22, "field")
    p:frame(c.x + 10, py, c.w - 20, 22, "line")
    local shown = mods.path
    while width(shown) > c.w - 40 do shown = shown:sub(2) end
    p:text(c.x + 16, py + 5, shown .. "_", "ink")
    py = py + 30
  end
  py = py + p:para(c.x + 10, py, c.w - 20, foot, "muted")
  close(py + 10)
  return py + 10
end

function S.mods(p, menu, c)
  local mods = menu.mods
  if not mods then return c.y end
  if mods.screen == "install" then
    return modsPath(p, mods, c, L("Install a mod"),
      L("A mod's folder or its .zip, copied into this device's save folder."),
      mods.canType and L("Drop the mod's folder or .zip on this window, or type the path of its .zip and press ENTER.")
        or mods.canPick and L("Choose the mod's .zip; the system's file picker opens.")
        or L("Drop the mod's folder or .zip on this window."),
      L("The mod is installed for every game; it is on until you turn it off. A mod already installed is replaced by the new copy."))
  end
  if mods.screen == "import" then
    local m, imp = mods:pendingImport()
    return modsPath(p, mods, c, L("Import a file"),
      m and L("%s for %s", imp.name, m.name) or nil,
      mods.canType and L("Drop the file on this window, or type its path and press ENTER.")
        or mods.canPick and L("Choose the file; the system's file picker opens.")
        or L("Drop the file on this window."),
      L("The file is checked against the mod's manifest and copied into the mod's folder. Nothing is uploaded."))
  end
  return modsList(p, mods, c)
end

function S.import(p, menu, c)
  local label = Games.label(menu.version)
  local y = c.y + heading(p, c, c.y, L("Bring your cartridge"),
    L("Import a verified ROM on this device. Nothing is uploaded."), true)
  local close = panel(p, c.x, y, c.w)
  local py = y + 10
  sectionLabel(p, c.x + 10, py, L("%s · NOT IMPORTED", label))
  py = py + LINE + 6
  local help = menu.canType
    and L("Drop the ROM file on this window, or type its path and press ENTER.")
    or menu.canPick and L("Choose the ROM file; the system's file picker opens.")
    or L("Importing a ROM on this device comes later.")
  py = py + p:para(c.x + 10, py, c.w - 20, help, "ink") + 8
  py = py + pickButton(p, c, menu:items(), py)
  if menu.canType then
    p:rect(c.x + 10, py, c.w - 20, 22, "field")
    p:frame(c.x + 10, py, c.w - 20, 22, "line")
    local shown = menu.path
    while width(shown) > c.w - 40 do shown = shown:sub(2) end
    local blink = math.floor((menu.clock or 0) * 2) % 2 == 0 and "_" or ""
    p:text(c.x + 16, py + 5, shown .. blink, "ink")
    py = py + 30
  end
  py = py + p:para(c.x + 10, py, c.w - 20,
    L("Clean dumps of Pokemon Red, Blue and Yellow (US) and of the German Rote, Blaue and Gelbe Edition; .zip and .7z where the system opens them."),
    "muted")
  close(py + 10)
  return py + 10
end

function S.importing(p, menu, c)
  local job = menu.importing or {}
  local y = c.y + heading(p, c, c.y, L("Importing %s", Games.label(job.version)),
    job.name or "", false)
  local close = panel(p, c.x, y, c.w)
  local py = y + 12
  -- the extractor's own step names are upstream's (English)
  local stage = job.stage or ""
  if stage == "Preparing" or stage == "Ready" then stage = L(stage) end
  py = py + p:para(c.x + 10, py, c.w - 20, stage, "ink") + 8
  p:frame(c.x + 10, py, c.w - 20, 12, "ink")
  p:rect(c.x + 12, py + 2, math.floor((c.w - 24) * (job.progress or 0)), 8, "accent")
  close(py + 24)
  return py + 24
end

-- ---------------------------------------------------------- co-op screens

local C = {}

local function cardLines(card)
  local names = {}
  for _, pl in ipairs(card.players or {}) do names[#names + 1] = pl.name end
  local who = #names > 0 and table.concat(names, ", ") or L("no players yet")
  local when = card.hosted and L("Last hosted %s", os.date("!%Y-%m-%d", card.hosted))
    or L("Never hosted")
  return L("%s · %s", Games.label(card.game), who), when
end

function C.list(p, coop, c, top)
  local rows = coop:items()
  local d = coop:details()
  local y
  if top then
    y = c.y + heading(p, c, c.y, L("Your campaigns"),
      L("A separate adventure for each group. Solo saves stay separate."), false)
  else
    y = c.y + heading(p, c, c.y, L("Choose your campaign"),
      L("Host %s with a matching cartridge. Your friends can join later.",
        Games.label(coop.version)), true)
  end
  local byCard = {}
  for i, r in ipairs(rows) do
    if r.campaign then
      byCard[r.campaign.id] = byCard[r.campaign.id] or {}
      byCard[r.campaign.id][r.id] = i
    end
  end
  for _, card in ipairs(d.cards) do
    local idx = byCard[card.id] or {}
    local hostI, renI, delI = idx.campaign, idx.rename, idx.delete
    local bws = { fitWidth(L("HOST →")), fitWidth(L("RENAME")), fitWidth(L("DELETE")) }
    local bw = bws[1] + bws[2] + bws[3] + 12
    -- the switch of wild Pokémon from both versions (#9), its own line
    local mixI = idx.mix
    local inline = c.w - bw - 20 >= 180
    local ch = inline and 3 * LINE + 14 or 3 * LINE + 44
    if mixI then ch = ch + 28 end
    p:rect(c.x, y, c.w, ch, "paper")
    p:frame(c.x, y, c.w, ch, "line")
    local tw = inline and c.w - bw - 30 or c.w - 20
    p:text(c.x + 10, y + 7, Ui.fit(card.title, tw), "ink")
    local who, when = cardLines(card)
    p:text(c.x + 10, y + 7 + LINE, Ui.fit(who, tw), "muted")
    p:text(c.x + 10, y + 7 + 2 * LINE, Ui.fit(when, tw), "muted")
    local bx = inline and c.x + c.w - bw - 10 or c.x + 10
    local by = inline and y + math.floor((ch - (mixI and 28 or 0) - 22) / 2) or y + 3 * LINE + 14
    for k, i in ipairs({ hostI, renI, delI }) do
      if i then
        rowButton(p, bx, by, bws[k], 22, i, rows[i], {
          label = k == 1 and L("HOST →") or nil, style = k == 1 and "primary" or nil })
      end
      bx = bx + bws[k] + 6
    end
    if mixI then
      local mw = fitWidth(rows[mixI].label)
      rowButton(p, c.x + c.w - mw - 10, y + ch - 28, mw, 22, mixI, rows[mixI])
    end
    y = y + ch + 6
  end
  if #d.cards == 0 then
    y = y + p:para(c.x, y, c.w, top and L("No campaigns on this device yet.")
      or L("No campaigns for this cartridge yet."), "muted") + 6
  end
  if d.deleted then
    local ri, rrow = rowOf(rows, "restore")
    local bw = fitWidth(rrow.label)
    local close = panel(p, c.x, y, c.w)
    local th = p:para(c.x + 10, y + 9, c.w - bw - 30,
      L("Deleted %s. A backup is kept.", d.deleted.title), "ink")
    rowButton(p, c.x + c.w - bw - 8, y + 6, bw, 22, ri, rrow)
    close(y + math.max(th + 12, 34))
    y = y + math.max(th + 12, 34) + 6
  end
  y = y + 6
  local n = #d.cards
  p:text(c.x, y + 5, n == 1 and L("1 campaign on this device")
    or L("%d campaigns on this device", n), "muted")
  local ni, nrow = rowOf(rows, "new")
  actionsRight(p, c, y, { { index = ni, row = nrow, label = L("+ NEW CAMPAIGN"), style = "primary" } })
  return y + 30
end

-- HOW YOU START and the row under it (#57): a label and a button each,
-- as the form's other rows; returns the y under them
local START_ROWS = { how = true, starter = true, save = true }
local function startRows(p, c, rows, py)
  for i, row in ipairs(rows) do
    if START_ROWS[row.id] then
      p:text(c.x + 10, py, row.label, "ink")
      py = py + LINE + 2
      rowButton(p, c.x + 10, py, c.w - 20, 24, i, row,
        { label = row.value, detail = row.id == "save" and L("PICK") or L("CHANGE") })
      py = py + 32
    end
  end
  return py
end

function C.new(p, coop, c)
  local rows = coop:items()
  local y = c.y + heading(p, c, c.y, L("Start a shared adventure"),
    L("Name the campaign, the trainer you will play and the rival."), true)
  local close = panel(p, c.x, y, c.w)
  local py = y + 10
  for _, id in ipairs({ "title", "you", "rival" }) do
    local i, row = rowOf(rows, id)
    p:text(c.x + 10, py, row.label, "ink")
    py = py + LINE + 2
    rowButton(p, c.x + 10, py, c.w - 20, 24, i, row, { label = row.value, detail = L("EDIT") })
    py = py + 32
  end
  -- wild Pokémon from both versions (#9, design A13.3), a game with a pair
  do
    local i, row = rowOf(rows, "mix")
    if row then
      p:text(c.x + 10, py, row.label, "ink")
      py = py + LINE + 2
      rowButton(p, c.x + 10, py, c.w - 20, 24, i, row, { label = row.value, detail = L("CHANGE") })
      py = py + 28
      py = py + p:para(c.x + 10, py, c.w - 20,
        L("The other version's wild Pokémon appear in half of their places. Changeable later on the campaign's card."),
        "muted") + 8
    end
  end
  py = startRows(p, c, rows, py) -- how the host's player starts (#57)
  p:text(c.x + 10, py, L("CARTRIDGE"), "ink")
  p:text(c.x + 10 + 90, py, L("%s · %s", Games.label(coop.version),
    CoopMenu.languageName(coop.version)), "muted")
  py = py + LINE + 6
  py = py + p:para(c.x + 10, py, c.w - 20,
    L("A new campaign uses a save slot of its own. Your solo progress stays separate."), "muted")
  close(py + 10)
  y = py + 18
  p:text(c.x, y + 5, L("Direct play · UDP 24680"), "muted")
  local gi, grow = rowOf(rows, "go")
  actionsRight(p, c, y, { { index = gi, row = grow, label = L("CREATE AND HOST →"), style = "primary" } })
  return y + 30
end

function C.delete(p, coop, c)
  local rows = coop:items()
  local d = coop:details()
  local y = c.y + heading(p, c, c.y, L("Delete this campaign?"), d.campaign.title, false)
  local close = panel(p, c.x, y, c.w)
  local py = y + 10 + p:para(c.x + 10, y + 10, c.w - 20,
    L("The campaign leaves the list. Its last state is kept as a backup you can restore."), "ink")
  close(py + 10)
  y = py + 18
  local list = {}
  for i, row in ipairs(rows) do
    list[#list + 1] = { index = i, row = row, style = row.id == "yes" and "primary" or nil }
  end
  actionsRight(p, c, y, list)
  return y + 30
end

function C.stop(p, coop, c)
  local rows = coop:items()
  local d = coop:details()
  local y = c.y + heading(p, c, c.y, L("Close this session?"),
    coop.campaign and coop.campaign.title or "", false)
  local close = panel(p, c.x, y, c.w)
  local text = d.partners == 1
    and L("1 friend will return to their launcher. The session cannot pass to another player.")
    or L("%d friends will return to their launcher. The session cannot pass to another player.",
      d.partners)
  local py = y + 10 + p:para(c.x + 10, y + 10, c.w - 20, text, "ink")
  close(py + 10)
  y = py + 18
  local list = {}
  for i, row in ipairs(rows) do
    list[#list + 1] = { index = i, row = row, style = row.id == "yes" and "primary" or nil }
  end
  actionsRight(p, c, y, list)
  return y + 30
end

function C.hosting(p, coop, c)
  local rows = coop:items()
  local d = coop:details()
  local title = d.campaign and d.campaign.title or ""
  local y = c.y + heading(p, c, c.y, title, L("Hosting %s · %s · Direct connection",
    Games.label(d.game), CoopMenu.languageName(d.game)), false)
  local a, b, wide = columns(c, 0.5)
  local close = panel(p, a.x, y, a.w)
  local ly = y + 10
  sectionLabel(p, a.x + 10, ly, L("PLAYERS · %d / %d", #d.players, d.max))
  ly = ly + LINE + 6
  for _, pl in ipairs(d.players) do
    p:rect(a.x + 10, ly, a.w - 20, 2 * LINE + 8, "paper")
    p:frame(a.x + 10, ly, a.w - 20, 2 * LINE + 8, "line")
    p:text(a.x + 18, ly + 4, pl.name, "ink")
    local what = pl.host and L("Host · this device") or L("Connected trainer")
    if pl.game and pl.game ~= d.game then what = what .. " · " .. Games.label(pl.game) end
    p:text(a.x + 18, ly + 4 + LINE, Ui.fit(what, a.w - 36), "muted")
    ly = ly + 2 * LINE + 12
  end
  -- wild Pokémon from both versions (#9): on, or the version it waits for
  if d.mix then
    local text = d.mix.waiting
      and L("Wild Pokémon from both versions: waiting for a %s player.", Games.label(d.mix.waiting))
      or L("Wild Pokémon from both versions: on.")
    ly = ly + p:para(a.x + 10, ly, a.w - 20, text, "ink") + 4
  end
  ly = ly + p:para(a.x + 10, ly, a.w - 20, L("You can enter now. Friends can join later."), "muted")
  close(ly + 10)
  local by = wide and y or ly + 22
  local close2 = panel(p, b.x, by, b.w)
  local ry = by + 10
  sectionLabel(p, b.x + 10, ry, L("FRIENDS JOIN AT"))
  ry = ry + LINE + 6
  if d.warning then
    ry = ry + p:para(b.x + 10, ry, b.w - 20, d.warning, "error") + 6
  end
  for _, it in ipairs(rowsWith(rows, "address")) do
    local bw = fitWidth(it.row.label)
    p:rect(b.x + 10, ry, b.w - 20, 1, "line")
    p:text(b.x + 10, ry + 5, Ui.fit(it.row.detail, b.w - bw - 30), "muted")
    p:text(b.x + 10, ry + 5 + LINE, Ui.fit(it.row.value, b.w - bw - 30), "ink")
    rowButton(p, b.x + b.w - bw - 10, ry + 8, bw, 20, it.index, it.row)
    ry = ry + 2 * LINE + 12
  end
  ry = ry + p:para(b.x + 10, ry, b.w - 20, L("Same network, VPN, or a forwarded game port."),
    "muted")
  close2(ry + 10)
  y = math.max(ly, ry) + 18
  local list = {}
  -- enter2: two players on this device, when CONTROLS has a device for each (#11)
  for _, id in ipairs({ "stop", "enter2", "enter" }) do
    local i, row = rowOf(rows, id)
    if row then
      list[#list + 1] = { index = i, row = row, style = id == "enter" and "primary" or nil,
                          label = id == "enter" and L("ENTER THE WORLD →") or nil }
    end
  end
  actionsRight(p, c, y, list)
  return y + 30
end

function C.join(p, coop, c)
  local rows = coop:items()
  local d = coop:details()
  local y = c.y + heading(p, c, c.y, L("Join a friend"),
    L("Find a nearby campaign or use the host's address."), true)
  local a, b, wide = columns(c, 0.55)
  local ly = y
  sectionLabel(p, a.x, ly, L("NEARBY"))
  ly = ly + LINE + 4
  local nearby = rowsWith(rows, "nearby")
  for k, it in ipairs(nearby) do
    local n = d.nearby[k]
    local bw = fitWidth(it.row.label .. " →")
    local ch = 3 * LINE + 12
    p:rect(a.x, ly, a.w, ch, "paper")
    p:frame(a.x, ly, a.w, ch, "line")
    local tw = a.w - bw - 28
    p:text(a.x + 10, ly + 6, Ui.fit(n.title, tw), "ink")
    p:text(a.x + 10, ly + 6 + LINE, Ui.fit(L("%s · %s · %s", Games.label(n.game),
      CoopMenu.languageName(n.game), n.players == 1 and L("1 player")
        or L("%d players", n.players)), tw), "muted")
    local fit = n.fit == coop.version and L("Your cartridge fits")
      or (n.fit and L("Joins with %s", Games.label(n.fit)))
      or L("Needs %s", CoopMenu.togetherText(n.game)) -- #9: or the other of its pair
    p:text(a.x + 10, ly + 6 + 2 * LINE, Ui.fit(fit, tw), n.fit and "muted" or "error")
    rowButton(p, a.x + a.w - bw - 10, ly + math.floor((ch - 22) / 2), bw, 22, it.index, it.row,
      { label = it.row.label .. " →" })
    ly = ly + ch + 6
  end
  if #nearby == 0 then
    ly = ly + p:para(a.x, ly, a.w, d.nearbyOff and L("Nearby search is off on this device.")
      or L("Searching the network..."), "muted") + 6
  end
  local recent = rowsWith(rows, "recent")
  if #recent > 0 then
    ly = ly + 8
    sectionLabel(p, a.x, ly, L("RECENT ADDRESSES"))
    ly = ly + LINE + 4
    for _, it in ipairs(recent) do
      rowButton(p, a.x, ly, math.min(a.w, fitWidth(it.row.label, 8)), 22, it.index, it.row)
      ly = ly + 28
    end
  end
  local by = wide and y or ly + 12
  local close = panel(p, b.x, by, b.w)
  local ry = by + 10
  sectionLabel(p, b.x + 10, ry, L("BY ADDRESS"))
  ry = ry + LINE + 6
  ry = ry + p:para(b.x + 10, ry, b.w - 20,
    L("A host name or address, with an optional :port. The default port is 24680."), "muted") + 8
  local ai, arow = rowOf(rows, "address")
  rowButton(p, b.x + 10, ry, b.w - 20, 24, ai, arow,
    { label = L("ENTER ADDRESS →"), style = "primary" })
  ry = ry + 32
  ry = ry + p:para(b.x + 10, ry, b.w - 20, L("Your cartridge: %s", Games.label(coop.version)),
    "muted")
  close(ry + 10)
  return math.max(ly, ry + 10)
end

local STEP_ICON = { ok = "check", no = "cross", wait = "dot", skip = "dash" }

function C.connecting(p, coop, c)
  local rows = coop:items()
  local d = coop:details()
  local st = d.status
  local title
  if st == "dialling" or st == "waiting" then title = L("Calling the host")
  elseif st == "unreachable" then title = L("Could not reach the host")
  elseif st == "probed" or st == "joining" or st == "joined" then title = L("You found your friend")
  elseif st == "refused" and d.steps and d.steps.fits == "no" then title = L("The cartridge does not fit")
  elseif st == "refused" then title = L("The host said no")
  else title = L("The session ended") end
  local sub = d.address or ""
  if d.title then sub = L("%s · %s", d.title, sub) end
  local y = c.y + heading(p, c, c.y, title, sub, false)
  local close = panel(p, c.x, y, c.w)
  local py = y + 8
  if d.steps then
    local fitsText = L("Cartridge fits")
    if d.steps.fits == "ok" then
      fitsText = L("Cartridge fits · %s / %s", Games.label(d.game), CoopMenu.languageName(d.game))
    elseif d.steps.fits == "no" then
      fitsText = L("Cartridge does not fit")
    end
    for _, step in ipairs({ { d.steps.found, L("Host found") },
                            { d.steps.protocol, L("Co-op protocol matches") },
                            { d.steps.fits, fitsText } }) do
      icon(p, c.x + 12, py + 3, STEP_ICON[step[1]], step[1] == "no" and "error" or "ink")
      p:text(c.x + 28, py, Ui.fit(step[2], c.w - 40), step[1] == "skip" and "muted" or "ink")
      py = py + LINE + 6
      p:rect(c.x + 10, py - 4, c.w - 20, 1, "line")
    end
    py = py + 4
  end
  if d.line then py = py + p:para(c.x + 10, py, c.w - 20, d.line, "ink") + 2 end
  if d.countdown then py = py + p:para(c.x + 10, py, c.w - 20, d.countdown, "muted") + 2 end
  if d.reason then py = py + p:para(c.x + 10, py, c.w - 20, d.reason, "error") + 4 end
  if d.known then
    py = py + p:para(c.x + 10, py, c.w - 20,
      L("This device is %s in that campaign.", d.known), "muted") + 2
  end
  if rowOf(rows, "how") then py = startRows(p, c, rows, py + 4) end -- a new player (#57)
  for _, tip in ipairs(d.tips or {}) do
    p:text(c.x + 10, py, "·", "muted")
    py = py + p:para(c.x + 22, py, c.w - 32, tip, "ink") + 4
  end
  close(py + 8)
  y = py + 16
  local list = {}
  for i, row in ipairs(rows) do
    local primary = row.id == "join" or row.id == "retry" or row.id == "switch"
    if not START_ROWS[row.id] then
      list[#list + 1] = { index = i, row = row, style = primary and "primary" or nil,
        label = (row.id == "join" or row.id == "switch") and (row.label .. " →") or nil }
    end
  end
  actionsRight(p, c, y, list)
  return y + 30
end

-- BRING A SAVE's pick (#57, design A4.1): this device's solo saves of the
-- game, those past Oak's lab
function C.bring(p, coop, c)
  local rows = coop:items()
  local y = c.y + heading(p, c, c.y, L("Bring a trainer"),
    L("Your team, PC, bag, money and place come along. The solo save stays as it is."), true)
  local any = false
  for i, row in ipairs(rows) do
    if row.id == "slot" then
      any = true
      local sv = row.save
      local sub = L("BADGES %d · POKéDEX %d · TIME %s", sv.badges or 0, sv.dex or 0, sv.time or "0:00")
      if not sv.bringable then sub = L("%s · NO STARTER YET", sub) end
      rowButton(p, c.x, y, c.w, 36, i, row, { sub = sub })
      y = y + 42
    end
  end
  if not any then
    y = y + p:para(c.x, y, c.w, L("No single-player save of this game on this device."), "muted") + 8
  end
  return y + 8
end

-- How player 2 starts (#64): ENTER WITH 2 PLAYERS and JOIN WITH 2 PLAYERS
-- ask it after player 2's name, for a player the campaign does not know
function C.start2(p, coop, c)
  local rows = coop:items()
  local y = c.y + heading(p, c, c.y, L("How player 2 starts"),
    L("Player 2 is new to this campaign. Pick how their adventure begins."), true)
  local close = panel(p, c.x, y, c.w)
  local py = startRows(p, c, rows, y + 10)
  close(py + 2)
  y = py + 10
  local gi, grow = rowOf(rows, "go2")
  actionsRight(p, c, y, { { index = gi, row = grow, label = grow.label .. " →", style = "primary" } })
  return y + 30
end

function C.entry(p, coop, c, ui)
  local d = coop:details()
  local k = d.keypad
  local y = c.y + heading(p, c, c.y, d.prompt,
    L("Type on the keyboard, or pick the letters with a pad or a tap. START or END finishes."),
    false)
  p:rect(c.x, y, c.w, 26, "field")
  p:frame(c.x, y, c.w, 26, "line")
  local shown = k.text
  while width(shown) > c.w - 20 do shown = shown:sub(2) end
  local blanks = math.max(0, math.min(k.max, math.floor((c.w - 20) / Ui.CHAR)) - #shown)
  p:text(c.x + 10, y + 6, shown .. ("_"):rep(blanks), "ink")
  y = y + 34
  local cols = 0
  for _, row in ipairs(k.rows) do cols = math.max(cols, #row) end
  local kw = math.min(40, math.floor((c.w - (cols - 1) * 4) / cols))
  local grid = cols * kw + (cols - 1) * 4
  local gx = c.x + math.floor((c.w - grid) / 2)
  for r, row in ipairs(k.rows) do
    local special = r == #k.rows
    local w = special and math.floor((grid - (#row - 1) * 4) / #row) or kw
    for col, key in ipairs(row) do
      local x = gx + (col - 1) * (w + 4)
      local focused = r == k.row and col == math.min(k.col, #row)
      button(p, x, y, w, 20, {
        key = "key:" .. r .. ":" .. col, act = { kind = "key", r = r, c = col },
        label = special and L(key) or key, style = focused and "selected" or nil,
      })
    end
    y = y + 24
  end
  -- the pad's cursor is the model's; keep the page focus on it
  ui.focus = "key:" .. k.row .. ":" .. math.min(k.col, #k.rows[k.row])
  return y
end

-- ------------------------------------------------------------ build

-- the content area for a page of w x h (x, w of the centred column)
local function content(W)
  local cw = math.min(W - 2 * Screens.MARGIN, Screens.MAX_WIDTH)
  return { x = math.floor((W - cw) / 2), w = cw }
end

local function notice(p, text, region, W)
  p:rect(region.x, region.y, region.w, region.h, "shell", 0.8)
  local w = math.min(W - 2 * Screens.MARGIN, 360)
  local lines = Ui.wrap(text, w - 24)
  local h = #lines * LINE + 24 + 30
  local x = math.floor((W - w) / 2)
  local y = region.y + math.max(8, math.floor((region.h - h) / 2))
  p:rect(x + 4, y + 4, w, h, "line")
  p:rect(x, y, w, h, "lcd")
  p:frame(x, y, w, h, "accent", 2)
  for i, line in ipairs(lines) do p:text(x + 12, y + 12 + (i - 1) * LINE, line, "ink") end
  local bw = fitWidth(L("OK"), 16)
  button(p, x + w - bw - 12, y + h - 32, bw, 22,
    { key = "ok", act = { kind = "ok" }, label = L("OK"), style = "primary" })
end

-- the screen's content function and its model
local function screenOf(menu)
  if menu.screen == "coop" and menu.coop then
    local coop = menu.coop
    local s = coop.screen
    if s == "host" or s == "campaigns" then
      return function(p, c) return C.list(p, coop, c, s == "campaigns") end, coop
    end
    return function(p, c, ui) return C[s](p, coop, c, ui) end, coop
  end
  if menu.screen == "saves" and menu.saves then
    return function(p, c) return S.saves(p, menu, c) end, menu.saves
  end
  if menu.screen == "mods" and menu.mods then
    return function(p, c) return S.mods(p, menu, c) end, menu.mods
  end
  local fn = S[menu.screen] or S.play
  return function(p, c) return fn(p, menu, c) end, menu
end

function Screens.model(menu)
  local _, model = screenOf(menu)
  return model
end

-- a page for the menu's current state; ui.focus and ui.scroll may be
-- corrected (a focus no longer on the page, a scroll past the end)
function Screens.build(menu, ui, opts)
  local W, H = opts.w, opts.h
  local draw, model = screenOf(menu)
  local function make(lift)
    local p = Ui.page(W, H)
    p:rect(0, 0, W, H, "shell")
    local top = topBar(p, menu, W, opts)
    local footY = H - footerHeight(W)
    local region = { x = 0, y = top, w = W, h = math.max(0, footY - top) }
    local c = content(W)
    c.y = top + 14
    p.clip = region
    p.dy = (lift or 0) - (ui.scroll or 0)
    local bottom = draw(p, c, ui) or c.y
    p.dy, p.clip = 0, nil
    local text = menu:currentNotice()
    if text then
      -- the message takes the focus; the page under it waits
      for _, n in ipairs(p.nodes) do
        if n.kind == "hit" then n.enabled = false end
      end
      notice(p, text, region, W)
    end
    footer(p, W, H, opts.device)
    p.region, p.contentHeight = region, bottom - top + 14
    return p
  end
  local page = make()
  -- a page shorter than the window sits a third of the way down
  local spare = page.region.h - page.contentHeight
  if spare > 24 then page = make(math.floor(spare / 3)) end
  -- a new screen: the focus starts on the model's cursor, the page at its top
  local sig = menu.screen .. "/" .. tostring(menu.coop and menu.coop.screen)
    .. "/" .. tostring(menu.saves and menu.saves.screen)
    .. "/" .. tostring(menu.mods and menu.mods.screen)
  if ui.sig ~= sig then
    ui.sig, ui.model = sig, nil
    if ui.focus and not ui.focus:find("^tab:") then ui.focus = nil end
  end
  -- the focus: a target on the page, following the model's cursor
  local function valid(key)
    local n = key and page:find(key)
    return n and n.enabled
  end
  if menu:currentNotice() then
    ui.focus = "ok"
  else
    local cursorKey = "row:" .. tostring(model.cursor)
    if ui.cursor ~= model.cursor or ui.model ~= model or not valid(ui.focus) then
      if valid(cursorKey) then
        ui.focus = cursorKey
      elseif not valid(ui.focus) then
        ui.focus = nil
        for _, n in ipairs(page:targets()) do
          if n.enabled and n.key:find("^row:") then ui.focus = n.key break end
        end
        if not ui.focus then
          for _, n in ipairs(page:targets()) do
            if n.enabled then ui.focus = n.key break end
          end
        end
      end
    end
    ui.cursor, ui.model = model.cursor, model
  end
  -- scroll the focused target into view, and never past the end
  local region = page.region
  local maxScroll = math.max(0, page.contentHeight - region.h)
  local scroll = math.max(0, math.min(ui.scroll or 0, maxScroll))
  local f = ui.focus and page:find(ui.focus)
  if f and f.clip then
    if f.y < region.y + 4 then
      scroll = scroll - (region.y + 4 - f.y)
    elseif f.y + f.h > region.y + region.h - 4 then
      scroll = scroll + (f.y + f.h - (region.y + region.h - 4))
    end
    scroll = math.max(0, math.min(scroll, maxScroll))
  end
  if scroll ~= (ui.scroll or 0) then
    ui.scroll = scroll
    page = make(spare > 24 and math.floor(spare / 3) or 0)
  end
  page.maxScroll = maxScroll
  return page
end

return Screens
