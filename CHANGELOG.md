# Changelog

## 0.1.2 — 2026-10-01

- Security: responses from the printer are now size- and time-limited. HTTP
  moved from QML's `XMLHttpRequest`, whose `abort()` leaves the transfer
  buffering inside the shell, to short `curl` calls capped at 1 MB (2 MB for
  thumbnails) and 10 seconds. An endless response from a broken or
  compromised Moonraker could previously exhaust the shell's memory.
  Reported by HANCORE-linux in the marketplace review.
- The API key now reaches curl on stdin, so it never appears in the process list.
- Thumbnails are fetched with the API key header directly; the one-shot token
  round trip is gone.
- Mock printer gains `flood`, `flood-declared`, `hang`, and `huge-thumbnail` scenarios.
- Screenshots and preview regenerated for the new "Compact when not printing" toggle, plus a compact-idle bar shot.

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
