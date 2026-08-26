import QtQuick
import Quickshell
import qs.Commons
import "plugin" as Plugin

ShellRoot {
  id: root

  property bool failed: false
  property var instance: null
  property var originalShellValues: null
  property var originalThemeShellValues: null
  property var originalUserShellValues: null
  property color originalBackground: "transparent"

  function fail(message) {
    if (root.failed) return
    root.failed = true
    console.error("WINDOW_SWITCHER_RUNTIME_SMOKE_FAIL: " + message)
  }

  function check(condition, message) {
    if (!condition) root.fail(message)
  }

  function parsedStatus() {
    try { return JSON.parse(root.instance.status("")) }
    catch (error) { root.fail("status returned invalid JSON: " + error); return ({}) }
  }

  Component {
    id: switcherFactory
    Plugin.WindowSwitcher {}
  }

  Component.onCompleted: {
    root.instance = switcherFactory.createObject(root)
    root.check(root.instance !== null, "production WindowSwitcher failed to instantiate")
    if (!root.instance) return

    var closed = root.parsedStatus()
    root.check(closed.open === false, "initial state must be closed")

    root.instance.clients = []
    root.instance.loading = false
    root.instance.modelError = ""
    root.check(root.parsedStatus().state === "empty", "zero-client state must be empty")

    root.instance.clients = [{ stableId: "1", appName: "One", displayTitle: "Window" }]
    root.instance.selectedIndex = 0
    var single = root.parsedStatus()
    root.check(single.state === "single" && single.selectedStableId === "1",
      "single-client state or stable identity is wrong")

    root.instance.clients = [
      { stableId: "1", appName: "One", displayTitle: "First" },
      { stableId: "2", appName: "Two", displayTitle: "Second" }
    ]
    root.instance.selectedIndex = 1
    var multiple = root.parsedStatus()
    root.check(multiple.state === "multiple" && multiple.selectedStableId === "2",
      "many-client state or selection is wrong")

    root.instance.modelError = "synthetic failure"
    root.check(root.parsedStatus().state === "error", "model failure must not render as empty")
    root.instance.modelError = ""

    themeTimer.start()
  }

  Timer {
    id: themeTimer
    interval: 500
    repeat: false
    onTriggered: {
      root.originalShellValues = Color.shellValues
      root.originalThemeShellValues = Color.themeShellValues
      root.originalUserShellValues = Color.userShellValues
      root.originalBackground = Color.background
      Color.themeShellValues = ({ "menu.background": "#123456" })
      Color.userShellValues = ({})
      Color.mergeShell()
      Qt.callLater(root.finishThemeCheck)
    }
  }

  function finishThemeCheck() {
    root.check(String(root.instance.backgroundColor).toLowerCase().indexOf("123456") >= 0,
      "menu background did not react to theme token mutation (got "
        + String(root.instance.backgroundColor) + ")")
    Color.background = root.originalBackground
    Color.themeShellValues = root.originalThemeShellValues || ({})
    Color.userShellValues = root.originalUserShellValues || ({})
    Color.mergeShell()
    root.instance.cancel()
    root.check(root.parsedStatus().open === false, "cancel did not close switcher")
    if (!root.failed) console.log("WINDOW_SWITCHER_RUNTIME_SMOKE_PASS")
  }
}
