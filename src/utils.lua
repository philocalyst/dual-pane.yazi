local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local string = _tl_compat and _tl_compat.string or string; local M = {}





function M.notify_error(msg)
   ya.notify({ title = "dual-pane", content = msg, timeout = 3, level = "error" })
end

function M.get_fzf_choice(filename, get_cwd)
   local permit = ya.hide()
   local cwd = tostring(get_cwd())

   local child, err = Command("bash"):
   args({ "-c", "cat " .. filename .. " | fzf" }):
   cwd(cwd):
   stdin(Command.INHERIT):
   stdout(Command.PIPED):
   stderr(Command.INHERIT):
   spawn()

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

   local st = output.status
   if not (st.success) and (st.code) ~= 130 then
      M.notify_error(string.format("`fzf` exited with error code %s", st.code))
      return ""
   end

   return ((output.stdout):gsub("\n$", ""))
end

function M.parse_copy_flags(args)
   local force = false
   local follow = false
   for i = 2, #args do
      if args[i] == "--force" then force = true end
      if args[i] == "--follow" then follow = true end
   end
   return force, follow
end

return M
