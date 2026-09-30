# Changelog

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
