import QtQuick
import Quickshell
import Quickshell.Wayland

// Full-screen transparent click-catcher for the Murmo panel.
//
// A Hyprland special workspace covers the monitor and takes focus, so a click on
// a window behind it moves nothing and emits no event; the panel is hidden by
// this layer-shell surface instead. Its input region is the whole surface minus
// the panel rectangle, so a press anywhere outside the panel lands here (and
// hides the panel), while presses on the panel pass through to it.
//
// ExclusionMode.Normal keeps the surface out of the bar's exclusive zone, so the
// bar and its Murmo icon keep receiving clicks on their own.
//
// Keyboard focus is None: the surface never takes keys, so typing and IME stay
// with the panel window underneath.
PanelWindow {
  id: catcher

  required property var targetScreen
  property bool active: false
  property rect panelRect: Qt.rect(0, 0, 0, 0) // the cut-out, in surface coordinates
  signal tapped()

  screen: targetScreen
  visible: active && !!targetScreen
  color: "transparent"
  exclusionMode: ExclusionMode.Normal
  WlrLayershell.layer: WlrLayer.Top
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
  WlrLayershell.namespace: "pinta365-murmo-catcher"

  anchors {
    top: true
    bottom: true
    left: true
    right: true
  }

  mask: Region {
    x: 0
    y: 0
    width: catcher.width
    height: catcher.height

    Region {
      intersection: Intersection.Subtract
      x: catcher.panelRect.x
      y: catcher.panelRect.y
      width: catcher.panelRect.width
      height: catcher.panelRect.height
    }
  }

  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.AllButtons
    onPressed: catcher.tapped()
  }
}
