-- Plasma OS - ícone do app safari (5x2 no dock = 5x4 pixels com meio-blocos)
-- '.' = fundo em degradê, '~' = fundo do dock (cantos arredondados)
local ROWS = { "~www~", "w..rw", "wg..w", "~www~" }
local PAL  = { w = 0xFFFFFF, r = 0xFF3B30, g = 0xDADDE2 }

local function ramp(c1, c2)
  local t = {}
  for i = 0, 3 do
    local f = i / 3
    local function ch(sh)
      local a, b = math.floor(c1 / sh) % 256, math.floor(c2 / sh) % 256
      return math.floor(a + (b - a) * f)
    end
    t[i + 1] = ch(65536) * 65536 + ch(256) * 256 + ch(1)
  end
  return t
end
local GRAD = ramp(0x5AC8FA, 0x1E6FE0)

return {
  bg = 0x2F80ED, fg = 0xFFFFFF,
  lines = { "(@)", " / " },
  draw = function(g, x, y)
    local dock = g.dockBg or 0xD5DCE4
    local function col(ch, r)
      if ch == "~" then return dock end
      if ch == "." then return GRAD[r] end
      return PAL[ch]
    end
    for cy = 0, 1 do
      local r1, r2 = cy * 2 + 1, cy * 2 + 2
      for cx = 1, 5 do
        local a = col(ROWS[r1]:sub(cx, cx), r1)
        local b = col(ROWS[r2]:sub(cx, cx), r2)
        if a == b then
          g.text(x + cx - 1, y + cy, " ", a, a)
        else
          g.text(x + cx - 1, y + cy, "▀", a, b)
        end
      end
    end
  end,
}
