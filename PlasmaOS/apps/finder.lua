-- Plasma OS - Finder: estilo Finder do OS X Yosemite
-- Clique seleciona, duplo clique (ou Enter) abre a pasta. ↑ ↓ movem a seleção,
-- Backspace sobe uma pasta. A barra lateral leva direto aos favoritos.

local SIDE = 16

local TOOL, SIDEBG, PANEL = 0xF0F0F2, 0xE9EBEE, 0xFFFFFF
local HEAD, SEL, CURFAV = 0xF6F6F8, 0x0A84FF, 0xD0D6DE
local INK, DIM, SEP = 0x1D1D1F, 0x86868B, 0xD1D1D6
local FOLDER, FOLDER_TAB, FILE = 0x5AB0F0, 0x3C8FD9, 0xDADDE2

local FAVS = {
  { "Disco",      "/" },
  { "Plasma",     "/PlasmaOS/" },
  { "Apps",       "/PlasmaOS/apps/" },
  { "Ícones",     "/PlasmaOS/icones/" },
  { "Fundos",     "/PlasmaOS/fundos/" },
  { "Biblioteca", "/PlasmaOS/biblioteca/" },
}

local function len(s)
  if unicode and unicode.len then return unicode.len(s) end
  return #s
end

local function usub(s, i, j)
  if unicode and unicode.sub then return unicode.sub(s, i, j) end
  return s:sub(i, j)
end

local function fmtSize(n)
  if n >= 1048576 then return string.format("%.1f MB", n / 1048576) end
  if n >= 1024 then return string.format("%d KB", math.floor(n / 1024)) end
  return string.format("%d B", n)
end

-- Caminhos ---------------------------------------------------------------

local function joinPath(p, name)
  if p:sub(-1) ~= "/" then p = p .. "/" end
  return p .. name
end

local function parentOf(p)
  if p == "/" then return "/" end
  local q = p:gsub("/$", "")
  return q:match("^(.*/)[^/]*$") or "/"
end

-- Disco ------------------------------------------------------------------

-- Pastas primeiro (terminam em "/"), depois arquivos, em ordem alfabética
local function listDir(ctx, p)
  local items = {}
  local ok, t = pcall(ctx.fs.list, p)
  if ok and type(t) == "table" then
    for _, n in ipairs(t) do items[#items + 1] = n end
  end
  table.sort(items, function(a, b)
    local da, db = a:sub(-1) == "/", b:sub(-1) == "/"
    if da ~= db then return da end
    return a < b
  end)
  return items
end

local function sizeOf(ctx, path)
  local ok, n = pcall(ctx.fs.size, path)
  if ok and type(n) == "number" then return n end
  return 0
end

local function indexOf(list, name)
  if not name then return nil end
  for i, v in ipairs(list) do
    if v == name then return i end
  end
  return nil
end

-- Estado -----------------------------------------------------------------

local function ensure(win, ctx)
  local s = win.state
  if not s then
    s = {
      path = "/", sel = nil, first = 1,
      back = {}, fwd = {},
      items = {}, itemsPath = nil,
      lastClick = -10,
    }
    win.state = s
  end
  if s.itemsPath ~= s.path then
    s.items = listDir(ctx, s.path)
    s.itemsPath = s.path
  end
  return s
end

local function navigate(s, path)
  if path == s.path then return end
  s.back[#s.back + 1] = s.path
  s.fwd = {}
  s.path = path
  s.sel = nil
  s.first = 1
  s.itemsPath = nil
end

local function goBack(s)
  if #s.back == 0 then return end
  s.fwd[#s.fwd + 1] = s.path
  s.path = table.remove(s.back)
  s.sel, s.first, s.itemsPath = nil, 1, nil
end

local function goFwd(s)
  if #s.fwd == 0 then return end
  s.back[#s.back + 1] = s.path
  s.path = table.remove(s.fwd)
  s.sel, s.first, s.itemsPath = nil, 1, nil
end

local function openItem(s, name)
  if name:sub(-1) == "/" then
    navigate(s, joinPath(s.path, name:sub(1, -2)) .. "/")
  end
  -- arquivos só ficam selecionados; abrir arquivo ainda não é suportado
end

local function moveSel(s, k)
  if #s.items == 0 then return end
  k = math.max(1, math.min(#s.items, k))
  s.sel = s.items[k]
end

local function titleOf(path)
  if path == "/" then return "Disco" end
  local q = path:gsub("/$", "")
  return q:match("([^/]+)$") or q
end

-- App -------------------------------------------------------------------

return {
  name = "Finder", letter = "F", color = 0x3A8FD9,

  init = function(win, ctx)
    ensure(win, ctx or {})
  end,

  draw = function(win, b, g, ctx)
    local s = ensure(win, ctx)
    g.fill(b.x, b.y, b.w, b.h, PANEL)
    if b.h < 8 or b.w < SIDE + 16 then return end

    -- barra de ferramentas: voltar, avançar e nome da pasta
    g.fill(b.x, b.y, b.w, 1, TOOL)
    g.fill(b.x, b.y + 1, b.w, 1, SEP)
    g.text(b.x + 1, b.y, "‹", #s.back > 0 and SEL or 0xC7C7CC, TOOL)
    g.text(b.x + 4, b.y, "›", #s.fwd > 0 and SEL or 0xC7C7CC, TOOL)
    local title = titleOf(s.path)
    g.text(b.x + math.max(0, math.floor((b.w - len(title)) / 2)), b.y, title, INK, TOOL)

    -- barra lateral com os favoritos
    g.fill(b.x, b.y + 2, SIDE, b.h - 2, SIDEBG)
    g.fill(b.x + SIDE, b.y + 2, 1, b.h - 2, SEP)
    g.text(b.x + 1, b.y + 2, "Favoritos", DIM, SIDEBG)
    for i, fav in ipairs(FAVS) do
      local y = b.y + 2 + i
      if y < b.y + b.h - 1 then
        local cur = (fav[2] == s.path)
        local bg = cur and CURFAV or SIDEBG
        g.fill(b.x + 1, y, SIDE - 2, 1, bg)
        g.text(b.x + 2, y, g.clip(fav[1], SIDE - 4), INK, bg)
      end
    end

    -- lista de arquivos
    local x0 = b.x + SIDE + 1
    local w = b.w - SIDE - 1
    local sizeW = 10
    g.fill(x0, b.y + 2, w, 1, HEAD)
    g.text(x0 + 4, b.y + 2, "Nome", DIM, HEAD)
    g.text(x0 + w - sizeW, b.y + 2, "Tamanho", DIM, HEAD)

    local rows = math.max(1, b.h - 5)
    local idx = indexOf(s.items, s.sel)
    if idx then
      if idx < s.first then s.first = idx end
      if idx >= s.first + rows then s.first = idx - rows + 1 end
    end
    local maxFirst = math.max(1, #s.items - rows + 1)
    s.first = math.max(1, math.min(s.first, maxFirst))

    if #s.items == 0 then
      g.text(x0 + 2, b.y + 4, "Pasta vazia.", DIM, PANEL)
    end

    for i = 0, rows - 1 do
      local k = s.first + i
      local name = s.items[k]
      if not name then break end
      local y = b.y + 3 + i
      local sel = (name == s.sel)
      local bg = sel and SEL or PANEL
      local fg = sel and 0xFFFFFF or INK
      g.fill(x0, y, w, 1, bg)

      -- ícone: pasta azul ou arquivo cinza
      local isDir = name:sub(-1) == "/"
      if isDir then
        g.fill(x0 + 1, y, 2, 1, sel and 0xFFFFFF or FOLDER_TAB)
      else
        g.fill(x0 + 1, y, 2, 1, sel and 0xE6F0FF or FILE)
      end

      local label = isDir and name:sub(1, -2) or name
      g.text(x0 + 4, y, g.clip(label, w - sizeW - 6), fg, bg)

      local sz = isDir and "--" or fmtSize(sizeOf(ctx, joinPath(s.path, name)))
      g.text(x0 + w - len(sz) - 1, y, sz, sel and 0xE6F0FF or DIM, bg)
    end

    -- rodapé com contagem e item selecionado
    g.fill(x0, b.y + b.h - 2, w, 1, SEP)
    g.fill(x0, b.y + b.h - 1, w, 1, HEAD)
    local info = #s.items .. (#s.items == 1 and " item" or " itens")
    if s.sel then info = info .. "  ·  " .. (s.sel:gsub("/$", "")) end
    g.text(x0 + 2, b.y + b.h - 1, g.clip(info, w - 4), DIM, HEAD)
  end,

  touch = function(win, b, x, y, ctx)
    local s = ensure(win, ctx)

    -- barra de ferramentas
    if y == b.y then
      if x >= b.x + 1 and x <= b.x + 2 then goBack(s)
      elseif x >= b.x + 4 and x <= b.x + 5 then goFwd(s) end
      return
    end
    if y == b.y + 1 then return end

    -- favoritos
    if x < b.x + SIDE then
      local i = y - (b.y + 2)
      if FAVS[i] then navigate(s, FAVS[i][2]) end
      return
    end

    -- lista: cabeçalho e rodapé não são itens
    if y == b.y + 2 or y >= b.y + b.h - 2 then return end
    local rel = y - (b.y + 3)
    local k = rel + s.first
    local name = s.items[k]
    if not name then return end

    local now = computer.uptime()
    if s.sel == name and now - s.lastClick < 0.6 then
      openItem(s, name)
    else
      s.sel = name
    end
    s.lastClick = now
  end,

  key = function(win, ch, code, ctx)
    local s = ensure(win, ctx)
    local idx = indexOf(s.items, s.sel) or 0
    if code == 200 then                              -- ↑
      moveSel(s, idx > 0 and idx - 1 or 1)
    elseif code == 208 then                          -- ↓
      moveSel(s, idx + 1)
    elseif code == 28 or code == 156 then            -- Enter
      if s.sel then openItem(s, s.sel) end
    elseif code == 14 then                           -- Backspace: pasta acima
      navigate(s, parentOf(s.path))
    end
  end,
}
