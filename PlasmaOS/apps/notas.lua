-- Plasma OS - Notas: estilo Notas do OS X Yosemite
-- Várias notas em /PlasmaOS/notas.txt, na barra lateral. Papel pautado, setas movem o cursor.
-- Ctrl+S salva. Clique numa nota para abrir; "+ Nova" cria outra; "Apagar" remove a atual.

local PATH = "/PlasmaOS/notas.txt"
local SEP  = "@@NOTA@@"          -- linha que separa uma nota da outra no arquivo

local BAR, PAPER, SIDEBG = 0xFFF8D6, 0xFFFDF2, 0xF5EFD0
local SELBG, RULE, MARGIN = 0xF2C94C, 0xE8DFC0, 0xF4B6B0
local INK, DIM, WHITE, SEP_C = 0x1D1D1F, 0x86868B, 0xFFFFFF, 0xDCD2A8
local BTN, BTN_OFF = 0xF2C94C, 0xE5E5EA
local CURSOR_BG = 0x1D1D1F
local SIDE = 17

local function len(s)
  if unicode and unicode.len then return unicode.len(s) end
  return #s
end

local function usub(s, i, j)
  if unicode and unicode.sub then return unicode.sub(s, i, j) end
  return s:sub(i, j)
end

-- Arquivo -----------------------------------------------------------------

local function splitLines(text)
  local out = {}
  for line in (text .. "\n"):gmatch("(.-)\n") do out[#out + 1] = line end
  if #out == 0 then out[1] = "" end
  return out
end

local function readAll(ctx)
  if not ctx.fs.exists(PATH) then return nil end
  local h = ctx.fs.open(PATH, "r")
  if not h then return nil end
  local parts = {}
  repeat
    local chunk = ctx.fs.read(h, math.huge)
    if chunk then parts[#parts + 1] = chunk end
  until not chunk
  ctx.fs.close(h)
  return table.concat(parts)
end

-- Lê o arquivo e devolve a lista de notas (cada uma como lista de linhas)
local function loadNotes(ctx)
  local notes = {}
  local raw = readAll(ctx) or ""
  local chunk = {}
  for line in (raw .. "\n"):gmatch("(.-)\n") do
    if line == SEP then
      notes[#notes + 1] = { lines = chunk }
      chunk = {}
    else
      chunk[#chunk + 1] = line
    end
  end
  notes[#notes + 1] = { lines = chunk }
  -- descarta a nota vazia que sobra quando o arquivo termina com quebra de linha
  if #notes > 1 and #notes[#notes].lines == 1 and notes[#notes].lines[1] == "" then
    notes[#notes] = nil
  end
  for _, n in ipairs(notes) do
    if #n.lines == 0 then n.lines = { "" } end
  end
  return notes
end

local function saveNotes(s, ctx)
  local texts = {}
  for i, n in ipairs(s.notes) do texts[i] = table.concat(n.lines, "\n") end
  local data = table.concat(texts, "\n" .. SEP .. "\n")
  local h, err = ctx.fs.open(PATH, "w")
  if not h then
    s.status = "Erro ao salvar: " .. tostring(err)
    return
  end
  local ok, werr = ctx.fs.write(h, data)
  ctx.fs.close(h)
  if not ok then
    s.status = "Erro ao gravar: " .. tostring(werr)
    return
  end
  s.dirty = false
  s.status = "Salvo"
end

-- Estado ------------------------------------------------------------------

local function ensure(win, ctx)
  local s = win.state
  if not s then
    local notes = loadNotes(ctx)
    s = { notes = notes, sel = 1, cy = 1, cx = 0, top = 1, left = 0,
          dirty = false, status = "" }
    win.state = s
  end
  return s
end

local function curLines(s)
  return s.notes[s.sel].lines
end

local function resetCursor(s)
  s.cy, s.cx, s.top, s.left = 1, 0, 1, 0
end

local function switchTo(s, i)
  if i < 1 or i > #s.notes or i == s.sel then return end
  s.sel = i
  resetCursor(s)
end

local function newNote(s)
  s.notes[#s.notes + 1] = { lines = { "" } }
  s.sel = #s.notes
  resetCursor(s)
  s.dirty = true
  s.status = ""
end

local function deleteNote(s)
  if #s.notes == 1 then
    s.notes[1] = { lines = { "" } }
  else
    table.remove(s.notes, s.sel)
    s.sel = math.min(s.sel, #s.notes)
  end
  resetCursor(s)
  s.dirty = true
  s.status = ""
end

local function clampCx(s)
  local L = curLines(s)
  s.cx = math.max(0, math.min(s.cx, len(L[s.cy])))
end

local function insertText(s, text)
  local L = curLines(s)
  local line = L[s.cy]
  L[s.cy] = usub(line, 1, s.cx) .. text .. usub(line, s.cx + 1)
  s.cx = s.cx + len(text)
  s.dirty = true
end

local function titleOf(note)
  for _, l in ipairs(note.lines) do
    local t = l:match("^%s*(.-)%s*$")
    if t ~= "" then return t end
  end
  return "Nova nota"
end

local function previewOf(note)
  local found = 0
  for _, l in ipairs(note.lines) do
    local t = l:match("^%s*(.-)%s*$")
    if t ~= "" then
      found = found + 1
      if found == 2 then return t end
    end
  end
  return "Sem texto adicional"
end

local function dateText()
  local ok, s = pcall(os.date, "%d/%m/%Y  %H:%M")
  if ok and s then return s end
  return ""
end

-- Desenho -----------------------------------------------------------------

local function tbtn(g, x, y, w, label, bg, fg)
  g.fill(x, y, w, 1, bg)
  g.text(x + math.max(0, math.floor((w - len(label)) / 2)), y, label, fg, bg)
end

return {
  name = "Notas", letter = "N", color = 0xF2C94C,

  init = function(win, ctx)
    ensure(win, ctx or {})
  end,

  draw = function(win, b, g, ctx)
    local s = ensure(win, ctx)
    g.fill(b.x, b.y, b.w, b.h, PAPER)
    if b.h < 6 or b.w < SIDE + 16 then return end

    -- barra superior
    g.fill(b.x, b.y, b.w, 1, BAR)
    g.fill(b.x, b.y + 1, b.w, 1, SEP_C)
    tbtn(g, b.x + 1, b.y, 9, "+ Nova", BTN, INK)
    tbtn(g, b.x + 11, b.y, 9, "Apagar", BTN_OFF, INK)
    tbtn(g, b.x + b.w - 11, b.y, 10, "Salvar", s.dirty and BTN or BTN_OFF, INK)
    local status = s.status ~= "" and s.status or (s.dirty and "Alterações não salvas" or "")
    local sx = b.x + 22
    local sw = b.w - 34
    if sw > 4 then
      g.text(sx, b.y, g.clip(status, sw), DIM, BAR)
    end

    -- barra lateral com as notas
    local ly0 = b.y + 3
    g.fill(b.x, b.y + 2, SIDE, b.h - 2, SIDEBG)
    g.fill(b.x + SIDE, b.y + 2, 1, b.h - 2, SEP_C)
    local ry = b.y + 2
    for i, note in ipairs(s.notes) do
      if ry + 1 < b.y + b.h then
        local sel = (i == s.sel)
        local bg = sel and SELBG or SIDEBG
        g.fill(b.x, ry, SIDE, 2, bg)
        g.text(b.x + 1, ry, g.clip(titleOf(note), SIDE - 2), INK, bg)
        g.text(b.x + 1, ry + 1, g.clip(previewOf(note), SIDE - 2), sel and INK or DIM, bg)
      end
      ry = ry + 2
    end

    -- papel pautado
    local ex = b.x + SIDE + 1
    local ew = b.w - SIDE - 1
    local textX = ex + 3
    local textW = ew - 4
    g.fill(ex, b.y + 2, ew, b.h - 2, PAPER)
    g.text(textX, b.y + 2, g.clip(dateText(), textW), DIM, PAPER)
    g.fill(ex + 1, b.y + 3, 1, b.h - 3, MARGIN)

    local nvis = math.max(1, math.floor((b.y + b.h - ly0) / 2))
    local L = curLines(s)

    -- acompanha o cursor
    if s.cy < s.top then s.top = s.cy end
    if s.cy > s.top + nvis - 1 then s.top = s.cy - nvis + 1 end
    if s.cx < s.left then s.left = s.cx end
    if s.cx > s.left + textW - 1 then s.left = s.cx - textW + 1 end
    s.top = math.max(1, s.top)
    s.left = math.max(0, s.left)

    for r = 0, nvis - 1 do
      local li = s.top + r
      local y = ly0 + r * 2
      if y >= b.y + b.h then break end
      if li <= #L then
        local line = L[li]
        g.text(textX, y, usub(line, s.left + 1, s.left + textW), INK, PAPER)
        if li == s.cy then
          local colX = s.cx - s.left
          if colX >= 0 and colX < textW then
            local ch = usub(line, s.cx + 1, s.cx + 1)
            if ch == "" then ch = " " end
            g.text(textX + colX, y, ch, WHITE, CURSOR_BG)
          end
        end
      end
      if y + 1 < b.y + b.h then
        g.text(ex + 2, y + 1, string.rep("─", ew - 3), RULE, PAPER)
      end
    end
  end,

  touch = function(win, b, x, y, ctx)
    local s = ensure(win, ctx)

    -- barra superior
    if y == b.y then
      if x >= b.x + 1 and x <= b.x + 9 then
        newNote(s)
      elseif x >= b.x + 11 and x <= b.x + 19 then
        deleteNote(s)
      elseif x >= b.x + b.w - 11 then
        saveNotes(s, ctx)
      end
      return
    end
    if y == b.y + 1 then return end

    -- barra lateral: abre a nota clicada
    if x < b.x + SIDE then
      local rel = y - (b.y + 2)
      if rel >= 0 and rel % 2 == 0 then
        local i = math.floor(rel / 2) + 1
        if s.notes[i] then
          switchTo(s, i)
        end
      end
      return
    end

    -- papel: cursor vai para a linha clicada (só nas linhas de texto)
    local ex = b.x + SIDE + 1
    local textX = ex + 3
    local ly0 = b.y + 3
    local rel = y - ly0
    if rel < 0 or rel % 2 ~= 0 then return end
    local li = s.top + math.floor(rel / 2)
    local L = curLines(s)
    if li < 1 or li > #L then return end
    s.cy = li
    s.cx = math.max(0, x - textX + s.left)
    clampCx(s)
  end,

  key = function(win, ch, code, ctx)
    local s = ensure(win, ctx)
    local L = curLines(s)

    if ch == 19 then                                   -- Ctrl+S
      saveNotes(s, ctx)
      return
    end
    local line = L[s.cy]

    if code == 200 then                                -- ↑
      if s.cy > 1 then s.cy = s.cy - 1; clampCx(s) end
    elseif code == 208 then                            -- ↓
      if s.cy < #L then s.cy = s.cy + 1; clampCx(s) end
    elseif code == 203 then                            -- ←
      if s.cx > 0 then
        s.cx = s.cx - 1
      elseif s.cy > 1 then
        s.cy = s.cy - 1
        s.cx = len(L[s.cy])
      end
    elseif code == 205 then                            -- →
      if s.cx < len(line) then
        s.cx = s.cx + 1
      elseif s.cy < #L then
        s.cy = s.cy + 1
        s.cx = 0
      end
    elseif code == 199 then s.cx = 0                   -- Home
    elseif code == 207 then s.cx = len(line)           -- End
    elseif code == 28 or code == 156 then              -- Enter
      local left = usub(line, 1, s.cx)
      local right = usub(line, s.cx + 1)
      L[s.cy] = left
      table.insert(L, s.cy + 1, right)
      s.cy = s.cy + 1
      s.cx = 0
      s.dirty = true
    elseif code == 14 then                             -- Backspace
      if s.cx > 0 then
        L[s.cy] = usub(line, 1, s.cx - 1) .. usub(line, s.cx + 1)
        s.cx = s.cx - 1
        s.dirty = true
      elseif s.cy > 1 then
        local prev = L[s.cy - 1]
        s.cx = len(prev)
        L[s.cy - 1] = prev .. line
        table.remove(L, s.cy)
        s.cy = s.cy - 1
        s.dirty = true
      end
    elseif code == 211 then                            -- Delete
      if s.cx < len(line) then
        L[s.cy] = usub(line, 1, s.cx) .. usub(line, s.cx + 2)
        s.dirty = true
      elseif s.cy < #L then
        L[s.cy] = line .. L[s.cy + 1]
        table.remove(L, s.cy + 1)
        s.dirty = true
      end
    elseif ch == 9 then
      insertText(s, "  ")
    elseif ch and ch >= 32 and ch < 127 then
      insertText(s, string.char(ch))
    elseif ch and ch >= 128 and unicode and unicode.char then
      local ok, c = pcall(unicode.char, ch)
      if ok then insertText(s, c) end
    end
    s.status = ""
  end,
}
