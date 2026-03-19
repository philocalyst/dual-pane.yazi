local patches_mod = require("patches")
local utils       = require("utils")
local macros_mod  = require("macros")

local DualPane_create   = patches_mod.DualPane_create
local restore_methods   = patches_mod.restore_methods
local config_dual_pane  = patches_mod.config_dual_pane
local config_single_pane = patches_mod.config_single_pane

local notify_error     = utils.notify_error
local get_fzf_choice   = utils.get_fzf_choice
local parse_copy_flags = utils.parse_copy_flags

local set_state        = macros_mod.set_state
local set_state_vector = macros_mod.set_state_vector
local get_cwd          = macros_mod.get_cwd
local expand_macros    = macros_mod.expand_macros

local type DualPane    = patches_mod.DualPane
local type SavedMethods = patches_mod.SavedMethods
local type SavedConfig = patches_mod.SavedConfig

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

local record M
  action_toggle:      function()
  action_toggle_zoom: function()
  action_focus_next:  function()
  action_copy_files:  function(boolean, boolean, boolean)
  action_tab_switch:  function(integer)
  action_tab_create:  function(string | nil)
  action_load_config: function(PluginState)
  action_save_config: function()
  action_reset_config: function()
  action_shell:       function(PluginState, string, boolean)
  flush_state_to_async: function()
  load_dds_state:     function(PluginState)
  parse_copy_flags:   function({string}): boolean, boolean
  get_fzf_choice:     function(string, function(): string): string
  notify_error:       function(string)
  get_cwd:            function(): string
end

M.action_toggle      = action_toggle
M.action_toggle_zoom = action_toggle_zoom
M.action_focus_next  = action_focus_next
M.action_copy_files  = action_copy_files
M.action_tab_switch  = action_tab_switch
M.action_tab_create  = action_tab_create
M.action_load_config = action_load_config
M.action_save_config = action_save_config
M.action_reset_config = action_reset_config
M.action_shell       = action_shell
M.flush_state_to_async = flush_state_to_async
M.load_dds_state     = load_dds_state
M.parse_copy_flags   = parse_copy_flags
M.get_fzf_choice     = get_fzf_choice
M.notify_error       = notify_error
M.get_cwd            = get_cwd

return M
