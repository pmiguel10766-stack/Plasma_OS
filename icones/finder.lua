-- Plasma OS - ícone do app finder (5x2 no dock)
return {
  bg = 0x3A8FD9, fg = 0xFFFFFF,
  lines = { "|-|", "-^-" },
  draw = function(g, x, y)
    g.fill(x, y, 5, 2, 0x3A8FD9)
    g.text(x + 1, y, "|-|", 0xFFFFFF, 0x3A8FD9)
    g.text(x + 1, y + 1, "-^-", 0xFFFFFF, 0x3A8FD9)
  end,
}
