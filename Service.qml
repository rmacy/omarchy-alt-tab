import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import "BindingScript.js" as BindingScript

Item {
  id: root

  property var shell: null
  property string omarchyPath: ""
  readonly property string ownerToken: "bitr0t.window-switcher-" + Date.now()
    + "-" + Math.random().toString(36).slice(2)
  property bool applyQueued: false
  property bool shuttingDown: false
  property int applyAttempts: 0
  property bool registrationFailed: false

  function queueApply() {
    if (root.shuttingDown) return
    root.applyAttempts = 0
    root.registrationFailed = false
    applyTimer.restart()
  }

  function applyBindings() {
    if (root.shuttingDown) return
    if (applyProcess.running) {
      root.applyQueued = true
      return
    }
    root.applyQueued = false
    applyProcess.command = ["hyprctl", "eval",
      BindingScript.generateApply({ ownerToken: root.ownerToken })]
    applyProcess.running = true
  }

  function notifyRegistrationFailure() {
    Quickshell.execDetached([
      "notify-send", "-u", "critical", "-a", "Window Switcher",
      "Window Switcher Alt-Tab registration failed",
      "Alt-Tab bindings could not be registered after "
        + BindingScript.REGISTRATION_RETRY.maxAttempts
        + " attempts. Run hyprctl reload to retry."
    ])
  }

  Timer {
    id: applyTimer
    interval: 100
    repeat: false
    onTriggered: root.applyBindings()
  }

  Timer {
    id: retryTimer
    repeat: false
    onTriggered: root.applyBindings()
  }

  Process {
    id: applyProcess
    onExited: function(exitCode) {
      if (root.shuttingDown) return
      if (exitCode === 0) {
        root.applyAttempts = 0
        root.registrationFailed = false
      } else {
        root.applyAttempts += 1
        if (root.applyAttempts < BindingScript.REGISTRATION_RETRY.maxAttempts) {
          retryTimer.interval = BindingScript.REGISTRATION_RETRY.baseDelayMs
            * Math.pow(2, root.applyAttempts - 1)
          retryTimer.restart()
          return
        }
        if (!root.registrationFailed) {
          root.registrationFailed = true
          console.warn("bitr0t.window-switcher: Alt-Tab registration failed after "
            + root.applyAttempts + " attempts")
          root.notifyRegistrationFailure()
        }
      }
      if (root.applyQueued) root.queueApply()
    }
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (!event || String(event.name) !== "configreloaded") return
      if (root.shell && typeof root.shell.callIfLoaded === "function")
        root.shell.callIfLoaded("bitr0t.window-switcher", "cancel", "config-reload")
      root.queueApply()
    }
  }

  Component.onCompleted: root.queueApply()

  Component.onDestruction: {
    root.shuttingDown = true
    applyTimer.stop()
    retryTimer.stop()
    if (applyProcess.running) applyProcess.running = false
    Quickshell.execDetached([
      "sh", "-c",
      'hyprctl eval "$1" >/dev/null 2>&1; hyprctl reload >/dev/null 2>&1',
      "window-switcher-cleanup",
      BindingScript.generateCleanup({ ownerToken: root.ownerToken })
    ])
  }
}
