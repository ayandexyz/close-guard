# Close Guard

[![Built for Omarchy: Plugin](https://raw.githubusercontent.com/tcballard/omarchy-badges/75975e5b5bf75e7ede3764bcd2950046f7abfe2c/badges/v1/omarchy-plugin.svg)](https://github.com/tcballard/omarchy-badges)

Stops `Super`+`W` from closing a window by accident. Pressing it opens a small
prompt instead:

> **Are you sure you want to close?**
> Window title · app
>
> **[ No ]** &nbsp; [ Yes ]

**No** is selected every time the prompt opens, so pressing `Enter` without
looking never closes anything.

| Key | Action |
| --- | --- |
| `Enter` / `Space` | Choose the selected button |
| `←` `→` / `h` `l` / `Tab` | Move between No and Yes |
| `y` | Yes, close the window |
| `n` / `Escape` / click outside | No, keep the window |
| `Super`+`Alt`+`W` | Close right away, no prompt |

The window to close is the one that was focused when you pressed `Super`+`W`.
The prompt shows on that window's monitor.

## Choose which apps ask

Click the shield in the bar. The panel lists your installed apps, the ones
that ask first at the top, with a search box to find the rest (10 shown at a
time). Switch an app on and only the apps you switched on ask; everything else
closes right away. With no apps switched on, every window asks.

In the panel, type to search, `↑` `↓` to move, `Enter` to switch the app on or
off, `Escape` to close.

Your choices are saved in `~/.local/state/close-guard/apps`, one window class
per line, and apply from the next `Super`+`W`.

## Requirements

- Omarchy 4 with Quattro shell-plugin support
- Hyprland 0.56 or newer, configured in Lua (Omarchy's default)

## Install

```bash
omarchy plugin add https://github.com/ayandexyz/close-guard --enable
```

Plugins cannot bind keys themselves, so give `Super`+`W` to Close Guard by
adding this block at the end of `~/.config/hypr/bindings.lua`:

```lua
-- close-guard: begin
do
  local guard = os.getenv("HOME") .. "/.config/omarchy/plugins/io.github.ayandexyz.close-guard/hypr/close-guard.lua"
  local file = io.open(guard, "r")
  if file then
    file:close()
    pcall(dofile, guard)
  end
end
-- close-guard: end
```

Hyprland reloads its config when you save the file. The block does nothing
while Close Guard is not installed, and an error in it can never stop the
rest of your config from loading.

## Turning it off

`omarchy plugin disable io.github.ayandexyz.close-guard` gives `Super`+`W`
its normal close back at once: the binding checks whether the plugin is
enabled on every press.

## Remove

```bash
omarchy plugin remove io.github.ayandexyz.close-guard
```

Then delete the `close-guard: begin` to `close-guard: end` block from
`~/.config/hypr/bindings.lua` (until you do, `Super`+`W` simply closes
windows), and delete your saved app picks:

```bash
rm -rf ~/.local/state/close-guard
```

## Validation and tests

```bash
./tests/run
omarchy plugin validate .
```

## Security

Omarchy plugins run as unsandboxed code inside `omarchy-shell`. Review this
repository before enabling it. What Close Guard does:

- **Closes only the window you were asked about.** The keybinding passes the
  focused window's address (checked to be hex); the prompt looks it up in
  Hyprland's own window list, and right before closing checks that the same
  window still exists. An unknown address opens no prompt.
- **Writes one file**, `~/.local/state/close-guard/apps` (owner-only
  permissions), holding the window classes you picked. It is written to a
  temporary file and renamed into place.
- **Runs these commands**, all with fixed arguments: `sh`, `head`, `timeout`,
  `mkdir`, `mktemp`, `printf` and `mv` to read and write that file (the read
  takes at most 64 KiB, only from a regular file that is not a symlink), and
  `omarchy-shell shell summon` from the keybinding.
- **Reads** `~/.config/omarchy/shell.json` (at most 1 MiB) from the keybinding
  to see whether the plugin is enabled.
- No network access, no privileges, no other dependencies.

To remove every trace: remove the plugin, delete the `close-guard` block from
`~/.config/hypr/bindings.lua`, and delete `~/.local/state/close-guard/`.

## License

MIT © 2026 Ayan De
