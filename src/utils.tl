local record M
  notify_error:    function(string)
  get_fzf_choice:  function(string, function(): string): string
  parse_copy_flags: function({string}): boolean, boolean
end

function M.notify_error(msg: string)
  ya.notify({ title = "dual-pane", content = msg, timeout = 3, level = "error" })
end

function M.get_fzf_choice(filename: string, get_cwd: function(): string): string
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
    M.notify_error(string.format(
      "Spawn `fzf` failed with error code %s. Do you have it installed?", err))
    return ""
  end

  local output, read_err = child:wait_with_output()
  permit:drop()

  if not output then
    M.notify_error(string.format("Cannot read `fzf` output, error code %s", read_err))
    return ""
  end

  local st = output.status as {string:any}
  if not (st.success as boolean) and (st.code as integer) ~= 130 then
    M.notify_error(string.format("`fzf` exited with error code %s", st.code))
    return ""
  end

  return ((output.stdout as string):gsub("\n$", ""))
end

function M.parse_copy_flags(args: {string}): boolean, boolean
  local force  = false
  local follow = false
  for i = 2, #args do
    if args[i] == "--force"  then force  = true end
    if args[i] == "--follow" then follow = true end
  end
  return force, follow
end

return M
