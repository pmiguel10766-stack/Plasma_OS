-- Plasma OS - Rede Local: placas de rede e modems instalados no computador
local function short(addr) return addr:sub(1, 8) end

local function cards()
  local out = {}
  for addr in component.list("modem") do
    out[#out + 1] = { kind = "Modem", addr = addr, color = 0x27AE60 }
  end
  for addr in component.list("internet") do
    out[#out + 1] = { kind = "Placa de rede", addr = addr, color = 0x2F80ED }
  end
  return out
end

return {
  name = "Rede Local", letter = "R", color = 0x1ABC9C,

  draw = function(win, b, g, ctx)
    g.fill(b.x, b.y, b.w, b.h, 0xFFFFFF)
    local list = cards()
    if #list == 0 then
      local msg = "Nenhuma rede encontrada."
      g.text(b.x + math.floor((b.w - #msg) / 2), b.y + math.floor(b.h / 2), msg, 0x86868B, 0xFFFFFF)
      return
    end
    for i, c in ipairs(list) do
      local y = b.y + (i - 1) * 3 + 1
      if y + 1 < b.y + b.h then
        g.fill(b.x + 2, y, 4, 2, c.color)
        g.text(b.x + 8, y, c.kind, 0x1D1D1F, 0xFFFFFF)
        g.text(b.x + 8, y + 1, "ID " .. short(c.addr) .. "  Ativo", 0x86868B, 0xFFFFFF)
      end
    end
  end,
}
