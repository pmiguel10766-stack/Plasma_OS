-- Plasma OS - Calendário: estilo iCal do OS X Yosemite
-- Hoje fica em vermelho. Clique num dia para selecioná-lo; ‹ › trocam de mês; clique no título volta a hoje.
-- Teclado: ← → dia, ↑ ↓ semana, PgUp PgDn mês, T hoje.

local MONTHS = {
  "Janeiro", "Fevereiro", "Março", "Abril", "Maio", "Junho",
  "Julho", "Agosto", "Setembro", "Outubro", "Novembro", "Dezembro",
}
local WEEKDAYS = { "Domingo", "Segunda-feira", "Terça-feira", "Quarta-feira",
  "Quinta-feira", "Sexta-feira", "Sábado" }
local SHORT = { "Dom", "Seg", "Ter", "Qua", "Qui", "Sex", "Sáb" }

local TOOL, PANEL = 0xF0F0F2, 0xFFFFFF
local SEP, INK, DIM = 0xD1D1D6, 0x1D1D1F, 0x86868B
local RED, SELBG, WEEKEND = 0xE05252, 0xDCEBFF, 0xE05252
local BLUE = 0x0A84FF

local function len(s)
  if unicode and unicode.len then return unicode.len(s) end
  return #s
end

-- Datas ------------------------------------------------------------------

local function today()
  local ok, t = pcall(os.date, "*t")
  if ok and type(t) == "table" then return t end
  return nil
end

-- Dia da semana (1 = domingo) do dia 1 e quantidade de dias do mês
local function monthInfo(y, m)
  local first = os.date("*t", os.time({ year = y, month = m, day = 1 })).wday
  local dim = os.date("*t", os.time({ year = y, month = m + 1, day = 0 })).day
  return first, dim
end

-- Soma dias à data selecionada (cuida de virada de mês e de ano)
local function shiftDays(s, n)
  local ok, t = pcall(os.time, { year = s.y, month = s.m, day = s.sel + n })
  if not ok or not t then return end
  local d = os.date("*t", t)
  s.y, s.m, s.sel = d.year, d.month, d.day
end

local function shiftMonth(s, n)
  local m = s.m + n
  local y = s.y
  while m < 1 do m = m + 12; y = y - 1 end
  while m > 12 do m = m - 12; y = y + 1 end
  local _, dim = monthInfo(y, m)
  s.y, s.m, s.sel = y, m, math.min(s.sel, dim)
end

local function ensure(win)
  local s = win.state
  if not s then
    local t = today()
    if not t then return nil end
    s = { y = t.year, m = t.month, sel = t.day, t = t }
    win.state = s
  end
  s.t = today() or s.t
  return s
end

-- Desenho ----------------------------------------------------------------

local function drawHeader(b, g, s)
  g.fill(b.x, b.y, b.w, 1, TOOL)
  g.text(b.x + 1, b.y, "‹", BLUE, TOOL)
  g.text(b.x + b.w - 2, b.y, "›", BLUE, TOOL)
  local title = MONTHS[s.m] .. " " .. s.y
  g.text(b.x + math.max(0, math.floor((b.w - len(title)) / 2)), b.y, title, INK, TOOL)
end


return {
  name = "Calendário", letter = "C", color = RED,

  init = function(win)
    ensure(win)
  end,

  draw = function(win, b, g, ctx)
    g.fill(b.x, b.y, b.w, b.h, PANEL)
    local s = ensure(win)
    if not s then
      g.text(b.x + 2, b.y + 2, "Data indisponível neste computador.", DIM, PANEL)
      return
    end
    if b.h < 6 or b.w < 22 then return end

    drawHeader(b, g, s)
    g.fill(b.x, b.y + 1, b.w, 1, SEP)

    -- dias da semana
    local cw = math.floor(b.w / 7)
    local gw = cw * 7
    local gx = b.x + math.floor((b.w - gw) / 2)
    local names = cw >= 5 and SHORT or { "D", "S", "T", "Q", "Q", "S", "S" }
    for i = 1, 7 do
      local fg = (i == 1 or i == 7) and WEEKEND or DIM
      local lab = names[i]
      g.text(gx + (i - 1) * cw + math.floor((cw - len(lab)) / 2), b.y + 2, lab, fg, PANEL)
    end

    -- grade dos dias
    local first, dim = monthInfo(s.y, s.m)
    local gy = b.y + 3
    local t = s.t
    local isThisMonth = t and t.year == s.y and t.month == s.m
    for day = 1, dim do
      local pos = first - 1 + (day - 1)
      local col = pos % 7
      local row = math.floor(pos / 7)
      local y = gy + row
      if y < b.y + b.h - 3 then
        local x = gx + col * cw
        local txt = string.format("%2d", day)
        local tx = x + math.floor((cw - 2) / 2)
        local isToday = isThisMonth and day == t.day
        local weekend = (col == 0 or col == 6)
        if isToday then
          g.fill(x + math.floor((cw - 4) / 2), y, 4, 1, RED)
          g.text(x + math.floor((cw - 4) / 2), y, " " .. txt .. " ", 0xFFFFFF, RED)
        elseif day == s.sel then
          g.fill(x + math.floor((cw - 4) / 2), y, 4, 1, SELBG)
          g.text(x + math.floor((cw - 4) / 2), y, " " .. txt .. " ", INK, SELBG)
        else
          g.text(tx, y, txt, weekend and WEEKEND or INK, PANEL)
        end
      end
    end

    -- rodapé com a data selecionada
    g.fill(b.x, b.y + b.h - 2, b.w, 1, SEP)
    g.fill(b.x, b.y + b.h - 1, b.w, 1, TOOL)
    local first_wd = first
    local wd = ((first_wd - 1) + (s.sel - 1)) % 7 + 1
    local line = WEEKDAYS[wd] .. ", " .. s.sel .. " de " .. MONTHS[s.m] .. " de " .. s.y
    g.text(b.x + 2, b.y + b.h - 1, g.clip(line, b.w - 4), INK, TOOL)
  end,

  touch = function(win, b, x, y, ctx)
    local s = ensure(win)
    if not s then return end

    if y == b.y then
      if x <= b.x + 3 then shiftMonth(s, -1)
      elseif x >= b.x + b.w - 4 then shiftMonth(s, 1)
      else
        local t = s.t
        if t then s.y, s.m, s.sel = t.year, t.month, t.day end
      end
      return
    end

    local cw = math.floor(b.w / 7)
    local gw = cw * 7
    local gx = b.x + math.floor((b.w - gw) / 2)
    local gy = b.y + 3
    if y < gy or y >= b.y + b.h - 3 then return end
    local col = math.floor((x - gx) / cw)
    local row = y - gy
    if col < 0 or col > 6 then return end
    local first = monthInfo(s.y, s.m)
    local day = row * 7 + col - (first - 1) + 1
    local _, dim = monthInfo(s.y, s.m)
    if day >= 1 and day <= dim then s.sel = day end
  end,

  key = function(win, ch, code, ctx)
    local s = ensure(win)
    if not s then return end
    if code == 203 then shiftDays(s, -1)
    elseif code == 205 then shiftDays(s, 1)
    elseif code == 200 then shiftDays(s, -7)
    elseif code == 208 then shiftDays(s, 7)
    elseif code == 201 then shiftMonth(s, -1)
    elseif code == 209 then shiftMonth(s, 1)
    elseif ch == 116 or ch == 84 then                       -- T / t
      local t = s.t
      if t then s.y, s.m, s.sel = t.year, t.month, t.day end
    end
  end,
}
