-- Plasma OS - biblioteca de trechos reutilizáveis para apps e sistema.
-- Uso: local T = dofile-equivalente; apps recebem via ctx.trechos.
local T = {}

-- Corta texto para caber em n caracteres
function T.clip(s, n)
  s = tostring(s)
  if #s <= n then return s end
  return s:sub(1, n)
end

-- Centraliza texto dentro de uma largura w
function T.center(s, w)
  s = tostring(s)
  local pad = math.max(0, math.floor((w - #s) / 2))
  return string.rep(" ", pad) .. s
end

-- Tamanho em KB e MB legíveis
function T.fmtBytes(n)
  if n >= 1048576 then return string.format("%.1f MB", n / 1048576) end
  return string.format("%d KB", math.floor(n / 1024))
end

-- Porcentagem segura (evita divisão por zero)
function T.pct(part, total)
  if not total or total <= 0 then return 0 end
  return math.floor(part / total * 100)
end

-- Barra de progresso: g é o auxiliar gráfico (fill/text)
function T.progress(g, x, y, w, frac, fg, bg)
  frac = math.max(0, math.min(1, frac))
  g.fill(x, y, w, 1, bg or 0xD6D6D6)
  local filled = math.floor(w * frac)
  if filled > 0 then g.fill(x, y, filled, 1, fg or 0x0A84FF) end
end

-- Botão arredondado visualmente simples (3 linhas)
function T.button(g, x, y, label, primary, w)
  local bw = w or (#label + 6)
  local bg = primary and 0x0A84FF or 0xD6D6D6
  local fg = primary and 0xFFFFFF or 0x1D1D1F
  g.fill(x, y, bw, 3, bg)
  g.text(x + math.floor((bw - #label) / 2), y + 1, label, fg, bg)
  return { x = x, y = y, w = bw, h = 3 }
end

-- Retângulo "cartão" branco
function T.card(g, x, y, w, h, bg)
  g.fill(x, y, w, h, bg or 0xFFFFFF)
end

return T
