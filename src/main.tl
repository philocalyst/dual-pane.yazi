local actions = require("actions")
local utils   = require("utils")
local macros  = require("macros")

local action_toggle      = actions.action_toggle
local action_toggle_zoom = actions.action_toggle_zoom
local action_focus_next  = actions.action_focus_next
local action_copy_files  = actions.action_copy_files
local action_tab_switch  = actions.action_tab_switch
local action_tab_create  = actions.action_tab_create
local action_load_config = actions.action_load_config
local action_save_config = actions.action_save_config
local action_reset_config = actions.action_reset_config
local action_shell       = actions.action_shell
local flush_state_to_async = actions.flush_state_to_async
local load_dds_state     = actions.load_dds_state

local parse_copy_flags   = utils.parse_copy_flags
local get_fzf_choice     = utils.get_fzf_choice
local notify_error       = utils.notify_error
local get_cwd            = macros.get_cwd
local expand_macros      = macros.expand_macros

local record SetupOpts
  enabled: boolean
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
        tab = (cx.tabs.idx - 1 + tab) % #cx.tabs
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

    local choice = get_fzf_choice(filename as string, get_cwd)
    if choice == "" then return end

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
