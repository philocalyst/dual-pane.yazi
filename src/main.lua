--- @sync entry

-- The dual-pane state: nil when inactive.
local dual_pane = nil

-- Saved Root/Tab/Header methods for restoration.
local saved = nil

-- A single pane: one header row above one file-list column.
local Pane = {}
Pane.__index = Pane

function Pane:new(area, tab, index)
	local chunks = ui.Layout()
		:direction(ui.Layout.VERTICAL)
		:constraints({ ui.Constraint.Length(1), ui.Constraint.Fill(1) })
		:split(area)

	local hdr = Header:new(chunks[1], tab)
	hdr._pane = index

	return setmetatable({
		_id = "pane",
		_area = area,
		_children = { hdr, Tab:new(chunks[2], tab) },
	}, self)
end

function Pane:reflow()
	local items = { self }
	for _, child in ipairs(self._children) do
		items = ya.list_merge(items, child:reflow())
	end
	return items
end

function Pane:redraw()
	local items = {}
	for _, child in ipairs(self._children) do
		items = ya.list_merge(items, ui.redraw(child))
	end
	return items
end

-- Mirror mouse events
function Pane:click(event, up) end

function Pane:scroll(event, step) end

function Pane:touch(event, step) end

-- The panes share a status bar
local Panes = {}
Panes.__index = Panes

function Panes:new(area, tab_left, tab_right)
	local chunks = ui.Layout()
		:direction(ui.Layout.VERTICAL)
		:constraints({ ui.Constraint.Fill(1), ui.Constraint.Length(1) })
		:split(area)

	local pane_chunks = ui.Layout()
		:direction(ui.Layout.HORIZONTAL)
		:constraints({ ui.Constraint.Percentage(50), ui.Constraint.Percentage(50) })
		:split(chunks[1])

	return setmetatable({
		_id = "panes",
		_area = area,
		_children = {
			Pane:new(pane_chunks[1], tab_left, 1),
			Pane:new(pane_chunks[2], tab_right, 2),
			Status:new(chunks[2], cx.active),
		},
	}, self)
end

function Panes:reflow()
	local items = { self }

	for _, child in ipairs(self._children) do
		items = ya.list_merge(items, child:reflow())
	end

	return items
end

function Panes:redraw()
	local items = {}

	for _, child in ipairs(self._children) do
		items = ya.list_merge(items, ui.redraw(child))
	end

	return items
end

-- Handle el mousse
function Panes:click(event, up) end

function Panes:scroll(event, step) end

function Panes:touch(event, step) end

-- Ensure both tracked tab indices remain in existence.
-- dual_pane.pending marks a pane index whose tab is being created asynchronously
-- we prevent a reset until the tab ACTUALLY appears in cx.tabs.
local function verify_tabs()
	for i = 1, #dual_pane.tabs do
		if cx.tabs[dual_pane.tabs[i]] then
			if dual_pane.pending == i then
				dual_pane.pending = nil
			end
		elseif dual_pane.pending ~= i then
			dual_pane.tabs[i] = cx.tabs.idx
		end
	end
end

-- Patching the Root/Tab/Header for the view.
local function patch_dual()
	Root.layout = function(self)
		self._chunks = ui.Layout()
			:direction(ui.Layout.HORIZONTAL)
			:constraints({ ui.Constraint.Percentage(100) })
			:split(self._area)
	end

	Root.build = function(self)
		verify_tabs()
		self._children = {
			Panes:new(self._chunks[1], cx.tabs[dual_pane.tabs[1]], cx.tabs[dual_pane.tabs[2]]),
			Modal:new(self._area),
		}
	end

	-- Hide parent and preview columns, focusing on just files
	Tab.layout = function(self)
		self._chunks = ui.Layout()
			:direction(ui.Layout.HORIZONTAL)
			:constraints({
				ui.Constraint.Percentage(0),
				ui.Constraint.Percentage(100),
				ui.Constraint.Percentage(0),
			})
			:split(self._area)
	end

	-- Highlight the active pane's cwd, and dim the inactive.
	Header.cwd = function(self)
		local max = self._area.w - self._right_width

		if max <= 0 then
			return ""
		end

		local s = ya.readable_path(tostring(self._current.cwd)) .. self:flags()
		local theme = self._pane == dual_pane.pane and th.tabs.active or th.tabs.inactive

		return ui.Span(ui.truncate(s, { max = max, rtl = true })):style(ui.Style():patch(theme))
	end
end

-- Patch Root for a single focused pane; restore Tab and Header to defaults.
local function patch_zoom()
	Root.layout = function(self)
		self._chunks = ui.Layout()
			:direction(ui.Layout.VERTICAL)
			:constraints({ ui.Constraint.Fill(1), ui.Constraint.Length(1) })
			:split(self._area)
	end

	Root.build = function(self)
		verify_tabs()

		local tab = cx.tabs[dual_pane.tabs[dual_pane.pane]]
		local chunks = ui.Layout()
			:direction(ui.Layout.VERTICAL)
			:constraints({ ui.Constraint.Length(1), ui.Constraint.Fill(1) })
			:split(self._chunks[1])

		local hdr = Header:new(chunks[1], tab)
		hdr._pane = dual_pane.pane

		self._children = {
			hdr,
			Tab:new(chunks[2], tab),
			Status:new(self._chunks[2], tab),
			Modal:new(self._area),
		}
	end

	-- Restore the original three-column Tab layout and cwd style.
	Tab.layout = saved.tab_layout
	Header.cwd = saved.header_cwd
end

local function save_methods()
	return {
		root_layout = Root.layout,
		root_build = Root.build,
		tab_layout = Tab.layout,
		header_cwd = Header.cwd,
	}
end

local function restore_methods()
	Root.layout = saved.root_layout
	Root.build = saved.root_build
	Tab.layout = saved.tab_layout
	Header.cwd = saved.header_cwd
	saved = nil
end

local function toggle()
	if dual_pane then
		restore_methods()
		dual_pane = nil
	else
		saved = save_methods()

		local idx1 = cx.tabs.idx
		local idx2, pending

		if #cx.tabs >= 2 then
			idx2 = idx1 % #cx.tabs + 1
		else
			-- No second tab just yet; create one and wait for it to appear.
			idx2 = idx1 + 1
			pending = 2
			ya.emit("tab_create", { tostring(cx.active.current.cwd) })
		end

		dual_pane = { pane = 1, view = "dual", tabs = { idx1, idx2 }, pending = pending }
		patch_dual()
	end
end

local function toggle_zoom()
	if not dual_pane then
		return
	end
	if dual_pane.view == "dual" then
		patch_zoom()
		dual_pane.view = "zoom"
	else
		patch_dual()
		dual_pane.view = "dual"
	end
end

local function next_pane()
	if not dual_pane then
		return
	end
	dual_pane.pane = dual_pane.pane % 2 + 1
	ya.emit("tab_switch", { dual_pane.tabs[dual_pane.pane] - 1 })
end

local function copy_files(cut, force, follow)
	if not dual_pane then
		return
	end

	local source = dual_pane.tabs[dual_pane.pane]
	local destination = dual_pane.tabs[dual_pane.pane % 2 + 1]

	ya.emit("yank", { cut = cut })
	ya.emit("tab_switch", { destination - 1 })
	ya.emit("paste", { force = force, follow = follow })
	ya.emit("unyank", {})
	ya.emit("tab_switch", { source - 1 })
end

local function tab_switch(by_number)
	if dual_pane then
		dual_pane.tabs[dual_pane.pane] = by_number
	end

	ya.emit("tab_switch", { by_number - 1 })
end

local function tab_create(target_directory)
	if target_directory then
		local path = target_directory == "--current" and tostring(cx.active.current.cwd) or target_directory

		ya.emit("tab_create", { path })
	else
		ya.emit("tab_create", {})
	end
	if dual_pane then
		-- Shift the other pane's index if it was after the newly inserted tab.
		local other = dual_pane.pane % 2 + 1

		if dual_pane.tabs[other] > dual_pane.tabs[dual_pane.pane] then
			dual_pane.tabs[other] = dual_pane.tabs[other] + 1
		end

		tab_switch(cx.tabs.idx + 1)
	end
end

local M = {}

function M:entry(job)
	local action = job.args[1]
	if action == "toggle" then
		toggle()
	elseif action == "toggle_zoom" then
		toggle_zoom()
	elseif action == "next_pane" then
		next_pane()
	elseif action == "copy_files" or action == "move_files" then
		local force, follow = false, false

		for index = 2, #job.args do
			if job.args[index] == "--force" then
				force = true
			elseif job.args[index] == "--follow" then
				follow = true
			end
		end

		copy_files(action == "move_files", force, follow)
	elseif action == "tab_switch" then
		if job.args[2] then
			local target_index = tonumber(job.args[2])

			if job.args[3] == "--relative" then
				target_index = (cx.tabs.idx - 1 + target_index) % #cx.tabs
			end

			tab_switch(target_index + 1)
		end
	elseif action == "tab_create" then
		tab_create(job.args[2])
	end
end

function M:setup(options)
	if options and options.enabled then
		self:entry({ args = { "toggle" } })
	end
end

return M
