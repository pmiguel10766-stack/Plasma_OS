-- Plasma OS - ícone do app calendario (5x2 no dock)
-- Faixa vermelha com o mês e papel branco com o dia de hoje.
local MESES = { "JAN", "FEV", "MAR", "ABR", "MAI", "JUN",
                "JUL", "AGO", "SET", "OUT", "NOV", "DEZ" }

return {
  bg = 0xE05252, fg = 0xFFFFFF,
  lines = { "[8]", "---" },
  draw = function(g, x, y)
    local dock = g.dockBg or 0xD5DCE4
    local red, paper, ink = 0xE8473F, 0xFFFFFF, 0x1D1D1F
    local mes, dia = "---", "--"
    local ok, d = pcall(os.date, "*t")
    if ok and type(d) == "table" then
      mes = MESES[d.month] or mes
      dia = tostring(d.day)
    end
    local txt = (#dia == 1) and (" " .. dia .. " ") or (dia .. " ")

    -- linha de cima: faixa vermelha (cantos arredondados com meio-bloco)
    g.text(x, y, "▄", red, dock)
    g.text(x + 1, y, mes, 0xFFFFFF, red)
    g.text(x + 4, y, "▄", red, dock)
    -- linha de baixo: papel branco com o dia
    g.text(x, y + 1, "▀", paper, dock)
    g.text(x + 1, y + 1, txt, ink, paper)
    g.text(x + 4, y + 1, "▀", paper, dock)
  end,
}
