-- Plasma OS - /init.lua (bootstrapper com diagnóstico)
local BOOT_FILE = "/PlasmaOS/boot.lua"
local INSTALLER_URL = "https://raw.githubusercontent.com/pmiguel10766-stack/-opencomputers-script/refs/heads/main/instalador.lua"

local gpu = component.proxy(component.list("gpu")())
gpu.bind(component.list("screen")())
local W, H = gpu.getResolution()
local line = 1

local function say(s, color)
  if line > H then gpu.fill(1, 1, W, H, " "); line = 1 end
  gpu.setBackground(0x000000)
  gpu.setForeground(color or 0xFFFFFF)
  gpu.set(1, line, tostring(s):sub(1, W))
  line = line + 1
end

local function readFile(path)
  local fs = component.proxy(computer.getBootAddress())
  if not fs.exists(path) then return nil end
  local h = fs.open(path, "r")
  local parts = {}
  repeat
    local c = fs.read(h, math.huge)
    if c then parts[#parts + 1] = c end
  until not c
  fs.close(h)
  return table.concat(parts)
end

local function runNamed(src, name)
  local fn, err = load(src, "=" .. name, "t")
  if not fn then return false, "erro de sintaxe: " .. tostring(err) end
  return xpcall(fn, function(e) return tostring(e) end)
end

local src = readFile(BOOT_FILE)
if src then
  say("Iniciando " .. BOOT_FILE)
  local ok, err = runNamed(src, BOOT_FILE)
  if not ok then
    say("ERRO em " .. BOOT_FILE, 0xFF5555)
    say(tostring(err), 0xFF5555)
    say("Anote esta mensagem e envie.")
  end
else
  say("Plasma OS não encontrado. Abra o instalador.", 0xFFFF55)
  say(INSTALLER_URL)
end

while true do computer.pullSignal(1) end
