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
  property string keyboardName: ""
  property string scriptPath: ""
  property int activeLayoutIndex: 0
  property string searchText: ""
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
    if (hostWidget) {
      root.activeLayoutIndex = hostWidget.activeLayoutIndex
      root.keyboardName = hostWidget.keyboardName
      root.scriptPath = hostWidget.scriptPath
    }
  }

  function applyEntries(entries, index) {
    if (entries.length === 0 || applyProc.running) return
    var serialized = Model.serializeEntries(entries)
    var boundedIndex = Math.max(0, Math.min(Number(index) || 0, entries.length - 1))
    root.errorText = ""
    applyProc.command = [root.scriptPath, serialized.layouts, serialized.variants,
      String(boundedIndex), root.keyboardName]
    applyProc.running = true
  }

  function chooseLayout(index) {
    root.activeLayoutIndex = index
    applyEntries(root.configuredLayouts, index)
  }

  function addLayout(entry) {
    var next = root.configuredLayouts.slice()
    next.push({ layout: entry.layout, variant: entry.variant, description: entry.description })
    root.configuredLayouts = next
    root.searchText = ""
    root.activeLayoutIndex = next.length - 1
    applyEntries(next, root.activeLayoutIndex)
  }

  function removeLayout(index) {
    if (root.configuredLayouts.length <= 1) return
    var next = root.configuredLayouts.slice()
    next.splice(index, 1)
    var nextIndex = Math.min(root.activeLayoutIndex, next.length - 1)
    root.configuredLayouts = next
    root.activeLayoutIndex = nextIndex
    applyEntries(next, nextIndex)
  }

  function moveCursor(delta) {
    var count = root.configuredLayouts.length + root.visibleAvailableLayouts.length
    if (count === 0) return
    root.selectedIndex = (root.selectedIndex + delta + count) % count
    root.cursorActive = true
  }

  function activateCursor() {
    var configuredCount = root.configuredLayouts.length
    if (root.selectedIndex < configuredCount) chooseLayout(root.selectedIndex)
    else addLayout(root.visibleAvailableLayouts[root.selectedIndex - configuredCount])
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
      if (code !== 0) root.errorText = "Could not apply keyboard layout"
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
    contentHeight: panel.fittedContentHeight(contentColumn.implicitHeight, Style.space(620))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
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
                color: root.rowColor(mouse.containsMouse,
                  root.cursorActive && root.selectedIndex === root.configuredLayouts.length + index)

                Text {
                  text: Model.labelFor(modelData)
                  color: root.rowForeground(mouse.containsMouse,
                    root.cursorActive && root.selectedIndex === root.configuredLayouts.length + index)
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
                    root.selectedIndex = root.configuredLayouts.length + index
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
            text: "Click a layout to activate it. Search to add another."
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
