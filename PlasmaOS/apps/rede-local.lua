-- Plasma OS - Rede Local: estilo painel Rede do OS X Yosemite
-- Lista de placas de rede e modems à esquerda; detalhes da interface escolhida à direita.
-- Clique numa interface para ver os detalhes. A lista atualiza sozinha.

local SIDE = 18

local SIDEBG, PANEL, WHITE = 0xE9EBEE, 0xFFFFFF, 0xFFFFFF
local INK, DIM, SEP = 0x1D1D1F, 0x86868B, 0xD1D1D6
local GREEN, GRAY, BLUE = 0x34C759, 0xAEAEB2, 0x0A84FF
local SELBG = 0xD0D6DE

local function len(s)
  if unicode and unicode.len then return unicode.len(s) end
  return #s
end

-- Chama um método do componente sem deixar um erro derrubar o app
local function call(proxy, method, ...)
  local f = proxy[method]
  if type(f) ~= "function" then return nil end
  local ok, v = pcall(f, ...)
  if ok then return v end
  return nil
end

local function short(addr)
  return addr:sub(1, 8)
end

local function fmtBytes(n)
  if not n then return "-" end
  if n >= 1024 then return string.format("%.1f KB", n / 1024) end
  return n .. " B"
end

-- Monta a lista de interfaces com os dados de cada uma
local function interfaces()
  local out = {}

  for addr in component.list("modem") do
    local p = component.proxy(addr)
    local wireless = call(p, "isWireless") == true
    local strength = wireless and call(p, "getStrength") or nil
    local rows = {
      { "Tipo", wireless and "Modem sem fio" or "Modem cabeado" },
      { "Estado", "Ativo", GREEN },
      { "Endereço", short(addr) },
      { "Pacote máximo", fmtBytes(call(p, "maxPacketSize")) },
    }
    if wireless then
      rows[#rows + 1] = { "Força do sinal", strength and (tostring(strength)) or "-" }
    end
    out[#out + 1] = {
      name = wireless and "Wi-Fi" or "Modem",
      dot = GREEN,
      rows = rows,
    }
  end

  for addr in component.list("internet") do
    local p = component.proxy(addr)
    local http = call(p, "isHttpEnabled") == true
    local tcp = call(p, "isTcpEnabled") == true
    local on = http or tcp
    out[#out + 1] = {
      name = "Placa de rede",
      dot = on and GREEN or GRAY,
      rows = {
        { "Tipo", "Internet card" },
        { "Estado", on and "Conectado" or "Desativado", on and GREEN or DIM },
        { "Endereço", short(addr) },
        { "HTTP", http and "Ativado" or "Desativado" },
        { "TCP", tcp and "Ativado" or "Desativado" },
      },
    }
  end

  return out
end

-- Desenho -----------------------------------------------------------------

local function row(g, x, y, w, k, v, vfg)
  g.fill(x, y, w, 1, WHITE)
  g.text(x + 2, y, k, INK, WHITE)
  local vs = tostring(v)
  g.text(x + w - 2 - len(vs), y, vs, vfg or DIM, WHITE)
  g.fill(x, y + 1, w, 1, SEP)
end

return {
  name = "Rede Local", letter = "R", color = 0x1ABC9C,

  init = function(win)
    win.state = win.state or { sel = 1 }
  end,

  draw = function(win, b, g, ctx)
    local s = win.state or { sel = 1 }
    win.state = s
    g.fill(b.x, b.y, b.w, b.h, PANEL)

    local list = interfaces()
    if #list == 0 then
      local msg = "Nenhuma rede encontrada."
      g.text(b.x + math.max(1, math.floor((b.w - len(msg)) / 2)),
        b.y + math.floor(b.h / 2), msg, DIM, PANEL)
      return
    end
    if s.sel > #list then s.sel = #list end
    if s.sel < 1 then s.sel = 1 end

    -- barra lateral com as interfaces
    g.fill(b.x, b.y, SIDE, b.h, SIDEBG)
    g.fill(b.x + SIDE, b.y, 1, b.h, SEP)
    g.text(b.x + 1, b.y, "Interfaces", DIM, SIDEBG)
    for i, it in ipairs(list) do
      local y = b.y + 1 + (i - 1) * 2
      if y + 1 < b.y + b.h then
        local sel = (i == s.sel)
        local bg = sel and SELBG or SIDEBG
        g.fill(b.x, y, SIDE, 2, bg)
        g.fill(b.x + 1, y, 1, 1, bg)
        g.text(b.x + 1, y, "●", it.dot, bg)
        g.text(b.x + 3, y, string.sub(it.name, 1, SIDE - 4), INK, bg)
        g.text(b.x + 3, y + 1, string.sub(it.rows[1][2], 1, SIDE - 4), sel and INK or DIM, bg)
      end
    end

    -- detalhes da interface escolhida
    local it = list[s.sel]
    local x0 = b.x + SIDE + 1
    local w = b.w - SIDE - 1
    local title = it.name
    g.text(x0 + math.max(0, math.floor((w - len(title)) / 2)), b.y, title, INK, PANEL)
    g.fill(x0, b.y + 1, w, 1, SEP)

    local y = b.y + 3
    for _, r in ipairs(it.rows) do
      if y + 1 < b.y + b.h then
        row(g, x0 + 1, y, w - 2, r[1], r[2], r[3])
      end
      y = y + 2
    end
  end,

  touch = function(win, b, x, y, ctx)
    local s = win.state or { sel = 1 }
    win.state = s
    if x >= b.x + SIDE then return end
    local rel = y - (b.y + 1)
    if rel < 0 or rel % 2 ~= 0 then return end
    local i = math.floor(rel / 2) + 1
    local count = #interfaces()
    if i >= 1 and i <= count then s.sel = i end
  end,
}
