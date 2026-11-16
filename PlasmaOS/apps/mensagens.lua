-- Plasma OS - Mensagens: conversas em bolhas, barra lateral e campo de envio
-- ↑ ↓ trocam de conversa. Enter envia. O sistema responde sozinho.

local SIDE = 16

local SIDEBG, SELBG = 0xE9EBEE, 0x0A84FF
local CHATBG, HEADBG = 0xFFFFFF, 0xF6F6F8
local FIELDBG = 0xF2F2F4
local THEIRS, THEIRS_FG = 0xE5E5EA, 0x1D1D1F
local MINE, MINE_FG = 0x0A84FF, 0xFFFFFF
local INK, DIM, SEP = 0x1D1D1F, 0x86868B, 0xD1D1D6

local function len(s)
  if unicode and unicode.len then return unicode.len(s) end
  return #s
end

local function usub(s, i, j)
  if unicode and unicode.sub then return unicode.sub(s, i, j) end
  return s:sub(i, j)
end

-- Quebra o texto em linhas de no máximo `width` colunas
local function wrap(text, width)
  width = math.max(4, width)
  local out = {}
  for para in (text .. "\n"):gmatch("([^\n]*)\n") do
    local line = ""
    for word in para:gmatch("%S+") do
      while len(word) > width do
        if line ~= "" then out[#out + 1] = line; line = "" end
        out[#out + 1] = usub(word, 1, width)
        word = usub(word, width + 1)
      end
      if line == "" then
        line = word
      elseif len(line) + 1 + len(word) <= width then
        line = line .. " " .. word
      else
        out[#out + 1] = line
        line = word
      end
    end
    out[#out + 1] = line
  end
  return out
end

local function newThreads(user)
  return {
    {
      name = "Plasma Sistema", preview = "Oi!",
      msgs = {
        { text = "Bem-vindo(a), " .. user .. "!", mine = false },
        { text = "Seu sistema está pronto.", mine = false },
        { text = "Oi!", mine = true },
      },
    },
    {
      name = "Dicas", preview = "Ajustes tem fundo de tela e energia.",
      msgs = {
        { text = "Use o Finder para explorar arquivos.", mine = false },
        { text = "Ajustes tem fundo de tela e energia.", mine = false },
      },
    },
  }
end

-- Estado da conversa (criado na primeira vez que o app é usado)
local function ensure(win, ctx)
  if not win.state then
    win.state = {
      sel = 1, draft = "", reply = nil,
      threads = newThreads(ctx.user or "você"),
    }
  end
  return win.state
end

local function send(s)
  local text = s.draft:match("^%s*(.-)%s*$")
  if text == "" then return end
  local th = s.threads[s.sel]
  th.msgs[#th.msgs + 1] = { text = text, mine = true }
  th.preview = text
  s.draft = ""
  s.reply = { sel = s.sel, at = computer.uptime() + 1.2 }
end

return {
  name = "Mensagens", letter = "M", color = 0x27AE60,

  init = function(win, ctx)
    ensure(win, ctx or {})
  end,

  draw = function(win, b, g, ctx)
    local s = ensure(win, ctx)

    -- resposta automática chegando
    if s.reply and computer.uptime() >= s.reply.at then
      local th = s.threads[s.reply.sel]
      if th then
        th.msgs[#th.msgs + 1] = { text = "Recebido.", mine = false }
        th.preview = "Recebido."
      end
      s.reply = nil
    end

    g.fill(b.x, b.y, b.w, b.h, CHATBG)
    if b.h < 6 or b.w < SIDE + 12 then return end

    -- barra lateral com as conversas
    g.fill(b.x, b.y, SIDE, b.h, SIDEBG)
    g.fill(b.x + SIDE, b.y, 1, b.h, SEP)
    g.text(b.x + 1, b.y, "Conversas", DIM, SIDEBG)
    local ry = b.y + 2
    for i, th in ipairs(s.threads) do
      if ry + 1 < b.y + b.h then
        local sel = (i == s.sel)
        local bg = sel and SELBG or SIDEBG
        g.fill(b.x, ry, SIDE, 2, bg)
        g.text(b.x + 1, ry, g.clip(th.name, SIDE - 2), sel and 0xFFFFFF or INK, bg)
        g.text(b.x + 1, ry + 1, g.clip(th.preview, SIDE - 2), sel and 0xDCEBFF or DIM, bg)
      end
      ry = ry + 3
    end

    -- cabeçalho da conversa
    local cx = b.x + SIDE + 1
    local cw = b.w - SIDE - 1
    local th = s.threads[s.sel]
    g.fill(cx, b.y, cw, 1, HEADBG)
    g.text(cx + math.max(0, math.floor((cw - len(th.name)) / 2)), b.y, th.name, INK, HEADBG)
    g.fill(cx, b.y + 1, cw, 1, SEP)

    -- campo de envio (duas últimas linhas)
    local inputY = b.y + b.h - 2
    local sepY = inputY - 1
    g.fill(cx, sepY, cw, 1, SEP)
    g.fill(cx, inputY, cw, 1, CHATBG)
    local fieldW = cw - 11
    g.fill(cx + 1, inputY, fieldW, 1, FIELDBG)
    if s.draft == "" then
      g.text(cx + 2, inputY, "Mensagem", 0xAEAEB2, FIELDBG)
    else
      local shown = s.draft .. "_"
      local maxw = fieldW - 2
      if len(shown) > maxw then shown = usub(shown, len(shown) - maxw + 1) end
      g.text(cx + 2, inputY, shown, INK, FIELDBG)
    end
    local bx = cx + cw - 9
    g.fill(bx, inputY, 8, 1, MINE)
    g.text(bx + 1, inputY, "Enviar", MINE_FG, MINE)

    -- mensagens, da mais nova para a mais antiga, de baixo para cima
    local top = b.y + 2
    local bottom = sepY - 1
    local maxBW = math.max(10, math.floor(cw * 0.7))
    local y = bottom
    for mi = #th.msgs, 1, -1 do
      if y < top then break end
      local m = th.msgs[mi]
      local lines = wrap(m.text, maxBW - 2)
      local bw = 0
      for _, ln in ipairs(lines) do
        if len(ln) > bw then bw = len(ln) end
      end
      bw = bw + 2
      local bgc = m.mine and MINE or THEIRS
      local fgc = m.mine and MINE_FG or THEIRS_FG
      local bxm = m.mine and (cx + cw - bw - 1) or (cx + 1)
      for li = #lines, 1, -1 do
        if y < top then break end
        g.fill(bxm, y, bw, 1, bgc)
        g.text(bxm + 1, y, lines[li], fgc, bgc)
        y = y - 1
      end
      y = y - 1  -- espaço entre mensagens
    end
  end,

  touch = function(win, b, x, y, ctx)
    local s = ensure(win, ctx)

    -- barra lateral: troca de conversa
    if x < b.x + SIDE then
      local rel = y - (b.y + 2)
      if rel >= 0 and rel % 3 < 2 then
        local i = math.floor(rel / 3) + 1
        if s.threads[i] then s.sel = i end
      end
      return
    end

    -- botão Enviar
    local cx = b.x + SIDE + 1
    local cw = b.w - SIDE - 1
    local inputY = b.y + b.h - 2
    if y == inputY and x >= cx + cw - 9 then
      send(s)
    end
  end,

  key = function(win, ch, code, ctx)
    local s = ensure(win, ctx)
    if code == 28 or code == 156 then              -- Enter
      send(s)
    elseif code == 14 then                         -- Backspace
      if s.draft ~= "" then s.draft = usub(s.draft, 1, len(s.draft) - 1) end
    elseif code == 200 then                        -- ↑
      s.sel = math.max(1, s.sel - 1)
    elseif code == 208 then                        -- ↓
      s.sel = math.min(#s.threads, s.sel + 1)
    elseif ch and ch >= 32 and ch < 127 and len(s.draft) < 200 then
      s.draft = s.draft .. string.char(ch)
    end
  end,
}
