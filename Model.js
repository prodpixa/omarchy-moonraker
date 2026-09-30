.pragma library

// Pure helpers for the Moonraker bar widget. Everything here is free of QML
// state so it can be unit-tested with plain node/qmltestrunner.

var DISPLAY_MODES = ["icon", "progress", "full"]
var TEMP_KEYS = ["nozzle", "bed", "chamber"]

// Candidate Klipper object names for a chamber sensor, most specific first.
var CHAMBER_CANDIDATES = [
  "heater_generic chamber",
  "temperature_sensor chamber",
  "temperature_fan chamber",
  "heater_generic chamber_heater",
  "temperature_sensor chamber_temp"
]

var ICONS = {
  printer: "\u{F042B}",   // nf-md-printer_3d
  nozzle: "\u{F0E5B}",    // nf-md-printer_3d_nozzle
  bed: "\u{F0438}",       // nf-md-radiator
  chamber: "\u{F050F}",   // nf-md-thermometer
  pause: "\u{F03E4}",     // nf-md-pause
  play: "\u{F040A}",      // nf-md-play
  stop: "\u{F04DB}",      // nf-md-stop
  check: "\u{F012C}",     // nf-md-check
  heat: "\u{F0238}",      // nf-md-fire
  lock: "\u{F033E}",      // nf-md-lock
  alert: "\u{F0026}",     // nf-md-alert
  offline: "\u{F0319}",   // nf-md-lan_disconnect
  web: "\u{F059F}",       // nf-md-web
  cog: "\u{F0493}",       // nf-md-cog
  refresh: "\u{F0450}"    // nf-md-refresh
}

function normalizeUrl(raw) {
  var url = String(raw || "").trim()
  if (url === "") return ""
  if (!/^https?:\/\//i.test(url)) url = "http://" + url
  return url.replace(/\/+$/, "")
}

function hostLabel(url) {
  var m = String(url || "").match(/^https?:\/\/([^\/:]+)/i)
  return m ? m[1] : ""
}

function normalizeDisplay(value) {
  var v = String(value || "")
  return DISPLAY_MODES.indexOf(v) >= 0 ? v : "progress"
}

function nextDisplay(value) {
  var i = DISPLAY_MODES.indexOf(normalizeDisplay(value))
  return DISPLAY_MODES[(i + 1) % DISPLAY_MODES.length]
}

// shell.json arrays reach QML as sequence wrappers, not JS arrays.
function toArray(value) {
  if (Array.isArray(value)) return value
  if (value && typeof value === "object" && typeof value.length === "number")
    return Array.prototype.slice.call(value)
  return null
}

function normalizeTemps(value) {
  value = toArray(value)
  if (!value) return ["nozzle", "bed"]
  var out = []
  for (var i = 0; i < TEMP_KEYS.length; i++)
    if (value.indexOf(TEMP_KEYS[i]) >= 0) out.push(TEMP_KEYS[i])
  return out
}

function toggleTemp(list, key) {
  var cur = normalizeTemps(list)
  var i = cur.indexOf(key)
  if (i >= 0) cur.splice(i, 1)
  else cur.push(key)
  return normalizeTemps(cur)
}

function pickChamberObject(objects, override) {
  var o = String(override || "").trim()
  if (o !== "") return o
  objects = toArray(objects)
  if (!objects) return ""
  for (var i = 0; i < CHAMBER_CANDIDATES.length; i++)
    if (objects.indexOf(CHAMBER_CANDIDATES[i]) >= 0) return CHAMBER_CANDIDATES[i]
  for (var j = 0; j < objects.length; j++) {
    var name = String(objects[j])
    if (/^(heater_generic|temperature_sensor|temperature_fan) .*chamber/i.test(name)
        && !/protection|thermal/i.test(name)) return name
  }
  return ""
}

function queryPath(chamberObject) {
  var objs = ["print_stats", "virtual_sdcard", "display_status", "extruder", "heater_bed", "webhooks"]
  if (chamberObject) objs.push(chamberObject)
  return "/printer/objects/query?" + objs.map(encodeURIComponent).join("&")
}

function isActiveState(state) {
  return state === "printing" || state === "paused"
}

function stateLabel(state, klippyState) {
  if (klippyState && klippyState !== "ready") {
    if (klippyState === "startup") return "Starting up"
    if (klippyState === "shutdown") return "Klipper shutdown"
    if (klippyState === "error") return "Klipper error"
    return "Klipper " + klippyState
  }
  switch (state) {
  case "printing": return "Printing"
  case "paused": return "Paused"
  case "complete": return "Complete"
  case "cancelled": return "Cancelled"
  case "error": return "Error"
  case "standby": return "Idle"
  default: return state ? state.charAt(0).toUpperCase() + state.slice(1) : "Unknown"
  }
}

function progressFraction(status) {
  var ds = status && status.display_status ? Number(status.display_status.progress) : 0
  var vs = status && status.virtual_sdcard ? Number(status.virtual_sdcard.progress) : 0
  var p = isFinite(ds) && ds > 0 ? ds : (isFinite(vs) ? vs : 0)
  return Math.max(0, Math.min(1, p))
}

// Remaining seconds, blending the slicer estimate with file-progress
// extrapolation the way Mainsail/Fluidd do. Returns -1 when unknown.
function remainingSeconds(printDuration, progress, slicerEstimate) {
  var elapsed = Number(printDuration) || 0
  var p = Number(progress) || 0
  var est = []
  if (p > 0.01 && elapsed > 0) est.push(Math.max(0, elapsed / p - elapsed))
  var slicer = Number(slicerEstimate) || 0
  if (slicer > 0) est.push(Math.max(0, slicer - elapsed))
  if (est.length === 0) return -1
  // Early in the print file extrapolation is noisy — trust the slicer.
  if (est.length === 2 && p < 0.05) return est[1]
  var sum = 0
  for (var i = 0; i < est.length; i++) sum += est[i]
  return sum / est.length
}

function formatDuration(seconds) {
  var s = Math.round(Number(seconds))
  if (!isFinite(s) || s < 0) return "—"
  var h = Math.floor(s / 3600)
  var m = Math.floor((s % 3600) / 60)
  if (h > 0) return h + "h " + (m < 10 ? "0" : "") + m + "m"
  if (m > 0) return m + "m"
  return s + "s"
}

function formatTemp(t) {
  var n = Number(t)
  return isFinite(n) ? Math.round(n) + "°" : "—"
}

function formatTempPair(temp, target) {
  var t = Number(target)
  return formatTemp(temp) + (isFinite(t) && t > 0 ? " / " + Math.round(t) + "°" : "")
}

function formatFilament(mm) {
  var n = Number(mm)
  if (!isFinite(n) || n <= 0) return "—"
  return n >= 1000 ? (n / 1000).toFixed(2) + " m" : Math.round(n) + " mm"
}

function baseName(path) {
  var p = String(path || "")
  var i = p.lastIndexOf("/")
  return i >= 0 ? p.slice(i + 1) : p
}

function displayFileName(path) {
  return baseName(path).replace(/\.(gcode(\.3mf)?|3mf|bgcode|g)$/i, "")
}

// Largest thumbnail from file metadata, resolved to a gcodes-root path.
function thumbnailPath(filename, metadata) {
  var thumbs = metadata && Array.isArray(metadata.thumbnails) ? metadata.thumbnails : []
  var best = null
  for (var i = 0; i < thumbs.length; i++) {
    var t = thumbs[i]
    if (!t || !t.relative_path) continue
    if (!best || (Number(t.width) || 0) > (Number(best.width) || 0)) best = t
  }
  if (!best) return ""
  var file = String(filename || "")
  var slash = file.lastIndexOf("/")
  var dir = slash >= 0 ? file.slice(0, slash + 1) : ""
  return dir + best.relative_path
}

function encodePath(path) {
  return String(path || "").split("/").map(encodeURIComponent).join("/")
}

function tempEntry(status, key, chamberObject) {
  var obj = null
  if (key === "nozzle") obj = status.extruder
  else if (key === "bed") obj = status.heater_bed
  else if (key === "chamber" && chamberObject) obj = status[chamberObject]
  if (!obj || obj.temperature === undefined) return null
  return {
    key: key,
    temperature: Number(obj.temperature),
    target: obj.target === undefined ? 0 : Number(obj.target)
  }
}

// Text painted in the bar. `data` is the widget's reduced state.
function barText(data, display, temps) {
  var mode = normalizeDisplay(display)
  if (!data.configured) return ICONS.printer
  if (data.authFailed) return ICONS.lock
  if (!data.online) return ICONS.offline
  if (data.klippyState && data.klippyState !== "ready") return ICONS.alert

  var parts = []
  var active = isActiveState(data.state)
  var icon = data.state === "paused" ? ICONS.pause
    : data.state === "error" ? ICONS.alert
    : data.state === "complete" ? ICONS.check
    : ICONS.printer
  parts.push(icon)

  if (mode !== "icon" && data.heating) {
    parts.push(ICONS.heat + " Heating")
  } else if (mode !== "icon" && active) {
    parts.push(Math.floor(data.progress * 100) + "%")
    if (data.remaining >= 0) parts.push(formatDuration(data.remaining))
  }

  if (mode === "full") {
    var list = normalizeTemps(temps)
    for (var i = 0; i < list.length; i++) {
      var entry = data.temps[list[i]]
      if (entry) parts.push(ICONS[list[i]] + " " + formatTemp(entry.temperature))
    }
  }

  return parts.join("  ")
}
