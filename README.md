# Touch Shortcuts — Pixelorama extension

A floating vertical panel with 6 big touch slots, built for one-handed
(left-handed) drawing on a tablet. Personal tool — no AI in the loop, nothing
phones home; it reads/writes only Pixelorama's own app-private storage.

## What it does

- **Tap a slot** — runs its action. Defaults (top to bottom):
  Undo · Pan · Color Picker · Pencil · Eraser · Lasso
- **Press and hold a slot** (~half a second) — the slot blinks, then tap any
  tool button in the tool palette (or the Undo / Redo buttons in the top bar):
  that slot now holds that shortcut. Tap the panel itself or anywhere
  unrecognizable to cancel (red flash).
- **Drag the small handle** on top of the panel — moves it anywhere on
  screen. **Tap the handle** (or the panel body) — collapse the panel to a
  small pill; tap it again to bring the slots back.
- **The ✕ on the handle's right** — dismisses the panel entirely. Bring it
  back via **Window menu → "Toggle Touch Shortcuts Panel"**; dismissal
  persists across restarts too.
- Slots, panel position, collapse and visibility **persist** across restarts
  (stored in Pixelorama's app-private `user://` storage — nothing leaves the
  device). While running, the panel also keeps itself out of Pixelorama's
  crash-suspicion list, so force-closing the app can't silently disable it
  on the next boot.

Slot highlight: a slot with a cyan ring is the tool currently active.

## Updating an installed version

Pixelorama caches extension code for as long as the app runs. To replace an
installed `.pck`, re-add it in Preferences → Extensions, then **fully close
Pixelorama (swipe it away / force stop) and reopen** — the change only takes
effect after a restart.

## Install

Works on stock Pixelorama v1.2.4 and on the N Pixel mod build (same
extension API).

1. Copy `TouchShortcuts.pck` anywhere the app can read (e.g. the tablet's
   Download folder).
2. Pixelorama → **Edit → Preferences → Extensions → Add Extension** →
   pick the `.pck` → **enable** it.
3. The panel appears on the right edge of the screen (default spot — out of a
   left drawing hand's way). Drag it wherever you like.

Uninstall: Preferences → Extensions → Touch Shortcuts → remove. Nothing else
is touched: the extension adds no tools, no menus except its toggle item, and
stores one settings file.

## Rebuild (for future agents)

Sources live in `extension/touch-shortcuts/` (outer repo). Pipeline:

```bash
./src/make_touch_extension.sh     # packs artifacts/build/TouchShortcuts.pck
./src/smoke_touch_extension.sh    # 26-check suite on clean stock v1.2.4
```

The smoke suite boots the REAL stock Pixelorama headless in an isolated fake
HOME with a test-driver extension and asserts against the live app: panel
structure, defaults, tool switching, a real undo, capture resolution
(tools + undo/redo buttons), the full bind flow, collapse, and persistence
across disable/re-enable. Requires the stock worktree at /tmp/stock-v124
(created automatically via `git worktree` from the fork checkout at the
v1.2.4 tag; needs one `godot --headless --import` pass, also automatic).

## Implementation notes (what took digging)

- Stock tool names used by the panel: `Pan`, `ColorPicker`, `Pencil`,
  `Eraser`, `Lasso` (see `src/Autoload/Tools.gd` — `Tools.tools` keys).
- `Tools.assign_tool(name, MOUSE_BUTTON_LEFT)` is the correct switch call in
  BOTH modes: on touchscreens Pixelorama boots in single-tool mode and
  internally redirects LEFT → the RIGHT slot.
- Undo/redo go through `Global.current_project.commit_undo()/commit_redo()`
  — exactly what the Edit menu and the top-bar quick buttons call.
- Godot 4.7 has NO `Viewport.gui_find_control()` — the extension walks the
  UI tree itself (`_find_control_at`) with Godot's picking rules. Dialogs are
  Windows outside that tree, so tapping one just cancels capture.
- Extension enabled-state config key is the JSON `name`, not the pck
  filename. Stock `user://` on Linux/desktop is `~/.local/share/pixelorama/`
  (custom user dir!), NOT `godot/app_userdata/...`.
- Headless gotcha for future suites: the dummy display server is 64x64 and
  never pumps buffered input — the driver flushes and falls back to direct
  event delivery; keep test positions inside 64x64.
