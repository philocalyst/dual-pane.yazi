local utils = require("utils")
local notify_error = utils.notify_error

local set_state = ya.sync(function(state: PluginState, key: string, value: any)
  (state as {string:any})[key] = value
end)

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
      expanded = expanded .. cmd:sub(i, -1)
      break
    end

    expanded = expanded .. cmd:sub(i, mi - 1)

    local urls = prepare_urls(macro as FileMacro)
    if urls == nil then
      notify_error(string.format("Invalid macro expansion '%%%s'", macro))
      return ""
    end

    local mod: UrlModifier = ""
    local suffix = cmd:sub(mj + 1, mj + 2)
    local _, _, found_mod = suffix:find(":([nse])")
    if found_mod then
      mod = found_mod as UrlModifier
      i = mj + 4
    else
      i = mj + 2
    end

    expanded = expanded .. (prepare_expansion(urls, mod) as string)
  end

  return expanded
end)

local record M
  set_state:        function(string, any)
  set_state_vector: function(string, {integer})
  get_state:        function(string): any
  get_cwd:          function(): string
  expand_macros:    function(string): string
end

M.set_state        = set_state
M.set_state_vector = set_state_vector
M.get_state        = get_state
M.get_cwd          = get_cwd
M.expand_macros    = expand_macros

return M
