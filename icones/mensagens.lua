-- Plasma OS - ícone do app mensagens (5x2 no dock)
return {
  bg = 0x27AE60, fg = 0xFFFFFF,
  lines = { "...", " V " },
  draw = function(g, x, y)
    g.fill(x, y, 5, 2, 0x27AE60)
    g.text(x + 1, y, "...", 0xFFFFFF, 0x27AE60)
    g.text(x + 1, y + 1, " V ", 0xFFFFFF, 0x27AE60)
  end,
}
