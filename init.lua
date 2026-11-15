-- Plasma OS - init.lua (bootstrapper)
-- Sem OpenOS. Fica na raiz do disco.

local BOOT_FILE    = "/plasmaOS/boot.lua"
local INSTALLER_URL = "https://raw.githubusercontent.com/pmiguel10766-stack/-opencomputers-script/refs/heads/main/instalador.lua"
local TIMEOUT   = 30
local ATTEMPTS  = 2

local gpu = component.proxy(component.list("gpu")())
gpu.bind(component.list("screen")())
local W, H = gpu.getResolution()

local line = 1
local function say(s, color)
  if line > H then
    gpu.setBackground(0x000000)
    gpu.fill(1, 1, W, H, " ")
    line = 1
  end
  gpu.setBackground(0x000000)
  gpu.setForeground(color or 0xFFFFFF)
  gpu.set(1, line, tostring(s):sub(1, W))
  line = line + 1
end

local function clear()
  gpu.setBackground(0x000000)
  gpu.fill(1, 1, W, H, " ")
  line = 1
end

local function readFile(path)
  local fs = component.proxy(computer.getBootAddress())
  if not fs.exists(path) then return nil end
  local h, err = fs.open(path, "r")
  if not h then return nil, err end
  local parts = {}
  while true do
    local chunk = fs.read(h, math.huge)
    if not chunk then break end
    parts[#parts + 1] = chunk
  end
  fs.close(h)
  return table.concat(parts)
end

local function download(url)
  local addr = component.list("internet")()
  if not addr then return nil, "sem placa de rede (internet card)" end
  local inet = component.proxy(addr)

  local ok, h = pcall(inet.request, url)
  if not ok or not h then return nil, tostring(h) end

  local deadline = computer.uptime() + TIMEOUT
  while true do
    local done, res = pcall(h.finishConnect)
    if not done then h.close(); return nil, tostring(res) end
    if res then break end
    if computer.uptime() > deadline then
      h.close()
      return nil, "tempo esgotado (" .. TIMEOUT .. "s)"
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
      if reason then return nil, tostring(reason) end
      return table.concat(parts)
    end
  end
end

local function runSource(src, name)
  local fn, err = load(src, "=" .. name, "t")
  if not fn then return false, err end
  fn()
  return true
end

local function start()
  clear()
  say("Plasma OS - inicializando")

  local boot, rerr = readFile(BOOT_FILE)
  if boot then
    local ok, err = runSource(boot, BOOT_FILE)
    if not ok then
      say("Erro ao iniciar " .. BOOT_FILE, 0xFF5555)
      say(err, 0xFF5555)
      say("Pressione uma tecla para tentar de novo.")
      repeat local sig = computer.pullSignal() until sig == "key_down"
      return start()
    end
    return
  end

  say("Plasma OS não encontrado. Baixando instalador...")

  local lastErr
  for attempt = 1, ATTEMPTS do
    say("Tentativa " .. attempt .. " de " .. ATTEMPTS .. " (até " .. TIMEOUT .. "s)")
    local src, err = download(INSTALLER_URL)
    if src then
      local ok, rerr2 = runSource(src, "instalador")
      if ok then return end
      err = rerr2
    end
    lastErr = err
    say("Falha: " .. tostring(err), 0xFF5555)
  end

  say("Não foi possível baixar o instalador.", 0xFF5555)
  say("URL que falhou:")
  say(INSTALLER_URL, 0xFFFF55)
  say("Pressione uma tecla para tentar de novo.")
  repeat local sig = computer.pullSignal() until sig == "key_down"
  return start()
end

start()
