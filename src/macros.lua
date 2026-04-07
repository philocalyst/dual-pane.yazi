local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local ipairs = _tl_compat and _tl_compat.ipairs or ipairs; local string = _tl_compat and _tl_compat.string or string; local table = _tl_compat and _tl_compat.table or table; local utils = require("utils")
local notify_error = utils.notify_error

local set_state = ya.sync(function(state, key, value)
   (state)[key] = value
end)

local set_state_vector = ya.sync(function(
   state, key, vector)
   local arr = {}
   for _, v in ipairs(vector) do
      arr[#arr + 1] = v
   end
   (state)[key] = arr
end)

local get_state = ya.sync(function(state, key)
   return (state)[key]
end)

local get_cwd = ya.sync(function()
   return tostring(cx.active.current.cwd)
end)


local prepare_urls = ya.sync(function(
   state, macro)

   local pane = (state.cpane or 1)
   local tabs = (state.ctabs or { 1, 1 })
   local this = cx.tabs[tabs[pane]]
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



local prepare_expansion = ya.sync(function(
   _state, urls, modifier)

   local parts = {}
   for _, url in ipairs(urls) do
      local name
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



local expand_macros = ya.sync(function(_state, cmd)
   local expanded = ""
   local i = 1

   while i <= #cmd do
      local mi, mj, macro = cmd:find("%%([fFcCdD])", i)
      if not mi then
         expanded = expanded .. cmd:sub(i, -1)
         break
      end

      expanded = expanded .. cmd:sub(i, mi - 1)

      local urls = prepare_urls(macro)
      if urls == nil then
         notify_error(string.format("Invalid macro expansion '%%%s'", macro))
         return ""
      end

      local mod = ""
      local suffix = cmd:sub(mj + 1, mj + 2)
      local _, _, found_mod = suffix:find(":([nse])")
      if found_mod then
         mod = found_mod
         i = mj + 4
      else
         i = mj + 2
      end

      expanded = expanded .. (prepare_expansion(urls, mod))
   end

   return expanded
end)

local M = {}







M.set_state = set_state
M.set_state_vector = set_state_vector
M.get_state = get_state
M.get_cwd = get_cwd
M.expand_macros = expand_macros

return M
