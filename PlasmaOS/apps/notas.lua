-- Plasma OS - Notas: bloco de texto salvo em /PlasmaOS/notas.txt
local PATH = "/PlasmaOS/notas.txt"
local BAR = 0xFFF8D6

local function load(ctx)
  if not ctx.fs.exists(PATH) then return "" end
  local h = ctx.fs.open(PATH, "r")
  if not h then return "" end
  local parts = {}
  repeat
    local chunk = ctx.fs.read(h, math.huge)
    if chunk then parts[#parts + 1] = chunk end
  until not chunk
  ctx.fs.close(h)
  return table.concat(parts)
end

local function save(win, ctx)
  local h = ctx.fs.open(PATH, "w")
  if not h then win.state.status = "Erro ao salvar" return end
  ctx.fs.write(h, win.state.text)
  ctx.fs.close(h)
  win.state.status = "Salvo"
end

return {
  name = "Notas", letter = "N", color = 0xF2C94C,

  init = function(win, ctx)
    win.state = win.state or { text = load(ctx), status = "" }
  end,

  draw = function(win, b, g, ctx)
    local s = win.state
    g.fill(b.x, b.y, b.w, b.h, 0xFFFDF2)
    g.fill(b.x, b.y, b.w, 1, BAR)
    g.text(b.x + 1, b.y, g.clip(s.status, b.w - 14), 0x86868B, BAR)
    local bx = b.x + b.w - 10
    g.fill(bx, b.y, 9, 1, 0xF2C94C)
    g.text(bx + 2, b.y, "Salvar", 0x1D1D1F, 0xF2C94C)

    local lines = {}
    for line in (s.text .. "\n"):gmatch("(.-)\n") do lines[#lines + 1] = line end
    local rows = b.h - 2
    local start = math.max(1, #lines - rows + 1)
    local y = b.y + 2
    for i = start, #lines do
      g.text(b.x + 2, y, g.clip(lines[i], b.w - 4), 0x1D1D1F, 0xFFFDF2)
      y = y + 1
    end
    local last = lines[#lines] or ""
    if y < b.y + b.h then
      g.text(b.x + 2 + #last, y - 1, "_", 0xF2C94C, 0xFFFDF2)
    end
  end,

  touch = function(win, b, x, y, ctx)
    if y == b.y and x >= b.x + b.w - 10 then save(win, ctx) end
  end,

  key = function(win, ch, code, ctx)
    local s = win.state
    s.status = ""
    if code == 28 or code == 156 then
      s.text = s.text .. "\n"
    elseif code == 14 then
      s.text = s.text:sub(1, -2)
    elseif ch and ch >= 32 and ch < 127 then
      s.text = s.text .. string.char(ch)
    end
  end,
}
