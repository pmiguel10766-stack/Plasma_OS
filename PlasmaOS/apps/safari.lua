-- Plasma OS - Safari: navegador HTTP/HTTPS (texto puro, sem imagens, CSS ou JS)
-- Precisa de uma placa de rede (internet card). Setas ↑ ↓ e PgUp/PgDn rolam a página.

local TIMEOUT      = 20          -- segundos até desistir de uma conexão
local MAX_BODY     = 200 * 1024  -- corta páginas maiores que isso
local MAX_REDIRECT = 3

-- Utilidades de texto (UTF-8 quando a GPU/Lua tiver a biblioteca unicode)
local function len(s)
  if unicode and unicode.len then return unicode.len(s) end
  return #s
end

local function usub(s, i, j)
  if unicode and unicode.sub then return unicode.sub(s, i, j) end
  return s:sub(i, j)
end

local function chr(v)
  if v < 128 then return string.char(v) end
  if unicode and unicode.char then
    local ok, c = pcall(unicode.char, v)
    if ok then return c end
  end
  return "?"
end

-- HTML -> texto -------------------------------------------------------------

local ENT = {
  amp = "&", lt = "<", gt = ">", quot = '"', apos = "'", nbsp = " ",
  copy = "(c)", reg = "(r)", ndash = "-", mdash = "--", hellip = "...",
  laquo = '"', raquo = '"',
}

local function decode(s)
  s = s:gsub("&#[xX](%x+);", function(n) return chr(tonumber(n, 16) or 63) end)
  s = s:gsub("&#(%d+);", function(n) return chr(tonumber(n) or 63) end)
  s = s:gsub("&(%a+);", function(n) return ENT[n:lower()] or ("&" .. n .. ";") end)
  return s
end

local BLOCK = {
  p = 1, div = 1, br = 1, li = 1, tr = 1, ul = 1, ol = 1, table = 1,
  section = 1, article = 1, header = 1, footer = 1, blockquote = 1, pre = 1,
  h1 = 1, h2 = 1, h3 = 1, h4 = 1, h5 = 1, h6 = 1,
}

-- "script" -> "[Ss][Cc][Rr][Ii][Pp][Tt]" (padrão sem diferenciar maiúsculas)
local function ci(word)
  return (word:gsub("%a", function(c) return "[" .. c:lower() .. c:upper() .. "]" end))
end

local function htmlToText(src)
  local s = src:gsub("\r", "")
  s = s:gsub("<!%-%-.-%-%->", "")
  s = s:gsub("<" .. ci("script") .. ".-</" .. ci("script") .. "%s*>", "")
  s = s:gsub("<" .. ci("style") .. ".-</" .. ci("style") .. "%s*>", "")
  s = s:gsub("<[^>]*>", function(tag)
    local name = tag:match("^<%s*/?%s*(%a[%w]*)")
    if name and BLOCK[name:lower()] then return "\n" end
    return ""
  end)
  s = decode(s)
  s = s:gsub("[ \t]+", " ")
  s = s:gsub(" *\n *", "\n")
  s = s:gsub("\n\n\n+", "\n\n")
  s = s:gsub("^%s+", ""):gsub("%s+$", "")
  return s
end

-- Quebra o texto em linhas de no máximo `width` colunas
local function wrap(text, width)
  width = math.max(10, width)
  local out = {}
  for para in (text .. "\n"):gmatch("([^\n]*)\n") do
    if para == "" then
      out[#out + 1] = ""
    else
      local line = ""
      for word in para:gmatch("%S+") do
        while len(word) > width do
          if line ~= "" then out[#out + 1] = line; line = "" end
          out[#out + 1] = usub(word, 1, width)
          word = usub(word, width + 1)
        end
        if line == "" then
          line = word
        elseif len(line) + 1 + len(word) <= width then
          line = line .. " " .. word
        else
          out[#out + 1] = line
          line = word
        end
      end
      if line ~= "" then out[#out + 1] = line end
    end
  end
  return out
end

-- URLs ------------------------------------------------------------------------

-- Resolve um Location de redirecionamento contra a página atual
local function resolve(base, loc)
  if loc:match("^%a[%w+.-]*://") then return loc end
  local host = base:match("^(%a[%w+.-]*://[^/]+)") or base
  if loc:sub(1, 1) == "/" then return host .. loc end
  return host .. "/" .. loc
end

-- Rede -----------------------------------------------------------------------

local function closeHandle(s)
  if s.handle then pcall(s.handle.close, s.handle) end
  s.handle = nil
end

local function fail(s, msg)
  closeHandle(s)
  s.msg = msg
end

local function startRequest(s, url, depth)
  closeHandle(s)
  local addr = component.list("internet")()
  if not addr then
    s.msg = "Sem placa de rede (internet card)."
    return
  end
  local inet = component.proxy(addr)
  local ok, h, err = pcall(inet.request, url)
  if not ok then
    s.msg = "Endereço não suportado: " .. tostring(h)
    return
  end
  if not h then
    s.msg = "Não foi possível abrir: " .. tostring(err)
    return
  end
  s.handle  = h
  s.reqUrl  = url
  s.depth   = depth or 0
  s.started = computer.uptime()
  s.body    = {}
  s.size    = 0
  s.msg     = "Carregando..."
end

local function finish(s)
  local h = s.handle
  local okr, code, reason, headers = pcall(h.response)
  if not okr then code, reason, headers = nil, nil, nil end
  closeHandle(s)

  code = tonumber(code) or 200
  if code >= 300 and code < 400 and headers then
    local loc = headers.Location or headers.location
    if type(loc) == "table" then loc = loc[1] end
    if loc and s.depth < MAX_REDIRECT then
      startRequest(s, resolve(s.reqUrl, tostring(loc)), s.depth + 1)
      return
    end
  end

  local text = htmlToText(table.concat(s.body))
  if text == "" then text = "(Página vazia)" end
  s.text    = text
  s.lines   = nil
  s.wrapW   = nil
  s.page    = s.reqUrl
  s.scroll  = 0
  if code >= 400 then
    s.msg = "Erro " .. code .. (reason and (" " .. tostring(reason)) or "")
  else
    s.msg = nil
  end
end

-- Chamado a cada redesenho: avança a conexão sem travar a interface
local function poll(s)
  local h = s.handle
  if not h then return end

  local ok, ready = pcall(h.finishConnect)
  if not ok then return fail(s, "Erro de conexão: " .. tostring(ready)) end
  if not ready then
    if computer.uptime() - s.started > TIMEOUT then
      fail(s, "Tempo esgotado.")
    end
    return
  end

  while s.size < MAX_BODY do
    local okr, chunk, reason = pcall(h.read, math.huge)
    if not okr then return fail(s, "Erro ao ler: " .. tostring(chunk)) end
    if not chunk then
      if reason then return fail(s, "Erro ao ler: " .. tostring(reason)) end
      return finish(s)
    end
    s.body[#s.body + 1] = chunk
    s.size = s.size + #chunk
  end
  finish(s)  -- limite de tamanho atingido
end

local function navigate(s)
  local url = s.input:match("^%s*(.-)%s*$")
  if url == "" then return end
  if not url:match("^%a[%w+.-]*://") then url = "http://" .. url end
  s.scroll = 0
  startRequest(s, url, 0)
end

-- Layout ---------------------------------------------------------------------

local function layout(s, width)
  if not s.text then return nil end
  if s.wrapW ~= width or not s.lines then
    s.lines = wrap(s.text, width)
    s.wrapW = width
  end
  return s.lines
end

return {
  name = "Safari", letter = "S", color = 0x2F80ED,

  init = function(win)
    win.state = win.state or {
      input = "", page = "", reqUrl = nil,
      msg = "Digite um endereço e pressione Enter.",
      text = nil, lines = nil, wrapW = nil, scroll = 0,
      handle = nil, body = {}, size = 0, depth = 0, started = 0,
    }
  end,

  draw = function(win, b, g, ctx)
    local s = win.state
    poll(s)

    local BAR, SEP, PANEL = 0xF0F0F2, 0xD1D1D6, 0xFFFFFF
    local INK, DIM, BLUE  = 0x1D1D1F, 0x86868B, 0x0A84FF

    g.fill(b.x, b.y, b.w, b.h, PANEL)

    -- barra de endereço
    g.fill(b.x, b.y, b.w, 1, BAR)
    local btnW = 6
    local fieldW = b.w - btnW - 2
    g.fill(b.x + 1, b.y, fieldW, 1, PANEL)
    local shown, fg
    if s.input == "" then
      shown, fg = "Digite um endereço", 0xAEAEB2
    else
      shown, fg = s.input .. "_", INK
    end
    local maxw = fieldW - 2
    if len(shown) > maxw then shown = usub(shown, len(shown) - maxw + 1) end
    g.text(b.x + 2, b.y, shown, fg, PANEL)

    local bx = b.x + b.w - btnW
    g.fill(bx, b.y, btnW, 1, BLUE)
    g.text(bx + 2, b.y, s.handle and "..." or "Ir", 0xFFFFFF, BLUE)

    -- separador
    g.fill(b.x, b.y + 1, b.w, 1, SEP)

    -- área da página
    local top = b.y + 2
    local ph = b.h - 2
    if ph < 1 then return end
    local statusRow = nil
    if s.msg and (s.text ~= nil or s.handle) then
      statusRow = top + ph - 1
      ph = ph - 1
    end

    local lines = layout(s, math.max(10, b.w - 2))
    if lines then
      local maxScroll = math.max(0, #lines - ph)
      if s.scroll > maxScroll then s.scroll = maxScroll end
      if s.scroll < 0 then s.scroll = 0 end
      for i = 1, ph do
        local ln = lines[s.scroll + i]
        if ln then g.text(b.x + 1, top + i - 1, g.clip(ln, b.w - 2), INK, PANEL) end
      end
      if maxScroll > 0 and not statusRow then
        local pct = math.floor(s.scroll / maxScroll * 100 + 0.5)
        local lab = pct .. "%"
        g.text(b.x + b.w - len(lab) - 1, top + ph - 1, lab, DIM, PANEL)
      end
    else
      -- sem página ainda: mensagem centralizada
      local msg = s.msg or "Digite um endereço e pressione Enter."
      local cy = top + math.floor(ph / 2)
      g.text(b.x + math.max(1, math.floor((b.w - len(msg)) / 2)), cy,
        g.clip(msg, b.w - 2), DIM, PANEL)
    end

    if statusRow then
      g.fill(b.x, statusRow, b.w, 1, BAR)
      g.text(b.x + 1, statusRow, g.clip(s.msg, b.w - 2), DIM, BAR)
    end
  end,

  touch = function(win, b, x, y, ctx)
    if y == b.y and x >= b.x + b.w - 6 then
      navigate(win.state)
    end
  end,

  key = function(win, ch, code, ctx)
    local s = win.state
    if code == 28 or code == 156 then            -- Enter
      navigate(s)
    elseif code == 14 then                       -- Backspace
      if s.input ~= "" then s.input = usub(s.input, 1, len(s.input) - 1) end
    elseif code == 200 then s.scroll = math.max(0, s.scroll - 1)      -- ↑
    elseif code == 208 then s.scroll = s.scroll + 1                   -- ↓
    elseif code == 201 then s.scroll = math.max(0, s.scroll - 8)      -- PgUp
    elseif code == 209 then s.scroll = s.scroll + 8                   -- PgDn
    elseif ch and ch >= 32 and ch < 127 and len(s.input) < 300 then
      s.input = s.input .. string.char(ch)
    end
  end,
}
