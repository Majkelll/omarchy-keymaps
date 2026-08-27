import QtQuick
import QtQuick.Controls
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

  // Mirrored from the bar widget, which owns every hyprctl read.
  property var configuredLayouts: []
  property var remapPairs: []
  property string keyboardName: ""
  property string scriptPath: ""
  property int activeLayoutIndex: 0

  property var availableLayouts: []
  property string searchText: ""
  property bool remapExpanded: false
  property bool remapSwapToo: true
  property string errorText: ""

  // "" when idle, "from" while waiting for the key to remap, "to" while
  // waiting for the key it should act as.
  property string captureStage: ""
  property var captureFrom: null
  property string captureError: ""

  // Single cursor shared by keyboard and mouse, in sections:
  //   "layouts"   - configured layouts; Enter activates, x removes.
  //   "remaps"    - configured remaps, only while expanded; Enter/x removes.
  //   "available" - search results; Enter adds.
  property string focusSection: "layouts"
  property int selectedIndex: 0
  property bool cursorActive: false

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.45)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property var remapGroups: Model.groupRemapPairs(remapPairs)
  readonly property var visibleAvailableLayouts: Model.filterAvailable(
    availableLayouts, configuredLayouts, searchText)
  readonly property var activeLayout: configuredLayouts[activeLayoutIndex] || null
  readonly property var describedLayouts: Model.describeEntries(configuredLayouts, availableLayouts)

  // Layout descriptions differ depending on where the entry came from (the XKB
  // catalogue names them, a reload from hyprctl only knows the code), so the
  // hero counts instead of naming.
  readonly property string summaryText: {
    var layouts = configuredLayouts.length
    if (layouts === 0) return "No layout configured"
    var text = layouts + (layouts === 1 ? " layout" : " layouts")
    var remaps = remapGroups.length
    if (remaps > 0) text += " - " + remaps + (remaps === 1 ? " remap" : " remaps")
    return text
  }

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
    if (!hostWidget) return
    if (hostWidget.configuredLayouts) root.configuredLayouts = hostWidget.configuredLayouts
    if (hostWidget.remapPairs) root.remapPairs = hostWidget.remapPairs
    root.activeLayoutIndex = hostWidget.activeLayoutIndex
    root.keyboardName = hostWidget.keyboardName
    root.scriptPath = hostWidget.scriptPath
  }

  onHostWidgetChanged: root.setFromHost()

  // Every apply ships the complete state - layouts, variants, active index and
  // remaps - through one script call, so a layout edit can never drop a remap
  // (or the reverse) by writing half the configuration.
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
    root.applyState(root.configuredLayouts, index, root.remapPairs)
  }

  function addLayout(entry) {
    if (!entry) return
    var next = root.configuredLayouts.slice()
    next.push({ layout: entry.layout, variant: entry.variant, description: entry.description })
    root.configuredLayouts = next
    root.searchText = ""
    root.activeLayoutIndex = next.length - 1
    root.applyState(next, root.activeLayoutIndex, root.remapPairs)
  }

  function removeLayout(index) {
    if (root.configuredLayouts.length <= 1) return
    var next = root.configuredLayouts.slice()
    next.splice(index, 1)
    var nextIndex = Math.min(root.activeLayoutIndex, next.length - 1)
    root.configuredLayouts = next
    root.activeLayoutIndex = nextIndex
    root.applyState(next, nextIndex, root.remapPairs)
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
      return
    }
    var from = root.captureFrom
    root.cancelCapture()
    root.addRemapPair(from, entry, root.remapSwapToo)
  }

  function addRemapPair(fromEntry, toEntry, alsoSwap) {
    if (!fromEntry || !toEntry) return
    var next = root.remapPairs.filter(function(pair) {
      return pair.from !== fromEntry.code && (!alsoSwap || pair.from !== toEntry.code)
    })
    next.push({ from: fromEntry.code, to: toEntry.keysym })
    if (alsoSwap && toEntry.code !== fromEntry.code)
      next.push({ from: toEntry.code, to: fromEntry.keysym })
    root.remapPairs = next
    root.remapExpanded = true
    root.applyState(root.configuredLayouts, root.activeLayoutIndex, next)
  }

  // `codes` carries every source key the displayed row stands for, so removing
  // a two-way row drops both of its directions at once.
  function removeRemapGroup(codes) {
    var next = root.remapPairs.filter(function(pair) { return codes.indexOf(pair.from) === -1 })
    root.remapPairs = next
    root.applyState(root.configuredLayouts, root.activeLayoutIndex, next)
  }

  function sectionCount(section) {
    if (section === "layouts") return root.configuredLayouts.length
    if (section === "remaps") return root.remapGroups.length
    if (section === "available") return root.visibleAvailableLayouts.length
    if (section === "summary" || section === "addRemap") return 1
    return 0
  }

  // Every row the arrow keys walk, in the order it is drawn. Anything not on
  // screen is not on the list: collapsed remaps, and the summary that expands
  // them when there is nothing to expand.
  readonly property var cursorRows: {
    var sections = ["layouts"]
    if (root.remapGroups.length > 0) sections.push("summary")
    if (root.remapExpanded) sections.push("remaps")
    if (root.captureStage === "") sections.push("addRemap")
    sections.push("available")

    var rows = []
    for (var i = 0; i < sections.length; i++) {
      var count = root.sectionCount(sections[i])
      for (var j = 0; j < count; j++) rows.push({ section: sections[i], index: j })
    }
    return rows
  }

  function hasCursorAt(section, index) {
    return root.cursorActive && root.focusSection === section && root.selectedIndex === index
  }

  function takeCursor(section, index) {
    root.cursorActive = true
    root.focusSection = section
    root.selectedIndex = index
  }

  function moveCursor(delta) {
    var rows = root.cursorRows
    if (rows.length === 0) return

    var at = -1
    for (var i = 0; i < rows.length; i++) {
      if (rows[i].section === root.focusSection && rows[i].index === root.selectedIndex) {
        at = i
        break
      }
    }

    var next = at === -1 ? (delta > 0 ? 0 : rows.length - 1) : (at + delta + rows.length) % rows.length
    root.takeCursor(rows[next].section, rows[next].index)
  }

  function activateCursor() {
    if (!root.cursorActive) return
    if (root.focusSection === "layouts") root.chooseLayout(root.selectedIndex)
    else if (root.focusSection === "summary") root.remapExpanded = !root.remapExpanded
    else if (root.focusSection === "remaps") root.removeSelected()
    else if (root.focusSection === "addRemap") root.startCapture()
    else root.addLayout(root.visibleAvailableLayouts[root.selectedIndex])
  }

  function removeSelected() {
    if (!root.cursorActive) return
    if (root.focusSection === "layouts") root.removeLayout(root.selectedIndex)
    else if (root.focusSection === "remaps") {
      var group = root.remapGroups[root.selectedIndex]
      if (group) root.removeRemapGroup(group.codes)
    }
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

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
      root.errorText = code === 0 ? "" : "Could not apply keyboard settings"
      if (code === 0) Qt.callLater(root.refresh)
    }
  }

  // One row of the panel's single cursor model. Visuals come from `hasCursor` /
  // `current` only - never from containsMouse - so mouse and keyboard can never
  // light up two rows at once.
  component PanelRow: CursorSurface {
    id: rowSurface

    required property string section
    required property int rowIndex
    property bool activeRow: false

    readonly property bool selected: root.hasCursorAt(section, rowIndex)

    signal activated()

    width: parent ? parent.width : 0
    hasCursor: selected
    current: activeRow
    foreground: root.foreground
    accent: Color.accent

    onSelectedChanged: if (selected) scrollArea.ensureVisible(rowSurface)

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onContainsMouseChanged: if (containsMouse) root.takeCursor(rowSurface.section, rowSurface.rowIndex)
      onClicked: rowSurface.activated()
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

    // While a key is being captured, every keystroke belongs to the capture -
    // Escape included, since remapping Caps Lock to Escape is the single most
    // common reason to open this at all. Cancelling is the button in the
    // prompt, never a key.
    Item {
      id: captureCatcher
      anchors.fill: parent
      z: 10
      enabled: root.captureStage !== ""
      focus: root.captureStage !== ""
      Keys.priority: Keys.BeforeItem

      // Anything clickable in the panel takes keyboard focus with it, which
      // would strand a capture waiting for a key that can no longer arrive.
      onActiveFocusChanged: {
        if (!activeFocus && root.captureStage !== "")
          Qt.callLater(function() {
            if (root.captureStage !== "") captureCatcher.forceActiveFocus()
          })
      }

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
      // The catcher claims plain letters (j/k/h/l navigate, x deletes), so it
      // must stand down whenever a capture or the search field owns the keys.
      blocked: root.captureStage !== "" || searchField.activeFocus
      onMoveRequested: function(dx, dy) { root.moveCursor(dx !== 0 ? dx : dy) }
      onActivateRequested: root.activateCursor()
      onDeleteRequested: root.removeSelected()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(text) {
        if (text === "/") searchField.forceActiveFocus()
        else if (text === "r" || text === "R") root.refresh()
        else if (text === "a" || text === "A") root.startCapture()
      }

      Flickable {
        id: scrollArea
        anchors.fill: parent
        contentWidth: width
        contentHeight: contentColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        // Keep a keyboard-selected row on screen; the panel is taller than its
        // cap as soon as a handful of layouts are configured.
        function ensureVisible(item) {
          if (!item || contentHeight <= height) return
          var top = item.mapToItem(contentColumn, 0, 0).y
          var margin = Style.spacing.lg
          if (top - margin < contentY) contentY = Math.max(0, top - margin)
          else if (top + item.height + margin > contentY + height)
            contentY = Math.min(contentHeight - height, top + item.height + margin - height)
        }

        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: contentColumn
          width: scrollArea.width
          spacing: Style.spacing.panelGap

          PanelHero {
            title: "Keyboard layouts"
            meta: root.summaryText
            detail: root.activeLayout ? Model.labelFor(root.activeLayout) : ""
            foreground: root.foreground
            fontFamily: root.fontFamily

            iconComponent: Component {
              Text {
                text: ""
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
              }
            }
          }

          PanelSeparator { foreground: root.foreground }

          PanelSectionHeader {
            text: "ACTIVE LAYOUTS"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Column {
            width: parent.width
            spacing: Style.spacing.sm

            Repeater {
              model: root.describedLayouts

              delegate: PanelRow {
                id: layoutRow
                required property var modelData
                required property int index

                section: "layouts"
                rowIndex: index
                activeRow: index === root.activeLayoutIndex
                implicitHeight: Style.spacing.controlHeight + Style.spacing.rowPaddingX
                onActivated: root.chooseLayout(index)

                Text {
                  id: layoutCode
                  text: Model.labelFor(layoutRow.modelData)
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  font.bold: true
                  anchors.left: parent.left
                  anchors.leftMargin: Style.spacing.rowPaddingX
                  anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                  visible: text !== ""
                  text: layoutRow.modelData.description
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  anchors.left: layoutCode.right
                  anchors.leftMargin: Style.spacing.xl
                  anchors.right: layoutRemove.visible ? layoutRemove.left : parent.right
                  anchors.rightMargin: Style.spacing.lg
                  anchors.verticalCenter: parent.verticalCenter
                  elide: Text.ElideRight
                }

                PanelActionButton {
                  id: layoutRemove
                  visible: root.configuredLayouts.length > 1 && layoutRow.selected
                  iconText: "󰅙"
                  tooltipText: "Remove layout"
                  foreground: root.foreground
                  hoverColor: Color.urgent
                  fontFamily: root.fontFamily
                  anchors.right: parent.right
                  anchors.rightMargin: Style.spacing.lg
                  anchors.verticalCenter: parent.verticalCenter
                  onClicked: root.removeLayout(layoutRow.index)
                }
              }
            }
          }

          PanelSeparator { foreground: root.foreground }

          PanelSectionHeader {
            text: "KEY REMAPPING"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          // Collapsible summary of what is already mapped.
          Button {
            width: parent.width
            visible: root.remapGroups.length > 0
            leftAlign: true
            iconText: root.remapExpanded ? "󰅀" : "󰅂"
            text: root.remapGroups.length + (root.remapGroups.length === 1 ? " remap" : " remaps")
            foreground: root.foreground
            fontFamily: root.fontFamily
            hasCursor: root.hasCursorAt("summary", 0)
            onHasCursorChanged: if (hasCursor) scrollArea.ensureVisible(this)
            onHovered: function(isHovered) { if (isHovered) root.takeCursor("summary", 0) }
            onClicked: root.remapExpanded = !root.remapExpanded
          }

          Column {
            width: parent.width
            spacing: Style.spacing.sm
            visible: root.remapExpanded && root.remapGroups.length > 0

            Repeater {
              model: root.remapGroups

              delegate: PanelRow {
                id: remapRow
                required property var modelData
                required property int index

                section: "remaps"
                rowIndex: index
                implicitHeight: Style.spacing.controlHeight + Style.spacing.lg
                onActivated: root.removeRemapGroup(modelData.codes)

                Text {
                  text: Model.keyLabel(remapRow.modelData.from)
                    + (remapRow.modelData.both ? "  ⇄  " : "  →  ")
                    + Model.keysymLabel(remapRow.modelData.to)
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  anchors.left: parent.left
                  anchors.leftMargin: Style.spacing.huge
                  anchors.right: remapRemove.visible ? remapRemove.left : parent.right
                  anchors.rightMargin: Style.spacing.lg
                  anchors.verticalCenter: parent.verticalCenter
                  elide: Text.ElideRight
                }

                PanelActionButton {
                  id: remapRemove
                  visible: remapRow.selected
                  iconText: "󰅙"
                  tooltipText: "Remove remap"
                  foreground: root.foreground
                  hoverColor: Color.urgent
                  fontFamily: root.fontFamily
                  anchors.right: parent.right
                  anchors.rightMargin: Style.spacing.lg
                  anchors.verticalCenter: parent.verticalCenter
                  onClicked: root.removeRemapGroup(remapRow.modelData.codes)
                }
              }
            }
          }

          Button {
            width: parent.width
            visible: root.captureStage === ""
            text: "Add a key remap"
            iconText: "󰐕"
            bordered: true
            foreground: root.foreground
            fontFamily: root.fontFamily
            hasCursor: root.hasCursorAt("addRemap", 0)
            onHasCursorChanged: if (hasCursor) scrollArea.ensureVisible(this)
            onHovered: function(isHovered) { if (isHovered) root.takeCursor("addRemap", 0) }
            onClicked: root.startCapture()
          }

          // Capture prompt. Everything in here is deliberately click-only: a
          // control that grabs the keyboard would eat the very keypress the
          // prompt is asking for.
          BorderSurface {
            width: parent.width
            visible: root.captureStage !== ""
            implicitHeight: captureColumn.implicitHeight + Style.spacing.huge * 2
            radius: Style.cornerRadius
            color: Style.hoverFillFor(root.foreground, Color.accent)
            borderSpec: Border.controlSpec("selected", root.foreground, Color.accent)

            Column {
              id: captureColumn
              anchors.centerIn: parent
              width: parent.width - Style.spacing.huge * 2
              spacing: Style.spacing.md

              Text {
                text: root.captureStage === "from"
                  ? "Press the key you want to remap"
                  : "Now press the key it should act as"
                color: root.foreground
                font.family: root.fontFamily
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
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
              }

              Text {
                visible: root.captureError !== ""
                text: root.captureError
                color: Color.urgent
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
              }

              Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Style.spacing.controlGap

                Text {
                  text: "Map both ways"
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  anchors.verticalCenter: parent.verticalCenter
                }

                ToggleSwitch {
                  checked: root.remapSwapToo
                  foreground: root.foreground
                  anchors.verticalCenter: parent.verticalCenter
                  onToggled: root.remapSwapToo = !root.remapSwapToo
                }
              }

              Button {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Cancel"
                bordered: true
                foreground: root.foreground
                fontFamily: root.fontFamily
                fontSize: Style.font.caption
                onClicked: root.cancelCapture()
              }
            }
          }

          PanelSeparator { foreground: root.foreground }

          PanelSectionHeader {
            text: "ADD LAYOUT"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          TextField {
            id: searchField
            width: parent.width
            placeholderText: "Search XKB layouts or variants"
            text: root.searchText
            foreground: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            onTextChanged: root.searchText = text
            onAccepted: root.addLayout(root.visibleAvailableLayouts[0])
            Keys.onEscapePressed: keyCatcher.forceActiveFocus()
          }

          Text {
            visible: root.visibleAvailableLayouts.length === 0
            text: root.searchText === "" ? "Type to search all XKB layouts" : "No matching layouts"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          Column {
            width: parent.width
            spacing: Style.spacing.sm

            Repeater {
              model: root.visibleAvailableLayouts

              delegate: PanelRow {
                id: availableRow
                required property var modelData
                required property int index

                section: "available"
                rowIndex: index
                implicitHeight: Style.spacing.controlHeight + Style.spacing.xl
                onActivated: root.addLayout(modelData)

                Text {
                  id: availableCode
                  text: Model.labelFor(availableRow.modelData)
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  font.bold: true
                  anchors.left: parent.left
                  anchors.leftMargin: Style.spacing.rowPaddingX
                  anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                  text: availableRow.modelData.description
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  anchors.left: availableCode.right
                  anchors.leftMargin: Style.spacing.xl
                  anchors.right: availableAdd.left
                  anchors.rightMargin: Style.spacing.lg
                  anchors.verticalCenter: parent.verticalCenter
                  elide: Text.ElideRight
                }

                Text {
                  id: availableAdd
                  text: "󰐕"
                  color: Color.accent
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.icon
                  anchors.right: parent.right
                  anchors.rightMargin: Style.spacing.rowPaddingX
                  anchors.verticalCenter: parent.verticalCenter
                }
              }
            }
          }

          Text {
            visible: root.errorText !== ""
            text: root.errorText
            color: Color.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            width: parent.width
            wrapMode: Text.WordWrap
          }

          Text {
            text: "Enter activates - x removes - / searches - a adds a remap - r reloads."
            color: Qt.darker(root.foreground, 1.6)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            width: parent.width
            wrapMode: Text.WordWrap
          }
        }
      }
    }
  }
}
