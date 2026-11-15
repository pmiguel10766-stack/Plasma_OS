-- Plasma OS - Finder: navega pelas pastas do disco de boot
local function listDir(ctx, p)
  local ok, t = pcall(ctx.fs.list, p)
  if ok and type(t) == "table" then table.sort(t) return t end
  return {}
end

return {
  name = "Finder", letter = "F", color = 0x3A8FD9,

  init = function(win)
    win.state = win.state or { path = "/", sel = nil }
  end,

  draw = function(win, b, g, ctx)
    local s = win.state
    local BAR = 0xF5F5F7
    g.fill(b.x, b.y, b.w, b.h, 0xFFFFFF)
    g.fill(b.x, b.y, b.w, 1, BAR)
    g.text(b.x + 1, b.y, "< Voltar", 0x0A84FF, BAR)
    g.text(b.x + 11, b.y, g.clip(s.path, b.w - 12), 0x86868B, BAR)

    local items = listDir(ctx, s.path)
    local rows = b.h - 3
    for i = 1, math.min(#items, rows) do
      local name = items[i]
      local y = b.y + 1 + i
      local isDir = name:sub(-1) == "/"
      local bg = (name == s.sel) and 0xDCEBFF or 0xFFFFFF
      g.fill(b.x, y, b.w, 1, bg)
      g.fill(b.x + 1, y, 2, 1, isDir and 0xF2C94C or 0xBDBDBD)
      local label = isDir and name:sub(1, -2) or name
      g.text(b.x + 4, y, g.clip(label, b.w - 6), 0x1D1D1F, bg)
    end
    if #items == 0 then
      g.text(b.x + 2, b.y + 3, "Pasta vazia.", 0x86868B, 0xFFFFFF)
    end
    g.text(b.x + 1, b.y + b.h - 1, #items .. " itens", 0x86868B, 0xFFFFFF)
  end,

  touch = function(win, b, x, y, ctx)
    local s = win.state
    if y == b.y then
      if x < b.x + 10 and s.path ~= "/" then
        local p = s.path:gsub("/$", "")
        s.path = p:match("^(.*/)[^/]*$") or "/"
        if s.path == "" then s.path = "/" end
        s.sel = nil
      end
      return
    end
    local items = listDir(ctx, s.path)
    local idx = y - (b.y + 1)
    if idx < 1 or idx > #items or idx > b.h - 3 then return end
    local name = items[idx]
    if name:sub(-1) == "/" then
      s.path = s.path .. name
      s.sel = nil
    else
      s.sel = name
    end
  end,
}
