-- Plasma OS - Calendário: grade do mês atual, com o dia de hoje destacado
local MONTHS = { "Janeiro", "Fevereiro", "Março", "Abril", "Maio", "Junho",
  "Julho", "Agosto", "Setembro", "Outubro", "Novembro", "Dezembro" }
local WEEK = { "D", "S", "T", "Q", "Q", "S", "S" }

local function info()
  local ok, r = pcall(function()
    local t = os.date("*t")
    local first = os.date("*t", os.time({ year = t.year, month = t.month, day = 1 })).wday
    local dim = os.date("*t", os.time({ year = t.year, month = t.month + 1, day = 0 })).day
    return { year = t.year, month = t.month, day = t.day, first = first, dim = dim }
  end)
  if ok then return r end
  return nil
end

return {
  name = "Calendário", letter = "C", color = 0xE05252,

  draw = function(win, b, g, ctx)
    g.fill(b.x, b.y, b.w, b.h, 0xFFFFFF)
    local d = info()
    if not d then
      g.text(b.x + 2, b.y + 2, "Data indisponível neste computador.", 0x86868B, 0xFFFFFF)
      return
    end

    local title = MONTHS[d.month] .. " " .. d.year
    g.text(b.x + math.floor((b.w - #title) / 2), b.y, title, 0xE05252, 0xFFFFFF)

    local gridW = 28
    local x0 = b.x + math.floor((b.w - gridW) / 2)
    for i, lbl in ipairs(WEEK) do
      g.text(x0 + (i - 1) * 4 + 1, b.y + 2, lbl, 0x86868B, 0xFFFFFF)
    end

    for day = 1, d.dim do
      local pos = d.first - 1 + (day - 1)
      local col = pos % 7
      local row = math.floor(pos / 7)
      local y = b.y + 3 + row
      if y < b.y + b.h then
        local x = x0 + col * 4
        local txt = string.format("%2d", day)
        if day == d.day then
          g.fill(x, y, 3, 1, 0xE05252)
          g.text(x, y, txt, 0xFFFFFF, 0xE05252)
        else
          g.text(x, y, txt, 0x1D1D1F, 0xFFFFFF)
        end
      end
    end
  end,
}
