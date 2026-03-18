local set_state = ya.sync(function(state: PluginState, key: string, value: any)
  (state as {string:any})[key] = value
end)

-- Stores a plain array into state, because tables are not assignable by
-- reference across the sync/async boundary.
local set_state_vector = ya.sync(function(
    state: PluginState, key: string, vector: {integer})
  local arr: {integer} = {}
  for _, v in ipairs(vector) do
    arr[#arr + 1] = v
  end
  (state as {string:any})[key] = arr
end)

local get_state = ya.sync(function(state: PluginState, key: string): any
  return (state as {string:any})[key]
end)

local get_cwd = ya.sync(function(): string
  return tostring(cx.active.current.cwd)
end)

local function notify_error(msg: string)
  ya.notify({ title = "dual-pane", content = msg, timeout = 3, level = "error" })
end

local function get_fzf_choice(filename: string): string
  local permit = ya.hide()
  local cwd    = tostring(get_cwd())

  local child, err = Command("bash")
    :args({ "-c", "cat " .. filename .. " | fzf" })
    :cwd(cwd)
    :stdin(Command.INHERIT)
    :stdout(Command.PIPED)
    :stderr(Command.INHERIT)
    :spawn()

  if not child then
    permit:drop()
    notify_error(string.format(
      "Spawn `fzf` failed with error code %s. Do you have it installed?", err))
    return ""
  end

  local output, read_err = child:wait_with_output()
  permit:drop()

  if not output then
    notify_error(string.format("Cannot read `fzf` output, error code %s", read_err))
    return ""
  end

  local st = output.status as {string:any}
  if not (st.success as boolean) and (st.code as integer) ~= 130 then
    notify_error(string.format("`fzf` exited with error code %s", st.code))
    return ""
  end

  return ((output.stdout as string):gsub("\n$", ""))
end

-- Returns the list of Urls that macro letter refers to, or nil if invalid.
local prepare_urls = ya.sync(function(
    state: PluginState, macro: FileMacro): {Url} | nil

  local pane  = (state.cpane or 1) as integer
  local tabs  = (state.ctabs or {1, 1}) as {integer}
  local this  = cx.tabs[tabs[pane]]
  local other = cx.tabs[tabs[pane % 2 + 1]]

  if macro == "f" then
    if #this.selected > 0 then return this.selected end
    if this.current.hovered ~= nil then
      return { this.current.hovered.url }
    end

  elseif macro == "d" then
    local cwd = this.current.cwd
    if cwd ~= nil then return { cwd } end

  elseif macro == "c" then
    local hov = this.current.hovered
    if hov ~= nil then return { hov.url } end

  elseif macro == "F" then
    if #other.selected > 0 then return other.selected end
    if other.current.hovered ~= nil then
      return { other.current.hovered.url }
    end

  elseif macro == "D" then
    local cwd = other.current.cwd
    if cwd ~= nil then return { cwd } end

  elseif macro == "C" then
    local hov = other.current.hovered
    if hov ~= nil then return { hov.url } end
  end

  return nil
end)

-- Turns a list of Urls into a shell-safe, space-separated string of names
-- according to `modifier`.
local prepare_expansion = ya.sync(function(
    _state: PluginState, urls: {Url}, modifier: UrlModifier): string

  local parts: {string} = {}
  for _, url in ipairs(urls) do
    local name: string
    if modifier == "n" then
      name = url:name() or ""
    elseif modifier == "s" then
      name = url:stem() or ""
    elseif modifier == "e" then
      name = url:ext() or ""
    else
      name = tostring(url)
    end
    parts[#parts + 1] = ya.quote(name)
  end
  -- join with single spaces (trailing space stripped by not adding one)
  return table.concat(parts, " ")
end)

-- Expands all %f/%F/%c/%C/%d/%D macros (and optional :n/:s/:e modifiers)
-- in `cmd`.  Returns "" and emits an error notification on failure.
local expand_macros = ya.sync(function(_state: PluginState, cmd: string): string
  local expanded = ""
  local i = 1

  while i <= #cmd do
    local mi, mj, macro = cmd:find("%%([fFcCdD])", i)
    if not mi then
      -- No more macros — append the rest and stop.
      expanded = expanded .. cmd:sub(i, -1)
      break
    end

    -- Text before this macro
    expanded = expanded .. cmd:sub(i, mi - 1)

    local urls = prepare_urls(macro as FileMacro)
    if urls == nil then
      notify_error(string.format("Invalid macro expansion '%%%s'", macro))
      return ""
    end

    -- Check for a modifier suffix (:n / :s / :e)
    local mod: UrlModifier = ""
    local suffix = cmd:sub(mj + 1, mj + 2)
    local _, _, found_mod = suffix:find(":([nse])")
    if found_mod then
      mod = found_mod as UrlModifier
      i = mj + 4   -- skip past %X:Y
    else
      i = mj + 2   -- skip past %X (1-indexed: mj points at the letter)
    end

    expanded = expanded .. prepare_expansion(urls, mod)
  end

  return expanded
end)

local record Pane
  _area:     any
  _chunks:   {any}
  _children: {any}
  pane:      integer  -- 1 or 2
end

-- Forward-declared so Pane can reference Root's metatable pattern.
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
  -- Header is a global yazi object; we monkey-patch `.pane` onto the instance.
  local hdr = (Header as any).new(self._chunks[1], tab) as Header
  hdr.pane = pane_index
  self._children = {
    hdr,
    (Tab as any).new(self._chunks[2], tab),
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
;(PaneObj as any).new = Pane_new

local function Panes_layout(self: Panes)
  self._chunks = ui.Layout()
    :direction(ui.Layout.VERTICAL)
    :constraints({
      ui.Constraint.Fill(1),
      ui.Constraint.Length(1),
    })
    :split(self._area)

  self._panes_chunks = ui.Layout()
    :direction(ui.Layout.HORIZONTAL)
    :constraints({
      ui.Constraint.Percentage(50),
      ui.Constraint.Percentage(50),
    })
    :split(self._chunks[1])
end

local function Panes_build(self: Panes, tab_left: Tab, tab_right: Tab)
  self._children = {
    Pane_new(PaneObj, self._panes_chunks[1], tab_left,  1),
    Pane_new(PaneObj, self._panes_chunks[2], tab_right, 2),
    Status.new(Status, self._chunks[2], cx.active),
  }
end

local function Panes_new(_: Panes, area: any, tab_left: Tab, tab_right: Tab): Panes
  local me: Panes = setmetatable({ _area = area } as Panes, Panes_mt)
  Panes_layout(me)
  Panes_build(me, tab_left, tab_right)
  return me
end

Panes_mt = { __index = Root as any }

local PanesObj: Panes = setmetatable({} as Panes, Panes_mt) as Panes
;(PanesObj as any).new = Panes_new

local record SavedConfig
  pane:  integer
  tabs:  {integer}
  paths: {{string:string}}
end

-- Saved originals of the methods we monkey-patch, so we can restore them.
local record SavedMethods
  root_layout:  function(Root)
  root_build:   function(Root)
  tab_layout:   function(Tab)
  header_cwd:   function(Header): uiSpan
  header_tabs:  function(Header): uiLine
end

local record DualPane
  pane:    integer         -- active pane index (1 or 2)
  tabs:    {integer}       -- tab index for each pane
  view:    ViewState | nil -- nil = off, "dual" = dual, "zoom" = single-zoomed
  saved:   SavedMethods | nil
end

-- Validate that all stored tab indices still exist; fall back to cx.tabs.idx.
local function verify_tabs(dp: DualPane)
  for i = 1, #dp.tabs do
    if (cx.tabs[dp.tabs[i]] as any) == nil then
      dp.tabs[i] = cx.tabs.idx
    end
  end
end

-- Patch Root to render two side-by-side panes.
local function config_dual_pane(dp: DualPane)
  Root.layout = function(root: Root)
    root._chunks = ui.Layout()
      :direction(ui.Layout.HORIZONTAL)
      :constraints({ ui.Constraint.Percentage(100) })
      :split(root._area)
  end

  Root.build = function(root: Root)
    verify_tabs(dp)
    root._children = {
      Panes_new(PanesObj, root._chunks[1],
        cx.tabs[dp.tabs[1]], cx.tabs[dp.tabs[2]]),
    }
  end
end

-- Patch Root to render only the active pane (zoomed / single-pane mode).
local function config_single_pane(dp: DualPane)
  Root.layout = function(root: Root)
    root._chunks = ui.Layout()
      :direction(ui.Layout.VERTICAL)
      :constraints({
        ui.Constraint.Fill(1),
        ui.Constraint.Length(1),
      })
      :split(root._area)
  end

  Root.build = function(root: Root)
    verify_tabs(dp)
    local tab = cx.tabs[dp.tabs[dp.pane]]
    root._children = {
      Pane_new(PaneObj, root._chunks[1], tab, dp.pane),
      Status.new(Status, root._chunks[2], tab),
    }
  end
end

-- Patch Header.cwd to highlight the active pane's path.
local function patch_header_cwd(dp: DualPane)
  Header.cwd = function(header: Header): uiSpan
    local max = header._area.w - header._right_width
    if max <= 0 then return ui.Span("") end

    local s = ya.readable_path(tostring(header._tab.current.cwd)) .. header:flags()
    local style = (header.pane == dp.pane)
      and THEME.manager.tab_active
      or  THEME.manager.tab_inactive

    return ui.Span(ya.truncate(s, { max = max, rtl = true })):style(style)
  end
end

-- Patch Header.tabs to show which tab each pane is on.
local function patch_header_tabs(dp: DualPane)
  Header.tabs = function(header: Header): uiLine
    local n = #cx.tabs
    if n == 1 then return ui.Line({}) end

    local active = dp.tabs[header.pane]
    local spans: {uiSpan} = {}
    for i = 1, n do
      local text: string
      if THEME.manager.tab_width > 2 then
        text = ya.truncate(
          tostring(i) .. " " .. cx.tabs[i]:name(),
          { max = THEME.manager.tab_width })
      else
        text = tostring(i)
      end

      local style = (i == active)
        and THEME.manager.tab_active
        or  THEME.manager.tab_inactive
      spans[#spans + 1] = ui.Span(" " .. text .. " "):style(style)
    end
    return ui.Line(spans)
  end
end

-- Force Tab to hide parent/preview panes (full-width file list only).
local function patch_tab_layout()
  Tab.layout = function(self: Tab)
    self._chunks = ui.Layout()
      :direction(ui.Layout.HORIZONTAL)
      :constraints({
        ui.Constraint.Percentage(0),
        ui.Constraint.Percentage(100),
        ui.Constraint.Percentage(0),
      })
      :split(self._area)
  end
end

-- Snapshot the original methods before patching.
local function save_methods(): SavedMethods
  return {
    root_layout  = Root.layout,
    root_build   = Root.build,
    tab_layout   = Tab.layout,
    header_cwd   = Header.cwd,
    header_tabs  = Header.tabs,
  }
end

-- Restore everything to what yazi shipped with.
local function restore_methods(saved: SavedMethods)
  Root.layout  = saved.root_layout
  Root.build   = saved.root_build
  Tab.layout   = saved.tab_layout
  Header.cwd   = saved.header_cwd
  Header.tabs  = saved.header_tabs
end

-- Build a fresh DualPane (called on first `toggle`).
local function DualPane_create(): DualPane
  local dp: DualPane = {
    pane  = 1,
    tabs  = {},
    view  = nil,
    saved = nil,
  }

  if cx then
    dp.tabs[1] = cx.tabs.idx
    dp.tabs[2] = (#cx.tabs > 1)
      and cx.tabs.idx % #cx.tabs + 1
      or  cx.tabs.idx
  else
    dp.tabs = {1, 1}
  end

  dp.saved = save_methods()
  config_dual_pane(dp)
  patch_header_cwd(dp)
  patch_header_tabs(dp)
  patch_tab_layout()
  dp.view = "dual"

  return dp
end

-- The singleton; nil means the plugin is inactive.
local dp: DualPane | nil = nil

local function action_toggle()
  if dp == nil then
    dp = DualPane_create()
  else
    restore_methods((dp as DualPane).saved as SavedMethods)
    dp = nil
  end
  ya.app_emit("resize", {})
end

local function action_toggle_zoom()
  if dp == nil then return end
  local d = dp as DualPane
  if d.view == "dual" then
    config_single_pane(d)
    d.view = "zoom"
  else
    config_dual_pane(d)
    d.view = "dual"
  end
  ya.app_emit("resize", {})
end

local function action_focus_next()
  if dp == nil then return end
  local d = dp as DualPane
  d.pane = d.pane % 2 + 1
  ya.manager_emit("tab_switch", { d.tabs[d.pane] - 1 })
  ya.app_emit("resize", {})
end

-- Copy (or move) selected/hovered files from the active pane to the other.
local function action_copy_files(cut: boolean, force: boolean, follow: boolean)
  if dp == nil then return end
  local d       = dp as DualPane
  local src_tab = d.tabs[d.pane]
  local dst_tab = d.tabs[d.pane % 2 + 1]

  ya.manager_emit("yank",      { cut = cut })
  ya.manager_emit("tab_switch", { dst_tab - 1 })
  ya.manager_emit("paste",     { force = force, follow = follow })
  ya.manager_emit("unyank",    {})
  ya.manager_emit("tab_switch", { src_tab - 1 })
  ya.app_emit("resize", {})
end

local function action_tab_switch(tab_number: integer)
  if dp ~= nil then
    (dp as DualPane).tabs[(dp as DualPane).pane] = tab_number
  end
  ya.manager_emit("tab_switch", { tab_number - 1 })
end

local function action_tab_create(dir?: string)
  if dir then
    local path: string
    if dir == "--current" then
      path = tostring(cx.active.current.cwd)
    else
      path = dir
    end
    ya.manager_emit("tab_create", { path })
  else
    ya.manager_emit("tab_create", {})
  end

  -- Adjust the non-active pane's tab index if it sits above the new tab.
  if dp ~= nil then
    local d     = dp as DualPane
    local this  = d.pane
    local other = d.pane % 2 + 1
    if d.tabs[other] > d.tabs[this] then
      d.tabs[other] = d.tabs[other] + 1
    end
    action_tab_switch(cx.tabs.idx + 1)
  end
end

local function action_load_config(state: PluginState)
  if dp == nil then return end
  local d   = dp as DualPane
  local len = #cx.tabs

  ya.manager_emit("tab_switch", { len - 1 })

  for _, path in ipairs(state.paths or {}) do
    ya.manager_emit("tab_create", { path.cwd })
    if path.file ~= "" then
      ya.manager_emit("reveal", { path.file })
    end
  end

  for _ = 1, len do
    ya.manager_emit("tab_close", { 0 })
  end

  d.tabs = { state.tabs[1], state.tabs[2] }
  d.pane = state.pane

  local other_tab = d.tabs[d.pane % 2 + 1]
  ya.manager_emit("tab_switch", { other_tab - 1 })
  ya.manager_emit("refresh", {})
  ya.manager_emit("tab_switch", { d.tabs[d.pane] - 1 })
  ya.app_emit("resize", {})
end

local function action_save_config()
  if dp == nil then return end
  local d = dp as DualPane

  local saved: SavedConfig = {
    pane  = d.pane,
    tabs  = { d.tabs[1], d.tabs[2] },
    paths = {},
  }

  for i = 1, #cx.tabs do
    local folder = cx.tabs[i].current
    local file   = folder.hovered and tostring(folder.hovered.url) or ""
    saved.paths[#saved.paths + 1] = { cwd = tostring(folder.cwd), file = file }
  end

  ps.pub_to(0, "@dual-pane", saved)
end

local function action_reset_config()
  if dp ~= nil then
    ps.pub_to(0, "@dual-pane", nil)
  end
end

local function action_shell(state: PluginState, cmd: string, blocking: boolean)
  local expanded = expand_macros(cmd)
  if expanded ~= "" then
    ya.manager_emit("shell", {
      block   = blocking,
      orphan  = true,
      confirm = true,
      expanded,
    })
  end
end

local function parse_copy_flags(args: {string}): boolean, boolean
  local force  = false
  local follow = false
  for i = 2, #args do
    if args[i] == "--force"  then force  = true end
    if args[i] == "--follow" then follow = true end
  end
  return force, follow
end

local function flush_state_to_async()
  if dp ~= nil then
    local d = dp as DualPane
    set_state("cpane", d.pane)
    if #d.tabs > 0 then
      set_state_vector("ctabs", d.tabs)
    end
  end
end

local function load_dds_state(state: PluginState)
  ps.sub_remote("@dual-pane", function(body: any)
    if body == nil then return end
    local b = body as {string:any}

    state.pane  = (b.pane as integer) or 1
    state.tabs  = {}
    state.paths = {}

    for _, tab in ipairs((b.tabs or {}) as {integer}) do
      state.tabs[#state.tabs + 1] = tab
    end
    for _, path in ipairs((b.paths or {}) as {{string:string}}) do
      state.paths[#state.paths + 1] = path
    end
  end)
end

local function entry(state: PluginState, args: {string})
  local action = args[1]
  if not action then return end

  -- Synchronous actions
  if action == "toggle" then
    action_toggle()

  elseif action == "toggle_zoom" then
    action_toggle_zoom()

  elseif action == "next_pane" then
    action_focus_next()

  elseif action == "copy_files" then
    local force, follow = parse_copy_flags(args)
    action_copy_files(false, force, follow)

  elseif action == "move_files" then
    local force, follow = parse_copy_flags(args)
    action_copy_files(true, force, follow)

  elseif action == "tab_switch" then
    if args[2] then
      local tab = tonumber(args[2]) as integer
      if args[3] == "--relative" then
        if dp ~= nil then
          tab = ((dp as DualPane).tabs[(dp as DualPane).pane] - 1 + tab)
                % #cx.tabs
        else
          tab = (cx.tabs.idx - 1 + tab) % #cx.tabs
        end
      end
      action_tab_switch(tab + 1)
    end

  elseif action == "tab_create" then
    action_tab_create(args[2])

  elseif action == "load_config" then
    action_load_config(state)

  elseif action == "save_config" then
    action_save_config()

  elseif action == "reset_config" then
    action_reset_config()
  end

  -- Always keep the async context current before async actions.
  flush_state_to_async()

  -- Async actions (shell / shell_fzf) run after the state flush.
  if action == "shell" then
    local cmd    = ""
    local block  = false
    local interactive = false

    for i = 2, #args do
      if args[i] == "--block" then
        block = true
      elseif args[i] == "--interactive" then
        interactive = true
      else
        -- Quote args that contain whitespace.
        if args[i]:find("%s") then
          cmd = cmd .. ya.quote(args[i]) .. " "
        else
          cmd = cmd .. args[i] .. " "
        end
      end
    end

    if interactive then
      local input_cmd, event = ya.input({
        title    = "Shell command:",
        value    = cmd,
        position = { "top-center", y = 3, w = 40 },
      })
      if event == 1 then
        action_shell(state, input_cmd, block)
      end
    elseif cmd ~= "" then
      action_shell(state, cmd, block)
    end

  elseif action == "shell_fzf" then
    local interactive = false
    local filename:   string | nil = nil

    for i = 2, #args do
      if args[i] == "--interactive" then
        interactive = true
      else
        filename = args[i]
      end
    end

    if filename == nil then return end

    local file = io.open(filename as string, "r")
    if not file then
      notify_error(string.format(
        "Cannot open shell_fzf file '%s'", filename))
      return
    end
    io.close(file)

    local choice = get_fzf_choice(filename as string)
    if choice == "" then return end

    -- Parse the choice line: run="…", desc="…", block=true|false
    local run_cmd, _, block_str =
      choice:match('run%s*=%s*"(.-)"%s*,%s*desc%s*=%s*"(.-)"%s*,%s*block%s*=%s*([^%s\n]+)')

    if not run_cmd or run_cmd == "" or not block_str then return end
    if block_str ~= "true" and block_str ~= "false" then return end

    local block = (block_str == "true")

    if interactive then
      local input_cmd, event = ya.input({
        title    = "Shell command:",
        value    = run_cmd,
        position = { "top-center", y = 3, w = 40 },
      })
      if event == 1 then
        action_shell(state, input_cmd, block)
      end
    else
      action_shell(state, run_cmd, block)
    end
  end
end

local record SetupOpts
  enabled: boolean
end

local function setup(state: PluginState, opts?: SetupOpts)
  load_dds_state(state)
  if opts and opts.enabled then
    entry(state, { "toggle" })
  end
end

return {
  entry = entry,
  setup = setup,
}
