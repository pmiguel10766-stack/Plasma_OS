-- Plasma OS - ícone do app fotos (5x2 no dock = 5x4 pixels com meio-blocos)
-- '.' = fundo em degradê, '~' = fundo do dock (cantos arredondados)
local ROWS = { "~roy~", "ewwwg", "pwwwc", "~vib~" }
local PAL  = { w = 0xFFFFFF, r = 0xFF3B30, o = 0xFF9500, y = 0xFFCC00, g = 0x34C759, c = 0x32ADE6, b = 0x007AFF, i = 0x5856D6, v = 0xAF52DE, p = 0xFF2D92, e = 0xFF6482 }

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
local GRAD = ramp(0xFFFFFF, 0xFFFFFF)

return {
  bg = 0x9B51E0, fg = 0xFFFFFF,
  lines = { "/\\ ", "/__" },
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
