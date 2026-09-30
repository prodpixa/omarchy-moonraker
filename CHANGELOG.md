# Changelog

## 0.1.1 — 2026-09-30

- Fix: the popup's "Hide when not printing" toggle hid the whole widget, and
  with it the popup needed to turn the option back off. The toggle is now
  **Compact when not printing** (`compactWhenIdle`): a dimmed icon that stays
  clickable. Full hiding (`hideWhenIdle`) is still available through
  `shell.json` or IPC, with the command to undo it documented.

## 0.1.0 — 2026-09-30

First release.

- Bar chip with three styles (`icon`, `progress`, `full`), cycled with a right click
- Detail popup: thumbnail, elapsed/remaining/finish time, layer, filament, temperatures
- Pause, resume, and cancel (confirmed with a second click)
- API key support; thumbnails load through Moonraker one-shot tokens
- States: not configured, unreachable, unauthorized, Klipper starting up,
  disconnected, or shut down, idle, heating, printing, paused, complete,
  cancelled, and error
- Automatic chamber sensor detection
- IPC: `toggle`, `showSettings`, `refresh`, `cycleDisplay`, `status`, `configure`
- Mock Moonraker and screenshot automation for development
