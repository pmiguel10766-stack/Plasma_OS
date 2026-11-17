-- Plasma OS - Loja: baixa e remove apps do repositório do Plasma OS no GitHub
-- Precisa de uma placa de rede (internet card).
--
-- O catálogo é o arquivo "catalogo.txt" na raiz do repositório. Uma linha por app:
--   nome|descrição|caminho no repositório|destino no disco
-- Exemplo:
--   Calculadora|Soma, subtrai, multiplica e divide.|apps/calculadora.lua|/PlasmaOS/apps/calculadora.lua
-- Linhas que começam com # são ignoradas.
--
-- Clique num app para ver os detalhes; "Obter" baixa e instala; "Remover" apaga o arquivo.
-- Depois de instalar um app, reinicie o Plasma para ele aparecer no dock.

local REPO    = "https://raw.githubusercontent.com/pmiguel10766-stack/Plasma_OS/main/"
local CATALOG = REPO .. "catalogo.txt"
local TIMEOUT = 15

local TOOL, SIDEBG, PANEL, SEP = 0xF0F0F2, 0xE9EBEE, 0xFFFFFF, 0xD1D1D6
local INK, DIM, WHITE, BLUE = 0x1D1D1F, 0x86868B, 0xFFFFFF, 0x0A84FF
local GREEN, GRAY, RED, SELBG = 0x34C759, 0xE5E5EA, 0xD93025, 0xD0D6DE
local SIDE = 20

local function len(s)
  if unicode and unicode.len then return unicode.len(s) end
  return #s
end

-- Rede -----------------------------------------------------------------------

local function getInternet()
  local addr = component.list("internet")()
  if not addr then return nil end
  return component.proxy(addr)
end

-- Baixa um arquivo inteiro. Devolve o conteúdo ou nil + motivo.
local function httpGet(inet, url)
  local okReq, h, err = pcall(inet.request, url)
  if not okReq then return nil, h end
  if not h then return nil, err end

  local deadline = computer.uptime() + TIMEOUT
  while not h.finishConnect() do
    if computer.uptime() > deadline then
      h.close()
      return nil, "tempo esgotado"
    end
    computer.pullSignal(0.1)
  end

  local parts = {}
  while true do
    local chunk, reason = h.read(math.huge)
    if chunk then
      parts[#parts + 1] = chunk
    else
      h.close()
      if reason then return nil, reason end
      return table.concat(parts)
    end
  end
end

-- Catálogo ----------------------------------------------------------------------

local function parseCatalog(text)
  local out = {}
  for line in (text .. "\n"):gmatch("(.-)\n") do
    line = line:match("^%s*(.-)%s*$")
    if line ~= "" and line:sub(1, 1) ~= "#" then
      local fields = {}
      for f in (line .. "|"):gmatch("([^|]*)|") do
        fields[#fields + 1] = f:match("^%s*(.-)%s*$")
      end
      if fields[1] and fields[1] ~= "" and fields[3] and fields[3] ~= "" and fields[4] and fields[4] ~= "" then
        out[#out + 1] = {
          name = fields[1], desc = fields[2] or "", src = fields[3], dest = fields[4],
        }
      end
    end
  end
  return out
end

-- Estado ----------------------------------------------------------------------

local function ensure(win)
  local s = win.state
  if not s then
    s = { apps = {}, sel = 1, status = "", loaded = false }
    win.state = s
  end
  return s
end

local function isInstalled(ctx, item)
  return ctx.fs.exists(item.dest)
end

local function loadCatalog(s)
  s.status = "Carregando catálogo..."
  local inet = getInternet()
  if not inet then
    s.status = "Sem placa de rede (internet card)."
    return
  end
  local body, err = httpGet(inet, CATALOG)
  if not body then
    s.status = "Não foi possível baixar o catálogo: " .. tostring(err)
    return
  end
  s.apps = parseCatalog(body)
  s.loaded = true
  s.sel = math.max(1, math.min(s.sel, #s.apps))
  s.status = #s.apps .. " apps no catálogo."
end

local function ensureDir(ctx, path)
  local dir = path:match("^(.*)/[^/]*$")
  if dir and dir ~= "" and not ctx.fs.exists(dir) then
    ctx.fs.makeDirectory(dir)
  end
end

local function install(s, ctx, item)
  local inet = getInternet()
  if not inet then
    s.status = "Sem placa de rede (internet card)."
    return
  end
  s.status = "Baixando " .. item.name .. "..."
  local body, err = httpGet(inet, REPO .. item.src)
  if not body or body == "" then
    s.status = "Falha ao baixar: " .. tostring(err or "arquivo vazio")
    return
  end
  if item.dest:sub(-4) == ".lua" then
    local fn, serr = load(body, "=" .. item.name, "t")
    if not fn then
      s.status = "Arquivo inválido: " .. tostring(serr)
      return
    end
  end
  ensureDir(ctx, item.dest)
  local h, werr = ctx.fs.open(item.dest, "w")
  if not h then
    s.status = "Erro ao gravar: " .. tostring(werr)
    return
  end
  ctx.fs.write(h, body)
  ctx.fs.close(h)
  s.status = item.name .. " instalado. Reinicie o Plasma para abrir."
end

local function remove(s, ctx, item)
  local ok, err = pcall(ctx.fs.remove, item.dest)
  if ok then
    s.status = item.name .. " removido. Reinicie o Plasma para atualizar o dock."
  else
    s.status = "Erro ao remover: " .. tostring(err)
  end
end

-- Desenho -----------------------------------------------------------------------

local function button(g, x, y, w, label, bg, fg)
  g.fill(x, y, w, 1, bg)
  g.text(x + math.max(0, math.floor((w - len(label)) / 2)), y, label, fg, bg)
end

return {
  name = "Loja", letter = "G", color = 0x2F80ED,

  init = function(win)
    ensure(win)
  end,

  draw = function(win, b, g, ctx)
    local s = ensure(win)
    g.fill(b.x, b.y, b.w, b.h, PANEL)
    if b.h < 8 or b.w < 40 then return end

    -- barra superior
    g.fill(b.x, b.y, b.w, 1, TOOL)
    g.fill(b.x, b.y + 1, b.w, 1, SEP)
    g.text(b.x + 2, b.y, "Loja", INK, TOOL)
    button(g, b.x + b.w - 14, b.y, 13, "Atualizar", BLUE, WHITE)

    local bottom = b.y + b.h - 2
    if not s.loaded then
      g.text(b.x + 2, b.y + 3, s.status ~= "" and s.status or "Clique em Atualizar para ver os apps.", DIM, PANEL)
    end

    -- lista de apps
    g.fill(b.x, b.y + 2, SIDE, b.h - 2, SIDEBG)
    g.fill(b.x + SIDE, b.y + 2, 1, b.h - 2, SEP)
    for i, item in ipairs(s.apps) do
      local y = b.y + 2 + (i - 1) * 2
      if y + 1 < bottom then
        local sel = (i == s.sel)
        local bg = sel and SELBG or SIDEBG
        g.fill(b.x, y, SIDE, 2, bg)
        g.text(b.x + 1, y, g.clip(item.name, SIDE - 2), INK, bg)
        local tag = isInstalled(ctx, item) and "Instalado" or ""
        g.text(b.x + 1, y + 1, tag, GREEN, bg)
      end
    end

    -- detalhes do app escolhido
    local x0 = b.x + SIDE + 2
    local w = b.w - SIDE - 3
    local item = s.apps[s.sel]
    if item then
      g.text(x0, b.y + 3, g.clip(item.name, w), INK, PANEL)
      g.text(x0, b.y + 5, g.clip(item.desc, w), DIM, PANEL)
      g.text(x0, b.y + 7, g.clip("Destino: " .. item.dest, w), DIM, PANEL)

      if isInstalled(ctx, item) then
        button(g, x0, b.y + 9, 12, "Remover", GRAY, INK)
      else
        button(g, x0, b.y + 9, 12, "Obter", BLUE, WHITE)
      end
    end

    -- rodapé com a mensagem de status
    g.fill(b.x + SIDE + 1, bottom, b.w - SIDE - 1, 1, SEP)
    g.fill(b.x + SIDE + 1, b.y + b.h - 1, b.w - SIDE - 1, 1, TOOL)
    if s.status ~= "" then
      local color = (s.status:match("^Falha") or s.status:match("^Erro") or s.status:match("^Não") or s.status:match("^Sem")) and RED or DIM
      g.text(x0, b.y + b.h - 1, g.clip(s.status, w), color, TOOL)
    end
  end,

  touch = function(win, b, x, y, ctx)
    local s = ensure(win)

    -- Atualizar
    if y == b.y and x >= b.x + b.w - 14 then
      loadCatalog(s)
      return
    end

    -- lista
    if x < b.x + SIDE and y >= b.y + 2 then
      local i = math.floor((y - (b.y + 2)) / 2) + 1
      if s.apps[i] then s.sel = i end
      return
    end

    -- botão Obter / Remover
    local item = s.apps[s.sel]
    local x0 = b.x + SIDE + 2
    if item and y == b.y + 9 and x >= x0 and x < x0 + 12 then
      if isInstalled(ctx, item) then
        remove(s, ctx, item)
      else
        install(s, ctx, item)
      end
    end
  end,
}
