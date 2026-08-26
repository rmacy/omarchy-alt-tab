import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

Item {
  id: root

  property var shell: null
  property string omarchyPath: ""
  readonly property string ownerToken: "bitr0t.window-switcher-" + Date.now()
    + "-" + Math.random().toString(36).slice(2)
  property bool applyQueued: false
  property bool shuttingDown: false

  function applyLua() {
    return [
      'local owner = "' + root.ownerToken + '"',
      '_G.bitr0t_window_switcher_owner = owner',
      'hl.unbind("ALT + TAB")',
      'hl.unbind("ALT + SHIFT + TAB")',
      'hl.bind("ALT + TAB",',
      '  hl.dsp.exec_cmd("omarchy-shell -q shell call bitr0t.window-switcher advance 1"),',
      '  { description = "Window switcher" })',
      'hl.bind("ALT + SHIFT + TAB",',
      '  hl.dsp.exec_cmd("omarchy-shell -q shell call bitr0t.window-switcher advance -1"),',
      '  { description = "Window switcher (reverse)" })'
    ].join("\n")
  }

  function cleanupLua() {
    return [
      'local owner = "' + root.ownerToken + '"',
      'if _G.bitr0t_window_switcher_owner == owner then',
      '  _G.bitr0t_window_switcher_owner = nil',
      '  hl.unbind("ALT + TAB")',
      '  hl.unbind("ALT + SHIFT + TAB")',
      'end'
    ].join("\n")
  }

  function queueApply() {
    if (!root.shuttingDown) applyTimer.restart()
  }

  function applyBindings() {
    if (root.shuttingDown) return
    if (applyProcess.running) {
      root.applyQueued = true
      return
    }
    root.applyQueued = false
    applyProcess.command = ["hyprctl", "eval", root.applyLua()]
    applyProcess.running = true
  }

  Timer {
    id: applyTimer
    interval: 100
    repeat: false
    onTriggered: root.applyBindings()
  }

  Process {
    id: applyProcess
    onExited: function(exitCode) {
      if (root.shuttingDown) return
      if (exitCode !== 0)
        console.warn("bitr0t.window-switcher: failed to register Alt-Tab bindings (exit " + exitCode + ")")
      if (root.applyQueued) root.queueApply()
    }
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (event && String(event.name) === "configreloaded") root.queueApply()
    }
  }

  Component.onCompleted: root.queueApply()

  Component.onDestruction: {
    root.shuttingDown = true
    applyTimer.stop()
    if (applyProcess.running) applyProcess.running = false
    Quickshell.execDetached([
      "sh", "-c",
      'hyprctl eval "$1" >/dev/null 2>&1; hyprctl reload >/dev/null 2>&1',
      "window-switcher-cleanup", root.cleanupLua()
    ])
  }
}
