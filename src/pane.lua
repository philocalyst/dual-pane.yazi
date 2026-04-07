






local Pane_mt

local function Pane_layout(self)
   self._chunks = ui.Layout():
   direction(ui.Layout.VERTICAL):
   constraints({
      ui.Constraint.Length(1),
      ui.Constraint.Fill(1),
   }):
   split(self._area)
end

local function Pane_build(self, tab, pane_index)
   local hdr = Header.new(self._chunks[1], tab)
   hdr.pane = pane_index
   self._children = {
      hdr,
      Tab.new(self._chunks[2], tab),
   }
end

local function Pane_new(_, area, tab, pane_index)
   local me = setmetatable({ _area = area }, Pane_mt)
   Pane_layout(me)
   Pane_build(me, tab, pane_index)
   return me
end

Pane_mt = { __index = Root }

local PaneObj = setmetatable({}, Pane_mt);
(PaneObj).new = Pane_new

local M = {}




M.Pane_new = Pane_new
M.PaneObj = PaneObj

return M
