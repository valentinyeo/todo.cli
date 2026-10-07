# todo.cli

A tiny, self-contained task list you can drive from anywhere. Everything shares
one store: **`%USERPROFILE%\Desktop\todo.txt`**.

- **todo.cli** — a dependency-free command-line front-end (Zig, no libc), built
  for shell scripts and AI agents.
- **zigtodo** — an ultra-light dark-themed Windows GUI panel that slides out of
  the right edge (Zig, raw Win32 — no runtime, no libc, no GC, no framework).

> The **todo.cli companion** Android app and optional **Cloudflare** sync are
> planned; see the roadmap at the bottom.

```
zig build -Doptimize=ReleaseSmall     # builds both -> zig-out/bin/
```

## CLI (`todo.cli`)

Plain, scriptable, with `--json` for agents:

```
todo.cli list [--all] [--json]     # --json prints [{"i","done","text"}, ...]
todo.cli add "buy oat milk"
todo.cli done <n> | undone <n>     # n is the index shown by `list`
todo.cli edit <n> "new text"
todo.cli rm <n>
todo.cli clear --yes
todo.cli path                      # where the store lives
```

**Install to the Start Menu** (per-user, no admin):

```
powershell -ExecutionPolicy Bypass -File tools\install.ps1
```

This copies the exe to `%LOCALAPPDATA%\Programs\zigtodo`, creates a Start Menu
shortcut, and after that just type **"zigtodo"** in the Start Menu to launch it.
A single-instance guard means launching again just brings the existing panel
forward.

## Interaction

**Reveal** — the panel lives as a 6 px strip on the right edge and slides out
when the cursor enters the **middle quarter of the right edge only** (the middle
25 % of the screen height). That keeps the top-right corner — window close
buttons, browser tabs, the tray — free of interference.

**Mouse**

| action | result |
|---|---|
| click a row | select it |
| click the checkbox | tick the task off |
| double-click a row | tick the task off |
| click **Add** (or Enter in the field) | add the typed task |
| click **Clear** | confirm, then empty the whole list |
| mouse wheel / drag the scrollbar | scroll |

**Keyboard**

| key | result |
|---|---|
| `j` / `k` or `↓` / `↑` | move selection down / up |
| `Ctrl+Enter` | edit the selected task inline |
| `Ctrl+E` (or `Space`, `Enter`) | toggle done — completed tasks drop to the bottom |
| `Delete` | remove the selected task |
| `Ctrl+Delete` | clear the whole list (then `y` to confirm) |
| `Esc` | cancel / hide the panel |

**Opening focuses the field.** Whether you reveal it by hovering or with the
hotkey, the panel takes focus and drops the caret in the input so you can type
straight away. When it closes it hands focus back to whatever window you were
using before.

**Interacting with anything inside keeps it open.** A simple hover-peek still
slides away when you leave, but the moment you click or type inside the panel
it pins itself open (so it never vanishes mid-task).

**Clicking anywhere outside the panel closes it immediately** (the window
deactivates, so focus is never trapped).

**Global hotkeys** (work from any app)

- `Ctrl+Alt+Space` — **toggle** the panel (press once to open and focus the
  input, again to close).
- `Ctrl+Alt+D` — dictate a task (see below).
- `Ctrl+Alt+Shift+Space` — toggle **docked mode** (see below).

Both fall back through a list if the combo is already taken; the panel footer
shows what actually registered.

## Docked mode

By default zigtodo hides as a 6 px strip. **Docked mode** pins it permanently on
the right edge and *reserves* that space, so it never overlaps your windows —
maximized windows, the desktop icons and the work area all shrink to fit around
it. It's done with the Windows **AppBar** protocol (`SHAppBarMessage`), the same
mechanism the taskbar uses.

Toggle it any of these ways:

- **Tray icon** → right-click → **Docked mode** (ticked when active).
- **Header button** — the **Dock** / **Undock** button in the panel.
- **`Ctrl+Alt+Shift+Space`**.

The choice is remembered in `%APPDATA%\zigtodo\config.txt` and restored on the
next launch. While docked the panel is always visible; `Esc` / clicking outside
won't hide it (the hotkey toggles dock on/off instead).

**Drag the left edge** of the bar to make it narrower or wider (220–680 px). The
width is saved too, so your docked size comes back next launch.

## Dictation (Deepgram)

Press **`Ctrl+Alt+D`**, speak, press it again. The recording is sent to
Deepgram and the transcript is added as a task.

Provide a key in **either** place:

- the `DEEPGRAM_API_KEY` environment variable, or
- a file named `deepgram.key` next to the executable (the token on the first line).

Without a key the footer reads `Dictation: set DEEPGRAM_API_KEY`. Audio is
captured as mono 16 kHz PCM and POSTed to Deepgram's prerecorded `nova-2`
endpoint over WinHTTP (so TLS comes from the OS — no crypto stack shipped).

> Deepgram is a paid third-party service; this project just calls its API.

## Style guide

The whole UI is custom-drawn from one palette so it stays consistent. It's a
"zinc" base with a single indigo accent.

| token | hex | use |
|---|---|---|
| `bg` | `#18181B` | panel background |
| `surface` | `#232327` | idle task cards |
| `input` | `#25252B` | text fields |
| `hover` | `#2C2C31` | hover state |
| `selected` | `#2F2F36` | selected card |
| `border` | `#33333A` | hairlines, empty checkbox |
| `accent` | `#6366F1` | the one accent: selection bar, filled check, Add button |
| `accent-hi` | `#818CF8` | accent hover |
| `text` | `#E4E4E7` | primary text |
| `muted` | `#A1A1AA` | secondary text |
| `faint` | `#71717A` | hints, completed text |
| `danger` | `#EF4444` | destructive / errors |

Type: Segoe UI — title 17 px semibold, body 15 px, buttons 14 px medium,
captions 12 px. Completed tasks use the body font with strikeout in `faint`.
Everything scales with the display DPI.

## Footprint (measured, ReleaseSmall)

| metric | value |
|---|---|
| executable | ~140 KB, statically linked, no libc |
| private working set | ~3.6 MB |
| idle CPU (closed) | 0 % |
| idle CPU (open & focused) | ~2 % (just the blinking text caret) |
| threads | 4 |

## Files

| file | role |
|---|---|
| `src/main.zig` | UI: edge reveal, custom-drawn list/chrome, input, hotkeys, tray |
| `src/dictation.zig` | mic capture (`waveIn`) + Deepgram request (`WinHTTP`) |
| `src/win32.zig` | hand-written Win32 bindings (avoids `@cImport`/libc bloat) |
| `src/icon.ico` | embedded tray/window icon |
| `build.zig` | links only `kernel32`, `user32`, `gdi32`, `shell32`, `winmm`, `winhttp` |
| `tools/*.ps1` | manual test helpers |

## Storage

Tasks always live in **`todo.txt` on your Desktop**
(`%USERPROFILE%\Desktop	odo.txt`, resolved through the shell so a
OneDrive-redirected Desktop works too). The same file is reused on every
launch, so you can also edit it by hand. Format, one per line:

```
[ ] buy oat milk
[x] ship the tray icon
```

Completed tasks are grouped at the bottom of the panel but kept in file order.
