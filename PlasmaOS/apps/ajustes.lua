-- Plasma OS - Ajustes: informações do sistema e troca de fundo
local function kb(n) return string.format("%d KB", math.floor(n / 1024)) end

return {
  name = "Ajustes", letter = "A", color = 0x7F8C8D,

  draw = function(win, b, g, ctx)
    g.fill(b.x, b.y, b.w, b.h, 0xF5F5F7)
    local total = computer.totalMemory()
    local used = total - computer.freeMemory()
    local maxE = computer.maxEnergy()
    local energy = maxE > 0 and math.floor(computer.energy() / maxE * 100) or 0

    local rows = {
      { "Usuário", ctx.user or "-" },
      { "Versão", ctx.version or "-" },
      { "Memória", kb(used) .. " de " .. kb(total) },
      { "Energia", energy .. "%" },
      { "Fundo de tela", "Trocar >", true },
    }

    for i, r in ipairs(rows) do
      local y = b.y + (i - 1) * 2 + 1
      if y + 1 < b.y + b.h then
        g.fill(b.x + 1, y, b.w - 2, 1, 0xFFFFFF)
        g.text(b.x + 3, y, r[1], 0x1D1D1F, 0xFFFFFF)
        local v = r[2]
        g.text(b.x + b.w - 3 - #v, y, v, r[3] and 0x0A84FF or 0x86868B, 0xFFFFFF)
      end
    end
  end,

  touch = function(win, b, x, y, ctx)
    local idx = math.floor((y - b.y - 1) / 2) + 1
    if (y - b.y - 1) % 2 == 0 and idx == 5 and ctx.nextWallpaper then
      ctx.nextWallpaper()
    end
  end,
}
