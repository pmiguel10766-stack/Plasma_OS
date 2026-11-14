-- init.lua - bootstrapper do Plasma OS (compatível com todas as versões do OpenComputers)
-- Se /PlasmaOS/boot.lua existe, roda o sistema.
-- Senão, baixa o instalador do GitHub e executa.

local BOOT_PATH = "/PlasmaOS/boot.lua"
local INSTALLER_URL = "https://raw.githubusercontent.com/pmiguel10766-stack/-opencomputers-script/refs/heads/main/instalador.lua"
local TIMEOUT = 30
local ATTEMPTS = 2
local BLOCK = 2048

-- Tela ----------------------------------------------------------------------

local gpuAddr = component.list("gpu")()
local gpu = gpuAddr and component.proxy(gpuAddr)
local W, H, line = 80, 25, 1

if gpu then
  pcall(function()
    local scrAddr = component.list("screen")()
    if scrAddr then gpu.bind(scrAddr) end
    gpu.setResolution(gpu.maxResolution())
    W, H = gpu.getResolution()
  end)
  gpu.setBackground(0x000000)
  gpu.setForeground(0xFFFFFF)
  gpu.fill(1, 1, W, H, " ")
end

local function say(msg)
  if not gpu then return end
  gpu.set(1, line, tostring(msg):sub(1, W))
  line = line + 1
  if line > H then
    gpu.fill(1, 1, W, H, " ")
    line = 1
  end
end

-- Arquivos ------------------------------------------------------------------

local bootFs = component.proxy(computer.getBootAddress())

local function readFile(fs, path)
  local okO, h, e = pcall(fs.open, path, "r")
  if not okO or not h then return nil, tostring(h or e) end
  local parts = {}
  while true do
    local okR, chunk = pcall(fs.read, h, BLOCK)
    if not okR then pcall(fs.close, h); return nil, tostring(chunk) end
    if not chunk then break end
    parts[#parts + 1] = chunk
  end
  pcall(fs.close, h)
  return table.concat(parts)
end

local function runCode(code, name)
  local fn, err = load(code, "=" .. name)
  if not fn then
    say("Erro de sintaxe em " .. name)
    say(tostring(err))
    return false
  end
  local ok, runErr = xpcall(fn, debug.traceback)
  if not ok then
    say("Erro ao executar " .. name)
    say(tostring(runErr))
    return false
  end
  return true
end

-- Download ------------------------------------------------------------------

local function download(url)
  local inetAddr = component.list("internet")()
  if not inetAddr then return nil, "sem placa de internet" end

  local net = component.proxy(inetAddr)
  local okReq, handle = pcall(net.request, url)
  if not okReq or not handle then return nil, "request: " .. tostring(handle) end

  local started = computer.uptime()

  while true do
    local okC, ready = pcall(handle.finishConnect, handle)
    if not okC then
      pcall(handle.close, handle)
      return nil, "conexão: " .. tostring(ready)
    end
    if ready then break end
    if computer.uptime() - started > TIMEOUT then
      pcall(handle.close, handle)
      return nil, "tempo esgotado ao conectar"
    end
    computer.pullSignal(0.1)
  end

  local parts = {}
  while true do
    if computer.uptime() - started > TIMEOUT then
      pcall(handle.close, handle)
      return nil, "tempo esgotado ao baixar"
    end
    local okR, chunk, reason = pcall(handle.read, handle, BLOCK)
    if not okR then
      pcall(handle.close, handle)
      return nil, "leitura: " .. tostring(chunk)
    end
    if chunk then
      parts[#parts + 1] = chunk
    elseif reason then
      pcall(handle.close, handle)
      return nil, tostring(reason)
    else
      break
    end
  end
  pcall(handle.close, handle)

  local data = table.concat(parts)
  if data == "" then return nil, "resposta vazia" end
  return data
end

-- Principal -----------------------------------------------------------------

if bootFs.exists(BOOT_PATH) then
  local code, err = readFile(bootFs, BOOT_PATH)
  if code then
    runCode(code, BOOT_PATH)
  else
    say("Não foi possível ler " .. BOOT_PATH)
    say(tostring(err))
  end
else
  say("Plasma OS não encontrado. Baixando o instalador...")
  local data, lastErr
  for attempt = 1, ATTEMPTS do
    say("Tentativa " .. attempt .. " de " .. ATTEMPTS)
    data, lastErr = download(INSTALLER_URL)
    if data then break end
    say("Falhou: " .. tostring(lastErr))
  end

  if data then
    runCode(data, "instalador.lua")
  else
    say("")
    say("Não foi possível baixar o instalador.")
    say("URL: " .. INSTALLER_URL)
  end
end

while true do
  computer.pullSignal(1)
end
