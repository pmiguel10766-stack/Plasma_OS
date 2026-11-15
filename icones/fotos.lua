-- Plasma OS - ícone do app fotos (5x2 no dock)
return {
  bg = 0x9B51E0, fg = 0xFFFFFF,
  lines = { "/\\ ", "/__" },
  draw = function(g, x, y)
    g.fill(x, y, 5, 2, 0x9B51E0)
    g.text(x + 1, y, "/\\ ", 0xFFFFFF, 0x9B51E0)
    g.text(x + 1, y + 1, "/__", 0xFFFFFF, 0x9B51E0)
  end,
}
