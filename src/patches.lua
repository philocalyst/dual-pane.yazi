local panes_mod = require("panes")
local pane_mod = require("pane")
local Panes_new = panes_mod.Panes_new
local PanesObj = panes_mod.PanesObj
local Pane_new = pane_mod.Pane_new
local PaneObj = pane_mod.PaneObj

local M = { SavedConfig = {}, SavedMethods = {}, DualPane = {} }



























local function verify_tabs(dp)
   for i = 1, #dp.tabs do
      if (cx.tabs[dp.tabs[i]]) == nil then
         dp.tabs[i] = cx.tabs.idx
      end
   end
end

local function config_dual_pane(dp)
   Root.layout = function(root)
      root._chunks = ui.Layout():
      direction(ui.Layout.HORIZONTAL):
      constraints({ ui.Constraint.Percentage(100) }):
      split(root._area)
   end

   Root.build = function(root)
      verify_tabs(dp)
      root._children = {
         Panes_new(PanesObj, root._chunks[1],
         cx.tabs[dp.tabs[1]], cx.tabs[dp.tabs[2]]),
      }
   end
end

local function config_single_pane(dp)
   Root.layout = function(root)
      root._chunks = ui.Layout():
      direction(ui.Layout.VERTICAL):
      constraints({
         ui.Constraint.Fill(1),
         ui.Constraint.Length(1),
      }):
      split(root._area)
   end

   Root.build = function(root)
      verify_tabs(dp)
      local tab = cx.tabs[dp.tabs[dp.pane]]
      root._children = {
         Pane_new(PaneObj, root._chunks[1], tab, dp.pane),
         Status.new(Status, root._chunks[2], tab),
      }
   end
end

local function patch_header_cwd(dp)
   Header.cwd = function(header)
      local max = header._area.w - header._right_width
      if max <= 0 then return ui.Span("") end

      local s = ya.readable_path(tostring(header._tab.current.cwd)) .. header:flags()
      local style = (header.pane == dp.pane) and
      THEME.manager.tab_active or
      THEME.manager.tab_inactive

      return ui.Span(ya.truncate(s, { max = max, rtl = true })):style(style)
   end
end

local function patch_header_tabs(dp)
   Header.tabs = function(header)
      local n = #cx.tabs
      if n == 1 then return ui.Line({}) end

      local active = dp.tabs[header.pane]
      local spans = {}
      for i = 1, n do
         local text
         if THEME.manager.tab_width > 2 then
            text = ya.truncate(
            tostring(i) .. " " .. cx.tabs[i]:name(),
            { max = THEME.manager.tab_width })
         else
            text = tostring(i)
         end

         local style = (i == active) and
         THEME.manager.tab_active or
         THEME.manager.tab_inactive
         spans[#spans + 1] = ui.Span(" " .. text .. " "):style(style)
      end
      return ui.Line(spans)
   end
end

local function patch_tab_layout()
   Tab.layout = function(self)
      self._chunks = ui.Layout():
      direction(ui.Layout.HORIZONTAL):
      constraints({
         ui.Constraint.Percentage(0),
         ui.Constraint.Percentage(100),
         ui.Constraint.Percentage(0),
      }):
      split(self._area)
   end
end

local function save_methods()
   return {
      root_layout = Root.layout,
      root_build = Root.build,
      tab_layout = Tab.layout,
      header_cwd = Header.cwd,
      header_tabs = Header.tabs,
   }
end

local function restore_methods(saved)
   Root.layout = saved.root_layout
   Root.build = saved.root_build
   Tab.layout = saved.tab_layout
   Header.cwd = saved.header_cwd
   Header.tabs = saved.header_tabs
end

local function DualPane_create()
   local dp = {
      pane = 1,
      tabs = {},
      view = nil,
      saved = nil,
   }

   if cx then
      dp.tabs[1] = cx.tabs.idx
      dp.tabs[2] = (#cx.tabs > 1) and
      cx.tabs.idx % #cx.tabs + 1 or
      cx.tabs.idx
   else
      dp.tabs = { 1, 1 }
   end

   dp.saved = save_methods()
   config_dual_pane(dp)
   patch_header_cwd(dp)
   patch_header_tabs(dp)
   patch_tab_layout()
   dp.view = "dual"

   return dp
end


return M
