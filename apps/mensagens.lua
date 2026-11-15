-- Plasma OS - Mensagens: conversa com bolhas, saudação com o nome do usuário
local SIDE = 16

local function bubble(g, x, y, text, mine, maxW)
  local w = math.min(#text + 2, maxW)
  local bx = mine and x - w or x
  g.fill(bx, y, w, 1, mine and 0x0A84FF or 0xE5E5EA)
  g.text(bx + 1, y, g.clip(text, w - 2), mine and 0xFFFFFF or 0x1D1D1F, mine and 0x0A84FF or 0xE5E5EA)
end

return {
  name = "Mensagens", letter = "M", color = 0x27AE60,

  draw = function(win, b, g, ctx)
    g.fill(b.x, b.y, b.w, b.h, 0xFFFFFF)
    g.fill(b.x, b.y, SIDE, b.h, 0xF5F5F7)

    g.fill(b.x, b.y, SIDE, 2, 0x27AE60)
    g.text(b.x + 1, b.y, "Plasma", 0xFFFFFF, 0x27AE60)
    g.text(b.x + 1, b.y + 1, "Sistema", 0xE6F5EC, 0x27AE60)

    local cx = b.x + SIDE + 1
    local cw = b.w - SIDE - 2
    local user = ctx.user or "você"
    bubble(g, cx, b.y + 3, "Bem-vindo(a), " .. user .. "!", false, cw)
    bubble(g, cx, b.y + 5, "Seu sistema está pronto.", false, cw)
    bubble(g, cx + cw, b.y + 7, "Oi!", true, cw)
    bubble(g, cx, b.y + 9, "Use o Finder para explorar arquivos.", false, cw)
  end,
}
