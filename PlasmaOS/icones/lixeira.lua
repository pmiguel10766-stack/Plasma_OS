-- Plasma OS - ícone do app lixeira (5x2 no dock)
return {
  bg = 0xBDC3C7, fg = 0x1D1D1F,
  lines = { "|=|", " U " },
  draw = function(g, x, y)
    g.fill(x, y, 5, 2, 0xBDC3C7)
    g.text(x + 1, y, "|=|", 0x1D1D1F, 0xBDC3C7)
    g.text(x + 1, y + 1, " U ", 0x1D1D1F, 0xBDC3C7)
  end,
}
