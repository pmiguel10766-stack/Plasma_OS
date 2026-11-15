-- Plasma OS - ícone do app notas (5x2 no dock)
return {
  bg = 0xF2C94C, fg = 0x1D1D1F,
  lines = { "===", "===" },
  draw = function(g, x, y)
    g.fill(x, y, 5, 2, 0xF2C94C)
    g.text(x + 1, y, "===", 0x1D1D1F, 0xF2C94C)
    g.text(x + 1, y + 1, "===", 0x1D1D1F, 0xF2C94C)
  end,
}
