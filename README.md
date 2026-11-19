# Touch Shortcuts — an extension for Pixelorama

A floating vertical panel with 6 big touch slots, made for drawing on a
tablet with one hand (it was built by a left-handed artist, for a left-handed
artist). Tap a slot to switch tools or undo — no reaching across the screen
to the tool palette mid-stroke.

Built for Pixelorama **v1.2.4-stable** (other 1.x versions may work, but only
v1.2.4 is tested).

## What it does

- **Tap a slot** — runs its action. Defaults, top to bottom:
  Undo · Pan · Color Picker · Pencil · Eraser · Lasso
- **Press and hold a slot** (about half a second) — the slot blinks, then tap
  any tool button in the tool palette (or the Undo / Redo buttons in the top
  bar): that slot is now that shortcut. Tap the panel itself or anywhere that
  isn't a shortcut to cancel (red flash). Works with every tool in the
  palette, including tools added by other extensions.
- **Drag the small handle** on top of the panel — moves it anywhere on
  screen. **Tap the handle** (or the panel body) — collapse the panel to a
  small pill; tap it again to bring the slots back.
- **The ✕ on the handle's right** — dismisses the panel entirely.
  Bring it back via **Window menu → "Toggle Touch Shortcuts Panel"**.
  Dismissal persists across restarts too.
- Slots, position, collapse and visibility **persist across restarts**. While
  the panel is running it also keeps itself out of Pixelorama's
  crash-suspicion list, so a force-closed app can't silently disable it. Everything
  is stored in Pixelorama's own app-private settings folder — the extension
  has no network access and collects nothing.
- A slot with a cyan ring is the tool that's currently active.

## Updating an installed version

Pixelorama caches extension code for as long as the app runs. To replace an
installed `.pck`, re-add it in Preferences → Extensions, then **fully close
Pixelorama (swipe it away / force stop) and reopen** — the change only takes
effect after a restart.

## Install

1. Download `TouchShortcuts.pck` (from this repo, or the
   [v1.0.0 release](../../releases)).
2. Open Pixelorama → **Edit → Preferences → Extensions → Add Extension** →
   pick the `.pck` file → enable it.
3. The panel appears on the right edge of the screen. Drag it wherever you
   like.

Uninstall: Preferences → Extensions → Touch Shortcuts → remove. The extension
adds no tools and no menus beyond its toggle item.

## Transparency: this extension was written by an AI

Yes, really, and on purpose. This panel was designed and written by an AI
coding agent (GLM, via the DeepSeek Harness) working from Naz's specs and
feedback — Naz is the left-handed tester who uses it daily on an Android
tablet. It is published as-is, in the spirit of a personal tool that might
save someone else the same thumb-reach. It reads/writes only its own settings
file inside Pixelorama's storage; there are no trackers, no network calls, no
telemetry. The source is one GDScript file — read it before you install it.

- Pixelorama is [Orama-Interactive/Pixelorama](https://github.com/Orama-Interactive/Pixelorama) (MIT).
- This extension is MIT too. No affiliation with the Pixelorama team.
- Issues welcome; support is best-effort.

## How it was verified

An automated suite boots a clean stock Pixelorama v1.2.4 headless with the
extension installed and runs 26 checks against the live app: panel structure
and defaults, tool switching, a real undo, the press-and-hold capture and
rebind flow (including against the top-bar undo/redo buttons), collapse, and
persistence across a disable/re-enable cycle. On-device touch behaviour was
verified by hand on an Android tablet.

## License

MIT — see [LICENSE](LICENSE).
