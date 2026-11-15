-- Plasma OS - Fotos: lista imagens .pic em /PlasmaOS/fotos
local function listPics(ctx)
  local ok, t = pcall(ctx.fs.list, "/PlasmaOS/fotos/")
  local out = {}
  if ok and type(t) == "table" then
    for _, name in ipairs(t) do
      if name:match("%.pic$") then out[#out + 1] = name:sub(1, -5) end
    end
  end
  table.sort(out)
  return out
end

return {
  name = "Fotos", letter = "P", color = 0x9B51E0,

  draw = function(win, b, g, ctx)
    g.fill(b.x, b.y, b.w, b.h, 0xFFFFFF)
    local pics = listPics(ctx)

    if #pics == 0 then
      -- estado vazio: uma montanha desenhada com blocos
      local cx = b.x + math.floor(b.w / 2)
      local top = b.y + math.floor(b.h / 2) - 3
      for row = 0, 4 do
        local ww = row * 2 + 1
        g.fill(cx - row, top + row, ww, 1, row < 2 and 0xC9D6E2 or 0x7F8C8D)
      end
      g.fill(b.x, top + 5, b.w, 1, 0xDCE7D3)
      local msg = "Nenhuma foto encontrada"
      g.text(b.x + math.floor((b.w - #msg) / 2), top + 7, msg, 0x86868B, 0xFFFFFF)
      return
    end

    local cardW, cardH = 14, 4
    local perRow = math.max(1, math.floor(b.w / (cardW + 1)))
    for i, name in ipairs(pics) do
      local col = (i - 1) % perRow
      local row = math.floor((i - 1) / perRow)
      local x = b.x + 1 + col * (cardW + 1)
      local y = b.y + 1 + row * (cardH + 1)
      if y + cardH <= b.y + b.h then
        g.fill(x, y, cardW, cardH - 1, 0x9B51E0)
        g.text(x + 1, y + cardH - 1, g.clip(name, cardW - 2), 0x1D1D1F, 0xFFFFFF)
      end
    end
  end,
}
