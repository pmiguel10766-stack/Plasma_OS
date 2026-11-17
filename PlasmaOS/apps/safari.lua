-- Plasma OS - Safari: navegador HTTP/HTTPS (texto puro, sem imagens, CSS ou JS)
-- Precisa de uma placa de rede (internet card).
-- Modo Normal: página completa, links azuis (clique, ou Tab + Enter).
-- Modo Leitura: só o texto, sem anúncios, menus, banners e pop-ups; espaçamento ajustável.
-- ↑ ↓ e PgUp/PgDn rolam. Enter na barra de endereço carrega o endereço. Ctrl+R troca o modo.

local TIMEOUT      = 20          -- segundos até desistir de uma conexão
local MAX_BODY     = 200 * 1024  -- corta páginas maiores que isso
local MAX_REDIRECT = 3

local PANEL, INK, DIM   = 0xFFFFFF, 0x1D1D1F, 0x86868B
local BLUE, FOCUS_BG    = 0x0A84FF, 0xDCEBFF
local BAR, SEP, HINT_BG = 0xF0F0F2, 0xD1D1D6, 0xF5F5F7


-- Marcadores de link no texto (bytes de controle que não aparecem em páginas comuns):
-- \1 n \2  = início do link número n     \4 = fim do link
local OPEN_A, OPEN_B, CLOSE = "\1", "\2", "\4"

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

-- Comprimento visível de um pedaço de texto, sem contar os marcadores de link
local function visLen(s)
  local plain = s:gsub("\1%d+\2", ""):gsub("\4", "")
  return len(plain)
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

-- Modo leitura: tira o que não é texto da página (anúncios, banners, menus, pop-ups...)
local DROP_TAGS = {
  nav = 1, aside = 1, footer = 1, form = 1, iframe = 1, noscript = 1, svg = 1,
  button = 1, select = 1, object = 1, embed = 1, dialog = 1, template = 1,
  canvas = 1, video = 1, audio = 1,
}
local JUNK_WORDS = {
  "ad", "ads", "advert", "advertisement", "banner", "menu", "popup", "pop%-up",
  "modal", "cookie", "cookies", "sidebar", "promo", "sponsor", "share", "social",
  "newsletter", "subscribe", "breadcrumb", "widget", "related", "taboola", "outbrain",
}

local function isJunkTag(tag)
  local attrs = tag:lower()
  for _, w in ipairs(JUNK_WORDS) do
    if attrs:find("class%s*=%s*[\"'][^\"']*%f[%w]" .. w .. "%f[%W]")
      or attrs:find("id%s*=%s*[\"'][^\"']*%f[%w]" .. w .. "%f[%W]") then
      return true
    end
  end
  return false
end

-- Remove os elementos de "chrome" do HTML. Devolve o HTML limpo e quantos foram removidos.
-- (Um elemento vai do seu <tag> até o primeiro </tag> igual: aproximação simples.)
local function removeJunk(src)
  local lower = src:lower()
  local out, pos, removed = {}, 1, 0
  while true do
    local s1, e1, name = src:find("<(%a[%w]*)[^>]*>", pos)
    if not s1 then
      out[#out + 1] = src:sub(pos)
      break
    end
    local lname = name:lower()
    local tag = src:sub(s1, e1)
    if DROP_TAGS[lname] or (isJunkTag(tag) and lname ~= "html" and lname ~= "body") then
      out[#out + 1] = src:sub(pos, s1 - 1)
      removed = removed + 1
      local _, ce = lower:find("</" .. lname .. "%s*>", e1 + 1)
      pos = ce and (ce + 1) or (e1 + 1)
    else
      out[#out + 1] = src:sub(pos, e1)
      pos = e1 + 1
    end
  end
  return table.concat(out), removed
end

-- Devolve o texto e a lista de links (href de cada <a>, na ordem em que aparecem)
local function htmlToText(src)
  local links = {}
  local s = src:gsub("\r", "")
  s = s:gsub("<!%-%-.-%-%->", "")
  s = s:gsub("<" .. ci("script") .. ".-</" .. ci("script") .. "%s*>", "")
  s = s:gsub("<" .. ci("style") .. ".-</" .. ci("style") .. "%s*>", "")

  -- <a href="..."> vira marcador de início; </a> vira marcador de fim
  s = s:gsub("<%s*[Aa]%f[%s>][^>]*>", function(tag)
    local href = tag:match('[Hh][Rr][Ee][Ff]%s*=%s*"([^"]*)"')
      or tag:match("[Hh][Rr][Ee][Ff]%s*=%s*'([^']*)'")
      or tag:match("[Hh][Rr][Ee][Ff]%s*=%s*([^%s>]+)")
    if href then
      href = decode(href):gsub("^%s+", ""):gsub("%s+$", "")
      if href ~= "" then
        links[#links + 1] = href
        return OPEN_A .. #links .. OPEN_B
      end
    end
    return ""
  end)
  s = s:gsub("<%s*/%s*[Aa]%s*>", CLOSE)

  s = s:gsub("<[^>]*>", function(tag)
    local name = tag:match("^<%s*/?%s*(%a[%w]*)")
    if name and BLOCK[name:lower()] then return "\n" end
    return ""
  end)
  s = decode(s)
  s = s:gsub("[ \t]+", " ")
  s = s:gsub(" *\n *", "\n")
  s = s:gsub("\n\n\n+", "\n\n")
  local text = s:gsub("^%s+", ""):gsub("%s+$", "")
  return text, links
end

-- Quebra o texto em linhas. Um link que atravessa a quebra é fechado no fim
-- da linha e reaberto no começo da próxima, para continuar azul.
local function wrap(text, width)
  width = math.max(10, width)
  local out = {}
  local open = nil             -- número do link aberto neste ponto do texto
  local line, lineLen = "", 0

  local function reopen()
    return open and (OPEN_A .. open .. OPEN_B) or ""
  end

  local function newLine()
    out[#out + 1] = line .. (open and CLOSE or "")
    line, lineLen = reopen(), 0
  end

  local function track(word)
    local pos = 1
    while true do
      local s1, e1, idx = word:find("\1(%d+)\2", pos)
      local s2 = word:find("\4", pos, true)
      if not s1 and not s2 then break end
      if s1 and (not s2 or s1 < s2) then
        open = tonumber(idx)
        pos = e1 + 1
      else
        open = nil
        pos = s2 + 1
      end
    end
  end

  for para in (text .. "\n"):gmatch("([^\n]*)\n") do
    for word in para:gmatch("%S+") do
      local vis = visLen(word)
      if lineLen > 0 and lineLen + 1 + vis > width then newLine() end
      if lineLen > 0 then
        line = line .. " "
        lineLen = lineLen + 1
      end
      line = line .. word
      lineLen = lineLen + vis
      track(word)
    end
    newLine()
  end
  return out
end

-- URLs ------------------------------------------------------------------------

-- Resolve um href ou um Location de redirecionamento contra a página atual
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

  local raw = table.concat(s.body)
  local text, links = htmlToText(raw)
  if text == "" then text = "(Página vazia)" end
  local cleaned, removed = removeJunk(raw)
  local readText = htmlToText(cleaned)

  s.text      = text
  s.links     = links
  s.readText  = readText
  s.removed   = removed
  s.lines     = nil
  s.wrapW     = nil
  s.page      = s.reqUrl
  s.scroll    = 0
  s.focus     = nil
  s.focusMode = false
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
  s.focusMode = false
  startRequest(s, url, 0)
end

-- Abre o link de número idx (clique ou Enter com o link selecionado)
local function followLink(s, idx)
  local href = s.links and s.links[idx]
  if not href then return end
  if href:sub(1, 1) == "#" then
    s.msg = "Links para dentro da página ainda não são suportados."
    return
  end
  if href:match("^%a[%w+.-]*:") and not href:match("^https?://") then
    s.msg = "Esse tipo de link não é suportado."
    return
  end
  local url
  if href:match("^%a[%w+.-]*://") then
    url = href
  elseif href:sub(1, 2) == "//" then
    url = ((s.page or ""):match("^(%a+):") or "http") .. ":" .. href
  else
    url = resolve(s.page ~= "" and s.page or "http://", href)
  end
  s.input = url
  s.scroll = 0
  s.focusMode = false
  startRequest(s, url, 0)
end

-- Layout ---------------------------------------------------------------------

local function layout(s, width)
  if not s.text then return nil end
  local key = s.mode .. ":" .. (s.gap or 0)
  if s.wrapW ~= width or s.lineKey ~= key or not s.lines then
    local src = s.text
    if s.mode == "reading" then
      -- modo leitura: texto limpo, sem links azuis
      src = s.readText or s.text
      src = src:gsub("\1%d+\2", ""):gsub("\4", "")
    end
    local lines = wrap(src, width)
    if s.mode == "reading" and (s.gap or 0) == 1 then
      -- espaçamento amplo: uma linha em branco depois de cada linha
      local spaced = {}
      for _, ln in ipairs(lines) do
        spaced[#spaced + 1] = ln
        spaced[#spaced + 1] = ""
      end
      lines = spaced
    end
    s.lines = lines
    s.wrapW = width
    s.lineKey = key
  end
  return s.lines
end

-- Botão de modo (aceso quando está ativo)
local function modeBtn(g, x, y, w, label, on)
  local bg = on and BLUE or 0xE5E5EA
  local fg = on and 0xFFFFFF or INK
  g.fill(x, y, w, 1, bg)
  g.text(x + math.max(0, math.floor((w - len(label)) / 2)), y, label, fg, bg)
end

-- Escolhe o próximo link (Tab) e rola a página até ele
local function nextLink(s)
  if s.mode ~= "normal" then return end
  local n = s.links and #s.links or 0
  if n == 0 then return end
  s.focus = ((s.focus or 0) % n) + 1
  s.focusMode = true
  s.msg = nil
  if s.lines then
    local pat = OPEN_A .. s.focus .. OPEN_B
    for i, ln in ipairs(s.lines) do
      if ln:find(pat, 1, true) then
        s.scroll = math.max(0, i - 3)
        break
      end
    end
  end
end

-- Desenha uma linha; no modo normal os links ficam azuis e guardam sua posição na tela
local function drawLine(g, s, x, y, line, width, fgc, bgc)
  local col, pos, link = 0, 1, nil

  local function put(txt)
    if txt == "" then return end
    if col >= width then
      col = col + len(txt)
      return
    end
    local vis = usub(txt, 1, width - col)
    local fg, bg = fgc, bgc
    if link then
      fg = BLUE
      if s.focus == link then bg = FOCUS_BG end
      s.hits[#s.hits + 1] = { x = x + col, y = y, w = len(vis), idx = link }
    end
    g.text(x + col, y, vis, fg, bg)
    col = col + len(txt)
  end

  while true do
    local m = line:find("[\1\4]", pos)
    if not m then
      put(line:sub(pos))
      break
    end
    put(line:sub(pos, m - 1))
    if line:sub(m, m) == "\1" then
      local idx = line:match("^\1(%d+)\2", m)
      if idx then
        link = tonumber(idx)
        pos = m + #idx + 2
      else
        pos = m + 1
      end
    else
      link = nil
      pos = m + 1
    end
  end
end

return {
  name = "Safari", letter = "S", color = 0x2F80ED,

  init = function(win)
    win.state = win.state or {
      input = "", page = "", reqUrl = nil,
      msg = "Digite um endereço e pressione Enter.",
      text = nil, readText = nil, links = nil, lines = nil, wrapW = nil,
      lineKey = nil, scroll = 0,
      focus = nil, focusMode = false, hits = {},
      mode = "normal", showWarn = true, removed = 0,
      gap = 0,
      handle = nil, body = {}, size = 0, depth = 0, started = 0,
    }
  end,

  draw = function(win, b, g, ctx)
    local s = win.state
    poll(s)
    s.hits = {}
    local reading = (s.mode == "reading")

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

    -- linha de modos: Normal, Leitura e Aviso
    local r2 = b.y + 2
    g.fill(b.x, r2, b.w, 1, BAR)
    modeBtn(g, b.x + 1, r2, 12, "Modo normal", not reading)
    modeBtn(g, b.x + 14, r2, 17, "Leitura (texto)", reading)
    modeBtn(g, b.x + b.w - 11, r2, 10, "Aviso", s.showWarn)
    g.fill(b.x, r2 + 1, b.w, 1, SEP)
    local top = b.y + 4

    -- linha do modo leitura: espaçamento
    if reading and b.w >= 36 then
      g.fill(b.x, top, b.w, 1, BAR)
      modeBtn(g, b.x + 1, top, 15, "Espaço: " .. ((s.gap or 0) == 1 and "amplo" or "justo"), (s.gap or 0) == 1)
      g.fill(b.x, top + 1, b.w, 1, SEP)
      top = top + 2
    end

    local ph = b.y + b.h - top
    if ph < 2 then return end

    -- área da página (modo leitura com as cores normais)
    local pageBg, pageFg = PANEL, INK
    g.fill(b.x, top, b.w, ph, pageBg)

    -- aviso logo abaixo dos botões (quando há página e o aviso está ligado)
    if s.showWarn and s.text ~= nil then
      local txt
      if reading then
        if (s.removed or 0) > 0 then
          txt = "Modo leitura: " .. s.removed .. " elementos ocultados (anúncios, menus, banners)."
        else
          txt = "Modo leitura: esta página não tinha elementos extras."
        end
      else
        txt = "Aviso: imagens e scripts não são exibidos · "
          .. (s.removed or 0) .. " anúncios/menus detectados (use Leitura)."
      end
      g.fill(b.x, top, b.w, 1, 0xFFF3C4)
      g.text(b.x + 1, top, g.clip(txt, b.w - 2), INK, 0xFFF3C4)
      top = top + 1
      ph = ph - 1
    end

    local statusText = s.msg
    if not statusText and s.focusMode and s.links and not reading then
      statusText = "Enter abre o link selecionado · Tab escolhe o próximo"
    end
    local statusRow = nil
    if statusText and (s.text ~= nil or s.handle or s.msg) and ph > 1 then
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
        if ln then drawLine(g, s, b.x + 1, top + i - 1, ln, b.w - 2, pageFg, pageBg) end
      end
      if maxScroll > 0 and not statusRow then
        local pct = math.floor(s.scroll / maxScroll * 100 + 0.5)
        local lab = pct .. "%"
        g.text(b.x + b.w - len(lab) - 1, top + ph - 1, lab, DIM, pageBg)
      end
    else
      -- sem página ainda: mensagem centralizada
      local msg = s.msg or "Digite um endereço e pressione Enter."
      local cy = top + math.floor(ph / 2)
      g.text(b.x + math.max(1, math.floor((b.w - len(msg)) / 2)), cy,
        g.clip(msg, b.w - 2), DIM, pageBg)
    end

    if statusRow then
      local bg = s.msg and BAR or HINT_BG
      g.fill(b.x, statusRow, b.w, 1, bg)
      g.text(b.x + 1, statusRow, g.clip(statusText, b.w - 2), DIM, bg)
    end
  end,

  touch = function(win, b, x, y, ctx)
    local s = win.state

    -- barra de endereço: botão Ir
    if y == b.y then
      if x >= b.x + b.w - 6 then navigate(s) end
      return
    end

    -- linha do modo leitura: espaçamento
    if y == b.y + 4 and s.mode == "reading" and b.w >= 36 then
      if x >= b.x + 1 and x <= b.x + 15 then
        s.gap = 1 - (s.gap or 0)
        s.lines = nil
      end
      return
    end

    -- linha de modos
    if y == b.y + 2 then
      if x >= b.x + 1 and x <= b.x + 12 then
        s.mode = "normal"
        s.lines = nil
        s.focusMode = false
        s.msg = "Modo normal: página completa, com links e cores originais."
      elseif x >= b.x + 14 and x <= b.x + 30 then
        s.mode = "reading"
        s.lines = nil
        s.focusMode = false
        s.msg = "Leitura (texto): só o texto puro, com o filtro visual ativo."
      elseif x >= b.x + b.w - 11 and x <= b.x + b.w - 2 then
        s.showWarn = not s.showWarn
      end
      return
    end

    -- clique num link (só existe no modo normal)
    for _, h in ipairs(s.hits or {}) do
      if h.y == y and x >= h.x and x < h.x + h.w then
        followLink(s, h.idx)
        return
      end
    end
  end,

  key = function(win, ch, code, ctx)
    local s = win.state
    if code == 28 or code == 156 then                 -- Enter
      if s.focusMode and s.focus then
        followLink(s, s.focus)
      else
        navigate(s)
      end
    elseif ch == 9 or code == 15 then                 -- Tab: próximo link
      nextLink(s)
    elseif ch == 18 then                              -- Ctrl+R: troca o modo
      s.mode = (s.mode == "normal") and "reading" or "normal"
      s.lines = nil
      s.focusMode = false
    elseif code == 14 then                            -- Backspace
      s.focusMode = false
      if s.input ~= "" then s.input = usub(s.input, 1, len(s.input) - 1) end
    elseif code == 200 then s.scroll = math.max(0, s.scroll - 1)      -- ↑
    elseif code == 208 then s.scroll = s.scroll + 1                   -- ↓
    elseif code == 201 then s.scroll = math.max(0, s.scroll - 8)      -- PgUp
    elseif code == 209 then s.scroll = s.scroll + 8                   -- PgDn
    elseif ch and ch >= 32 and ch < 127 and len(s.input) < 300 then
      s.focusMode = false
      s.input = s.input .. string.char(ch)
    end
  end,
}
