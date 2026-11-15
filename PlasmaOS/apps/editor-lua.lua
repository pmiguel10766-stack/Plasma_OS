-- Plasma OS - Editor Lua: escreve scripts com destaque de sintaxe
local DIR = "/PlasmaOS/scripts/"
local FILE = DIR .. "editor.lua"
local BG, TXT, KEY, NUM, CMT, NUMBAR = 0x1E1E24, 0xE6E6E6, 0xFF7AB2, 0xF2C94C, 0x6C9A5B, 0x3A3A44

local KW = {}
for w in ("and break do else elseif end false for function if in local nil not or repeat return then true until while"):gmatch("%a+") do
  KW[w] = true
end

local function paint(g, x, y, line, maxw)
  if line:match("^%s*%-%-") then
    g.text(x, y, g.clip(line, maxw), CMT, BG)
    return
  end
  local pos, col = 1, 0
  while pos <= #line and col < maxw do
    local s, e = line:find("^[%a_][%w_]*", pos)
    local fg = TXT
    if s then
      fg = KW[line:sub(s, e)] and KEY or TXT
    else
      s, e = line:find("^%d+", pos)
      if s then fg = NUM else s, e = pos, pos end
    end
    local chunk = line:sub(s, e)
    g.text(x + col, y, chunk:sub(1, maxw - col), fg, BG)
    col = col + #chunk
    pos = e + 1
  end
end

local function save(win, ctx)
  local fs = ctx.fs
  if not fs.exists(DIR) then fs.makeDirectory(DIR) end
  local h = fs.open(FILE, "w")
  if not h then win.state.status = "Erro ao salvar" return end
  fs.write(h, table.concat(win.state.lines, "\n"))
  fs.close(h)
  win.state.status = "Salvo em scripts/editor.lua"
end

return {
  name = "Editor Lua", letter = "E", color = 0x2D2D3A,

  init = function(win, ctx)
    if win.state then return end
    local lines = {}
    if ctx.fs.exists(FILE) then
      local h = ctx.fs.open(FILE, "r")
      local parts = {}
      repeat
        local c = h and ctx.fs.read(h, math.huge)
        if c then parts[#parts + 1] = c end
      until not c
      if h then ctx.fs.close(h) end
      for line in (table.concat(parts) .. "\n"):gmatch("(.-)\n") do lines[#lines + 1] = line end
    end
    if #lines == 0 then lines = { "" } end
    win.state = { lines = lines, status = "" }
  end,

  draw = function(win, b, g, ctx)
    local s = win.state
    g.fill(b.x, b.y, b.w, b.h, BG)
    g.fill(b.x, b.y, b.w, 1, NUMBAR)
    g.text(b.x + 1, b.y, g.clip(s.status, b.w - 14), 0xAEAEB2, NUMBAR)
    local bx = b.x + b.w - 10
    g.fill(bx, b.y, 9, 1, 0x0A84FF)
    g.text(bx + 2, b.y, "Salvar", 0xFFFFFF, 0x0A84FF)

    local rows = b.h - 2
    local start = math.max(1, #s.lines - rows + 1)
    local y = b.y + 1
    local gutter = 4
    for i = start, #s.lines do
      g.fill(b.x, y, gutter, 1, NUMBAR)
      g.text(b.x, y, string.format("%3d", i), 0x7A7A86, NUMBAR)
      paint(g, b.x + gutter + 1, y, s.lines[i], b.w - gutter - 2)
      y = y + 1
    end
    local last = s.lines[#s.lines]
    if y - 1 < b.y + b.h then
      g.text(b.x + gutter + 1 + #last, y - 1, "|", 0x0A84FF, BG)
    end
  end,

  touch = function(win, b, x, y, ctx)
    if y == b.y and x >= b.x + b.w - 10 then save(win, ctx) end
  end,

  key = function(win, ch, code, ctx)
    local s = win.state
    s.status = ""
    if code == 28 or code == 156 then
      s.lines[#s.lines + 1] = ""
    elseif code == 14 then
      local last = s.lines[#s.lines]
      if last ~= "" then
        s.lines[#s.lines] = last:sub(1, -2)
      elseif #s.lines > 1 then
        table.remove(s.lines)
      end
    elseif ch and ch >= 32 and ch < 127 then
      s.lines[#s.lines] = s.lines[#s.lines] .. string.char(ch)
    end
  end,
}
