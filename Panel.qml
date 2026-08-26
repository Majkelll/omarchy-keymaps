import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "io.github.majkelll.omarchy-keymaps"
  ipcTarget: "io.github.majkelll.omarchy-keymaps"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  property var configuredLayouts: []
  property var availableLayouts: []
  property var remapPairs: []
  property string keyboardName: ""
  property string scriptPath: ""
  property int activeLayoutIndex: 0
  property string searchText: ""
  property bool remapSwapToo: true
  property bool remapExpanded: false
  // "" when idle, "from" while waiting for the key to remap, "to" while
  // waiting for the key it should act as.
  property string captureStage: ""
  property var captureFrom: null
  property string captureError: ""
  property string errorText: ""
  property bool cursorActive: false
  property int selectedIndex: 0

  readonly property color contentForeground: bar ? bar.foreground : Color.foreground
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property var visibleAvailableLayouts: Model.filterAvailable(
    availableLayouts, configuredLayouts, searchText)

  function open() {
    root.refresh()
    root.controller.show()
    Qt.callLater(function() { if (root.opened) keyCatcher.forceActiveFocus() })
  }

  function close() {
    root.controller.hide()
    root.cursorActive = false
    root.errorText = ""
    root.captureStage = ""
    root.captureFrom = null
    root.captureError = ""
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function refresh() {
    if (!xkbProc.running) xkbProc.running = true
  }

  function setFromHost() {
    if (hostWidget && hostWidget.configuredLayouts)
      root.configuredLayouts = hostWidget.configuredLayouts
    if (hostWidget && hostWidget.remapPairs)
      root.remapPairs = hostWidget.remapPairs
    if (hostWidget) {
      root.activeLayoutIndex = hostWidget.activeLayoutIndex
      root.keyboardName = hostWidget.keyboardName
      root.scriptPath = hostWidget.scriptPath
    }
  }

  function applyState(entries, index, pairs) {
    if (entries.length === 0 || applyProc.running) return
    var serialized = Model.serializeEntries(entries)
    var boundedIndex = Math.max(0, Math.min(Number(index) || 0, entries.length - 1))
    var body = Model.remapPairsToSymbolsBody(pairs)
    root.errorText = ""
    applyProc.command = [root.scriptPath, serialized.layouts, serialized.variants,
      String(boundedIndex), root.keyboardName, body === "" ? "" : Qt.btoa(body)]
    applyProc.running = true
  }

  function chooseLayout(index) {
    root.activeLayoutIndex = index
    applyState(root.configuredLayouts, index, root.remapPairs)
  }

  function addLayout(entry) {
    var next = root.configuredLayouts.slice()
    next.push({ layout: entry.layout, variant: entry.variant, description: entry.description })
    root.configuredLayouts = next
    root.searchText = ""
    root.activeLayoutIndex = next.length - 1
    applyState(next, root.activeLayoutIndex, root.remapPairs)
  }

  function removeLayout(index) {
    if (root.configuredLayouts.length <= 1) return
    var next = root.configuredLayouts.slice()
    next.splice(index, 1)
    var nextIndex = Math.min(root.activeLayoutIndex, next.length - 1)
    root.configuredLayouts = next
    root.activeLayoutIndex = nextIndex
    applyState(next, nextIndex, root.remapPairs)
  }

  function startCapture() {
    root.captureStage = "from"
    root.captureFrom = null
    root.captureError = ""
    Qt.callLater(function() { captureCatcher.forceActiveFocus() })
  }

  function cancelCapture() {
    root.captureStage = ""
    root.captureFrom = null
    root.captureError = ""
    Qt.callLater(function() { if (root.opened) keyCatcher.forceActiveFocus() })
  }

  function acceptCapturedKey(entry) {
    if (root.captureStage === "from") {
      root.captureFrom = entry
      root.captureStage = "to"
      root.captureError = ""
      return
    }
    var from = root.captureFrom
    root.cancelCapture()
    root.addRemapPair(from, entry, root.remapSwapToo)
  }

  function addRemapPair(fromEntry, toEntry, alsoSwap) {
    if (!fromEntry || !toEntry) return
    var next = root.remapPairs.filter(function(p) {
      return p.from !== fromEntry.code && (!alsoSwap || p.from !== toEntry.code)
    })
    next.push({ from: fromEntry.code, to: toEntry.keysym })
    if (alsoSwap && toEntry.code !== fromEntry.code)
      next.push({ from: toEntry.code, to: fromEntry.keysym })
    root.remapPairs = next
    root.remapExpanded = true
    applyState(root.configuredLayouts, root.activeLayoutIndex, next)
  }

  // Takes every source key a displayed row stands for, so removing a swap
  // drops both of its directions at once.
  function removeRemapGroup(codes) {
    var next = root.remapPairs.filter(function(p) { return codes.indexOf(p.from) === -1 })
    root.remapPairs = next
    applyState(root.configuredLayouts, root.activeLayoutIndex, next)
  }

  readonly property var remapGroups: Model.groupRemapPairs(remapPairs)
  readonly property int visiblePairCount: root.remapExpanded ? root.remapGroups.length : 0

  function moveCursor(delta) {
    var count = root.configuredLayouts.length + root.visiblePairCount
      + root.visibleAvailableLayouts.length
    if (count === 0) return
    root.selectedIndex = (root.selectedIndex + delta + count) % count
    root.cursorActive = true
  }

  function activateCursor() {
    var configuredCount = root.configuredLayouts.length
    var pairsCount = root.visiblePairCount
    var i = root.selectedIndex

    if (i < configuredCount) chooseLayout(i)
    else if (i < configuredCount + pairsCount) removeRemapGroup(root.remapGroups[i - configuredCount].codes)
    else addLayout(root.visibleAvailableLayouts[i - configuredCount - pairsCount])
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function rowColor(hovered, selected) {
    if (selected) return Style.selectedFillFor(contentForeground, Color.accent)
    if (hovered) return Style.hoverFillFor(contentForeground, Color.accent)
    return "transparent"
  }

  function rowForeground(hovered, selected) {
    if (selected) return Style.selectedStateColor(contentForeground, Color.accent)
    return hovered ? Style.hoverStateColor(contentForeground, Color.accent) : contentForeground
  }

  onHostWidgetChanged: root.setFromHost()

  Process {
    id: xkbProc
    command: ["xkbcli", "list", "--load-exotic"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.availableLayouts = Model.parseXkb(text)
    }
  }

  Process {
    id: applyProc
    onExited: function(code) {
      if (code !== 0) root.errorText = "Could not apply keyboard settings"
      else {
        root.errorText = ""
        Qt.callLater(root.refresh)
      }
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(460))
    contentHeight: panel.fittedContentHeight(contentColumn.implicitHeight, Style.space(720))

    // While a key is being captured every keystroke belongs to the capture,
    // so the panel's normal navigation handler stands down.
    Item {
      id: captureCatcher
      anchors.fill: parent
      z: 10
      enabled: root.captureStage !== ""
      focus: root.captureStage !== ""
      Keys.priority: Keys.BeforeItem

      // Anything clickable in the panel (the swap toggle, a stray control)
      // takes keyboard focus with it, which would silently strand a capture
      // waiting for a key that can no longer arrive. Take it straight back.
      onActiveFocusChanged: {
        if (!activeFocus && root.captureStage !== "")
          Qt.callLater(function() {
            if (root.captureStage !== "") captureCatcher.forceActiveFocus()
          })
      }
      // Every key is fair game here, Escape included - remapping Caps Lock to
      // Escape is the single most common reason to use this at all, so the
      // capture must never steal Escape for "cancel". Cancelling is the
      // button in the prompt instead.
      Keys.onPressed: function(event) {
        event.accepted = true
        var entry = Model.keyByScan(event.nativeScanCode)
        if (!entry) {
          root.captureError = "That key is not supported yet - try another."
          return
        }
        root.captureError = ""
        root.acceptCapturedKey(entry)
      }
    }

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.captureStage !== ""
      onMoveRequested: function(dx, dy) {
        if (dx !== 0) root.moveCursor(dx)
        else if (dy !== 0) root.moveCursor(dy)
      }
      onActivateRequested: if (root.cursorActive) root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(text) {
        if (text === "/") {
          searchField.forceActiveFocus()
        } else if (text === "r" || text === "R") {
          root.refresh()
        } else if (text === "a" || text === "A") {
          root.startCapture()
        }
      }

      Flickable {
        id: scrollArea
        anchors.fill: parent
        contentWidth: contentColumn.width
        contentHeight: contentColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        ScrollBar.vertical: ScrollBar {
          policy: scrollArea.contentHeight > scrollArea.height ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff
        }

        Column {
          id: contentColumn
          width: scrollArea.width
          spacing: Style.space(14)

          Item {
            width: parent.width
            implicitHeight: Math.max(heroIcon.implicitHeight, heroText.implicitHeight)

            Text {
              id: heroIcon
              text: "\uf11c"
              color: root.contentForeground
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.display
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
            }

            Column {
              id: heroText
              anchors.left: heroIcon.right
              anchors.leftMargin: Style.space(14)
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)

              Text {
                text: "Keyboard layouts"
                color: root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.title
                font.bold: true
              }

              Text {
                text: root.configuredLayouts.length + " configured - "
                  + (root.configuredLayouts[root.activeLayoutIndex]
                    ? root.configuredLayouts[root.activeLayoutIndex].description
                    : "no active layout")
                color: Qt.darker(root.contentForeground, 1.4)
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 1.1
                elide: Text.ElideRight
                width: parent.width
              }
            }
          }

          PanelSeparator { foreground: root.contentForeground }

          PanelSectionHeader {
            text: "ACTIVE LAYOUTS"
            foreground: root.contentForeground
            fontFamily: root.contentFontFamily
          }

          Column {
            width: parent.width
            spacing: Style.space(4)

            Repeater {
              model: root.configuredLayouts

              delegate: Rectangle {
                required property var modelData
                required property int index
                width: parent ? parent.width : 0
                height: Style.space(44)
                radius: Style.space(7)
                color: root.rowColor(mouse.containsMouse,
                  root.cursorActive && root.selectedIndex === index)

                Text {
                  text: Model.labelFor(modelData)
                  color: root.rowForeground(mouse.containsMouse,
                    root.cursorActive && root.selectedIndex === index)
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.body
                  font.bold: true
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(12)
                  anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                  text: modelData.description
                  color: Qt.darker(root.contentForeground, 1.45)
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.caption
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(62)
                  anchors.right: removeButton.left
                  anchors.rightMargin: Style.space(8)
                  anchors.verticalCenter: parent.verticalCenter
                  elide: Text.ElideRight
                }

                Text {
                  id: removeButton
                  text: "\uf2ed"
                  visible: root.configuredLayouts.length > 1
                  color: mouse.containsMouse ? Color.urgent : Qt.darker(root.contentForeground, 1.35)
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.body
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(12)
                  anchors.verticalCenter: parent.verticalCenter

                  MouseArea {
                    id: removeMouse
                    anchors.fill: parent
                    anchors.margins: -Style.space(8)
                    hoverEnabled: true
                    onClicked: root.removeLayout(index)
                  }
                }

                Rectangle {
                  visible: index === root.activeLayoutIndex
                  width: Style.space(3)
                  height: Style.space(24)
                  radius: width / 2
                  color: Color.accent
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                }

                MouseArea {
                  id: mouse
                  anchors.fill: parent
                  anchors.rightMargin: removeButton.visible ? Style.space(38) : 0
                  hoverEnabled: true
                  onEntered: { root.cursorActive = true; root.selectedIndex = index }
                  onClicked: root.chooseLayout(index)
                }
              }
            }
          }

          PanelSeparator { foreground: root.contentForeground }

          PanelSectionHeader {
            text: "KEY REMAPPING"
            foreground: root.contentForeground
            fontFamily: root.contentFontFamily
          }

          // Collapsible summary of what is already mapped.
          Rectangle {
            width: parent.width
            visible: root.remapGroups.length > 0
            height: Style.space(38)
            radius: Style.space(7)
            color: root.rowColor(summaryMouse.containsMouse, false)

            Text {
              text: (root.remapExpanded ? "▾  " : "▸  ")
                + root.remapGroups.length + (root.remapGroups.length === 1 ? " remap" : " remaps")
              color: root.rowForeground(summaryMouse.containsMouse, false)
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.body
              font.bold: true
              anchors.left: parent.left
              anchors.leftMargin: Style.space(12)
              anchors.verticalCenter: parent.verticalCenter
            }

            MouseArea {
              id: summaryMouse
              anchors.fill: parent
              hoverEnabled: true
              onClicked: root.remapExpanded = !root.remapExpanded
            }
          }

          Column {
            width: parent.width
            spacing: Style.space(4)
            visible: root.remapExpanded && root.remapGroups.length > 0

            Repeater {
              model: root.remapGroups

              delegate: Rectangle {
                required property var modelData
                required property int index
                readonly property int cursorIndex: root.configuredLayouts.length + index
                width: parent ? parent.width : 0
                height: Style.space(40)
                radius: Style.space(7)
                color: root.rowColor(mouse.containsMouse,
                  root.cursorActive && root.selectedIndex === cursorIndex)

                Text {
                  text: Model.keyLabel(modelData.from)
                    + (modelData.both ? "  ⇄  " : "  →  ")
                    + Model.keysymLabel(modelData.to)
                  color: root.rowForeground(mouse.containsMouse,
                    root.cursorActive && root.selectedIndex === cursorIndex)
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.body
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(24)
                  anchors.right: removeRemapButton.left
                  anchors.rightMargin: Style.space(8)
                  anchors.verticalCenter: parent.verticalCenter
                  elide: Text.ElideRight
                }

                Text {
                  id: removeRemapButton
                  text: ""
                  color: mouse.containsMouse ? Color.urgent : Qt.darker(root.contentForeground, 1.35)
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.body
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(12)
                  anchors.verticalCenter: parent.verticalCenter
                }

                MouseArea {
                  id: mouse
                  anchors.fill: parent
                  hoverEnabled: true
                  onEntered: { root.cursorActive = true; root.selectedIndex = cursorIndex }
                  onClicked: root.removeRemapGroup(modelData.codes)
                }
              }
            }
          }

          // Idle: the button that starts a capture.
          Rectangle {
            width: parent.width
            visible: root.captureStage === ""
            height: Style.space(42)
            radius: Style.space(7)
            color: root.rowColor(addMouse.containsMouse, false)
            border.width: 1
            border.color: Qt.darker(root.contentForeground, 2.2)

            Text {
              text: "+  Add a key remap"
              color: addMouse.containsMouse ? Color.accent : root.contentForeground
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.body
              font.bold: true
              anchors.centerIn: parent
            }

            MouseArea {
              id: addMouse
              anchors.fill: parent
              hoverEnabled: true
              onClicked: root.startCapture()
            }
          }

          // Capturing: prompt for the physical key press.
          Rectangle {
            width: parent.width
            visible: root.captureStage !== ""
            height: captureColumn.implicitHeight + Style.space(24)
            radius: Style.space(7)
            color: Style.hoverFillFor(root.contentForeground, Color.accent)
            border.width: 1
            border.color: Color.accent

            Column {
              id: captureColumn
              anchors.centerIn: parent
              width: parent.width - Style.space(24)
              spacing: Style.space(6)

              Text {
                text: root.captureStage === "from"
                  ? "Press the key you want to remap"
                  : "Now press the key it should act as"
                color: root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.body
                font.bold: true
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
              }

              Text {
                visible: root.captureFrom !== null
                text: root.captureFrom ? "Remapping " + root.captureFrom.label : ""
                color: Color.accent
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
              }

              Text {
                visible: root.captureError !== ""
                text: root.captureError
                color: Color.urgent
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.caption
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
              }

              Item {
                width: parent.width
                height: swapCheck.implicitHeight

                CheckBox {
                  id: swapCheck
                  anchors.horizontalCenter: parent.horizontalCenter
                  // Never pull keyboard focus out of an in-progress capture.
                  focusPolicy: Qt.NoFocus
                  text: "Map both ways"
                  checked: root.remapSwapToo
                  onToggled: {
                    root.remapSwapToo = checked
                    captureCatcher.forceActiveFocus()
                  }
                  contentItem: Text {
                    text: parent.text
                    color: root.contentForeground
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                    leftPadding: parent.indicator.width + parent.spacing
                    verticalAlignment: Text.AlignVCenter
                  }
                }
              }

              Item {
                width: parent.width
                height: cancelLabel.implicitHeight + Style.space(12)

                Rectangle {
                  anchors.centerIn: parent
                  width: cancelLabel.implicitWidth + Style.space(24)
                  height: parent.height
                  radius: Style.space(6)
                  color: cancelMouse.containsMouse
                    ? Style.hoverFillFor(root.contentForeground, Color.urgent)
                    : "transparent"

                  Text {
                    id: cancelLabel
                    text: "Cancel"
                    color: cancelMouse.containsMouse
                      ? Color.urgent
                      : Qt.darker(root.contentForeground, 1.4)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                    anchors.centerIn: parent
                  }

                  MouseArea {
                    id: cancelMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: root.cancelCapture()
                  }
                }
              }
            }
          }

          PanelSeparator { foreground: root.contentForeground }

          PanelSectionHeader {
            text: "ADD LAYOUT"
            foreground: root.contentForeground
            fontFamily: root.contentFontFamily
          }

          TextField {
            id: searchField
            width: parent.width
            placeholderText: "Search XKB layouts or variants"
            text: root.searchText
            color: root.contentForeground
            font.family: root.contentFontFamily
            onTextChanged: root.searchText = text
            onAccepted: {
              if (root.visibleAvailableLayouts.length > 0)
                root.addLayout(root.visibleAvailableLayouts[0])
            }
          }

          Text {
            visible: root.visibleAvailableLayouts.length === 0
            text: root.searchText === "" ? "Type to search all XKB layouts" : "No matching layouts"
            color: Qt.darker(root.contentForeground, 1.45)
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.caption
          }

          Column {
            width: parent.width
            spacing: Style.space(4)

            Repeater {
              model: root.visibleAvailableLayouts

              delegate: Rectangle {
                required property var modelData
                required property int index
                width: parent ? parent.width : 0
                height: Style.space(42)
                radius: Style.space(7)
                readonly property int cursorIndex: root.configuredLayouts.length
                  + root.visiblePairCount + index
                color: root.rowColor(mouse.containsMouse,
                  root.cursorActive && root.selectedIndex === cursorIndex)

                Text {
                  text: Model.labelFor(modelData)
                  color: root.rowForeground(mouse.containsMouse,
                    root.cursorActive && root.selectedIndex === cursorIndex)
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.body
                  font.bold: true
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(12)
                  anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                  text: modelData.description
                  color: Qt.darker(root.contentForeground, 1.45)
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.caption
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(62)
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(12)
                  anchors.verticalCenter: parent.verticalCenter
                  elide: Text.ElideRight
                }

                Text {
                  text: "+"
                  color: Color.accent
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.title
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(12)
                  anchors.verticalCenter: parent.verticalCenter
                }

                MouseArea {
                  id: mouse
                  anchors.fill: parent
                  hoverEnabled: true
                  onEntered: {
                    root.cursorActive = true
                    root.selectedIndex = cursorIndex
                  }
                  onClicked: root.addLayout(modelData)
                }
              }
            }
          }

          Text {
            visible: root.errorText !== ""
            text: root.errorText
            color: Color.urgent
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
            width: parent.width
          }

          Text {
            text: "Click a layout to activate it, or add a key remap by pressing the two keys."
            color: Qt.darker(root.contentForeground, 1.55)
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.caption
            width: parent.width
            wrapMode: Text.WordWrap
          }
        }
      }
    }
  }
}
