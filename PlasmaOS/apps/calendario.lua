-- Plasma OS - ícone do app calendario (5x2 no dock)
-- Faixa vermelha com o mês e papel branco com o dia de hoje.
-- "key" diz ao dock quando redesenhar: o ícone muda sozinho quando o dia muda.

local MESES = { "JAN", "FEV", "MAR", "ABR", "MAI", "JUN",
                "JUL", "AGO", "SET", "OUT", "NOV", "DEZ" }

local function today()
  local ok, d = pcall(os.date, "*t")
  if ok and type(d) == "table" then return d end
  return nil
end

return {
  bg = 0xE05252, fg = 0xFFFFFF,
  lines = { "NOV", "16" },

  key = function()
    local d = today()
    if not d then return "" end
    return d.year .. "-" .. d.yday
  end,

  draw = function(g, x, y)
    local dock = g.dockBg or 0xD5DCE4
    local red, paper, ink = 0xE8473F, 0xFFFFFF, 0x1D1D1F

    local d = today()
    local mes, dia = "---", "--"
    if d then
      mes = MESES[d.month] or mes
      dia = tostring(d.day)
    end

    -- faixa vermelha com o mês (cantos arredondados com meio-bloco)
    g.text(x, y, "▄", red, dock)
    g.fill(x + 1, y, 3, 1, red)
    g.text(x + 1, y, mes, 0xFFFFFF, red)
    g.text(x + 4, y, "▄", red, dock)

    -- papel branco com o dia, centralizado
    g.text(x, y + 1, "▀", paper, dock)
    g.fill(x + 1, y + 1, 3, 1, paper)
    g.text(x + (#dia == 1 and 2 or 1), y + 1, dia, ink, paper)
    g.text(x + 4, y + 1, "▀", paper, dock)
  end,
}
