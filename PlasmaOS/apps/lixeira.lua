-- Plasma OS - Lixeira: estilo Lixeira do OS X Yosemite
-- Itens em /PlasmaOS/lixeira/. Clique para selecionar, Apagar remove o item escolhido.
-- Esvaziar pede uma segunda confirmação (clique de novo em até 4 segundos).
-- ↑ ↓ mudam a seleção; Delete ou Backspace apagam o item selecionado.

local DIR = "/PlasmaOS/lixeira/"
local CONFIRM_TIME = 4

local TOOL, PANEL, SEP = 0xF0F0F2, 0xFFFFFF, 0xD1D1D6
local INK, DIM, WHITE = 0x1D1D1F, 0x86868B, 0xFFFFFF
local SELBG, RED, GRAY = 0x0A84FF, 0xD93025, 0xE5E5EA
local FOLDER, FOLDER_TAB, FILE = 0x5AB0F0, 0x3C8FD9, 0xDADDE2

local function len(s)
  if unicode and unicode.len then return unicode.len(s) end
  return #s
end

local function fmtSize(n)
  if n >= 1048576 then return string.format("%.1f MB", n / 1048576) end
  if n >= 1024 then return string.format("%d KB", math.floor(n / 1024)) end
  return string.format("%d B", n)
end

-- Pastas primeiro, depois arquivos, em ordem alfabética
local function listItems(ctx)
  local out = {}
  local ok, t = pcall(ctx.fs.list, DIR)
  if ok and type(t) == "table" then
    for _, n in ipairs(t) do out[#out + 1] = n end
  end
  table.sort(out, function(a, b)
    local da, db = a:sub(-1) == "/", b:sub(-1) == "/"
    if da ~= db then return da end
    return a < b
  end)
  return out
end

local function sizeOf(ctx, name)
  if name:sub(-1) == "/" then return nil end
  local ok, n = pcall(ctx.fs.size, DIR .. name)
  if ok and type(n) == "number" then return n end
  return 0
end

local function removeItem(ctx, name)
  pcall(ctx.fs.remove, DIR .. name)
end

local function ensure(win)
  local s = win.state
  if not s then
    s = { sel = nil, armed = false, armedAt = 0 }
    win.state = s
  end
  return s
end

local function indexOf(list, name)
  for i, v in ipairs(list) do
    if v == name then return i end
  end
  return nil
end

return {
  name = "Lixeira", letter = "L", color = 0xBDC3C7,

  init = function(win)
    ensure(win)
  end,

  draw = function(win, b, g, ctx)
    local s = ensure(win)
    g.fill(b.x, b.y, b.w, b.h, PANEL)
    if b.h < 6 or b.w < 24 then return end

    local items = listItems(ctx)
    if s.sel and not indexOf(items, s.sel) then s.sel = nil end

    -- barra superior
    g.fill(b.x, b.y, b.w, 1, TOOL)
    g.fill(b.x, b.y + 1, b.w, 1, SEP)
    local count = #items .. (#items == 1 and " item" or " itens")
    g.text(b.x + 2, b.y, count, DIM, TOOL)
    local title = "Lixeira"
    g.text(b.x + math.max(0, math.floor((b.w - len(title)) / 2)), b.y, title, INK, TOOL)

    -- lista ou mensagem de vazio
    local listTop = b.y + 2
    local bottomSep = b.y + b.h - 2
    local rows = bottomSep - listTop
    if #items == 0 then
      local msg = "A lixeira está vazia."
      g.text(b.x + math.max(1, math.floor((b.w - len(msg)) / 2)),
        b.y + math.floor(b.h / 2), msg, DIM, PANEL)
    end

    for i = 1, math.min(#items, rows) do
      local name = items[i]
      local y = listTop + i - 1
      local sel = (name == s.sel)
      local bg = sel and SELBG or PANEL
      local fg = sel and WHITE or INK
      g.fill(b.x, y, b.w, 1, bg)

      local isDir = name:sub(-1) == "/"
      if isDir then
        g.fill(b.x + 2, y, 3, 1, sel and WHITE or FOLDER_TAB)
      else
        g.fill(b.x + 2, y, 3, 1, sel and 0xE6F0FF or FILE)
      end

      local label = isDir and name:sub(1, -2) or name
      local sz = sizeOf(ctx, name)
      local szText = sz and fmtSize(sz) or "--"
      local szW = len(szText)
      g.text(b.x + 7, y, g.clip(label, b.w - szW - 11), fg, bg)
      g.text(b.x + b.w - szW - 2, y, szText, sel and 0xE6F0FF or DIM, bg)
    end

    -- rodapé: botões Apagar e Esvaziar
    g.fill(b.x, bottomSep, b.w, 1, SEP)
    local by = b.y + b.h - 1
    g.fill(b.x, by, b.w, 1, TOOL)

    local canDelete = s.sel ~= nil
    g.fill(b.x + 1, by, 10, 1, canDelete and SELBG or GRAY)
    g.text(b.x + 3, by, "Apagar", canDelete and WHITE or DIM, canDelete and SELBG or GRAY)

    local emptyBg = s.armed and RED or GRAY
    local emptyFg = s.armed and WHITE or INK
    local emptyLabel = s.armed and "Confirmar" or "Esvaziar"
    local bw = 12
    g.fill(b.x + b.w - bw - 1, by, bw, 1, emptyBg)
    g.text(b.x + b.w - bw - 1 + math.floor((bw - len(emptyLabel)) / 2), by,
      emptyLabel, emptyFg, emptyBg)

    -- dica no meio do rodapé
    local hint
    if s.armed then
      hint = "Clique de novo para apagar tudo."
    elseif s.sel then
      hint = s.sel:gsub("/$", "")
    else
      hint = ""
    end
    if len(hint) > 0 and b.w > 52 then
      g.text(b.x + 13, by, g.clip(hint, b.w - 28), DIM, TOOL)
    end

    -- confirmação expira sozinha
    if s.armed and computer.uptime() - s.armedAt > CONFIRM_TIME then
      s.armed = false
    end
  end,

  touch = function(win, b, x, y, ctx)
    local s = ensure(win)
    local items = listItems(ctx)
    local by = b.y + b.h - 1
    local listTop = b.y + 2
    local bottomSep = b.y + b.h - 2

    -- rodapé
    if y == by then
      if x >= b.x + 1 and x <= b.x + 10 then
        if s.sel then
          removeItem(ctx, s.sel)
          s.sel = nil
          s.armed = false
        end
      elseif x >= b.x + b.w - 13 then
        if s.armed and computer.uptime() - s.armedAt <= CONFIRM_TIME then
          for _, name in ipairs(items) do removeItem(ctx, name) end
          s.sel = nil
          s.armed = false
        else
          s.armed = true
          s.armedAt = computer.uptime()
        end
      end
      return
    end

    -- lista: escolhe um item
    if y >= listTop and y < bottomSep then
      local i = y - listTop + 1
      if items[i] then
        s.sel = items[i]
        s.armed = false
      end
    end
  end,

  key = function(win, ch, code, ctx)
    local s = ensure(win)
    local items = listItems(ctx)
    local idx = s.sel and indexOf(items, s.sel) or 0
    if code == 200 then                                  -- ↑
      idx = math.max(1, idx - 1)
      s.sel = items[idx]
    elseif code == 208 then                              -- ↓
      idx = math.min(#items, idx + 1)
      s.sel = items[idx]
    elseif code == 211 or code == 14 then                -- Delete / Backspace
      if s.sel then
        removeItem(ctx, s.sel)
        s.sel = nil
      end
    end
  end,
}
