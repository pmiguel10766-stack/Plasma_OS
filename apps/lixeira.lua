-- Plasma OS - Lixeira: itens em /PlasmaOS/lixeira, com botão Esvaziar
local DIR = "/PlasmaOS/lixeira/"

local function items(ctx)
  local ok, t = pcall(ctx.fs.list, DIR)
  if ok and type(t) == "table" then table.sort(t) return t end
  return {}
end

return {
  name = "Lixeira", letter = "L", color = 0xBDC3C7,

  draw = function(win, b, g, ctx)
    g.fill(b.x, b.y, b.w, b.h, 0xFFFFFF)
    local list = items(ctx)
    if #list == 0 then
      local msg = "A lixeira está vazia."
      g.text(b.x + math.floor((b.w - #msg) / 2), b.y + math.floor(b.h / 2), msg, 0x86868B, 0xFFFFFF)
      return
    end
    for i = 1, math.min(#list, b.h - 3) do
      local y = b.y + i
      g.fill(b.x + 1, y, 2, 1, 0xBDBDBD)
      g.text(b.x + 4, y, g.clip(list[i], b.w - 6), 0x1D1D1F, 0xFFFFFF)
    end
    local bx = b.x + b.w - 14
    local by = b.y + b.h - 1
    g.fill(bx, by, 13, 1, 0xD93025)
    g.text(bx + 2, by, "Esvaziar", 0xFFFFFF, 0xD93025)
  end,

  touch = function(win, b, x, y, ctx)
    if y == b.y + b.h - 1 and x >= b.x + b.w - 14 then
      for _, name in ipairs(items(ctx)) do
        pcall(ctx.fs.remove, DIR .. name)
      end
    end
  end,
}
