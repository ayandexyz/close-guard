-- Exercises hypr/close-guard.lua against a stubbed `hl`, with HOME and
-- XDG_STATE_HOME pointed at a throwaway directory by tests/run.
--   lua tests/binding_test.lua hypr/close-guard.lua

local script = assert(arg[1], "usage: binding_test.lua path/to/close-guard.lua")
local state = assert(os.getenv("XDG_STATE_HOME"))

local binds, active, dispatched = {}, nil, {}
hl = {
  unbind = function() end,
  bind = function(keys, fn) binds[keys] = fn end,
  dispatch = function(d) dispatched[#dispatched + 1] = d end,
  dsp = {
    exec_cmd = function(c) return { exec = c } end,
    window = { close = function() return { close = true } end },
  },
  get_active_window = function() return active end,
}

assert(dofile(script) == true, "plugin listed in shell.json should take Super+W")

local function write_list(text)
  local f = assert(io.open(state .. "/close-guard/apps", "w"))
  f:write(text)
  f:close()
end

local function press(class, address)
  dispatched = {}
  active = class and { class = class, initial_class = class, address = address or "0xabc123" } or nil
  binds["SUPER + W"]()
  return dispatched[1]
end

local failures = 0
local function check(name, ok)
  print((ok and "ok   " or "FAIL ") .. name)
  if not ok then failures = failures + 1 end
end

write_list("")
local d = press("kitty", "0x58b02f585a20")
check("empty list: every window asks", d.exec ~= nil)
check("address is passed to the prompt", d.exec and d.exec:find('{"address":"0x58b02f585a20"}', 1, true) ~= nil)

write_list("# comment\n  Kitty \n")
check("listed app asks", press("kitty").exec ~= nil)
check("unlisted app closes at once", press("chromium").close == true)
check("no focused window closes (no prompt)", press(nil).close == true)
check("malformed address never reaches the command", press("kitty", "0x1'; rm -rf ~; '").close == true)

write_list("kitty\n" .. string.rep("x", 70000))
check("oversized list is ignored (every window asks)", press("chromium").exec ~= nil)

os.exit(failures == 0 and 0 or 1)
