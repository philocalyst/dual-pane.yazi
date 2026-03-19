local record Pane
  _area:     Rect
  _chunks:   {Rect}
  _children: {any}
  pane:      integer
end

local Pane_mt: metatable<Pane>

local function Pane_layout(self: Pane)
  self._chunks = ui.Layout()
    :direction(ui.Layout.VERTICAL)
    :constraints({
      ui.Constraint.Length(1),
      ui.Constraint.Fill(1),
    })
    :split(self._area)
end

local function Pane_build(self: Pane, tab: Tab, pane_index: integer)
  local hdr = Header.new(self._chunks[1], tab)
  hdr.pane = pane_index
  self._children = {
    hdr,
    Tab.new(self._chunks[2], tab),
  }
end

local function Pane_new(_: Pane, area: any, tab: Tab, pane_index: integer): Pane
  local me: Pane = setmetatable({ _area = area } as Pane, Pane_mt)
  Pane_layout(me)
  Pane_build(me, tab, pane_index)
  return me
end

Pane_mt = { __index = Root as any }

local PaneObj: Pane = setmetatable({} as Pane, Pane_mt) as Pane
;(PaneObj as {string:any}).new = Pane_new

local record M
  Pane_new: function(Pane, any, Tab, integer): Pane
  PaneObj:  Pane
end

M.Pane_new = Pane_new
M.PaneObj  = PaneObj

return M
