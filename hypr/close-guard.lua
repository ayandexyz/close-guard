-- Close Guard keybindings for Hyprland 0.56 or newer, configured in Lua.
--
-- Load it from ~/.config/hypr/bindings.lua with the block in README.md.
-- Returns true when Close Guard holds Super+W, false when the shell does not
-- have the plugin enabled (Omarchy's own Super+W then stays in place).
--
-- Loading it twice in one Lua state does nothing the second time. Nothing
-- here is ever torn down from Lua (removing a keybind object crashed
-- Hyprland 0.56.2); a fresh `hyprctl reload` is how changes are picked up.

if rawget(_G, "__close_guard") then
  return true
end

local PLUGIN_ID = "io.github.ayandexyz.close-guard"

-- Reads at most `limit` bytes; a longer file is treated as unreadable rather
-- than parsed truncated.
local function read_capped(path, limit)
  local file = io.open(path, "r")
  if not file then
    return nil
  end
  local text = file:read(limit + 1)
  file:close()
  if text and #text > limit then
    return nil
  end
  return text or ""
end

-- Enabled means shell.json lists the plugin and does not disable it. A
-- shell.json that cannot be read counts as disabled, so Super+W falls back to
-- a plain close rather than to a prompt that might never appear.
local function enabled()
  local text = read_capped((os.getenv("HOME") or "") .. "/.config/omarchy/shell.json", 1024 * 1024)
  if not text then
    return false
  end
  if not text:find('"' .. PLUGIN_ID .. '"', 1, true) then
    return false
  end
  local disabled = text:match('"disabledPlugins"%s*:%s*(%b[])')
  return not (disabled and disabled:find('"' .. PLUGIN_ID .. '"', 1, true))
end

if not enabled() then
  return false
end

_G.__close_guard = true

hl.unbind("SUPER + W")

-- The apps picked in the bar panel: lowercase window classes, one per line.
-- nil when none are picked, which means every window asks.
local function guarded_classes()
  local state = os.getenv("XDG_STATE_HOME") or ((os.getenv("HOME") or "") .. "/.local/state")
  local text = read_capped(state .. "/close-guard/apps", 65536)
  if not text then
    return nil
  end
  local set, any = {}, false
  for raw in text:gmatch("[^\n]+") do
    local class = raw:lower():match("^%s*(.-)%s*$")
    if class:match("^[a-z0-9._-]+$") then
      set[class], any = true, true
    end
  end
  return any and set or nil
end

local function wants_prompt(window)
  if not window then
    return false
  end
  local set = guarded_classes()
  if not set then
    return true
  end
  return set[tostring(window.class or ""):lower()] == true
    or set[tostring(window.initial_class or ""):lower()] == true
end

-- Checked again on every press, so `omarchy plugin disable` gives Super+W its
-- plain close back immediately, and picking apps in the bar panel applies to
-- the very next press, without waiting for a config reload.
hl.bind("SUPER + W", function()
  local window = hl.get_active_window()
  -- The address goes to the prompt so it asks about exactly this window. It is
  -- shape-checked before it is put into the command line.
  local address = window and tostring(window.address or ""):match("^0x%x+$")
  if address and enabled() and wants_prompt(window) then
    hl.dispatch(hl.dsp.exec_cmd("omarchy-shell shell summon " .. PLUGIN_ID
      .. " '{\"address\":\"" .. address .. "\"}'"))
  else
    hl.dispatch(hl.dsp.window.close())
  end
end, { description = "Close window (ask first)" })

-- Escape hatch that never asks, e.g. if the shell itself is not responding.
hl.bind("SUPER + ALT + W", hl.dsp.window.close(), { description = "Close window (no prompt)" })

return true
