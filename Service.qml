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
      'local submap = "bitr0t-window-switcher"',
      '_G.bitr0t_window_switcher_owner = owner',
      '_G.bitr0t_window_switcher_active = false',
      'local function shell_call(method, argument)',
      '  local suffix = argument and (" " .. argument) or ""',
      '  hl.exec_cmd("omarchy-shell -q shell call bitr0t.window-switcher " .. method .. suffix)',
      'end',
      'local function reset_and_call(method)',
      '  if _G.bitr0t_window_switcher_owner ~= owner or not _G.bitr0t_window_switcher_active then return end',
      '  _G.bitr0t_window_switcher_active = false',
      '  hl.dispatch(hl.dsp.submap("reset"))',
      '  if method then',
      '    hl.timer(function() shell_call(method, "ignored") end, { timeout = 40, type = "oneshot" })',
      '  end',
      'end',
      'local function begin(direction)',
      '  _G.bitr0t_window_switcher_active = true',
      '  hl.dispatch(hl.dsp.submap(submap))',
      '  shell_call("advance", tostring(direction))',
      'end',
      'hl.unbind("ALT + TAB")',
      'hl.unbind("ALT + SHIFT + TAB")',
      'hl.unbind("ALT + ALT_L")',
      'hl.unbind("ALT + ALT_R")',
      'hl.define_submap(submap, function()',
      '  hl.bind("ALT + TAB", function() shell_call("advance", "1") end,',
      '    { description = "Window switcher: next" })',
      '  hl.bind("ALT + SHIFT + TAB", function() shell_call("advance", "-1") end,',
      '    { description = "Window switcher: previous" })',
      '  hl.bind("ESCAPE", function() reset_and_call("cancel") end,',
      '    { description = "Window switcher: cancel" })',
      '  hl.bind("RETURN", function() reset_and_call("commit") end,',
      '    { description = "Window switcher: select" })',
      'end)',
      'hl.bind("ALT + TAB", function() begin(1) end,',
      '  { description = "Window switcher" })',
      'hl.bind("ALT + SHIFT + TAB", function() begin(-1) end,',
      '  { description = "Window switcher (reverse)" })',
      'hl.bind("ALT + ALT_L", function() reset_and_call("commit") end,',
      '  { release = true, non_consuming = true, submap_universal = true })',
      'hl.bind("ALT + ALT_R", function() reset_and_call("commit") end,',
      '  { release = true, non_consuming = true, submap_universal = true })'
    ].join("\n")
  }

  function cleanupLua() {
    return [
      'local owner = "' + root.ownerToken + '"',
      'if _G.bitr0t_window_switcher_owner == owner then',
      '  _G.bitr0t_window_switcher_owner = nil',
      '  _G.bitr0t_window_switcher_active = false',
      '  hl.dispatch(hl.dsp.submap("reset"))',
      '  hl.unbind("ALT + TAB")',
      '  hl.unbind("ALT + SHIFT + TAB")',
      '  hl.unbind("ALT + ALT_L")',
      '  hl.unbind("ALT + ALT_R")',
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
