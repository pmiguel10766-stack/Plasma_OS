-- Plasma OS - ícone do app calendario (5x2 no dock)
return {
  bg = 0xE05252, fg = 0xFFFFFF,
  lines = { "[8]", "---" },
  draw = function(g, x, y)
    g.fill(x, y, 5, 2, 0xE05252)
    g.text(x + 1, y, "[8]", 0xFFFFFF, 0xE05252)
    g.text(x + 1, y + 1, "---", 0xFFFFFF, 0xE05252)
  end,
}
