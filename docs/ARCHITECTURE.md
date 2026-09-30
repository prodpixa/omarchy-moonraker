# Architecture

## Files

| File | Role |
|------|------|
| `manifest.json` | Omarchy plugin manifest: id `io.github.prodpixa.moonraker`, kind `bar-widget`, entry point `Panel.qml`, defaults, and the settings schema. |
| `Panel.qml` | The widget: bar chip, popup, HTTP client, polling, settings persistence, and IPC. |
| `Model.js` | Pure helpers with no QML state: URL normalization, state labels, ETA math, formatting, chamber detection, and bar text. |
| `dev/install.sh` | Copies the plugin into `~/.config/omarchy/plugins/io.github.prodpixa.moonraker` and restarts the shell. |
| `dev/mock_moonraker.py` | Fake Moonraker with switchable scenarios, for development and screenshots. |
| `dev/assets/thumbnail.png` | Thumbnail the mock serves for its fake job. |
| `dev/screenshots.sh` | Walks the widget through every state and captures `docs/screenshots/`. |
| `dev/crop_popup.py`, `dev/crop_bar.py` | Crop the popup card and the bar chip out of screenshots (used by `screenshots.sh`). |

## How it plugs into Omarchy

`Panel.qml` extends `qs.Ui.Panel`, the same base the built-in popup widgets use
(Power, Weather, and others). The shell injects three properties:

- `bar`: a facade over the host bar (`foreground`, `urgent`, `fontFamily`,
  `run()`, `shell.updateEntryInline()`, …). Colors bind to it, so a theme change
  repaints the widget immediately.
- `settings`: the widget's entry from `shell.json`.
- `moduleName`: `io.github.prodpixa.moonraker`.

The UI is built from the shell's own kit, `qs.Ui` (`WidgetButton`,
`KeyboardPanel`, `PanelKeyCatcher`, `Button`, `ButtonGroup`, `TextField`,
`Toggle`, `PanelSeparator`, `PanelSectionHeader`), plus `qs.Commons.Style` for
sizes. That's where the native look comes from: borders, spacing, focus rings,
and popup placement are the same code the built-in widgets run.

Settings are saved with `bar.shell.updateEntryInline(moduleName, settings)`,
the capability-scoped API Omarchy gives third-party plugins. It rewrites only
this widget's entry in `shell.json`.

## Talking to Moonraker

All requests go through `XMLHttpRequest` from QML, so there are no external
processes. When an API key is set it goes in the `X-Api-Key` header.

| When | Request |
|------|---------|
| First connect / after the URL or key changes | `GET /printer/objects/list`: finds the chamber sensor object |
| Every poll | `GET /printer/objects/query?print_stats&virtual_sdcard&display_status&extruder&heater_bed&webhooks[&<chamber>]` |
| When the file name changes | `GET /server/files/metadata?filename=…`: slicer estimate, layer count, thumbnails |
| Popup open, with a thumbnail and an API key | `GET /access/oneshot_token` → image URL `…/server/files/gcodes/<thumb>?token=…` |
| Pause / Resume / Cancel | `POST /printer/print/pause`, `/resume`, `/cancel` |

`<img>`/`Image` elements can't send headers. With an API key set, the widget
first gets a Moonraker one-shot token (valid for 5 seconds, single use) and
puts it in the thumbnail URL instead.

### Polling

- Every `pollInterval` seconds (default 5), or every 3 seconds or less while
  printing or while the popup is open.
- One request at a time. QML's XHR has no reliable timeout, so a request that
  runs for more than 8 seconds is aborted and the printer is reported unreachable.
- A `generation` counter is bumped whenever the URL or key changes, or the
  widget is destroyed. Responses from an older generation are dropped, so
  switching printers never mixes data.

### State mapping

| Source | Widget state |
|--------|--------------|
| No URL | *Not configured* |
| Network error / timeout | *Unreachable*: dimmed, disconnect icon |
| HTTP 401/403 | *Unauthorized*: lock icon, settings open automatically |
| HTTP 503 or a "Klippy …" error | Klipper *disconnected* |
| `webhooks.state` ≠ `ready` | Klipper *starting up* / *shutdown* / *error*, with `webhooks.state_message` shown |
| `print_stats.state` | *Idle* (`standby`), *Printing*, *Paused*, *Complete*, *Cancelled*, *Error* |
| Printing, progress 0, a heater more than 2° under its target | *Heating* |

Progress is `display_status.progress`, falling back to `virtual_sdcard.progress`.
Layers come from `print_stats.info` (`SET_PRINT_STATS_INFO`), falling back to
the file metadata's `layer_count`.

### Time remaining

`Model.remainingSeconds()` averages two estimates, similar to Mainsail/Fluidd:

- file-based: `elapsed / progress − elapsed`
- slicer-based: `metadata.estimated_time − elapsed`

Below 5% progress only the slicer estimate is used, because file extrapolation
is noisy early in a print.

### Chamber detection

When `chamberObject` is empty, the first of these that exists is used:
`heater_generic chamber`, `temperature_sensor chamber`, `temperature_fan chamber`,
`heater_generic chamber_heater`, `temperature_sensor chamber_temp`. After
that, any `heater_generic`/`temperature_sensor`/`temperature_fan` whose name
contains "chamber" (ignoring thermal-protection sensors).

## Shell quirks worth knowing

- **Arrays from `shell.json`** reach QML as sequence wrappers, where
  `Array.isArray()` is false. `Model.toArray()` converts them.
- **Hot reload caches components.** Saving files under `~/.config/omarchy/plugins`
  triggers a reload, but the previously compiled QML can stay in use. Run
  `omarchy restart shell` (which `dev/install.sh` does).
- **`console.log` from third-party plugins doesn't reach the shell log.** Debug
  through IPC instead (`status` returns the live state).
- **Editing `shell.json` from outside** rebuilds the whole bar (several seconds).
  The `configure` IPC goes through the shell and applies instantly.
- The third-party `bar` facade has no `shellQuote()`. The widget quotes the URL itself.

## Security notes

- The API key lives in `shell.json` in plain text, like all widget settings.
- `status` over IPC never includes the key.
- `configure` accepts only the known setting keys.
- The key is sent only to the configured URL.
