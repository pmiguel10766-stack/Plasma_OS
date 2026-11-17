-- Plasma OS - /PlasmaOS/boot.lua
-- Assistente de usuário no primeiro uso, depois a área de trabalho.
-- Carrega apps, ícones, fundos e biblioteca de /PlasmaOS/.
-- Sem OpenOS. Estilo OS X Yosemite. Barra de menu com RAM e Bateria.

local BOOT_ADDR = computer.getBootAddress()
local CFG_PATH  = "/PlasmaOS/usuario.cfg"
local VERSION   = "0.6"

local gpuAddr = component.list("gpu")()
local scrAddr = component.list("screen")()
if not gpuAddr or not scrAddr then error("Plasma OS: precisa de GPU e tela.") end
local gpu = component.proxy(gpuAddr)
gpu.bind(scrAddr)
local mw, mh = gpu.maxResolution()
gpu.setResolution(mw, mh)
local w, h = gpu.getResolution()

local bootFs = component.proxy(BOOT_ADDR)

-- Paleta do sistema
local C = {
  menuBg = 0xE8E8E8, menuFg = 0x1A1A1A,
  dockBg = 0xD5DCE4, white = 0xFFFFFF,
  dark = 0x222222, sub = 0x6E6E6E, alertBg = 0xF2F2F2,
  panel = 0xFFFFFF, blue = 0x0A84FF, barBg = 0xD6D6D6, red = 0xD93025,
  close = 0xFF5F57, minim = 0xFEBC2E, zoom = 0x28C840,
  titleActive = 0xD9D9D9, titleIdle = 0xF2F2F2, dotOff = 0xC8C8C8,
  shadow = 0x59636E,
}

-- Utilidades ------------------------------------------------------------

local function tlen(s)
  if unicode and unicode.len then return unicode.len(s) end
  local ok, n = pcall(function() return utf8.len(s) end)
  if ok and n then return n end
  return #s
end

local function mix(c1, c2, t)
  local r1, g1, b1 = math.floor(c1 / 65536) % 256, math.floor(c1 / 256) % 256, c1 % 256
  local r2, g2, b2 = math.floor(c2 / 65536) % 256, math.floor(c2 / 256) % 256, c2 % 256
  local r = math.floor(r1 + (r2 - r1) * t)
  local g = math.floor(g1 + (g2 - g1) * t)
  local b = math.floor(b1 + (b2 - b1) * t)
  return r * 65536 + g * 256 + b
end

local function clockText()
  local ok, s = pcall(os.date, "%H:%M")
  if ok and s then return s end
  local t = math.floor(computer.uptime())
  return string.format("%02d:%02d", math.floor(t / 3600) % 24, math.floor(t / 60) % 60)
end

-- Textos da barra de status (do mais longo ao mais curto) e % de bateria
local function statusCandidates()
  local total = computer.totalMemory()
  local ram = 0
  if total > 0 then
    ram = math.floor((total - computer.freeMemory()) / total * 100 + 0.5)
  end
  local maxE = computer.maxEnergy()
  local bat = 100
  if maxE > 0 and maxE < math.huge then
    bat = math.floor(computer.energy() / maxE * 100 + 0.5)
  end
  local clk = clockText()
  return {
    string.format("RAM: %d%%   Bateria: %d%%   %s", ram, bat, clk),
    string.format("RAM %d%%  Bat %d%%  %s", ram, bat, clk),
    clk,
  }, bat
end

local function readFile(path)
  if not bootFs.exists(path) then return nil end
  local hnd = bootFs.open(path, "r")
  if not hnd then return nil end
  local parts = {}
  repeat
    local chunk = bootFs.read(hnd, math.huge)
    if chunk then parts[#parts + 1] = chunk end
  until not chunk
  bootFs.close(hnd)
  return table.concat(parts)
end

local function writeFile(path, data)
  local dir = path:match("^(.*)/[^/]*$")
  if dir and dir ~= "" and not bootFs.exists(dir) then bootFs.makeDirectory(dir) end
  local hnd, err = bootFs.open(path, "w")
  if not hnd then return false, err end
  bootFs.write(hnd, data)
  bootFs.close(hnd)
  return true
end

-- Carrega um módulo Lua (tabela) de um arquivo do disco
local function loadModule(path)
  local src = readFile(path)
  if not src then return nil end
  local fn, err = load(src, "=" .. path, "t")
  if not fn then return nil, err end
  local ok, res = pcall(fn)
  if ok and type(res) == "table" then return res end
  return nil, res
end

-- Hash simples (djb2). Não é segurança forte, só evita senha em texto puro.
local function hashPw(s)
  local hsh = 5381
  for i = 1, #s do hsh = (hsh * 33 + s:byte(i)) % 4294967296 end
  return string.format("%08x", hsh)
end

local function loadUser()
  local data = readFile(CFG_PATH)
  if not data then return nil end
  local name = data:match("user=([^\r\n]+)")
  if not name then return nil end
  return { name = name, hash = data:match("hash=([^\r\n]*)") or "",
           wall = tonumber(data:match("wall=(%d+)")) }
end

local function hit(list, x, y)
  for i = #list, 1, -1 do
    local b = list[i]
    if x >= b.x and x < b.x + b.w and y >= b.y and y < b.y + b.h then return b end
  end
  return nil
end

-- Auxiliar gráfico passado para os apps (fill, text, clip, len)
local G = {}
function G.fill(x, y, cw, ch, bg)
  gpu.setBackground(bg)
  gpu.fill(x, y, cw, ch, " ")
end
function G.text(x, y, s, fg, bg)
  if bg then gpu.setBackground(bg) end
  if fg then gpu.setForeground(fg) end
  gpu.set(x, y, tostring(s))
end
function G.clip(s, n)
  s = tostring(s)
  if tlen(s) <= n then return s end
  if unicode and unicode.sub then return unicode.sub(s, 1, n) end
  return s:sub(1, n)
end
G.len = tlen
G.dockBg = C.dockBg   -- os ícones usam para os cantos arredondados

-- Tela de carregamento (logo + barra fina) ------------------------------
-- Logo: Júpiter (faixas de cor, Grande Mancha Vermelha, sombra) com um "P" azul
-- 12x12 pixels = 12x6 células com meios-blocos
local ORB_P = {
  "####.",
  "#...#",
  "#...#",
  "####.",
  "#....",
  "#....",
  "#....",
}
local function drawOrb(x0, y0, bg)
  local N = 12
  local R = N / 2 - 0.2
  local cx, cy = (N - 1) / 2, (N - 1) / 2
  local CREAM, ORANGE, RED, PBLUE = 0xF2DDB8, 0xC9803F, 0xB5442E, 0x0A2F6B
  local function glyph(px, py)
    local gx, gy = px - 3, py - 2
    if gx >= 0 and gx < 5 and gy >= 0 and gy < 7 then
      return ORB_P[gy + 1]:sub(gx + 1, gx + 1) == "#"
    end
    return false
  end
  local function pix(px, py)
    local dx, dy = px - cx, py - cy
    local d = math.sqrt(dx * dx + dy * dy)
    if d > R then return nil end
    if glyph(px, py) then return PBLUE end
    local base = (math.sin(py * 1.6) > 0.15) and ORANGE or CREAM
    local sx, sy = px - 8, py - 7                       -- Grande Mancha Vermelha
    if sx * sx / 2.2 + sy * sy / 1.4 < 1 then base = RED end
    local t = d / R                                     -- sombra nas bordas
    return mix(base, 0x2A1A10, t * t * 0.55)
  end
  for cy2 = 0, N / 2 - 1 do
    for cx2 = 0, N - 1 do
      local a, b = pix(cx2, cy2 * 2), pix(cx2, cy2 * 2 + 1)
      if a or b then
        gpu.setBackground(bg)
        if a and b then
          gpu.setForeground(a); gpu.setBackground(b)
          gpu.set(x0 + cx2, y0 + cy2, "▀")
        elseif a then
          gpu.setForeground(a)
          gpu.set(x0 + cx2, y0 + cy2, "▀")
        else
          gpu.setForeground(b)
          gpu.set(x0 + cx2, y0 + cy2, "▄")
        end
      end
    end
  end
end

local SPL = { drawn = false }
local function splash(frac, msg)
  local SW, SH = w, h
  local BG = 0xF2F2F2
  local N = 12
  local x0 = math.floor((SW - N) / 2) + 1
  local y0 = math.max(2, math.floor(SH / 2) - 6)
  if not SPL.drawn then
    SPL.drawn = true
    gpu.setBackground(BG)
    gpu.fill(1, 1, SW, SH, " ")
    drawOrb(x0, y0, BG)
    local title = "Plasma OS"
    gpu.setBackground(BG)
    gpu.setForeground(0x1A1A1A)
    gpu.set(math.floor((SW - tlen(title)) / 2) + 1, y0 + 8, title)
  end

  -- barra fina de progresso
  local BW = 24
  local bx = math.floor((SW - BW) / 2) + 1
  gpu.setBackground(BG)
  gpu.setForeground(0xD0D0D0)
  gpu.set(bx, y0 + 10, string.rep("▄", BW))
  local filled = math.floor(BW * math.max(0, math.min(1, frac)))
  if filled > 0 then
    gpu.setForeground(0x555555)
    gpu.set(bx, y0 + 10, string.rep("▄", filled))
  end
  if msg then
    gpu.setBackground(BG)
    gpu.fill(1, y0 + 12, SW, 1, " ")
    gpu.setForeground(0x8A8A8A)
    gpu.set(math.floor((SW - tlen(msg)) / 2) + 1, y0 + 12, msg)
  end
end

-- Biblioteca de trechos, fundos, apps e ícones -------------------------

-- Apps conhecidos ficam nesta ordem no dock; os outros arquivos de /PlasmaOS/apps/ entram depois
local APP_ORDER = {
  "finder", "safari", "calendario", "notas", "fotos",
  "mensagens", "ajustes", "lixeira", "editor-lua", "rede-local",
}

local function discoverApps()
  local found, seen = {}, {}
  for _, n in ipairs(APP_ORDER) do
    found[#found + 1] = n
    seen[n] = true
  end
  local ok, t = pcall(bootFs.list, "/PlasmaOS/apps/")
  if ok and type(t) == "table" then
    local extra = {}
    for _, name in ipairs(t) do
      local base = name:match("^(.-)%.lua$")
      if base and not seen[base] then
        extra[#extra + 1] = base
        seen[base] = true
      end
    end
    table.sort(extra)
    for _, n in ipairs(extra) do found[#found + 1] = n end
  end
  return found
end

local APP_FILES = discoverApps()
local FUNDO_FILES = { "padrao", "montanha" }
local LOAD_TOTAL = 1 + #FUNDO_FILES + #APP_FILES
local loadStep = 0
local function loading(msg)
  splash(loadStep / LOAD_TOTAL, msg)
end
loading("Iniciando...")

loading("Carregando biblioteca...")
local TRECHOS = loadModule("/PlasmaOS/biblioteca/trechos.lua") or {}
loadStep = loadStep + 1

local DEFAULT_WALL = {
  name = "Montanha", sky1 = 0x4A90D9, sky2 = 0xCFE3F5,
  ground = 0x2D4A2B,
}
local WALLPAPERS = {}
for _, f in ipairs(FUNDO_FILES) do
  loading("Carregando fundo " .. f .. "...")
  local wp = loadModule("/PlasmaOS/fundos/" .. f .. ".lua")
  if wp then WALLPAPERS[#WALLPAPERS + 1] = wp end
  loadStep = loadStep + 1
end
if #WALLPAPERS == 0 then WALLPAPERS[1] = DEFAULT_WALL end
local wallIdx = 1

local apps = {}
for _, f in ipairs(APP_FILES) do
  loading("Carregando " .. f .. "...")
  local app = loadModule("/PlasmaOS/apps/" .. f .. ".lua")
  if app then
    app.file = f
    app.name = app.name or f:gsub("^%l", string.upper)
    app.icon = loadModule("/PlasmaOS/icones/" .. f .. ".lua")  -- pode ser nil
    apps[#apps + 1] = app
  end
  loadStep = loadStep + 1
end
splash(1, "Pronto.")
computer.pullSignal(0.4)

-- Contexto entregue aos apps (preenchido em main)
local CTX = {}

-- Estado ----------------------------------------------------------------

local windows   = {}   -- último = topo
local dragging  = nil  -- { win, dx, dy }
local resizing  = nil  -- janela sendo redimensionada
local cascade   = 0
local running   = true
local openMenu  = nil  -- menu suspenso aberto
local dockLabel = nil  -- { idx, untilT }
local MIN_W, MIN_H = 24, 6
local dockY, dockW, dockX0 = h - 3, 2, 1

local function layoutDock()
  dockY  = h - 3
  dockW  = #apps * 6 + 2
  dockX0 = math.floor((w - dockW) / 2)
end

-- Assistente de usuário (estilo Assistente de Configuração do OS X) -----

local setupBackdrop = function() end   -- definido mais abaixo (fundo + barra de menu)

local setup = { step = "welcome", name = "", pw = "", pw2 = "", err = nil }
local sbtns = {}

local function ctext(px, pw_, y, s, fg)
  gpu.setBackground(C.panel)
  gpu.setForeground(fg or C.dark)
  gpu.set(px + math.floor((pw_ - tlen(s)) / 2), y, s)
end

local function sbutton(x, y, label, primary, action, bw)
  bw = bw or (tlen(label) + 6)
  gpu.setBackground(primary and C.blue or C.barBg)
  gpu.setForeground(primary and C.white or C.dark)
  gpu.fill(x, y, bw, 3, " ")
  gpu.set(x + math.floor((bw - tlen(label)) / 2), y + 1, label)
  table.insert(sbtns, { x = x, y = y, w = bw, h = 3, action = action })
end

local function field(x, y, fw, text, masked)
  local shown = masked and string.rep("*", tlen(text)) or text
  if tlen(shown) > fw - 3 then shown = shown:sub(-(fw - 3)) end
  gpu.setBackground(C.barBg)
  gpu.setForeground(C.dark)
  gpu.fill(x, y, fw, 3, " ")
  gpu.set(x + 2, y + 1, shown .. "_")
end

-- Etapas (a de fundo só existe se houver mais de um fundo)
local function stepList()
  local list = { "welcome", "name", "pass", "pass2" }
  if #WALLPAPERS > 1 then list[#list + 1] = "wall" end
  return list
end

local function stepWall(d)
  wallIdx = (wallIdx - 1 + d) % #WALLPAPERS + 1
end

local function submitName()
  local n = setup.name:match("^%s*(.-)%s*$")
  if n == "" then setup.err = "Digite um nome."; return end
  setup.name = n
  setup.err = nil
  setup.step = "pass"
end

local function finishSetup()
  local hsh = setup.pw ~= "" and hashPw(setup.pw) or ""
  local ok, err = writeFile(CFG_PATH,
    "user=" .. setup.name .. "\nhash=" .. hsh .. "\nwall=" .. wallIdx .. "\n")
  if not ok then
    setup.err = "Erro ao salvar: " .. tostring(err)
    local list = stepList()
    setup.step = list[#list]
    return
  end
  setup.hash = hsh
  setup.err = nil
  setup.step = "done"
  setup.doneAt = computer.uptime() + 3
end

local function submitPass2()
  if setup.pw2 ~= setup.pw then
    setup.err = "As senhas não coincidem."
    setup.pw2 = ""
    return
  end
  setup.err = nil
  if #WALLPAPERS > 1 then setup.step = "wall" else finishSetup() end
end

local function drawSetup()
  sbtns = {}
  setupBackdrop()

  local showOrb = h >= 28                  -- telas baixas: sem a esfera
  local top = showOrb and 8 or 1
  local pw_ = math.min(60, w - 2)
  local ph_ = top + 14
  local px = math.floor((w - pw_) / 2) + 1
  local py = math.max(2, math.floor((h - ph_) / 2) + 1)
  local T = py + top

  gpu.setBackground(C.shadow)              -- sombra
  gpu.fill(px + 2, py + ph_, pw_, 1, " ")
  gpu.fill(px + pw_, py + 1, 2, ph_, " ")
  gpu.setBackground(C.panel)               -- painel
  gpu.fill(px, py, pw_, ph_, " ")
  if showOrb then drawOrb(px + math.floor((pw_ - 12) / 2), py + 1, C.panel) end

  local s = setup
  local by = py + ph_ - 4
  local nextX = px + pw_ - 20

  -- bolinhas de progresso
  if s.step ~= "done" then
    local list = stepList()
    local x0 = px + math.floor((pw_ - (#list * 2 - 1)) / 2)
    for i, name in ipairs(list) do
      local cur = (name == s.step)
      gpu.setBackground(C.panel)
      gpu.setForeground(cur and C.blue or 0xB8B8B8)
      gpu.set(x0 + (i - 1) * 2, py + top, cur and "●" or "○")
    end
  end

  if s.step == "welcome" then
    ctext(px, pw_, T + 2, "Bem-vindo(a) ao Plasma OS")
    ctext(px, pw_, T + 3, "Vamos criar o seu usuário. Leva um minuto.", C.sub)
    sbutton(nextX, by, "Continuar", true, function() setup.step = "name" end, 16)

  elseif s.step == "name" then
    ctext(px, pw_, T + 2, "Nome do usuário")
    ctext(px, pw_, T + 3, "Como você quer ser chamado?", C.sub)
    field(px + 4, T + 5, pw_ - 8, s.name, false)
    if s.err then ctext(px, pw_, T + 9, s.err, C.red) end
    sbutton(px + 3, by, "Voltar", false, function() setup.step = "welcome"; setup.err = nil end, 12)
    sbutton(nextX, by, "Continuar", true, submitName, 16)

  elseif s.step == "pass" then
    ctext(px, pw_, T + 2, "Senha")
    ctext(px, pw_, T + 3, "Deixe em branco para não usar senha.", C.sub)
    field(px + 4, T + 5, pw_ - 8, s.pw, true)
    sbutton(px + 3, by, "Voltar", false, function() setup.step = "name"; setup.err = nil end, 12)
    sbutton(nextX, by, "Continuar", true, function()
      setup.step = "pass2"; setup.pw2 = ""; setup.err = nil
    end, 16)

  elseif s.step == "pass2" then
    ctext(px, pw_, T + 2, "Confirmar senha")
    ctext(px, pw_, T + 3, "Digite a senha novamente.", C.sub)
    field(px + 4, T + 5, pw_ - 8, s.pw2, true)
    if s.err then ctext(px, pw_, T + 9, s.err, C.red) end
    sbutton(px + 3, by, "Voltar", false, function() setup.step = "pass"; setup.err = nil end, 12)
    sbutton(nextX, by, (#WALLPAPERS > 1) and "Continuar" or "Concluir", true, submitPass2, 16)

  elseif s.step == "wall" then
    local wp = WALLPAPERS[wallIdx] or {}
    ctext(px, pw_, T + 2, "Fundo de tela")
    ctext(px, pw_, T + 3, "Escolha o visual da área de trabalho (← →).", C.sub)
    sbutton(px + 6, T + 5, "<", false, function() stepWall(-1) end, 7)
    sbutton(px + pw_ - 13, T + 5, ">", false, function() stepWall(1) end, 7)
    ctext(px, pw_, T + 6, wp.name or ("Fundo " .. wallIdx))
    ctext(px, pw_, T + 7, wallIdx .. " / " .. #WALLPAPERS, C.sub)
    if s.err then ctext(px, pw_, T + 9, s.err, C.red) end
    sbutton(px + 3, by, "Voltar", false, function() setup.step = "pass2"; setup.err = nil end, 12)
    sbutton(nextX, by, "Concluir", true, finishSetup, 16)

  elseif s.step == "done" then
    local left = math.max(0, math.ceil(s.doneAt - computer.uptime()))
    ctext(px, pw_, T + 3, "Tudo pronto, " .. s.name .. "!")
    ctext(px, pw_, T + 5, "O Plasma OS abre em " .. left .. " segundos.", C.sub)
  end
end

local function setupKey(ch, code)
  local s = setup
  if code == 28 or code == 156 then            -- Enter
    if s.step == "welcome" then s.step = "name"
    elseif s.step == "name" then submitName()
    elseif s.step == "pass" then s.step = "pass2"; s.pw2 = ""; s.err = nil
    elseif s.step == "pass2" then submitPass2()
    elseif s.step == "wall" then finishSetup() end
    return
  end
  if s.step == "wall" then                     -- setas trocam o fundo
    if code == 203 then stepWall(-1) elseif code == 205 then stepWall(1) end
    return
  end
  if code == 14 then                           -- Backspace
    if s.step == "name" then s.name = s.name:sub(1, -2)
    elseif s.step == "pass" then s.pw = s.pw:sub(1, -2)
    elseif s.step == "pass2" then s.pw2 = s.pw2:sub(1, -2) end
    return
  end
  if ch and ch >= 32 and ch < 127 then
    local c = string.char(ch)
    if s.step == "name" and tlen(s.name) < 24 then s.name = s.name .. c
    elseif s.step == "pass" and #s.pw < 32 then s.pw = s.pw .. c
    elseif s.step == "pass2" and #s.pw2 < 32 then s.pw2 = s.pw2 .. c end
  end
end

local function runSetup()
  local dirty, lastDraw = true, 0
  while true do
    -- só redesenha quando algo muda (a esfera custa várias chamadas de GPU)
    if dirty or setup.step == "done" or computer.uptime() - lastDraw > 5 then
      drawSetup()
      dirty = false
      lastDraw = computer.uptime()
    end
    if setup.step == "done" and computer.uptime() >= setup.doneAt then
      return { name = setup.name, hash = setup.hash, wall = wallIdx }
    end
    local sig, _, a, b = computer.pullSignal(0.5)
    if sig == "touch" then
      local btn = hit(sbtns, a, b)
      if btn then btn.action() end
      dirty = true
    elseif sig == "key_down" then
      setupKey(a, b)
      dirty = true
    end
  end
end

-- Janelas ---------------------------------------------------------------

local function topWindow()
  for i = #windows, 1, -1 do
    if not windows[i].minimized then return windows[i] end
  end
  return nil
end

local function bringToFront(win)
  for i, v in ipairs(windows) do
    if v == win then table.remove(windows, i); break end
  end
  table.insert(windows, win)
end

local function closeWindow(win)
  for i, v in ipairs(windows) do
    if v == win then table.remove(windows, i); return end
  end
end

local function clampPos(win)
  local maxX = math.max(1, w - win.w + 1)
  local maxY = math.max(2, dockY - 1)
  win.x = math.min(math.max(win.x, 1), maxX)
  win.y = math.min(math.max(win.y, 2), maxY)
end

local function toggleMax(win)
  if win.maxed then
    win.x, win.y, win.w, win.h = win.saved.x, win.saved.y, win.saved.w, win.saved.h
    win.maxed = false
  else
    win.saved = { x = win.x, y = win.y, w = win.w, h = win.h }
    win.x, win.y = 1, 2
    win.w, win.h = w, dockY - 2
    win.maxed = true
  end
end

local function bodyOf(win)
  return { x = win.x, y = win.y + 1, w = win.w, h = win.h - 1 }
end

local function openWindow(app)
  for _, win in ipairs(windows) do
    if win.app == app then
      win.minimized = false
      bringToFront(win)
      return
    end
  end
  cascade = (cascade % 5) + 1
  local win = {
    app = app, x = 8 + cascade * 3, y = 4 + cascade * 2,
    w = 46, h = 16, minimized = false, maxed = false,
  }
  clampPos(win)
  if app.init then pcall(app.init, win, CTX) end
  table.insert(windows, win)
end

local function windowAt(x, y)
  for i = #windows, 1, -1 do
    local win = windows[i]
    if not win.minimized
      and x >= win.x and x < win.x + win.w
      and y >= win.y and y < win.y + win.h then
      return win
    end
  end
  return nil
end

local function drawWindow(win, active)
  local x, y = win.x, win.y

  -- sombra (embaixo e à direita)
  gpu.setBackground(C.shadow)
  gpu.fill(x + 2, y + win.h, win.w, 1, " ")
  gpu.fill(x + win.w, y + 1, 2, win.h, " ")

  -- barra de título com semáforo redondo (cinza quando inativa)
  local bar = active and C.titleActive or C.titleIdle
  gpu.setBackground(bar)
  gpu.fill(x, y, win.w, 1, " ")
  gpu.setForeground(active and C.close or C.dotOff); gpu.set(x + 2, y, "●")
  gpu.setForeground(active and C.minim or C.dotOff); gpu.set(x + 4, y, "●")
  gpu.setForeground(active and C.zoom  or C.dotOff); gpu.set(x + 6, y, "●")
  gpu.setForeground(active and C.menuFg or C.sub)
  local title = win.app.name or "App"
  gpu.set(x + math.floor((win.w - tlen(title)) / 2), y, title)

  -- corpo: o próprio app desenha dentro dele
  local b = bodyOf(win)
  gpu.setBackground(C.alertBg)
  gpu.fill(b.x, b.y, b.w, b.h, " ")
  if win.app.draw then
    local ok, err = pcall(win.app.draw, win, b, G, CTX)
    if not ok then
      gpu.setBackground(C.alertBg)
      gpu.setForeground(C.red)
      gpu.set(b.x + 1, b.y, G.clip("Erro no app: " .. tostring(err), b.w - 2))
    end
  end

  -- alça de redimensionar no canto inferior direito
  gpu.setBackground(C.alertBg)
  gpu.setForeground(C.sub)
  gpu.set(x + win.w - 1, y + win.h - 1, "/")
end

-- Barra de menu e menus suspensos ---------------------------------------

local menuBar = {}

-- Reconstrói a barra: "●", nome do app ativo, e os menus fixos
local function rebuildMenuBar()
  local t = topWindow()
  local titles = {
    "●", (t and t.app.name) or "Plasma",
    "Arquivo", "Editar", "Visualizar", "Janela", "Ajuda",
  }
  menuBar = {}
  local x = 2
  for _, name in ipairs(titles) do
    local l = tlen(name)
    menuBar[#menuBar + 1] = { name = name, x1 = x, x2 = x + l - 1 }
    x = x + l + 3
  end
end

local function dropdownRect()
  if not openMenu then return nil end
  local maxl = 0
  for _, it in ipairs(openMenu.items) do
    if tlen(it[1]) > maxl then maxl = tlen(it[1]) end
  end
  local bw = maxl + 4
  local x = openMenu.x
  if x + bw - 1 > w then x = w - bw + 1 end
  return x, 2, bw, #openMenu.items
end

local function drawDropdown()
  local x, y, bw, n = dropdownRect()
  if not x then return end
  gpu.setBackground(C.shadow)
  gpu.fill(x + 1, y + n, bw, 1, " ")
  gpu.fill(x + bw, y + 1, 1, n, " ")
  gpu.setBackground(C.panel)
  gpu.fill(x, y, bw, n, " ")
  for i, it in ipairs(openMenu.items) do
    gpu.setBackground(C.panel)
    gpu.setForeground(it[2] and C.dark or C.sub)
    gpu.set(x + 2, y + i - 1, it[1])
  end
end

local function drawMenu(minimal)
  gpu.setBackground(C.menuBg)
  gpu.setForeground(C.menuFg)
  gpu.fill(1, 1, w, 1, " ")
  if minimal then                       -- assistente: só o "●" e o status
    gpu.set(2, 1, "●")
  else
    for _, m in ipairs(menuBar) do
      if openMenu and openMenu.name == m.name then
        gpu.setBackground(C.blue); gpu.setForeground(C.white)
      else
        gpu.setBackground(C.menuBg); gpu.setForeground(C.menuFg)
      end
      gpu.set(m.x1, 1, m.name)
    end
  end

  -- RAM, bateria e hora à direita (usa a versão que couber)
  local last = (not minimal) and menuBar[#menuBar] or nil
  local limit = last and (last.x2 + 2) or 4
  local cands, bat = statusCandidates()
  for _, s in ipairs(cands) do
    local sx = w - tlen(s)
    if sx > limit then
      gpu.setBackground(C.menuBg)
      gpu.setForeground(bat <= 15 and C.red or C.menuFg)
      gpu.set(sx, 1, s)
      break
    end
  end
end

-- Dock -----------------------------------------------------------------

local function isOpen(app)
  for _, win in ipairs(windows) do
    if win.app == app then return true end
  end
  return false
end

local dockBuf, dockTried = nil, false
local dockKey = nil

-- Junta as chaves dos ícones: quando alguma muda (ex.: o dia), o dock é refeito
local function iconKey()
  local parts = {}
  for _, app in ipairs(apps) do
    if app.icon and app.icon.key then
      local ok, k = pcall(app.icon.key)
      parts[#parts + 1] = ok and tostring(k) or "?"
    end
  end
  return table.concat(parts, "|")
end

-- Desenha a base do dock com a origem em (ox, oy): tela ou buffer
local function paintDock(ox, oy)
  gpu.setBackground(C.dockBg)
  gpu.fill(ox, oy, dockW, 3, " ")
  for i, app in ipairs(apps) do
    local x = ox + 1 + (i - 1) * 6
    if app.icon and app.icon.draw then
      pcall(app.icon.draw, G, x, oy)
    else
      gpu.setBackground(app.color or 0x7F8C8D)
      gpu.fill(x, oy, 5, 2, " ")
      gpu.setForeground(C.white)
      gpu.set(x + 2, oy, app.letter or "?")
    end
  end
end

local function drawDock()
  local key = iconKey()
  if key ~= dockKey and dockBuf then
    pcall(gpu.freeBuffer, dockBuf)
    dockBuf, dockTried = nil, false
  end
  dockKey = key

  -- na primeira vez, tenta guardar o dock num buffer de vídeo
  if not dockTried then
    dockTried = true
    if gpu.allocateBuffer then
      local ok, id = pcall(gpu.allocateBuffer, dockW, 3)
      if ok and id then
        local drew = pcall(function()
          gpu.setActiveBuffer(id)
          paintDock(1, 1)
          gpu.setActiveBuffer(0)
        end)
        if drew then
          dockBuf = id
        else
          pcall(gpu.setActiveBuffer, 0)
          pcall(gpu.freeBuffer, id)
        end
      end
    end
  end

  local blitted = false
  if dockBuf then
    local ok, res = pcall(gpu.bitblt, 0, dockX0, dockY, dockW, 3, dockBuf, 1, 1)
    blitted = ok and res ~= false
    if not blitted then dockBuf = nil end
  end
  if not blitted then paintDock(dockX0, dockY) end

  -- ponto embaixo dos apps abertos (muda toda hora, fica fora do buffer)
  gpu.setBackground(C.dockBg)
  gpu.setForeground(C.dark)
  for i, app in ipairs(apps) do
    if isOpen(app) then
      gpu.set(dockX0 + 1 + (i - 1) * 6 + 2, dockY + 2, "●")
    end
  end
end

local function drawDockLabel()
  if not dockLabel or not apps[dockLabel.idx] then return end
  local text = " " .. tostring(apps[dockLabel.idx].name or "App") .. " "
  local tl = tlen(text)
  local cx = dockX0 + 1 + (dockLabel.idx - 1) * 6 + 2
  local x = math.max(1, math.min(w - tl + 1, cx - math.floor(tl / 2)))
  gpu.setBackground(C.menuBg)
  gpu.setForeground(C.menuFg)
  gpu.set(x, dockY - 1, text)
end

-- Fundo estilo Yosemite (céu, serras, Half Dome, chão e pinheiros) ----------
-- Montado uma vez em retângulos. Se a GPU tiver buffer de vídeo, o fundo
-- inteiro é copiado com um único bitblt a cada redesenho.

local scene, trees, groundColor = {}, {}, 0x2D4A2B
local sceneIdx, wallBuf = 0, nil

local function buildScene()
  local p = WALLPAPERS[wallIdx]
  local sky1   = p.sky1   or DEFAULT_WALL.sky1
  local sky2   = p.sky2   or DEFAULT_WALL.sky2
  local ground = p.ground or DEFAULT_WALL.ground
  local lit    = p.dome   or 0xA8A29B   -- lado iluminado do Half Dome
  local shade  = p.shade  or 0x6F6A66   -- lado em sombra
  groundColor = ground

  scene = {}
  local gy = math.floor(h * 0.72)

  local function add(x, y, rw, rh, c)
    if rw > 0 and rh > 0 then
      scene[#scene + 1] = { x = x, y = y, w = rw, h = rh, c = c }
    end
  end

  -- céu em faixas (azul em cima, claro no horizonte)
  local rows = math.max(1, gy - 2)
  local bands = math.min(24, rows)
  for b = 0, bands - 1 do
    local y1 = 2 + math.floor(b * rows / bands)
    local y2 = 2 + math.floor((b + 1) * rows / bands) - 1
    add(1, y1, w, y2 - y1 + 1, mix(sky1, sky2, (b + 0.5) / bands))
  end

  -- serra: junta colunas vizinhas de mesma altura em um só retângulo
  local function ridge(colour, base, amp, f1, f2, ph)
    local sx, prev = 1, nil
    for x = 1, w + 1 do
      local hg
      if x <= w then
        hg = math.max(1, math.floor(base + amp * math.sin(x / f1 + ph)
          + amp / 2 * math.sin(x / f2)))
      end
      if hg ~= prev then
        if prev then add(sx, gy - prev, x - sx, prev, colour) end
        sx, prev = x, hg
      end
    end
  end

  ridge(mix(sky2, ground, 0.25), h * 0.18, h * 0.05, 11, 4, 0)

  -- Half Dome: face esquerda íngreme (sombra), lado direito arredondado
  local cx = math.floor(w * 0.70)
  local cw = math.max(8, math.floor(w * 0.20))
  local dh = math.floor(h * 0.42)
  local sx, ph, pc = 1, 0, lit
  for x = cx - cw, cx + cw + 1 do
    local hg, col = 0, lit
    if x >= 1 and x <= w and x <= cx + cw then
      local t = (x - cx) / cw
      if t < 0 then
        hg = math.floor(dh * math.sqrt(math.max(0, 1 - (t * 3) ^ 2)))
        col = shade
      else
        hg = math.floor(dh * math.sqrt(math.max(0, 1 - t * t)))
        col = (t < 0.15) and shade or lit
      end
    end
    if hg ~= ph or col ~= pc then
      if ph > 0 then add(sx, gy - ph, x - sx, ph, pc) end
      sx, ph, pc = x, hg, col
    end
  end

  ridge(mix(sky2, ground, 0.55), h * 0.10, h * 0.03, 7, 3, 2)

  -- chão
  add(1, gy, w, h - gy + 1, ground)

  -- pinheiros: duas linhas de texto prontas
  trees = {}
  for r = 0, 1 do
    local cells = {}
    for x = 1, w do
      cells[x] = (math.random() < 0.38) and "▲" or " "
    end
    trees[#trees + 1] = {
      y = gy + r, s = table.concat(cells),
      fg = mix(ground, 0x000000, r == 0 and 0.35 or 0.2),
    }
  end
end

local function paintScene()
  for _, r in ipairs(scene) do
    gpu.setBackground(r.c)
    gpu.fill(r.x, r.y, r.w, r.h, " ")
  end
  gpu.setBackground(groundColor)
  for _, tr in ipairs(trees) do
    gpu.setForeground(tr.fg)
    gpu.set(1, tr.y, tr.s)
  end
end

local function ensureScene()
  if sceneIdx == wallIdx then return end
  sceneIdx = wallIdx
  buildScene()
  if wallBuf then
    pcall(gpu.freeBuffer, wallBuf)
    wallBuf = nil
  end
  if gpu.allocateBuffer then
    local ok, id = pcall(gpu.allocateBuffer, w, h)
    if ok and id then
      local drew = pcall(function()
        gpu.setActiveBuffer(id)
        paintScene()
        gpu.setActiveBuffer(0)
      end)
      if drew then
        wallBuf = id
      else
        pcall(gpu.setActiveBuffer, 0)
        pcall(gpu.freeBuffer, id)
      end
    end
  end
end

local function drawWallpaper()
  if wallBuf then
    local ok, res = pcall(gpu.bitblt, 0, 1, 1, w, h, wallBuf, 1, 1)
    if ok and res ~= false then return end
    wallBuf = nil
  end
  paintScene()
end

setupBackdrop = function()
  ensureScene()
  drawWallpaper()
  drawMenu(true)
end

local function redraw()
  rebuildMenuBar()
  ensureScene()
  drawWallpaper()

  local active = topWindow()
  for _, win in ipairs(windows) do
    if not win.minimized then drawWindow(win, win == active) end
  end
  drawDock()
  drawDockLabel()
  drawMenu()
  drawDropdown()
end

-- Ações de menu --------------------------------------------------------

local function closeTop()
  local t = topWindow()
  if t then closeWindow(t) end
end

local function closeAll()
  for i = #windows, 1, -1 do windows[i] = nil end
end

local function minimizeTop()
  local t = topWindow()
  if t then t.minimized = true end
end

local function restoreAll()
  for _, win in ipairs(windows) do win.minimized = false end
end

local function zoomTop()
  local t = topWindow()
  if t then toggleMax(t) end
end

local function nextWallpaper()
  wallIdx = wallIdx % #WALLPAPERS + 1
end

local function quit()
  running = false
end

local MENU_ITEMS = {
  ["●"]          = { { "Sair do Plasma (Q)", quit } },
  ["Arquivo"]    = { { "Fechar janela", closeTop }, { "Fechar todas", closeAll } },
  ["Editar"]     = { { "Desfazer (em breve)" } },
  ["Visualizar"] = { { "Trocar fundo", nextWallpaper } },
  ["Janela"]     = { { "Minimizar", minimizeTop }, { "Restaurar todas", restoreAll },
                     { "Maximizar / Restaurar", zoomTop } },
  ["Ajuda"]      = { { "Sobre o Plasma OS " .. VERSION } },
}

-- Eventos da área de trabalho ------------------------------------------

local function handleTouch(x, y)
  -- menu suspenso aberto: clique dentro executa, fora fecha
  if openMenu then
    local dx, dy, bw, n = dropdownRect()
    if x >= dx and x < dx + bw and y >= dy and y < dy + n then
      local item = openMenu.items[y - dy + 1]
      openMenu = nil
      if item and item[2] then item[2]() end
      return
    end
    openMenu = nil
  end

  -- barra de menu
  if y == 1 then
    for _, m in ipairs(menuBar) do
      if x >= m.x1 and x <= m.x2 then
        if openMenu and openMenu.name == m.name then
          openMenu = nil
        elseif MENU_ITEMS[m.name] then
          openMenu = { name = m.name, x = m.x1, items = MENU_ITEMS[m.name] }
        end
        return
      end
    end
    return
  end

  -- dock
  if y >= dockY and y <= dockY + 2 then
    local rel = x - dockX0 - 1
    if rel >= 0 then
      local idx = math.floor(rel / 6) + 1
      if idx <= #apps and rel % 6 < 5 then
        openWindow(apps[idx])
        dockLabel = { idx = idx, untilT = computer.uptime() + 2.5 }
      end
    end
    return
  end

  -- janelas
  local win = windowAt(x, y)
  if not win then return end
  bringToFront(win)

  if y == win.y then
    if x == win.x + 2 then closeWindow(win); return
    elseif x == win.x + 4 then win.minimized = true; return
    elseif x == win.x + 6 then toggleMax(win); return
    end
    dragging = { win = win, dx = x - win.x, dy = y - win.y }
  elseif x == win.x + win.w - 1 and y == win.y + win.h - 1 then
    resizing = win
  elseif win.app.touch then
    pcall(win.app.touch, win, bodyOf(win), x, y, CTX)
  end
end

local function handleDrag(x, y)
  if dragging then
    local win = dragging.win
    win.x = x - dragging.dx
    win.y = y - dragging.dy
    clampPos(win)
    win.maxed = false
  elseif resizing then
    local win = resizing
    win.maxed = false
    win.w = math.max(MIN_W, x - win.x + 1)
    win.h = math.max(MIN_H, y - win.y + 1)
    win.w = math.min(win.w, w - win.x + 1)
    win.h = math.min(win.h, dockY - win.y)
    win.h = math.max(win.h, MIN_H)
  end
end

-- Teclado: vai para a janela da frente. Q sai só se ela não usa teclado.
local function handleKey(ch, code)
  local top = topWindow()
  if top and top.app.key then
    pcall(top.app.key, top, ch, code, CTX)
    return
  end
  if ch == 113 or ch == 81 then running = false end
end

local function desktop()
  pcall(redraw)
  while running do
    local sig, _, a, b = computer.pullSignal(1)
    if sig == "touch" then
      pcall(handleTouch, a, b)
    elseif sig == "drag" then
      pcall(handleDrag, a, b)
    elseif sig == "drop" then
      dragging = nil
      resizing = nil
    elseif sig == "key_down" then
      pcall(handleKey, a, b)
    end
    if dockLabel and computer.uptime() > dockLabel.untilT then dockLabel = nil end
    pcall(redraw)
  end

  if wallBuf then pcall(gpu.freeBuffer, wallBuf) end
  if dockBuf then pcall(gpu.freeBuffer, dockBuf) end
  gpu.setBackground(0x000000)
  gpu.setForeground(0xFFFFFF)
  gpu.fill(1, 1, w, h, " ")
  gpu.set(1, 1, "Plasma OS encerrado. Reinicie para voltar.")
end

-- Início ---------------------------------------------------------------

local function main()
  local user = loadUser()
  if not user then
    user = runSetup()
  end

  if user.wall and WALLPAPERS[user.wall] then wallIdx = user.wall end

  CTX.fs            = bootFs
  CTX.user          = user.name
  CTX.version       = VERSION
  CTX.nextWallpaper = nextWallpaper
  CTX.trechos       = TRECHOS
  CTX.G             = G

  layoutDock()
  desktop()
end

main()
