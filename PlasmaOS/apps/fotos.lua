-- Plasma OS - Fotos: galeria no estilo do app Fotos do OS X Yosemite
-- Lê os arquivos .pic de /PlasmaOS/fotos/.
--
-- Formato .pic (texto):
--   primeira linha: largura altura           (ex.: 8 4)
--   depois, uma linha por linha da imagem, com uma cor hexadecimal de 6 dígitos
--   por pixel, separadas por espaço          (ex.: ff0000 00ff00 ...)
--
-- Clique numa foto para selecioná-la; clique de novo (ou Enter) para abrir.
-- Em tela cheia, Backspace ou o botão "‹ Fotos" volta à galeria.

local DIR = "/PlasmaOS/fotos/"
local CARD_W, CARD_H = 16, 7       -- miniatura: 16 colunas por 4 linhas de texto
local THUMB_ROWS = 4

local TOOL, PANEL, SEP = 0xF0F0F2, 0xFFFFFF, 0xD1D1D6
local INK, DIM, WHITE = 0x1D1D1F, 0x86868B, 0xFFFFFF
local BLUE, GRAY, EMPTY = 0x0A84FF, 0xE5E5EA, 0xDCE7D3
local SELBG = 0xDCEBFF

local function len(s)
  if unicode and unicode.len then return unicode.len(s) end
  return #s
end

-- Lista e leitura -------------------------------------------------------------

local function listPics(ctx)
  local out = {}
  local ok, t = pcall(ctx.fs.list, DIR)
  if ok and type(t) == "table" then
    for _, name in ipairs(t) do
      if name:match("%.pic$") then out[#out + 1] = name:sub(1, -5) end
    end
  end
  table.sort(out)
  return out
end

local function readFile(ctx, path)
  if not ctx.fs.exists(path) then return nil end
  local h = ctx.fs.open(path, "r")
  if not h then return nil end
  local parts = {}
  repeat
    local chunk = ctx.fs.read(h, math.huge)
    if chunk then parts[#parts + 1] = chunk end
  until not chunk
  ctx.fs.close(h)
  return table.concat(parts)
end

-- Converte o texto de um .pic em { w, h, px[y][x] = cor }. Devolve nil se não bater com o formato.
local function parsePic(text)
  local lines = {}
  for line in (text .. "\n"):gmatch("(.-)\n") do
    if line:match("%S") then lines[#lines + 1] = line end
  end
  local w, h = (lines[1] or ""):match("^%s*(%d+)%s+(%d+)%s*$")
  w, h = tonumber(w), tonumber(h)
  if not w or not h or w < 1 or h < 1 or #lines < h + 1 then return nil end
  local px = {}
  for y = 1, h do
    local row, x = {}, 0
    for tok in lines[y + 1]:gmatch("%x+") do
      x = x + 1
      row[x] = tonumber(tok, 16) or 0
    end
    if x < w then return nil end
    px[y] = row
  end
  return { w = w, h = h, px = px }
end

-- Imagens e miniaturas são guardadas no estado para não reler o disco a cada quadro
local function getImage(win, ctx, name)
  local s = win.state
  if s.images[name] == nil then
    local img = parsePic(readFile(ctx, DIR .. name .. ".pic") or "") or false
    s.images[name] = img
  end
  return s.images[name] or nil
end

-- Cor de uma posição da imagem, em coordenadas de 0 a 1
local function sample(img, u, v)
  local ix = math.min(img.w, math.max(1, math.floor(u * img.w) + 1))
  local iy = math.min(img.h, math.max(1, math.floor(v * img.h) + 1))
  return img.px[iy][ix] or 0
end

-- Miniatura: uma tabela de células (cor de cima, cor de baixo) de 16 x 4
local function getThumb(win, ctx, name)
  local s = win.state
  if s.thumbs[name] then return s.thumbs[name] end
  local img = getImage(win, ctx, name)
  local cells = {}
  for cy = 0, THUMB_ROWS - 1 do
    local row = {}
    for cx = 0, CARD_W - 1 do
      if img then
        local u = cx / CARD_W
        row[cx + 1] = {
          sample(img, u, (2 * cy) / (2 * THUMB_ROWS)),
          sample(img, u, (2 * cy + 1) / (2 * THUMB_ROWS)),
        }
      else
        row[cx + 1] = { EMPTY, EMPTY }
      end
    end
    cells[cy + 1] = row
  end
  s.thumbs[name] = cells
  return cells
end

-- Estado ----------------------------------------------------------------------

local function ensure(win)
  local s = win.state
  if not s then
    s = {
      view = "gallery", sel = nil, open = nil,
      images = {}, thumbs = {}, lastClick = -10, lastName = nil,
    }
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

-- Desenho -----------------------------------------------------------------------

local function drawGallery(win, b, g, ctx, s, pics)
  -- barra superior
  g.fill(b.x, b.y, b.w, 1, TOOL)
  g.fill(b.x, b.y + 1, b.w, 1, SEP)
  g.text(b.x + 2, b.y, #pics .. (#pics == 1 and " foto" or " fotos"), DIM, TOOL)
  local title = "Fotos"
  g.text(b.x + math.max(0, math.floor((b.w - len(title)) / 2)), b.y, title, INK, TOOL)
  local canOpen = s.sel ~= nil
  g.fill(b.x + b.w - 9, b.y, 8, 1, canOpen and BLUE or GRAY)
  g.text(b.x + b.w - 7, b.y, "Abrir", canOpen and WHITE or DIM, canOpen and BLUE or GRAY)

  -- galeria de miniaturas
  local listTop = b.y + 2
  local bottom = b.y + b.h - 2
  if #pics == 0 then
    local cx = b.x + math.floor(b.w / 2)
    local top = b.y + math.floor(b.h / 2) - 3
    for row = 0, 4 do
      local ww = row * 2 + 1
      g.fill(cx - row, top + row, ww, 1, row < 2 and 0xC9D6E2 or 0x7F8C8D)
    end
    g.fill(b.x, top + 5, b.w, 1, EMPTY)
    local msg = "Nenhuma foto encontrada"
    g.text(b.x + math.max(1, math.floor((b.w - len(msg)) / 2)), top + 7, msg, DIM, PANEL)
    return
  end

  local perRow = math.max(1, math.floor((b.w - 1) / (CARD_W + 1)))
  for i, name in ipairs(pics) do
    local col = (i - 1) % perRow
    local row = math.floor((i - 1) / perRow)
    local x = b.x + 1 + col * (CARD_W + 1)
    local y = listTop + row * (CARD_H + 1)
    if y + CARD_H - 1 < bottom then
      local sel = (name == s.sel)
      if sel then g.fill(x - 1, y - 1, CARD_W + 2, CARD_H + 1, SELBG) end
      local thumb = getThumb(win, ctx, name)
      for cy = 1, THUMB_ROWS do
        for cx = 1, CARD_W do
          local c = thumb[cy][cx]
          g.text(x + cx - 1, y + cy - 1, "▀", c[1], c[2])
        end
      end
      local label = name
      g.text(x, y + THUMB_ROWS, g.clip(label, CARD_W), INK, sel and SELBG or PANEL)
    end
  end

  -- rodapé com a foto selecionada
  g.fill(b.x, bottom, b.w, 1, SEP)
  g.fill(b.x, b.y + b.h - 1, b.w, 1, TOOL)
  local info = s.sel or "Selecione uma foto"
  if s.sel then
    local img = getImage(win, ctx, s.sel)
    if img then info = info .. "  ·  " .. img.w .. " × " .. img.h .. " px" end
  end
  g.text(b.x + 2, b.y + b.h - 1, g.clip(info, b.w - 4), DIM, TOOL)
end

local function drawViewer(win, b, g, ctx, s)
  g.fill(b.x, b.y, b.w, b.h, PANEL)
  g.fill(b.x, b.y, b.w, 1, TOOL)
  g.fill(b.x, b.y + 1, b.w, 1, SEP)
  g.text(b.x + 1, b.y, "‹ Fotos", BLUE, TOOL)
  g.text(b.x + math.max(0, math.floor((b.w - len(s.open)) / 2)), b.y, s.open, INK, TOOL)

  local img = getImage(win, ctx, s.open)
  if not img then
    local msg = "Não foi possível abrir esta foto."
    g.text(b.x + math.max(1, math.floor((b.w - len(msg)) / 2)), b.y + math.floor(b.h / 2), msg, DIM, PANEL)
    return
  end

  -- encaixa a imagem na área, mantendo a proporção; cada célula mostra 2 pixels (meio-blocos)
  local W = b.w
  local H2 = (b.h - 2) * 2                       -- altura em pixels da tela
  local scale = math.max(img.w / W, img.h / H2, 1)
  local dw, dh = img.w / scale, img.h / scale
  local ox = math.floor((W - dw) / 2)
  local oy = math.floor((H2 - dh) / 2)
  local top = b.y + 2

  for cy = 0, b.h - 3 do
    for cx = 0, W - 1 do
      local colors = {}
      for half = 0, 1 do
        local sx, sy = cx - ox, (2 * cy + half) - oy
        if sx >= 0 and sx < dw and sy >= 0 and sy < dh then
          colors[half + 1] = sample(img, (sx + 0.5) / dw, (sy + 0.5) / dh)
        else
          colors[half + 1] = PANEL
        end
      end
      g.text(b.x + cx, top + cy, "▀", colors[1], colors[2])
    end
  end
end

return {
  name = "Fotos", letter = "P", color = 0x9B51E0,

  init = function(win, ctx)
    ensure(win)
  end,

  draw = function(win, b, g, ctx)
    local s = ensure(win)
    g.fill(b.x, b.y, b.w, b.h, PANEL)
    if b.h < 6 or b.w < 20 then return end

    if s.view == "viewer" and s.open then
      drawViewer(win, b, g, ctx, s)
    else
      s.view = "gallery"
      drawGallery(win, b, g, ctx, s, listPics(ctx))
    end
  end,

  touch = function(win, b, x, y, ctx)
    local s = ensure(win)

    if s.view == "viewer" then
      if y == b.y and x <= b.x + 8 then
        s.view = "gallery"
        s.open = nil
      end
      return
    end

    -- barra superior
    if y == b.y then
      if x >= b.x + b.w - 9 and s.sel then
        s.view, s.open = "viewer", s.sel
      end
      return
    end

    local pics = listPics(ctx)
    local perRow = math.max(1, math.floor((b.w - 1) / (CARD_W + 1)))
    local listTop = b.y + 2
    local rel_y = y - listTop
    if rel_y < 0 or y >= b.y + b.h - 2 then return end
    local row = math.floor(rel_y / (CARD_H + 1))
    local rel_x = x - (b.x + 1)
    local col = math.floor(rel_x / (CARD_W + 1))
    if col < 0 or col >= perRow then return end
    local name = pics[row * perRow + col + 1]
    if not name then return end

    local now = computer.uptime()
    if s.sel == name and now - s.lastClick < 0.6 then
      s.view, s.open = "viewer", name
    else
      s.sel = name
    end
    s.lastClick = now
  end,

  key = function(win, ch, code, ctx)
    local s = ensure(win)
    if s.view == "viewer" then
      if code == 14 then
        s.view, s.open = "gallery", nil
      end
      return
    end

    local pics = listPics(ctx)
    local perRow = math.max(1, math.floor(((win.w or 46) - 1) / (CARD_W + 1)))
    local idx = s.sel and indexOf(pics, s.sel) or 0
    if code == 203 then idx = math.max(1, idx - 1)
    elseif code == 205 then idx = math.min(#pics, idx + 1)
    elseif code == 200 then idx = math.max(1, idx - perRow)
    elseif code == 208 then idx = math.min(#pics, idx + perRow)
    elseif code == 28 or code == 156 then
      if s.sel then s.view, s.open = "viewer", s.sel end
      return
    else
      return
    end
    if #pics > 0 then s.sel = pics[idx] end
  end,
}
