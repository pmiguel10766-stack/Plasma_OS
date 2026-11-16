-- Plasma OS - Ajustes: estilo "Preferências do Sistema" do OS X Yosemite
-- Grade de painéis; cada um abre uma tela de detalhe com a barra "‹ Ajustes" para voltar.

local TRACK = 0xE4E4E7   -- barra de ferramentas
local SEP   = 0xD1D1D6   -- linhas finas
local PANEL = 0xF5F5F7   -- fundo da janela
local WHITE = 0xFFFFFF
local INK   = 0x1D1D1F
local DIM   = 0x86868B
local BLUE  = 0x0A84FF
local RED   = 0xD93025
local TRACKBAR = 0xDCDCE0

local function len(s)
  if unicode and unicode.len then return unicode.len(s) end
  return #s
end

local function usub(s, i, j)
  if unicode and unicode.sub then return unicode.sub(s, i, j) end
  return s:sub(i, j)
end

local function mix(c1, c2, t)
  local r1, g1, b1 = math.floor(c1 / 65536) % 256, math.floor(c1 / 256) % 256, c1 % 256
  local r2, g2, b2 = math.floor(c2 / 65536) % 256, math.floor(c2 / 256) % 256, c2 % 256
  return math.floor(r1 + (r2 - r1) * t) * 65536
       + math.floor(g1 + (g2 - g1) * t) * 256
       + math.floor(b1 + (b2 - b1) * t)
end

local function fmtBytes(n)
  if n >= 1048576 then return string.format("%.1f MB", n / 1048576) end
  return string.format("%d KB", math.floor(n / 1024))
end

local function uptime()
  local t = math.floor(computer.uptime())
  return string.format("%dh %02dmin", math.floor(t / 3600), math.floor(t / 60) % 60)
end

-- Painéis da grade (3 colunas x 2 linhas)
local TILES = {
  { id = "info",   label = "Geral",   color = 0x8E8E93, mark = "i" },
  { id = "wall",   label = "Desktop", color = 0x2BB0E0, mark = "▲" },
  { id = "energy", label = "Energia", color = 0x34C759, mark = "%" },
  { id = "mem",    label = "Memória", color = 0xFF9500, mark = "M" },
  { id = "user",   label = "Usuário", color = 0xFF2D55, mark = "U" },
  { id = "about",  label = "Sobre",   color = 0x5856D6, mark = "?" },
}
local TITLES = { grid = "Preferências" }
for _, t in ipairs(TILES) do TITLES[t.id] = t.label end

-- Ícone 6x2 com sombra embaixo e a marca no centro
local function icon(g, x, y, color, mark)
  g.fill(x, y, 6, 1, color)
  g.fill(x, y + 1, 6, 1, mix(color, 0x000000, 0.14))
  g.text(x + 2, y, mark, WHITE, color)
end

-- Barra horizontal (tipo "barra de progresso" do Yosemite)
local function bar(g, x, y, w, frac, fill)
  g.fill(x, y, w, 1, TRACKBAR)
  local f = math.floor(w * math.max(0, math.min(1, frac)) + 0.5)
  if f > 0 then g.fill(x, y, f, 1, fill or BLUE) end
end

-- Linha "rótulo ........ valor" em cartão branco
local function row(g, x, y, w, k, v, vfg)
  g.fill(x, y, w, 1, WHITE)
  g.text(x + 2, y, k, INK, WHITE)
  g.text(x + w - 2 - len(v), y, v, vfg or DIM, WHITE)
  g.fill(x, y + 1, w, 1, SEP)
end

local function centerText(g, b, y, s, fg, bg)
  g.text(b.x + math.max(0, math.floor((b.w - len(s)) / 2)), y, g.clip(s, b.w), fg or INK, bg or PANEL)
end

-- Telas --------------------------------------------------------------------

local function drawGrid(b, g, top)
  local tw = math.floor(b.w / 3)
  for i, t in ipairs(TILES) do
    local c = (i - 1) % 3
    local r = math.floor((i - 1) / 3)
    local x = b.x + c * tw + math.floor((tw - 6) / 2)
    local y = top + r * 6 + 1
    if y + 3 < b.y + b.h then
      icon(g, x, y, t.color, t.mark)
      -- rótulo centralizado sob o ícone
      local lw = len(t.label)
      g.fill(b.x + c * tw, y + 3, tw, 1, PANEL)
      g.text(b.x + c * tw + math.max(0, math.floor((tw - lw) / 2)), y + 3,
        g.clip(t.label, tw), INK, PANEL)
    end
  end
end

local function drawInfo(b, g, top, ctx)
  local total = computer.totalMemory()
  local used = total - computer.freeMemory()
  local items = {
    { "Sistema", "Plasma OS" },
    { "Versão", ctx.version or "-" },
    { "Usuário", ctx.user or "-" },
    { "Tempo ligado", uptime() },
    { "Memória", fmtBytes(used) .. " de " .. fmtBytes(total) },
  }
  local w = b.w - 4
  for i, it in ipairs(items) do
    local y = top + (i - 1) * 2
    if y < b.y + b.h - 1 then row(g, b.x + 2, y, w, it[1], it[2]) end
  end
end

local function drawEnergy(b, g, top)
  local maxE = computer.maxEnergy()
  local e = computer.energy()
  local frac = (maxE > 0) and (e / maxE) or 0
  local pct = math.floor(frac * 100 + 0.5)
  local low = pct <= 15
  centerText(g, b, top + 1, pct .. "%", low and RED or INK)
  local bw = b.w - 8
  bar(g, b.x + 4, top + 3, bw, frac, low and RED or 0x34C759)
  centerText(g, b, top + 5, "Energia armazenada", DIM)
  centerText(g, b, top + 6, string.format("%d de %d EU", math.floor(e), math.floor(maxE)), DIM)
end

local function drawMem(b, g, top)
  local total = computer.totalMemory()
  local free = computer.freeMemory()
  local used = total - free
  local frac = (total > 0) and (used / total) or 0
  centerText(g, b, top + 1, math.floor(frac * 100 + 0.5) .. "%", INK)
  bar(g, b.x + 4, top + 3, b.w - 8, frac, 0xFF9500)
  row(g, b.x + 2, top + 5, b.w - 4, "Em uso", fmtBytes(used))
  row(g, b.x + 2, top + 7, b.w - 4, "Livre", fmtBytes(free))
  row(g, b.x + 2, top + 9, b.w - 4, "Total", fmtBytes(total))
end

local function drawUser(b, g, top, ctx)
  local name = ctx.user or "?"
  local initial = usub(name, 1, 1):upper()
  local ax = b.x + math.floor((b.w - 8) / 2)
  g.fill(ax, top + 1, 8, 3, 0xFF2D55)
  g.fill(ax, top + 3, 8, 1, mix(0xFF2D55, 0x000000, 0.14))
  g.text(ax + 3, top + 2, initial, WHITE, 0xFF2D55)
  centerText(g, b, top + 5, name, INK)
  centerText(g, b, top + 6, "Conta local", DIM)
end

local function drawAbout(b, g, top, ctx)
  centerText(g, b, top + 1, "Plasma OS", INK)
  centerText(g, b, top + 3, "Versão " .. (ctx.version or "-"), DIM)
  centerText(g, b, top + 4, "Sistema para OpenComputers", DIM)
  centerText(g, b, top + 6, "Memória total " .. fmtBytes(computer.totalMemory()), DIM)
end

local function drawWall(b, g, top, ctx)
  local names = ctx.wallNames
  if not names then
    -- sem lista de fundos: só o botão de trocar
    local w = b.w - 4
    row(g, b.x + 2, top, w, "Trocar fundo de tela", ">", BLUE)
    return
  end
  local cur = ctx.wallIdx and ctx.wallIdx() or 1
  for i, name in ipairs(names) do
    local y = top + (i - 1) * 2
    if y < b.y + b.h - 1 then
      g.fill(b.x + 2, y, b.w - 4, 1, WHITE)
      local on = (i == cur)
      g.text(b.x + 4, y, on and "●" or "○", on and BLUE or DIM, WHITE)
      g.text(b.x + 6, y, g.clip(name, b.w - 10), INK, WHITE)
      g.fill(b.x + 2, y + 1, b.w - 4, 1, SEP)
    end
  end
end

return {
  name = "Ajustes", letter = "A", color = 0x7F8C8D,

  draw = function(win, b, g, ctx)
    win.view = win.view or "grid"
    local view = win.view
    local top = b.y + 2

    g.fill(b.x, b.y, b.w, b.h, PANEL)

    -- barra de ferramentas
    g.fill(b.x, b.y, b.w, 1, TRACK)
    g.fill(b.x, b.y + 1, b.w, 1, SEP)
    local title = TITLES[view] or "Ajustes"
    if view ~= "grid" then
      g.text(b.x + 1, b.y, "‹ Preferências", BLUE, TRACK)
    end
    g.text(b.x + math.max(0, math.floor((b.w - len(title)) / 2)), b.y,
      title, INK, TRACK)

    if view == "grid" then
      drawGrid(b, g, top)
    elseif view == "info" then
      drawInfo(b, g, top, ctx)
    elseif view == "energy" then
      drawEnergy(b, g, top)
    elseif view == "mem" then
      drawMem(b, g, top)
    elseif view == "user" then
      drawUser(b, g, top, ctx)
    elseif view == "about" then
      drawAbout(b, g, top, ctx)
    elseif view == "wall" then
      drawWall(b, g, top, ctx)
    end
  end,

  touch = function(win, b, x, y, ctx)
    local view = win.view or "grid"

    -- barra de ferramentas: "‹ Preferências" volta à grade
    if y == b.y then
      if view ~= "grid" and x < b.x + 16 then win.view = "grid" end
      return
    end

    local top = b.y + 2
    if view == "grid" then
      local tw = math.floor(b.w / 3)
      local c = math.floor((x - b.x) / tw)
      local r = math.floor((y - top - 1) / 6)
      if c < 0 or c > 2 or r < 0 or r > 1 then return end
      local t = TILES[r * 3 + c + 1]
      if t then win.view = t.id end

    elseif view == "wall" then
      local names = ctx.wallNames
      if not names then
        if y == top and ctx.nextWallpaper then ctx.nextWallpaper() end
        return
      end
      local i = math.floor((y - top) / 2) + 1
      if names[i] and ctx.setWallpaper then ctx.setWallpaper(i) end
    end
  end,
}
