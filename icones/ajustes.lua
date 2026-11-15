-- Plasma OS - ícone do app ajustes (5x2 no dock)
return {
  bg = 0x7F8C8D, fg = 0xFFFFFF,
  lines = { "(*)", "/ \\" },
  draw = function(g, x, y)
    g.fill(x, y, 5, 2, 0x7F8C8D)
    g.text(x + 1, y, "(*)", 0xFFFFFF, 0x7F8C8D)
    g.text(x + 1, y + 1, "/ \\", 0xFFFFFF, 0x7F8C8D)
  end,
}
