import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Moonraker printer widget: a bar chip showing print progress / time left /
// temperatures, plus a popup with job details, controls, and settings.
// Talks to Moonraker's HTTP API directly (no curl dependency) and sends the
// optional API key as X-Api-Key, so it works over VPNs and untrusted networks.
Panel {
  id: root
  moduleName: "pixa.moonraker"
  ipcTarget: "pixa.moonraker"
  // Own the IpcHandler so the target can expose refresh/cycleDisplay too.
  manageIpc: false

  // ---------- Settings ----------
  readonly property string baseUrl: Model.normalizeUrl(setting("url", ""))
  readonly property string apiKey: String(setting("apiKey", "")).trim()
  readonly property string display: Model.normalizeDisplay(setting("display", "progress"))
  readonly property var barTemps: Model.normalizeTemps(setting("temps", ["nozzle", "bed"]))
  readonly property int pollSeconds: Math.max(2, Math.min(120, Number(setting("pollInterval", 5)) || 5))
  readonly property bool hideWhenIdle: setting("hideWhenIdle", false) === true
  readonly property bool hideWhenOffline: setting("hideWhenOffline", false) === true
  readonly property bool configured: baseUrl !== ""

  // Theme colors come from the bar so the widget follows `omarchy theme set`;
  // fall back to the shell palette while the bar is not injected yet.
  readonly property color fg: bar ? bar.foreground : Color.foreground
  readonly property color urgentColor: bar ? bar.urgent : Color.urgent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  // ---------- Printer state ----------
  property bool online: false
  property bool everConnected: false
  property string lastError: ""
  property bool authFailed: false
  property string klippyState: ""
  property string klippyMessage: ""
  property string printState: ""
  property string filename: ""
  property string statusMessage: ""
  property real progress: 0
  property real printDuration: 0
  property real totalDuration: 0
  property real filamentUsed: 0
  property int currentLayer: 0
  property int totalLayer: 0
  property var temps: ({})
  property var fileMeta: null
  property string metaFor: ""
  property string chamberObject: ""
  property bool objectsProbed: false
  property string thumbnailSource: ""
  property string thumbnailFor: ""

  // ---------- UI state ----------
  property bool settingsOpen: false
  property bool cancelArmed: false
  property bool actionBusy: false
  property int generation: 0
  property var inflight: null
  property real inflightSince: 0

  readonly property bool printing: online && Model.isActiveState(printState)
  readonly property real remaining: printing
    ? Model.remainingSeconds(printDuration, progress, fileMeta ? fileMeta.estimated_time : 0)
    : -1
  readonly property bool finished: online && filename !== ""
    && (printState === "complete" || printState === "cancelled" || printState === "error")
  readonly property bool klippyReady: klippyState === "" || klippyState === "ready"
  readonly property bool problem: configured && (authFailed
    || (everConnected && (!online || !klippyReady || printState === "error")))

  // PRINT_START is still bringing heaters up: printing, no progress yet, and a
  // heater more than a couple of degrees short of its target.
  readonly property bool heating: {
    if (!printing || printState !== "printing" || progress > 0.001) return false
    for (var k in temps) {
      var t = temps[k]
      if (t && t.target > 0 && t.temperature < t.target - 2) return true
    }
    return false
  }

  readonly property string barLabel: Model.barText({
    configured: root.configured,
    online: root.online,
    authFailed: root.authFailed,
    heating: root.heating,
    klippyState: root.klippyState,
    state: root.printState,
    progress: root.progress,
    remaining: root.remaining,
    temps: root.temps
  }, root.display, root.barTemps)

  readonly property bool iconOnly: barLabel.indexOf(" ") < 0

  readonly property string heroStatus: {
    if (!configured) return "Not configured"
    if (authFailed) return "Unauthorized"
    if (!online) return everConnected ? "Offline" : (lastError ? "Unreachable" : "Connecting…")
    if (heating) return "Heating"
    return Model.stateLabel(printState, klippyState)
  }

  readonly property bool hiddenByRule: (hideWhenOffline && configured && !online)
    || (hideWhenIdle && configured && online && !printing)

  // ---------- Settings persistence ----------
  function saveSettings(patch) {
    var next = Object.assign({}, root.settings || {}, patch)
    root.settings = next
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, next)
  }

  function cycleDisplay() {
    saveSettings({ display: Model.nextDisplay(root.display) })
  }

  // ---------- HTTP ----------
  function request(method, path, onDone) {
    var gen = root.generation
    var xhr = new XMLHttpRequest()
    xhr.onreadystatechange = function() {
      if (xhr.readyState !== XMLHttpRequest.DONE) return
      if (!root || gen !== root.generation) return
      var body = null
      try { body = JSON.parse(xhr.responseText) } catch (e) {}
      if (xhr.status >= 200 && xhr.status < 300 && body) {
        onDone(null, body.result !== undefined ? body.result : body)
        return
      }
      var msg = ""
      if (xhr.status === 0) msg = "No response from " + Model.hostLabel(root.baseUrl)
      else if (xhr.status === 401 || xhr.status === 403)
        msg = root.apiKey === "" ? "This printer requires an API key" : "The printer rejected this API key"
      else if (body && body.error && body.error.message) msg = String(body.error.message)
      else msg = "HTTP " + xhr.status
      onDone({ status: xhr.status, auth: xhr.status === 401 || xhr.status === 403, message: msg }, body)
    }
    xhr.open(method, root.baseUrl + path)
    if (root.apiKey !== "") xhr.setRequestHeader("X-Api-Key", root.apiKey)
    xhr.send()
    return xhr
  }

  function markOffline(err) {
    root.online = false
    root.authFailed = !!(err && err.auth)
    root.lastError = (err && err.message) || "Unreachable"
    // Surface the settings the moment the key is the problem.
    if (root.authFailed && root.opened) root.settingsOpen = true
  }

  function poll() {
    if (!configured) return
    if (inflight) {
      // XHR has no reliable timeout in QML; abort a request that hangs.
      if (Date.now() - inflightSince < 8000) return
      var stale = inflight
      inflight = null
      stale.abort()
      markOffline({ message: "Timed out reaching " + Model.hostLabel(baseUrl) })
    }
    if (!objectsProbed) {
      probeObjects()
      return
    }
    inflightSince = Date.now()
    inflight = request("GET", Model.queryPath(chamberObject), function(err, result) {
      root.inflight = null
      if (err) {
        // Klippy not ready still means Moonraker is reachable.
        if (err.status === 503 || (err.message && /klippy/i.test(err.message))) {
          root.online = true
          root.everConnected = true
          root.authFailed = false
          root.klippyState = "disconnected"
          root.klippyMessage = ""
          root.lastError = err.message
          return
        }
        root.markOffline(err)
        return
      }
      root.applyStatus(result && result.status ? result.status : {})
    })
  }

  function probeObjects() {
    inflightSince = Date.now()
    inflight = request("GET", "/printer/objects/list", function(err, result) {
      root.inflight = null
      if (err) {
        root.markOffline(err)
        return
      }
      root.chamberObject = Model.pickChamberObject(result ? result.objects : [], root.setting("chamberObject", ""))
      root.objectsProbed = true
      root.poll()
    })
  }

  function applyStatus(status) {
    online = true
    everConnected = true
    authFailed = false
    lastError = ""

    var ps = status.print_stats || {}
    var wh = status.webhooks || {}
    klippyState = wh.state ? String(wh.state) : "ready"
    klippyMessage = klippyState === "ready" ? "" : String(wh.state_message || "")
    printState = String(ps.state || "")
    filename = String(ps.filename || "")
    statusMessage = String(ps.message || (status.display_status && status.display_status.message) || "")
    printDuration = Number(ps.print_duration) || 0
    totalDuration = Number(ps.total_duration) || 0
    filamentUsed = Number(ps.filament_used) || 0
    progress = Model.progressFraction(status)
    var info = ps.info || {}
    currentLayer = Number(info.current_layer) || 0
    totalLayer = Number(info.total_layer) || 0

    var next = {}
    for (var i = 0; i < Model.TEMP_KEYS.length; i++) {
      var entry = Model.tempEntry(status, Model.TEMP_KEYS[i], chamberObject)
      if (entry) next[Model.TEMP_KEYS[i]] = entry
    }
    temps = next

    if (filename !== metaFor) loadMetadata()
    if (opened) loadThumbnail()
  }

  function loadMetadata() {
    var file = filename
    metaFor = file
    fileMeta = null
    thumbnailSource = ""
    thumbnailFor = ""
    if (file === "") return
    request("GET", "/server/files/metadata?filename=" + encodeURIComponent(file), function(err, result) {
      if (err || root.metaFor !== file) return
      root.fileMeta = result
      if (root.totalLayer === 0 && result && result.layer_count) root.totalLayer = Number(result.layer_count) || 0
      if (root.opened) root.loadThumbnail()
    })
  }

  // Image elements can't send headers, so with an API key we trade it for a
  // Moonraker one-shot token and pass that as a query parameter.
  function loadThumbnail() {
    var rel = Model.thumbnailPath(filename, fileMeta)
    if (rel === "" || thumbnailFor === rel) return
    thumbnailFor = rel
    var url = baseUrl + "/server/files/gcodes/" + Model.encodePath(rel)
    if (apiKey === "") {
      thumbnailSource = url
      return
    }
    request("GET", "/access/oneshot_token", function(err, token) {
      if (err || root.thumbnailFor !== rel) {
        root.thumbnailFor = ""
        return
      }
      root.thumbnailSource = url + "?token=" + encodeURIComponent(String(token))
    })
  }

  function reset() {
    generation++
    if (inflight) inflight.abort()
    inflight = null
    online = false
    everConnected = false
    authFailed = false
    lastError = ""
    klippyState = ""
    klippyMessage = ""
    printState = ""
    filename = ""
    metaFor = ""
    fileMeta = null
    temps = ({})
    objectsProbed = false
    chamberObject = ""
    thumbnailSource = ""
    thumbnailFor = ""
    Qt.callLater(poll)
  }

  function printAction(action) {
    if (actionBusy) return
    actionBusy = true
    request("POST", "/printer/print/" + action, function(err) {
      root.actionBusy = false
      if (err) root.lastError = err.message
      root.poll()
    })
  }

  function requestCancel() {
    if (!cancelArmed) {
      cancelArmed = true
      cancelDisarm.restart()
      return
    }
    cancelArmed = false
    printAction("cancel")
  }

  function openWebUi() {
    if (!configured || !root.bar) return
    root.bar.run("xdg-open '" + root.baseUrl.replace(/'/g, "'\\''") + "'")
  }

  onBaseUrlChanged: reset()
  onApiKeyChanged: reset()

  onOpenedChanged: {
    if (opened) {
      settingsOpen = !configured || authFailed
      cancelArmed = false
      urlField.text = setting("url", "")
      keyField.text = setting("apiKey", "")
      poll()
      loadThumbnail()
    }
  }

  Component.onCompleted: poll()
  Component.onDestruction: {
    generation++
    if (inflight) inflight.abort()
  }

  IpcHandler {
    target: "pixa.moonraker"

    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): void { root.poll() }
    function cycleDisplay(): void { root.cycleDisplay() }
    // Merge settings from a JSON object, e.g. '{"url":"http://printer","display":"full"}'.
    function configure(json: string): string {
      var patch
      try { patch = JSON.parse(json) } catch (e) { return "invalid JSON" }
      if (!patch || typeof patch !== "object" || Array.isArray(patch)) return "expected a JSON object"
      var allowed = ["url", "apiKey", "display", "temps", "pollInterval", "hideWhenIdle", "hideWhenOffline", "chamberObject"]
      var clean = {}
      for (var k in patch) {
        if (allowed.indexOf(k) < 0) return "unknown setting: " + k
        clean[k] = patch[k]
      }
      root.saveSettings(clean)
      return "ok"
    }
    function showSettings(): void {
      root.open()
      root.settingsOpen = true
    }
    // Machine-readable snapshot for scripts (never includes the API key).
    function status(): string {
      return JSON.stringify({
        configured: root.configured, online: root.online, state: root.printState,
        auth: !root.authFailed, klippy: root.klippyState, file: root.filename, progress: root.progress,
        remaining: root.remaining, temps: root.temps, error: root.lastError
      })
    }
  }

  Timer {
    interval: (root.opened || root.printing ? Math.min(root.pollSeconds, 3) : root.pollSeconds) * 1000
    running: root.configured
    repeat: true
    onTriggered: root.poll()
  }

  Timer {
    id: cancelDisarm
    interval: 3000
    onTriggered: root.cancelArmed = false
  }

  visible: !hiddenByRule
  implicitWidth: visible ? button.implicitWidth : 0
  implicitHeight: visible ? button.implicitHeight : 0

  readonly property real openPanelIndicatorWidth: iconOnly || button.vertical ? 0 : button.labelWidth

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: button.vertical ? Model.ICONS.printer : root.barLabel
    fontSize: root.iconOnly || button.vertical ? Style.bar.iconFont : Style.font.body
    fixedWidth: root.iconOnly && !button.vertical ? Style.bar.iconSlot : -1
    active: root.problem
    dimmed: !root.configured || (root.everConnected && !root.online)
    tooltipText: ""
    onPressed: function(b) {
      if (b === Qt.RightButton) root.cycleDisplay()
      else if (b === Qt.MiddleButton) root.openWebUi()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(400))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: urlField.activeFocus || keyField.activeFocus
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "r") root.poll()
        else if (t === "s") root.settingsOpen = !root.settingsOpen
        else if (t === "o") root.openWebUi()
      }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(14)

        // ---------- Hero: icon · name/status · percent ----------
        Item {
          width: parent.width
          implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight, heroPercent.implicitHeight)

          Text {
            id: heroIcon
            textFormat: Text.PlainText
            text: root.authFailed ? Model.ICONS.lock
              : !root.online && root.configured ? Model.ICONS.offline
              : !root.klippyReady || root.printState === "error" ? Model.ICONS.alert
              : root.heating ? Model.ICONS.heat
              : root.printState === "paused" ? Model.ICONS.pause
              : root.printState === "complete" ? Model.ICONS.check
              : Model.ICONS.printer
            color: root.problem ? root.urgentColor : root.fg
            font.family: root.fontFamily
            font.pixelSize: Style.font.display
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            Behavior on color { ColorAnimation { duration: 200 } }
          }

          Column {
            id: heroLabels
            anchors.left: heroIcon.right
            anchors.leftMargin: Style.space(14)
            anchors.right: heroPercent.left
            anchors.rightMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              textFormat: Text.PlainText
              text: root.printing || root.filename !== "" ? Model.displayFileName(root.filename)
                : (Model.hostLabel(root.baseUrl) || "3D Printer")
              color: root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
              elide: Text.ElideMiddle
              width: parent.width
            }

            Text {
              textFormat: Text.PlainText
              text: root.heroStatus.toUpperCase()
              color: root.problem ? root.urgentColor : Qt.darker(root.fg, 1.4)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.2
              elide: Text.ElideRight
              width: parent.width
            }
          }

          Text {
            id: heroPercent
            textFormat: Text.PlainText
            visible: (root.printing && !root.heating) || root.finished
            text: Math.floor(root.progress * 100) + "%"
            color: root.fg
            font.family: root.fontFamily
            font.pixelSize: Style.font.displayLarge
            font.bold: true
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
          }
        }

        // ---------- Error / message line ----------
        Text {
          visible: text !== ""
          width: parent.width
          textFormat: Text.PlainText
          readonly property bool isError: root.lastError !== "" || !root.klippyReady || root.printState === "error"
          text: root.lastError !== "" ? root.lastError
            : !root.klippyReady ? root.klippyMessage
            : root.statusMessage
          color: isError ? root.urgentColor : root.fg
          opacity: isError ? 1 : 0.7
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.Wrap
        }

        // ---------- Progress bar ----------
        Item {
          visible: root.printing
          width: parent.width
          implicitHeight: Style.space(8)

          Rectangle {
            id: track
            anchors.fill: parent
            radius: height / 2
            color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.12)
          }

          Rectangle {
            anchors.left: track.left
            anchors.verticalCenter: track.verticalCenter
            height: track.height
            radius: track.radius
            color: root.fg
            width: Math.max(track.height, track.width * root.progress)
            Behavior on width { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }

            SequentialAnimation on opacity {
              running: root.printState === "paused" && root.opened
              loops: Animation.Infinite
              alwaysRunToEnd: true
              NumberAnimation { from: 1.0; to: 0.45; duration: 900; easing.type: Easing.InOutSine }
              NumberAnimation { from: 0.45; to: 1.0; duration: 900; easing.type: Easing.InOutSine }
            }
          }
        }

        // ---------- Job details (+ thumbnail) ----------
        Row {
          visible: root.printing || root.finished
          width: parent.width
          spacing: Style.space(14)

          Rectangle {
            id: thumbFrame
            visible: thumb.status === Image.Ready
            width: visible ? Style.space(92) : 0
            height: Style.space(92)
            radius: Style.cornerRadius
            color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.06)

            Image {
              id: thumb
              anchors.fill: parent
              anchors.margins: Style.space(4)
              source: root.thumbnailSource
              fillMode: Image.PreserveAspectFit
              asynchronous: true
              smooth: true
              mipmap: true
            }
          }

          Column {
            width: parent.width - (thumbFrame.visible ? thumbFrame.width + parent.spacing : 0)
            spacing: Style.spacing.labelGap

            InfoPair {
              label: root.finished ? "Print time" : "Elapsed"
              value: Model.formatDuration(root.printDuration)
            }
            InfoPair {
              visible: root.printing
              label: "Remaining"
              value: Model.formatDuration(root.remaining)
            }
            InfoPair {
              visible: root.printing
              label: "Finishes at"
              value: root.remaining >= 0 ? Qt.formatTime(new Date(Date.now() + root.remaining * 1000), "HH:mm") : "—"
            }
            InfoPair {
              visible: root.printing && root.totalLayer > 0
              label: "Layer"
              value: root.currentLayer + " / " + root.totalLayer
            }
            InfoPair { label: "Filament"; value: Model.formatFilament(root.filamentUsed) }
          }
        }

        // ---------- Temperatures ----------
        PanelSeparator {
          visible: tempsColumn.visible
          foreground: root.fg
        }

        Column {
          id: tempsColumn
          visible: root.online && Object.keys(root.temps).length > 0
          width: parent.width
          spacing: Style.space(10)

          PanelSectionHeader {
            text: "TEMPERATURES"
            foreground: root.fg
            fontFamily: root.fontFamily
          }

          Column {
            width: parent.width
            spacing: Style.spacing.labelGap

            Repeater {
              model: Model.TEMP_KEYS
              InfoPair {
                required property string modelData
                readonly property var entry: root.temps[modelData] || null
                visible: entry !== null
                label: Model.ICONS[modelData] + "  " + modelData.charAt(0).toUpperCase() + modelData.slice(1)
                value: entry ? Model.formatTempPair(entry.temperature, entry.target) : ""
                heating: entry !== null && entry.target > 0
              }
            }
          }
        }

        // ---------- Actions ----------
        PanelSeparator { foreground: root.fg }

        Row {
          id: actionRow
          width: parent.width
          spacing: Style.space(6)

          readonly property int count: (root.printing ? 2 : 0) + 2
          readonly property real cellWidth: (width - spacing * (count - 1)) / count

          ActionButton {
            visible: root.printing
            iconText: root.printState === "paused" ? Model.ICONS.play : Model.ICONS.pause
            text: root.printState === "paused" ? "Resume" : "Pause"
            enabled: !root.actionBusy
            onClicked: root.printAction(root.printState === "paused" ? "resume" : "pause")
          }

          ActionButton {
            visible: root.printing
            iconText: Model.ICONS.stop
            text: root.cancelArmed ? "Confirm" : "Cancel"
            active: root.cancelArmed
            enabled: !root.actionBusy
            onClicked: root.requestCancel()
          }

          ActionButton {
            iconText: Model.ICONS.web
            text: "Web UI"
            enabled: root.configured
            onClicked: { root.openWebUi(); root.close() }
          }

          ActionButton {
            iconText: Model.ICONS.cog
            text: "Settings"
            active: root.settingsOpen
            onClicked: root.settingsOpen = !root.settingsOpen
          }
        }

        // ---------- Settings ----------
        Column {
          visible: root.settingsOpen
          width: parent.width
          spacing: Style.space(10)

          PanelSeparator { foreground: root.fg }

          PanelSectionHeader {
            text: "CONNECTION"
            foreground: root.fg
            fontFamily: root.fontFamily
          }

          TextField {
            id: urlField
            width: parent.width
            placeholderText: "Moonraker URL (http://192.168.1.50)"
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            foreground: root.fg
            onAccepted: keyField.forceActiveFocus()
          }

          TextField {
            id: keyField
            width: parent.width
            password: true
            placeholderText: "API key (optional)"
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            foreground: root.fg
            onAccepted: saveButton.clicked()
          }

          Button {
            id: saveButton
            width: parent.width
            iconText: Model.ICONS.check
            text: "Save & connect"
            fontSize: Style.font.bodySmall
            foreground: root.fg
            fontFamily: root.fontFamily
            bordered: true
            onClicked: {
              root.saveSettings({ url: urlField.text.trim(), apiKey: keyField.text.trim() })
              keyCatcher.forceActiveFocus()
              root.reset()
            }
          }

          PanelSectionHeader {
            text: "BAR DISPLAY"
            foreground: root.fg
            fontFamily: root.fontFamily
          }

          ButtonGroup {
            width: parent.width
            options: [
              { value: "icon", label: "Icon" },
              { value: "progress", label: "Progress" },
              { value: "full", label: "+ Temps" }
            ]
            value: root.display
            foreground: root.fg
            fontFamily: root.fontFamily
            fontSize: Style.font.bodySmall
            focusable: false
            onChanged: function(v) { root.saveSettings({ display: v }) }
          }

          PanelSectionHeader {
            visible: root.display === "full"
            text: "TEMPERATURES IN BAR"
            foreground: root.fg
            fontFamily: root.fontFamily
          }

          Row {
            id: tempToggleRow
            visible: root.display === "full"
            width: parent.width
            spacing: Style.space(6)
            readonly property real cellWidth: (width - spacing * 2) / 3

            Repeater {
              model: Model.TEMP_KEYS
              Button {
                required property string modelData
                width: tempToggleRow.cellWidth
                iconText: Model.ICONS[modelData]
                text: modelData.charAt(0).toUpperCase() + modelData.slice(1)
                fontSize: Style.font.bodySmall
                foreground: root.fg
                fontFamily: root.fontFamily
                bordered: true
                active: root.barTemps.indexOf(modelData) >= 0
                onClicked: root.saveSettings({ temps: Model.toggleTemp(root.barTemps, modelData) })
              }
            }
          }

          Toggle {
            width: parent.width
            label: "Hide when not printing"
            checked: root.hideWhenIdle
            foreground: root.fg
            fontFamily: root.fontFamily
            titleSize: Style.font.bodySmall
            onClicked: root.saveSettings({ hideWhenIdle: !root.hideWhenIdle })
          }
        }
      }
    }
  }

  component ActionButton: Button {
    width: actionRow.cellWidth
    iconSize: Style.font.title
    fontSize: Style.font.bodySmall
    foreground: root.fg
    fontFamily: root.fontFamily
    horizontalPadding: Style.spacing.controlPaddingX
    verticalPadding: Style.spacing.controlPaddingY + Style.space(2)
    bordered: true
    opacity: enabled ? 1 : 0.5
  }

  component InfoPair: Row {
    property string label: ""
    property string value: ""
    property bool heating: false

    width: parent.width
    spacing: Style.space(8)

    InfoLabel { text: label }
    Item { width: Math.max(0, parent.width - parent.children[0].implicitWidth - parent.children[2].implicitWidth - parent.spacing * 2); height: 1 }
    InfoValue { text: value; font.bold: heating }
  }

  component InfoLabel: Text {
    textFormat: Text.PlainText
    color: root.fg
    opacity: 0.6
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

  component InfoValue: Text {
    textFormat: Text.PlainText
    color: root.fg
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
  }
}
