global record Url
  name:   function(Url): string
  stem:   function(Url): string
  ext:    function(Url): string
end

global record File
  url: Url
end

global record Folder
  cwd:     Url
  hovered: File
  selected: {Url}
end

global record Rect
  x: integer
  y: integer
  w: integer
  h: integer
end

global record Tab
  current: Folder
  selected: {Url}

  -- layout() is monkey-patched by this plugin
  layout: function(Tab)

  -- Tab also holds the _area and _chunks fields used by Pane/Panes
  _area:   Rect
  _chunks: {Rect}
  
  -- Extra methods found in Yazi 0.3+
  name: function(Tab): string
  new: function(any, Tab): Tab
end

global record Tabs
  idx: integer
  metamethod __index: function(Tabs, integer): Tab
  metamethod __len:   function(Tabs): integer
end

global record Cx
  active: Tab
  tabs:   Tabs
end

global cx: Cx

global record ThemeManager
  tab_active:   any
  tab_inactive: any
  tab_width:    integer
end

global record Theme
  manager: ThemeManager
end

global THEME: Theme

global record Permit
  drop: function(Permit)
end

-- ya.*
global record ya
  sync:          function(any): (function(...: any): any)
  hide:          function(): Permit
  quote:         function(string): string
  truncate:      function(string, any): string
  readable_path: function(string): string
  manager_emit:  function(string, any)
  app_emit:      function(string, any)
  notify:        function(any)
  input:         function(any): string, integer
end

-- ps.*
global record ps
  pub_to:     function(integer, string, any)
  sub_remote: function(string, function)
end

-- Command
global record CommandChild
  wait_with_output: function(CommandChild): CommandOutput, string
end

global record CommandOutput
  stdout: string
  status: {string:any}
end

global record CommandBuilder
  args:   function(self: CommandBuilder, {string}): CommandBuilder
  cwd:    function(self: CommandBuilder, string):   CommandBuilder
  stdin:  function(self: CommandBuilder, any):      CommandBuilder
  stdout: function(self: CommandBuilder, any):      CommandBuilder
  stderr: function(self: CommandBuilder, any):      CommandBuilder
  spawn:  function(self: CommandBuilder): CommandChild, any
end

global record Command
  INHERIT: any
  PIPED:   any
  metamethod __call: function(Command, string): CommandBuilder
end

-- ui.*
global record uiSpan
  style: function(self: uiSpan, any): uiSpan
end

global record uiLine
end

global record ui
  Span:       function(string): uiSpan
  Line:       function({uiSpan}): uiLine
  Layout:     any
  Constraint: any
end

-- Root, Header, Status (yazi rendering objects)
global record Root
  _area:     Rect
  _chunks:   {Rect}
  _children: {any}
  layout:    function(Root)
  build:     function(Root)
end

global record Header
  _area:        Rect
  _tab:         Tab
  _right_width: integer
  pane:         integer
  cwd:          function(Header): uiSpan
  tabs:         function(Header): uiLine
  flags:        function(Header): string
  new:          function(any, Tab): Header
end

global record Status
  new: function(Status, any, Tab): Status
end
