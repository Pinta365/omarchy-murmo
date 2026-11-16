import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Commons
import qs.Ui

// Murmo web-app panel toggle with an unread badge.
//
// Left click asks bin/murmo-panel to show or hide the Chromium app window
// (app_id "chrome-<url-host>__-murmo-panel" on the special workspace "murmo").
// The badge mirrors the "(N) prefix Murmo puts on the window title; the
// Hyprland toplevel list drives it, so it updates without any polling.
//
// The shown special covers the monitor and takes focus, so a click on a window
// behind it changes nothing and emits no Hyprland focus event. The panel is
// therefore hidden by a transparent full-screen click-catcher (ClickCatcher.qml)
// whose input region excludes the panel rectangle and the bar: a press anywhere
// else hides the panel.
BarWidget {
  id: root
  moduleName: "pinta365.murmo"

  readonly property string url: String(setting("url", "https://murmo.org/"))

  // Absolute path to the helper, so it works regardless of PATH.
  readonly property string pluginDir: Qt.resolvedUrl(".").toString().replace(/^file:\/\//, "")
  readonly property string panelScript: pluginDir + "bin/murmo-panel"

  readonly property color foreground: bar ? bar.barForeground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color badgeText: Color.background
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  // The bar surface this widget lives on, and how thick the bar is.
  readonly property var barWindow: root.QsWindow ? root.QsWindow.window : null
  readonly property string barPosition: bar ? String(bar.position) : "top"
  readonly property real barThickness: {
    if (!barWindow) return 0
    return (barPosition === "left" || barPosition === "right") ? barWindow.width : barWindow.height
  }

  // ---- Panel presence + unread count, driven by Quickshell.Hyprland.
  property var panelToplevel: null
  property int unread: 0

  // Chromium app windows ignore --class and build their Wayland app_id as
  // "chrome-<url-host>__-<profile-directory>"; the launcher names the profile
  // directory "murmo-panel", so the id looks like "chrome-murmo.org__-murmo-panel".
  readonly property var panelPattern: /^chrome-.*__-murmo-panel$/

  function matchesPanel(toplevel) {
    if (!toplevel) return false

    var appId = toplevel.wayland ? String(toplevel.wayland.appId || "") : ""
    if (panelPattern.test(appId)) return true

    // Fall back to the raw IPC object, which carries "class" too.
    var cls = toplevel.lastIpcObject ? String(toplevel.lastIpcObject.class || "") : ""
    return panelPattern.test(cls)
  }

  function findPanelToplevel() {
    var values = Hyprland.toplevels.values
    for (var i = 0; i < values.length; i++)
      if (matchesPanel(values[i])) return values[i]

    return null
  }

  function refresh() {
    var found = findPanelToplevel()
    if (found !== panelToplevel) panelToplevel = found

    var title = ""
    if (found) title = String(found.title || (found.wayland ? found.wayland.title : "") || "")

    // Murmo prefixes the title with "(N) " while messages are unread.
    var match = /^\((\d+)\)/.exec(title)
    unread = match ? parseInt(match[1], 10) : 0
  }

  function toggle() {
    if (!bar) return
    bar.run(Util.shellQuote(panelScript) + " toggle " + Util.shellQuote(url))
  }

  // ── hiding the panel on a click outside it ─────────────────────────────────────────────────────────────────────
  //
  // The shown state and the panel's screen rectangle come from Hyprland. The bar
  // exists once per monitor, so there is one catcher per monitor; only the one
  // that was clicked hides the panel (a second hide cannot happen).

  readonly property string special: "murmo"
  property var shownOn: ({}) // monitor name → true, from Hyprland's activespecial

  readonly property bool panelShown: {
    for (var key in shownOn) return true
    return false
  }

  // The panel window's live geometry (hidden as well), in layout coordinates.
  readonly property var panelIpc: panelToplevel ? panelToplevel.lastIpcObject : null
  readonly property real panelX: panelIpc && panelIpc.at ? Number(panelIpc.at[0]) : 0
  readonly property real panelY: panelIpc && panelIpc.at ? Number(panelIpc.at[1]) : 0
  readonly property real panelW: panelIpc && panelIpc.size ? Number(panelIpc.size[0]) : 0
  readonly property real panelH: panelIpc && panelIpc.size ? Number(panelIpc.size[1]) : 0
  readonly property int panelMonitor: panelIpc && panelIpc.monitor !== undefined ? Number(panelIpc.monitor) : -1

  function updateShown(data) {
    var parts = String(data || "").split(",")
    var name = parts[0]
    var monitor = parts.slice(1).join(",")
    var next = {}
    for (var key in shownOn) next[key] = shownOn[key]
    if (name === "special:" + special) next[monitor] = true
    else delete next[monitor]
    shownOn = next
  }

  function monitorIdFor(screen) {
    if (!screen) return -1
    var monitors = Hyprland.monitors.values
    for (var i = 0; i < monitors.length; i++)
      if (String(monitors[i].name) === String(screen.name)) return monitors[i].id
    return -1
  }

  // The panel rectangle in the catcher surface's own coordinates. With
  // ExclusionMode.Normal the surface starts past the bar's exclusive zone, so
  // the bar edge shifts it by the bar thickness.
  function panelCut(screen) {
    if (!screen || !panelShown || panelW <= 0 || panelH <= 0) return Qt.rect(0, 0, 0, 0)
    var offsetX = barPosition === "left" ? barThickness : 0
    var offsetY = barPosition === "top" ? barThickness : 0
    var left = panelX - screen.x - offsetX
    var top = panelY - screen.y - offsetY
    var x0 = Math.max(0, Math.round(left))
    var y0 = Math.max(0, Math.round(top))
    var x1 = Math.min(screen.width, Math.round(left + panelW))
    var y1 = Math.min(screen.height, Math.round(top + panelH))
    if (x1 <= x0 || y1 <= y0) return Qt.rect(0, 0, 0, 0)
    return Qt.rect(x0, y0, x1 - x0, y1 - y0)
  }

  // Hide the shown special. toggle_special acts on the *focused* monitor, so the
  // panel's own monitor is focused first and the clicked monitor is focused back
  // afterwards, leaving focus where the user clicked.
  function hidePanel(screen) {
    if (!bar || !panelShown) return
    var panel = panelMonitor
    var clicked = monitorIdFor(screen)
    var hide = "hyprctl dispatch " + Util.shellQuote("hl.dsp.workspace.toggle_special('" + special + "')")
    if (panel >= 0 && clicked >= 0 && panel !== clicked) {
      hide = "hyprctl dispatch " + Util.shellQuote("hl.dsp.focus({ monitor = " + panel + " })")
        + " ; " + hide
        + " ; hyprctl dispatch " + Util.shellQuote("hl.dsp.focus({ monitor = " + clicked + " })")
    }
    shownOn = ({}); // act at once: no second click may toggle again
    bar.run(hide)
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  // The toplevel list changing (open/close) re-finds the panel window.
  Connections {
    target: Hyprland.toplevels
    function onValuesChanged() { root.refresh() }
  }

  // The window (re)titleing updates the badge.
  Connections {
    target: root.panelToplevel
    function onTitleChanged() { root.refresh() }
  }

  // Whether the special is shown on each monitor.
  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (String(event.name || "") === "activespecial") root.updateShown(event.data)
    }
  }

  // Hyprland emits nothing for a floating window being moved or resized, so the
  // catcher's cut-out follows the panel's geometry by re-reading it while shown.
  Timer {
    interval: 250
    running: root.panelShown
    repeat: true
    onTriggered: Hyprland.refreshToplevels()
  }

  // Seed the shown state at startup, in case the shell restarted with the panel up.
  Process {
    id: seed
    command: ["hyprctl", "-j", "monitors"]
    running: true
    stdout: StdioCollector {
      onStreamFinished: {
        var next = {}
        try {
          var monitors = JSON.parse(text)
          for (var i = 0; i < monitors.length; i++) {
            var special = monitors[i].specialWorkspace
            if (special && String(special.name) === "special:" + root.special) next[String(monitors[i].name)] = true
          }
        } catch (e) {
          // leave it empty; the next activespecial fills it in
        }
        root.shownOn = next
      }
    }
  }

  Component.onCompleted: refresh()

  // One catcher per bar surface (= per monitor); the clicked one hides the panel.
  ClickCatcher {
    id: catcher
    targetScreen: root.barWindow ? root.barWindow.screen : null
    active: root.panelShown
    panelRect: root.panelCut(catcher.targetScreen)
    onTapped: root.hidePanel(catcher.targetScreen)
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰻞"
    slotSize: Style.bar.iconSlot
    tooltipText: "Murmo"
    onPressed: function(b) { root.toggle() }
  }

  Rectangle {
    id: badge
    visible: root.unread > 0
    anchors.right: button.right
    anchors.top: button.top
    anchors.rightMargin: -Style.spaceReal(3)
    anchors.topMargin: -Style.spaceReal(1)
    width: Math.max(Style.space(12), badgeLabel.implicitWidth + Style.space(4))
    height: Style.space(12)
    radius: height / 2
    color: root.urgent
    border.width: 1
    border.color: root.badgeText

    Text {
      id: badgeLabel
      anchors.centerIn: parent
      text: root.unread > 99 ? "99+" : String(root.unread)
      color: root.badgeText
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
    }
  }
}
