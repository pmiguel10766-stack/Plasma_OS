-- Plasma OS - /PlasmaOS/boot.lua
-- Assistente de usuário no primeiro uso, depois a área de trabalho.
-- Carrega apps, ícones, fundos e biblioteca de /PlasmaOS/.
-- Sem OpenOS. Lua 5.2 (sem operadores de bits).

local BOOT_ADDR = computer.getBootAddress()
local CFG_PATH  = "/PlasmaOS/usuario.cfg"
local VERSION   = "0.5"

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
  dockBg = 0x9AA6B2, white = 0xFFFFFF,
  dark = 0x222222, sub = 0x6E6E6E, alertBg = 0xF2F2F2,
  panel = 0xFFFFFF, blue = 0x0A84FF, barBg = 0xD6D6D6, red = 0xD93025,
  close = 0xFF5F57, minim = 0xFEBC2E, zoom = 0x28C840,
  titleActive = 0xBDBDBD, titleIdle = 0xF2F2F2,
}

-- Utilidades ------------------------------------------------------------

local function tlen(s)
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
  return { name = name, hash = data:match("hash=([^\r\n]*)") or "" }
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
  return s:sub(1, n)
end
G.len = tlen

-- Biblioteca de trechos, fundos, apps e ícones -------------------------

local TRECHOS = loadModule("/PlasmaOS/biblioteca/trechos.lua") or {}

local DEFAULT_WALL = {
  name = "Montanha", sky1 = 0x5B7A99, sky2 = 0xC9D6E2,
  rock = 0xC0643A, ground = 0x2F4A3B, rockX = 0.08, rockW = 0.30, rockH = 0.35,
}
local WALLPAPERS = {}
for _, f in ipairs({ "padrao", "montanha" }) do
  local wp = loadModule("/PlasmaOS/fundos/" .. f .. ".lua")
  if wp then WALLPAPERS[#WALLPAPERS + 1] = wp end
end
if #WALLPAPERS == 0 then WALLPAPERS[1] = DEFAULT_WALL end
local wallIdx = 1

local APP_FILES = {
  "finder", "safari", "calendario", "notas", "fotos",
  "mensagens", "ajustes", "lixeira", "editor-lua", "rede-local",
}
local apps = {}
for _, f in ipairs(APP_FILES) do
  local app = loadModule("/PlasmaOS/apps/" .. f .. ".lua")
  if app then
    app.file = f
    app.icon = loadModule("/PlasmaOS/icones/" .. f .. ".lua")  -- pode ser nil
    apps[#apps + 1] = app
  end
end

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

-- Assistente de usuário -------------------------------------------------

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

local function submitName()
  local n = setup.name:match("^%s*(.-)%s*$")
  if n == "" then setup.err = "Digite um nome."; return end
  setup.name = n
  setup.err = nil
  setup.step = "pass"
end

local function finishSetup()
  local hsh = setup.pw ~= "" and hashPw(setup.pw) or ""
  local ok, err = writeFile(CFG_PATH, "user=" .. setup.name .. "\nhash=" .. hsh .. "\n")
  if not ok then
    setup.err = "Erro ao salvar: " .. tostring(err)
    setup.step = "pass2"
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
  finishSetup()
end

local function drawSetup()
  sbtns = {}
  local p = WALLPAPERS[wallIdx]
  gpu.setBackground(p.sky2)
  gpu.fill(1, 1, w, h, " ")
  local pw_, ph_ = 56, 14
  local px = math.floor((w - pw_) / 2) + 1
  local py = math.floor((h - ph_) / 2) + 1
  gpu.setBackground(C.panel)
  gpu.fill(px, py, pw_, ph_, " ")

  local s = setup
  local by = py + ph_ - 5
  local nextX = px + pw_ - 20

  if s.step == "welcome" then
    ctext(px, pw_, py + 3, "Bem-vindo(a) ao Plasma OS")
    ctext(px, pw_, py + 5, "Vamos criar o seu usuário. Leva um minuto.", C.sub)
    sbutton(nextX, by, "Continuar", true, function() setup.step = "name" end, 16)

  elseif s.step == "name" then
    ctext(px, pw_, py + 2, "Nome do usuário")
    ctext(px, pw_, py + 4, "Como você quer ser chamado?", C.sub)
    field(px + 4, py + 6, pw_ - 8, s.name, false)
    if s.err then ctext(px, pw_, py + 10, s.err, C.red) end
    sbutton(px + 3, by, "Voltar", false, function() setup.step = "welcome"; setup.err = nil end, 12)
    sbutton(nextX, by, "Continuar", true, submitName, 16)

  elseif s.step == "pass" then
    ctext(px, pw_, py + 2, "Senha")
    ctext(px, pw_, py + 4, "Deixe em branco para não usar senha.", C.sub)
    field(px + 4, py + 6, pw_ - 8, s.pw, true)
    sbutton(px + 3, by, "Voltar", false, function() setup.step = "name"; setup.err = nil end, 12)
    sbutton(nextX, by, "Continuar", true, function()
      setup.step = "pass2"; setup.pw2 = ""; setup.err = nil
    end, 16)

  elseif s.step == "pass2" then
    ctext(px, pw_, py + 2, "Confirmar senha")
    ctext(px, pw_, py + 4, "Digite a senha novamente.", C.sub)
    field(px + 4, py + 6, pw_ - 8, s.pw2, true)
    if s.err then ctext(px, pw_, py + 10, s.err, C.red) end
    sbutton(px + 3, by, "Voltar", false, function() setup.step = "pass"; setup.err = nil end, 12)
    sbutton(nextX, by, "Concluir", true, submitPass2, 16)

  elseif s.step == "done" then
    local left = math.max(0, math.ceil(s.doneAt - computer.uptime()))
    ctext(px, pw_, py + 3, "Tudo pronto, " .. s.name .. "!")
    ctext(px, pw_, py + 5, "O Plasma OS abre em " .. left .. " segundos.", C.sub)
  end
end

local function setupKey(ch, code)
  local s = setup
  if code == 28 or code == 156 then            -- Enter
    if s.step == "welcome" then s.step = "name"
    elseif s.step == "name" then submitName()
    elseif s.step == "pass" then s.step = "pass2"; s.pw2 = ""; s.err = nil
    elseif s.step == "pass2" then submitPass2() end
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
  while true do
    drawSetup()
    if setup.step == "done" and computer.uptime() >= setup.doneAt then
      return { name = setup.name, hash = setup.hash }
    end
    local sig, _, a, b = computer.pullSignal(0.5)
    if sig == "touch" then
      local btn = hit(sbtns, a, b)
      if btn then btn.action() end
    elseif sig == "key_down" then
      setupKey(a, b)
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

  -- barra de título (mais escura na janela ativa)
  gpu.setBackground(active and C.titleActive or C.titleIdle)
  gpu.fill(x, y, win.w, 1, " ")
  gpu.setBackground(C.close); gpu.set(x + 2, y, " ")
  gpu.setBackground(C.minim); gpu.set(x + 4, y, " ")
  gpu.setBackground(C.zoom);  gpu.set(x + 6, y, " ")
  gpu.setBackground(active and C.titleActive or C.titleIdle)
  gpu.setForeground(C.menuFg)
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

local MENU_TITLES = { "*", "Arquivo", "Editar", "Visualizar", "Janela", "Ajuda" }
local menuBar = {}
do
  local x = 2
  for _, name in ipairs(MENU_TITLES) do
    menuBar[#menuBar + 1] = { name = name, x1 = x, x2 = x + #name - 1 }
    x = x + #name + 3
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
  gpu.setBackground(C.panel)
  gpu.fill(x, y, bw, n, " ")
  for i, it in ipairs(openMenu.items) do
    gpu.setBackground(C.panel)
    gpu.setForeground(it[2] and C.dark or C.sub)
    gpu.set(x + 2, y + i - 1, it[1])
  end
end

local function drawMenu()
  gpu.setBackground(C.menuBg)
  gpu.setForeground(C.menuFg)
  gpu.fill(1, 1, w, 1, " ")
  for _, m in ipairs(menuBar) do
    if openMenu and openMenu.name == m.name then
      gpu.setBackground(C.blue); gpu.setForeground(C.white)
    else
      gpu.setBackground(C.menuBg); gpu.setForeground(C.menuFg)
    end
    gpu.set(m.x1, 1, m.name)
  end
  gpu.setBackground(C.menuBg)
  gpu.setForeground(C.menuFg)
  local clock = clockText()
  gpu.set(w - #clock - 1, 1, clock)
end

-- Dock -----------------------------------------------------------------

local function drawDock()
  gpu.setBackground(C.dockBg)
  gpu.fill(dockX0, dockY, dockW, 3, " ")
  for i, app in ipairs(apps) do
    local x = dockX0 + 1 + (i - 1) * 6
    if app.icon and app.icon.draw then
      pcall(app.icon.draw, G, x, dockY)
    else
      gpu.setBackground(app.color or 0x7F8C8D)
      gpu.fill(x, dockY, 5, 2, " ")
      gpu.setForeground(C.white)
      gpu.set(x + 2, dockY, app.letter or "?")
    end
  end
end

local function drawDockLabel()
  if not dockLabel or not apps[dockLabel.idx] then return end
  local text = " " .. apps[dockLabel.idx].name .. " "
  local cx = dockX0 + 1 + (dockLabel.idx - 1) * 6 + 2
  local x = math.max(1, math.min(w - #text + 1, cx - math.floor(#text / 2)))
  gpu.setBackground(C.menuBg)
  gpu.setForeground(C.menuFg)
  gpu.set(x, dockY - 1, text)
end

local function redraw()
  local p = WALLPAPERS[wallIdx]
  local top, bottom = 2, h - 4
  for y = top, bottom do
    local t = (y - top) / math.max(1, bottom - top)
    gpu.setBackground(mix(p.sky2, p.sky1, t))
    gpu.fill(1, y, w, 1, " ")
  end
  local rx = math.floor(w * (p.rockX or 0.08))
  local rw = math.floor(w * (p.rockW or 0.30))
  local rh = math.floor(h * (p.rockH or 0.35))
  gpu.setBackground(p.rock or 0xC0643A)
  gpu.fill(rx + 1, 6, rw, rh, " ")
  local gy = math.floor(h * 0.7)
  gpu.setBackground(p.ground or 0x2F4A3B)
  gpu.fill(1, gy, w, bottom - gy + 1, " ")

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
  ["*"]          = { { "Sair do Plasma (Q)", quit } },
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
  redraw()
  while running do
    local sig, _, a, b = computer.pullSignal(1)
    if sig == "touch" then
      handleTouch(a, b)
    elseif sig == "drag" then
      handleDrag(a, b)
    elseif sig == "drop" then
      dragging = nil
      resizing = nil
    elseif sig == "key_down" then
      handleKey(a, b)
    end
    if dockLabel and computer.uptime() > dockLabel.untilT then dockLabel = nil end
    redraw()
  end

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
