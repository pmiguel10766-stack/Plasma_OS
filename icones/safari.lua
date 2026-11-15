-- Plasma OS - ícone do app safari (5x2 no dock)
return {
  bg = 0x2F80ED, fg = 0xFFFFFF,
  lines = { "(@)", " / " },
  draw = function(g, x, y)
    g.fill(x, y, 5, 2, 0x2F80ED)
    g.text(x + 1, y, "(@)", 0xFFFFFF, 0x2F80ED)
    g.text(x + 1, y + 1, " / ", 0xFFFFFF, 0x2F80ED)
  end,
}
