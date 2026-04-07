local pane_mod = require("pane")
local Pane_new = pane_mod.Pane_new
local PaneObj = pane_mod.PaneObj

local Panes_mt

local function Panes_layout(self)
   self._chunks = ui.Layout():
   direction(ui.Layout.VERTICAL):
   constraints({
      ui.Constraint.Fill(1),
      ui.Constraint.Length(1),
   }):
   split(self._area)

   self._panes_chunks = ui.Layout():
   direction(ui.Layout.HORIZONTAL):
   constraints({
      ui.Constraint.Percentage(50),
      ui.Constraint.Percentage(50),
   }):
   split(self._chunks[1])
end

local function Panes_build(self, tab_left, tab_right)
   self._children = {
      Pane_new(PaneObj, self._panes_chunks[1], tab_left, 1),
      Pane_new(PaneObj, self._panes_chunks[2], tab_right, 2),
      Status.new(Status, self._chunks[2], cx.active),
   }
end

local function Panes_new(_, area, tab_left, tab_right)
   local me = setmetatable({ _area = area }, Panes_mt)
   Panes_layout(me)
   Panes_build(me, tab_left, tab_right)
   return me
end

Panes_mt = { __index = Root }

local PanesObj = setmetatable({}, Panes_mt);
(PanesObj).new = Panes_new

local M = {}




M.Panes_new = Panes_new
M.PanesObj = PanesObj

return M
