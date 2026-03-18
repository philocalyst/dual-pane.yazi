local record PluginState
  cpane: integer
  ctabs: {integer}
  -- Fields used only for load_config / save_config round-trips via DDS:
  pane:  integer
  tabs:  {integer}
  paths: {{string:string}}  -- list of {cwd=…, file=…}
end

-- Macro letters accepted by _prepare_urls
local enum FileMacro
  "f" "F" "c" "C" "d" "D"
end

-- URL modifier suffixes (:n  :s  :e  or empty)
local enum UrlModifier
  "" "n" "s" "e"
end

-- View states for DualPane
local enum ViewState
  "dual"  -- both panes visible
  "zoom"  -- only the active pane (single-pane zoom)
end

local record Panes
  _area:         any
  _chunks:       {any}
  _panes_chunks: {any}
  _children:     {any}
end

local Panes_mt: metatable<Panes>

