import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import "WindowModel.js" as WindowModel

Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null
  readonly property var appLibrary: root.shell ? root.shell.appLibrary : null

  property bool opened: false
  property bool loading: false
  property bool commitWhenReady: false
  property int requestSerial: 0
  property int pendingDirection: 1
  property int queuedDelta: 0
  property int selectedIndex: -1
  property int targetMonitorId: -1
  property string targetMonitorName: ""
  property var clients: []

  readonly property color backgroundColor: Color.menu.background
  readonly property color foregroundColor: Color.menu.text
  readonly property color borderColor: Color.menu.border
  readonly property color scrimColor: Color.menu.scrim
  readonly property color selectedColor: Color.menu.selectedBackground
  readonly property color selectedTextColor: Color.menu.selectedText
  readonly property color selectedBorderColor: Color.menu.selectedBorder
  readonly property int cardWidth: Math.max(Style.space(112), 112)
  readonly property int cardHeight: Math.max(Style.space(138), 138)
  readonly property int cardSpacing: Math.max(Style.spacing.lg, 12)
  readonly property int panelPadding: Math.max(Style.spacing.xl, 20)

  function monitorScreen(name) {
    var screens = Quickshell.screens || []
    for (var i = 0; i < screens.length; i++) {
      if (String(screens[i].name || "") === String(name || "")) return screens[i]
    }
    return screens.length > 0 ? screens[0] : null
  }

  function desktopEntry(client) {
    if (!root.appLibrary) return null
    var entries = root.appLibrary.sortedEntries("") || []
    var keys = [String(client.initialClass || ""), String(client.class || "")]
    var best = null
    var bestScore = 100

    for (var i = 0; i < entries.length; i++) {
      var entry = entries[i]
      var entryId = String(entry.id || "").replace(/\.desktop$/i, "").toLowerCase()
      var entryName = String(root.appLibrary.entryName(entry) || "").toLowerCase()
      for (var j = 0; j < keys.length; j++) {
        var key = keys[j].replace(/\.desktop$/i, "").toLowerCase()
        if (!key) continue
        var score = 100
        if (entryId === key) score = 0
        else if (entryId.slice(-(key.length + 1)) === "." + key
                 || key.slice(-(entryId.length + 1)) === "." + entryId) score = 1
        else if (entryName === key) score = 2
        if (score < bestScore) {
          best = entry
          bestScore = score
        }
      }
    }
    return best
  }

  function decorate(client) {
    var entry = root.desktopEntry(client)
    var appName = entry ? root.appLibrary.entryName(entry) : ""
    var iconName = entry ? String(entry.icon || "")
      : String(client.initialClass || client.class || "application-x-executable")
    var decorated = ({})
    for (var key in client) decorated[key] = client[key]
    decorated.appName = appName || String(client.class || client.initialClass || "Application")
    decorated.displayTitle = WindowModel.shortenedTitle(client.title || decorated.appName, 96)
    decorated.iconSource = root.appLibrary
      ? root.appLibrary.iconSource(iconName)
      : Quickshell.iconPath(iconName, true)
    return decorated
  }

  function showForFocusedMonitor(direction) {
    var monitor = Hyprland.focusedMonitor
    if (!monitor) return false

    root.requestSerial += 1
    clientsProcess.serial = root.requestSerial
    root.pendingDirection = Number(direction) < 0 ? -1 : 1
    root.queuedDelta = 0
    root.commitWhenReady = false
    root.targetMonitorId = Number(monitor.id)
    root.targetMonitorName = String(monitor.name || "")
    root.clients = []
    root.selectedIndex = -1
    root.loading = true
    root.opened = true
    clientsProcess.command = ["hyprctl", "-j", "clients"]
    clientsProcess.running = true
    Qt.callLater(function() { keyScope.forceActiveFocus() })
    return true
  }

  function advance(direction) {
    var delta = Number(direction) < 0 ? -1 : 1
    if (!root.opened) return root.showForFocusedMonitor(delta) ? "ok" : "unavailable"
    if (root.loading) root.queuedDelta += delta
    else root.select(delta)
    return "ok"
  }

  function open(payloadJson) {
    var direction = 1
    try {
      var payload = JSON.parse(payloadJson || "{}")
      direction = Number(payload.direction) < 0 ? -1 : 1
    } catch (_error) { }
    root.advance(direction)
  }

  function close() {
    root.cancel()
  }

  function cancel() {
    root.requestSerial += 1
    root.opened = false
    root.loading = false
    root.commitWhenReady = false
    root.clients = []
    root.selectedIndex = -1
    if (clientsProcess.running) clientsProcess.running = false
  }

  function select(delta) {
    root.selectedIndex = WindowModel.nextIndex(root.selectedIndex, delta, root.clients.length)
    if (root.selectedIndex >= 0) strip.positionViewAtIndex(root.selectedIndex, ListView.Contain)
  }

  function commit() {
    if (!root.opened) return
    if (root.loading) {
      root.commitWhenReady = true
      return
    }
    if (root.selectedIndex < 0 || root.selectedIndex >= root.clients.length) {
      root.cancel()
      return
    }

    var address = String(root.clients[root.selectedIndex].address || "")
    root.cancel()
    if (!/^0x[0-9a-f]+$/i.test(address)) return
    Quickshell.execDetached([
      "hyprctl", "dispatch",
      'hl.dsp.focus({ window = "address:' + address + '" })'
    ])
  }

  function applyClients(text, serial, exitCode) {
    if (serial !== root.requestSerial || !root.opened) return
    root.loading = false
    var parsed = []
    if (exitCode === 0) {
      try { parsed = JSON.parse(String(text || "[]")) } catch (_error) { parsed = [] }
    }
    var filtered = WindowModel.switchableClients(parsed, root.targetMonitorId)
    var decorated = []
    for (var i = 0; i < filtered.length; i++) decorated.push(root.decorate(filtered[i]))
    root.clients = decorated
    root.selectedIndex = WindowModel.initialIndex(root.pendingDirection, decorated.length)
    if (root.queuedDelta !== 0)
      root.selectedIndex = WindowModel.nextIndex(root.selectedIndex, root.queuedDelta, decorated.length)

    if (decorated.length === 0) {
      root.cancel()
      return
    }
    Qt.callLater(function() {
      keyScope.forceActiveFocus()
      strip.positionViewAtIndex(root.selectedIndex, ListView.Contain)
      if (root.commitWhenReady) root.commit()
    })
  }

  function status(_argument) {
    return JSON.stringify({
      open: root.opened,
      loading: root.loading,
      monitor: root.targetMonitorName,
      count: root.clients.length,
      selectedIndex: root.selectedIndex,
      selectedAddress: root.selectedIndex >= 0 && root.selectedIndex < root.clients.length
        ? String(root.clients[root.selectedIndex].address || "") : ""
    })
  }

  Process {
    id: clientsProcess
    property int serial: 0
    stdout: StdioCollector { id: clientsOutput; waitForEnd: true }
    onExited: function(exitCode) {
      root.applyClients(clientsOutput.text, clientsProcess.serial, exitCode)
    }
  }

  PanelWindow {
    id: panel
    visible: root.opened
    screen: root.monitorScreen(root.targetMonitorName)
    anchors { top: true; right: true; bottom: true; left: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "bitr0t-window-switcher"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    FocusScope {
      id: keyScope
      anchors.fill: parent
      focus: root.opened

      Keys.priority: Keys.BeforeItem
      Keys.onPressed: function(event) {
        var reverse = !!(event.modifiers & Qt.ShiftModifier)
        if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
          root.advance(reverse || event.key === Qt.Key_Backtab ? -1 : 1)
          event.accepted = true
        } else if (event.key === Qt.Key_Left) {
          root.select(-1)
          event.accepted = true
        } else if (event.key === Qt.Key_Right) {
          root.select(1)
          event.accepted = true
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
          root.commit()
          event.accepted = true
        } else if (event.key === Qt.Key_Escape) {
          root.cancel()
          event.accepted = true
        }
      }
      Keys.onReleased: function(event) {
        if (event.key === Qt.Key_Alt || event.key === Qt.Key_AltGr) {
          root.commit()
          event.accepted = true
        }
      }

      Rectangle {
        anchors.fill: parent
        color: root.scrimColor
        opacity: 0.58

        MouseArea {
          anchors.fill: parent
          onClicked: root.cancel()
        }
      }

      Rectangle {
        id: switcherPanel
        anchors.centerIn: parent
        width: Math.min(panel.width - Style.space(64),
          root.clients.length * root.cardWidth
            + Math.max(0, root.clients.length - 1) * root.cardSpacing
            + root.panelPadding * 2)
        height: root.cardHeight + root.panelPadding * 2
        radius: Math.max(Style.cornerRadius, 18)
        color: root.backgroundColor
        border.color: root.borderColor
        border.width: 1
        opacity: root.loading || root.clients.length > 0 ? 1 : 0
        scale: root.loading || root.clients.length > 0 ? 1 : 0.96

        Behavior on opacity { NumberAnimation { duration: 120 } }
        Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

        MouseArea { anchors.fill: parent; onClicked: function(mouse) { mouse.accepted = true } }

        Text {
          anchors.centerIn: parent
          visible: root.loading
          text: "Loading windows…"
          color: root.foregroundColor
          opacity: 0.72
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.body
        }

        ListView {
          id: strip
          visible: !root.loading
          anchors.fill: parent
          anchors.margins: root.panelPadding
          orientation: ListView.Horizontal
          spacing: root.cardSpacing
          clip: true
          model: root.clients
          currentIndex: root.selectedIndex
          boundsBehavior: Flickable.StopAtBounds
          highlightMoveDuration: 170
          highlightMoveVelocity: -1

          highlight: Rectangle {
            radius: Math.max(Style.cornerRadius - 4, 12)
            color: "transparent"
            border.color: root.selectedBorderColor
            border.width: 2
          }

          delegate: Rectangle {
            id: windowCard
            required property var modelData
            required property int index
            readonly property bool selected: index === root.selectedIndex

            width: root.cardWidth
            height: root.cardHeight
            radius: Math.max(Style.cornerRadius - 4, 12)
            color: selected ? root.selectedColor : "transparent"
            border.color: selected ? root.selectedBorderColor : "transparent"
            border.width: selected ? 1 : 0
            scale: selected ? 1.0 : 0.91
            y: selected ? 0 : Style.space(7)
            opacity: selected ? 1 : 0.68

            Behavior on scale { NumberAnimation { duration: 170; easing.type: Easing.OutCubic } }
            Behavior on y { NumberAnimation { duration: 170; easing.type: Easing.OutCubic } }
            Behavior on opacity { NumberAnimation { duration: 140 } }
            Behavior on color { ColorAnimation { duration: 140 } }

            Column {
              anchors.fill: parent
              anchors.margins: Style.spacing.md
              spacing: Style.spacing.sm

              Item {
                width: parent.width
                height: Math.max(Style.space(76), 76)

                Image {
                  anchors.centerIn: parent
                  width: Math.max(Style.space(68), 68)
                  height: width
                  source: String(windowCard.modelData.iconSource || "")
                  fillMode: Image.PreserveAspectFit
                  sourceSize.width: width * Screen.devicePixelRatio
                  sourceSize.height: height * Screen.devicePixelRatio
                  asynchronous: true
                  smooth: true
                }
              }

              Text {
                width: parent.width
                text: String(windowCard.modelData.appName || "Application")
                color: windowCard.selected ? root.selectedTextColor : root.foregroundColor
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                maximumLineCount: 1
                font.family: Style.font.menuFamily
                font.pixelSize: Style.font.body
                font.weight: windowCard.selected ? Font.DemiBold : Font.Medium
              }

              Text {
                width: parent.width
                text: String(windowCard.modelData.displayTitle || "")
                color: windowCard.selected ? root.selectedTextColor : root.foregroundColor
                opacity: 0.7
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                maximumLineCount: 1
                font.family: Style.font.menuFamily
                font.pixelSize: Style.font.caption
              }
            }

            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              onEntered: root.selectedIndex = windowCard.index
              onClicked: root.commit()
            }
          }
        }
      }
    }
  }
}
