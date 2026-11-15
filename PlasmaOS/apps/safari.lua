-- Plasma OS - Safari: barra de endereço e página de estado (sem HTTP ainda)
return {
  name = "Safari", letter = "S", color = 0x2F80ED,

  init = function(win)
    win.state = win.state or { url = "", msg = nil }
  end,

  draw = function(win, b, g, ctx)
    local s = win.state
    local BAR = 0xF0F0F2
    g.fill(b.x, b.y, b.w, b.h, 0xFFFFFF)
    g.fill(b.x, b.y, b.w, 1, BAR)
    g.fill(b.x + 2, b.y, b.w - 4, 1, 0xFFFFFF)
    local shown = s.url ~= "" and s.url or "Digite um endereço"
    g.text(b.x + 4, b.y, g.clip(shown, b.w - 8), s.url ~= "" and 0x1D1D1F or 0xAEAEB2, 0xFFFFFF)

    local cy = b.y + math.floor(b.h / 2)
    local msg = s.msg or "Digite um endereço e pressione Enter."
    g.text(b.x + math.max(1, math.floor((b.w - #msg) / 2)), cy, g.clip(msg, b.w - 2), 0x86868B, 0xFFFFFF)
  end,

  key = function(win, ch, code, ctx)
    local s = win.state
    if code == 28 or code == 156 then            -- Enter
      if s.url == "" then return end
      if component.list("internet")() then
        s.msg = "Navegação na internet ainda não implementada."
      else
        s.msg = "Sem placa de rede (internet card)."
      end
    elseif code == 14 then                       -- Backspace
      s.url = s.url:sub(1, -2)
    elseif ch and ch >= 32 and ch < 127 then
      s.url = s.url .. string.char(ch)
    end
  end,
}
