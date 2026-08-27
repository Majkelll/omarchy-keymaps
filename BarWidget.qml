import QtQuick
import Quickshell.Hyprland
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

BarWidget {
  id: root
  moduleName: "io.github.majkelll.omarchy-keymaps"

  property var configuredLayouts: []
  property var remapPairs: []
  property string layoutFull: ""
  property string keyboardName: ""
  property int activeLayoutIndex: 0
  property bool refreshPending: false
  property string layoutOutput: ""
  property string variantOutput: ""

  readonly property string scriptPath: String(Qt.resolvedUrl("scripts/omarchy-keymaps-set")).replace(/^file:\/\//, "")
  readonly property string layoutLabel: configuredLayouts.length > 0
    ? Model.labelFor(configuredLayouts[Math.min(activeLayoutIndex, configuredLayouts.length - 1)])
    : "-"
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  function refresh() {
    if (layoutProc.running || variantProc.running || devicesProc.running || remapProc.running) {
      refreshPending = true
      return
    }
    refreshPending = false
    layoutProc.running = true
    variantProc.running = true
    devicesProc.running = true
    remapProc.running = true
  }

  // State the panel mirrors, by the name it carries on both sides. The panel is
  // a separately loaded component, so each name is checked rather than assumed.
  readonly property var mirroredProperties: ["bar", "settings", "configuredLayouts",
    "remapPairs", "activeLayoutIndex", "keyboardName", "scriptPath"]

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
    for (var i = 0; i < root.mirroredProperties.length; i++) {
      var name = root.mirroredProperties[i]
      if (name in target) target[name] = root[name]
    }
  }

  function updateConfigured() {
    var layoutRaw = Model.optionString(root.layoutOutput)
    var variantRaw = Model.optionString(root.variantOutput)
    root.configuredLayouts = Model.layoutEntries(layoutRaw, variantRaw)
    root.injectPanel()
  }

  function updateDevices(raw) {
    var devices
    try { devices = JSON.parse(String(raw || "{}")).keyboards || [] }
    catch (error) { devices = [] }

    var candidate = null
    for (var i = 0; i < devices.length; i++) {
      var name = String(devices[i].name || "")
      if (name.indexOf("hl-virtual-keyboard") === 0) continue
      if (name === "video-bus" || name.indexOf("power-button") === 0) continue
      if (name.endsWith("-system-control") || name.endsWith("-consumer-control")) continue
      candidate = devices[i]
      if (devices[i].main) break
    }

    if (!candidate) return
    root.keyboardName = String(candidate.name || "")
    root.layoutFull = String(candidate.active_keymap || "")
    root.activeLayoutIndex = Number(candidate.active_layout_index || 0)
    root.injectPanel()
  }

  function open() {
    root.refresh()
    if (panelLoader.item) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  Component.onCompleted: root.refresh()
  onBarChanged: root.injectPanel()
  onSettingsChanged: root.injectPanel()
  onConfiguredLayoutsChanged: root.injectPanel()
  onRemapPairsChanged: root.injectPanel()
  onActiveLayoutIndexChanged: root.injectPanel()
  onKeyboardNameChanged: root.injectPanel()

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (!event || !event.name) return
      var name = String(event.name)
      if (name.indexOf("activelayout") !== -1 || name === "configreloaded") root.refresh()
    }
  }

  Process {
    id: layoutProc
    command: ["hyprctl", "getoption", "input:kb_layout", "-j"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.layoutOutput = text
        root.updateConfigured()
      }
    }
    onRunningChanged: if (!running && root.refreshPending) Qt.callLater(root.refresh)
  }

  Process {
    id: variantProc
    command: ["hyprctl", "getoption", "input:kb_variant", "-j"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.variantOutput = text
        root.updateConfigured()
      }
    }
    onRunningChanged: if (!running && root.refreshPending) Qt.callLater(root.refresh)
  }

  Process {
    id: devicesProc
    command: ["hyprctl", "-j", "devices"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.updateDevices(text)
    }
    onRunningChanged: if (!running && root.refreshPending) Qt.callLater(root.refresh)
  }

  Process {
    id: remapProc
    command: ["bash", "-lc", "cat \"$HOME/.config/xkb/symbols/omarchy-keymaps\" 2>/dev/null || true"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.remapPairs = Model.parseSymbolsBody(text)
        root.injectPanel()
      }
    }
    onRunningChanged: if (!running && root.refreshPending) Qt.callLater(root.refresh)
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  IpcHandler {
    target: "io.github.majkelll.omarchy-keymaps"
    function refresh(): void { root.refresh() }
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.layoutLabel
    fontSize: Style.font.caption
    horizontalMargin: 6
    tooltipText: root.layoutFull || "Keyboard layouts"
    onPressed: function() { root.toggle() }
  }
}
