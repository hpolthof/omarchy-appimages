import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Passive mirror of BarWidget: it renders what the widget hands it and calls
// back into the widget for every read and write. Renaming happens in place --
// a row turns into a text field and back -- because a separate dialog for one
// short string is more ceremony than the job needs.
//
// A row is not itself clickable. Its two buttons are the only things that act,
// so there is never a question of what a click on a row will do, and both have
// a key of their own for the keyboard. The cursor runs past the last row into
// the footer, so sync and the folder are reachable with the arrow keys too.
Panel {
  id: root
  moduleName: "io.github.hpolthof.appimages"

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  // Mirrored from BarWidget, which owns every read and write.
  property var rows: []
  property string directory: ""
  property string listError: ""
  property string busyId: ""

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.45)
  readonly property color faint: Qt.darker(foreground, 1.7)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  // One cursor spans the rows and then the two footer buttons, so nothing in
  // the panel is mouse-only.
  readonly property int rowCount: root.rows.length
  readonly property int syncIndex: root.rowCount
  readonly property int folderIndex: root.rowCount + 1
  readonly property int cursorCount: root.rowCount + 2

  // The row being renamed, by id. At most one at a time: the field owns the
  // keyboard while it is up, so a second one would have nothing to type into.
  property string editingId: ""
  property int selectedIndex: 0
  property bool cursorActive: false

  // Deleting removes a file from disk, so it always goes through the dialog --
  // there is no keystroke or click that skips it.
  property string confirmId: ""
  property string confirmName: ""
  property bool confirmOpened: false

  function open() {
    root.controller.show()
    Qt.callLater(function() { if (root.opened) keyCatcher.forceActiveFocus() })
  }

  function close() {
    root.controller.hide()
    root.cursorActive = false
    root.editingId = ""
    root.confirmOpened = false
    root.confirmId = ""
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function hasCursorAt(index) {
    return root.cursorActive && root.selectedIndex === index
  }

  function takeCursor(index) {
    root.selectedIndex = index
    root.cursorActive = true
  }

  function moveCursor(delta) {
    if (root.cursorCount === 0) return
    var at = root.cursorActive ? root.selectedIndex : (delta > 0 ? -1 : 0)
    root.takeCursor(((at + delta) % root.cursorCount + root.cursorCount) % root.cursorCount)
  }

  function selectedRow() {
    if (!root.cursorActive || root.selectedIndex >= root.rowCount) return null
    return root.rows[root.selectedIndex] || null
  }

  // ----------------------------------------------------------------- actions

  // Run it, or focus the window it already has. The widget decides which;
  // either way the panel has served its purpose and gets out of the way.
  function activateRow(row) {
    if (!row || !root.hostWidget) return
    root.hostWidget.activate(row)
    root.close()
  }

  function toggleHidden(row) {
    if (!row || !root.hostWidget) return
    root.hostWidget.setHidden(row.id)
  }

  function askDelete(row) {
    if (!row) return
    root.confirmId = row.id
    root.confirmName = row.name
    root.confirmOpened = true
    // selectedIndex on the dialog is only an initial value; reset it so a
    // previous confirm cannot leave the cursor sitting on Delete.
    deleteConfirm.selectedIndex = 0
  }

  function confirmDelete() {
    var id = root.confirmId
    root.confirmOpened = false
    root.confirmId = ""
    if (id !== "" && root.hostWidget) root.hostWidget.remove(id)
  }

  function cancelDelete() {
    root.confirmOpened = false
    root.confirmId = ""
  }

  function startEditing(id) {
    root.editingId = root.editingId === id ? "" : id
  }

  function commitEdit(id, text) {
    root.editingId = ""
    if (root.hostWidget) root.hostWidget.rename(id, String(text).trim())
  }

  function syncNow() {
    if (root.hostWidget) root.hostWidget.syncNow()
  }

  function openFolder() {
    if (root.hostWidget) root.hostWidget.openFolder()
  }

  function activateSelected() {
    root.activateRow(root.selectedRow())
  }

  function renameSelected() {
    var row = root.selectedRow()
    if (row) root.startEditing(row.id)
  }

  function hideSelected() {
    root.toggleHidden(root.selectedRow())
  }

  function deleteSelected() {
    root.askDelete(root.selectedRow())
  }

  // Enter means "do the thing this cursor position is for": launch a row's
  // AppImage, or press the footer button it has landed on.
  function activateCursor() {
    if (!root.cursorActive) return
    if (root.selectedIndex < root.rowCount) root.activateSelected()
    else if (root.selectedIndex === root.syncIndex) root.syncNow()
    else if (root.selectedIndex === root.folderIndex) root.openFolder()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  // One row of the panel's single cursor model. Visuals follow `hasCursor`
  // only, so mouse and keyboard can never light up two rows at once. The row
  // itself does nothing on click -- it only hands the cursor to whatever the
  // mouse is over, so the buttons stay the only way to act.
  component AppRow: CursorSurface {
    id: rowSurface

    required property int rowIndex
    readonly property bool selected: root.hasCursorAt(rowIndex)

    width: parent ? parent.width : 0
    hasCursor: selected
    foreground: root.foreground
    accent: Color.accent

    onSelectedChanged: if (selected) scrollArea.ensureVisible(rowSurface)

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.NoButton
      onContainsMouseChanged: if (containsMouse) root.takeCursor(rowSurface.rowIndex)
    }
  }

  // A footer button that shares the row cursor, so the arrow keys reach it.
  component FooterButton: PanelActionButton {
    required property int cursorIndex

    foreground: root.dim
    hoverColor: root.foreground
    hasCursor: root.hasCursorAt(cursorIndex)
    onHovered: function(isHovered) { if (isHovered) root.takeCursor(cursorIndex) }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(480))
    contentHeight: panel.fittedContentHeight(contentColumn.implicitHeight, Style.space(620))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      // While a name is being typed the field owns every key, including the
      // ones this catcher would otherwise read as navigation or shortcuts.
      blocked: root.editingId !== "" || root.confirmOpened
      onMoveRequested: function(dx, dy) { root.moveCursor(dx !== 0 ? dx : dy) }
      onActivateRequested: root.activateCursor()
      onDeleteRequested: root.deleteSelected()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(text) {
        var key = String(text).toLowerCase()
        if (key === "r") root.renameSelected()
        else if (key === "h") root.hideSelected()
        else if (key === "s") root.syncNow()
        else if (key === "o") root.openFolder()
      }

      Flickable {
        id: scrollArea
        anchors.fill: parent
        contentWidth: width
        contentHeight: contentColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        function ensureVisible(item) {
          if (!item) return
          var top = item.mapToItem(contentColumn, 0, 0).y
          var bottom = top + item.height
          if (top < contentY) contentY = top
          else if (bottom > contentY + height) contentY = bottom - height
        }

        Column {
          id: contentColumn
          width: scrollArea.width
          spacing: Style.spacing.sm

          PanelHero {
            width: parent.width
            title: "AppImages"
            foreground: root.foreground
            fontFamily: root.fontFamily

            iconComponent: Component {
              Text {
                text: Model.GLYPH.package
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
              }
            }
          }

          Item {
            width: 1
            height: Style.spacing.md
          }

          PanelSeparator {
            width: parent.width
            foreground: root.foreground
          }

          PanelSectionHeader {
            width: parent.width
            visible: root.rowCount > 0
            // The count rides along with the section label rather than sitting
            // in a pill of its own; it is a detail about the list below, not a
            // headline.
            text: "APPS \u2013 " + root.rowCount
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Text {
            width: parent.width
            visible: root.listError !== ""
            text: root.listError
            color: Color.urgent
            wrapMode: Text.Wrap
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Text {
            width: parent.width
            visible: root.rowCount === 0 && root.listError === ""
            text: "Nothing here yet. Drop an AppImage in the folder and it appears in your launcher."
            color: root.dim
            wrapMode: Text.Wrap
            topPadding: Style.spacing.md
            bottomPadding: Style.spacing.md
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Repeater {
            model: root.rows

            delegate: AppRow {
              id: row

              required property int index
              required property var modelData

              rowIndex: index
              implicitHeight: rowContent.implicitHeight + Style.spacing.md * 2
              radius: Style.cornerRadius

              Row {
                id: rowContent
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Style.spacing.rowPaddingX
                anchors.rightMargin: Style.spacing.rowPaddingX
                spacing: Style.spacing.controlGap

                Item {
                  width: Style.space(28)
                  height: Style.space(28)
                  anchors.verticalCenter: parent.verticalCenter

                  Image {
                    anchors.fill: parent
                    visible: row.modelData.icon !== ""
                    source: row.modelData.icon !== "" ? "file://" + row.modelData.icon : ""
                    fillMode: Image.PreserveAspectFit
                    sourceSize.width: width * 2
                    sourceSize.height: height * 2
                    asynchronous: true
                    smooth: true
                  }

                  // An AppImage with no embedded icon still needs to occupy
                  // the same column, or its name would sit out of line.
                  Text {
                    anchors.centerIn: parent
                    visible: row.modelData.icon === ""
                    text: Model.GLYPH.package
                    color: root.faint
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.iconLarge
                  }
                }

                Column {
                  width: rowContent.width - Style.space(28) - actions.width - rowContent.spacing * 2
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.spacing.xxs

                  Text {
                    width: parent.width
                    visible: root.editingId !== row.modelData.id
                    text: row.modelData.name
                    // A hidden AppImage is still here, it just is not on
                    // offer; the row says so by receding rather than shouting.
                    color: row.modelData.hidden ? root.faint : root.foreground
                    elide: Text.ElideRight
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                  }

                  TextField {
                    id: nameField
                    width: parent.width
                    visible: root.editingId === row.modelData.id
                    foreground: root.foreground
                    verticalPadding: Style.spacing.xs
                    placeholderText: row.modelData.name
                    onVisibleChanged: {
                      if (!visible) return
                      // Prefill only a name the user chose; an inherited one
                      // is already the placeholder, and starting empty makes
                      // "type nothing, press Enter" mean "reset".
                      text = row.modelData.custom ? row.modelData.name : ""
                      forceActiveFocus()
                      selectAll()
                    }
                    onAccepted: root.commitEdit(row.modelData.id, text)
                    Keys.onEscapePressed: root.editingId = ""
                  }

                  Text {
                    width: parent.width
                    text: Model.detailLine(row.modelData)
                    color: root.faint
                    elide: Text.ElideRight
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                }

                Row {
                  id: actions
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.spacing.xs

                  PanelActionButton {
                    iconText: row.modelData.running ? Model.GLYPH.focus : Model.GLYPH.play
                    foreground: row.modelData.running ? Color.accent : root.dim
                    hoverColor: Color.accent
                    tooltipText: row.modelData.running ? "Focus  ·  Enter" : "Run  ·  Enter"
                    onClicked: root.activateRow(row.modelData)
                  }

                  PanelActionButton {
                    iconText: Model.GLYPH.rename
                    foreground: root.editingId === row.modelData.id ? Color.accent : root.dim
                    hoverColor: root.foreground
                    enabled: root.busyId === ""
                    tooltipText: row.modelData.custom
                      ? "Rename, empty resets  ·  r"
                      : "Rename  ·  r"
                    onClicked: root.startEditing(row.modelData.id)
                  }

                  PanelActionButton {
                    iconText: row.modelData.hidden ? Model.GLYPH.eyeOff : Model.GLYPH.eye
                    foreground: row.modelData.hidden ? Color.accent : root.dim
                    hoverColor: root.foreground
                    enabled: root.busyId === ""
                    tooltipText: row.modelData.hidden
                      ? "Show in launcher  ·  h"
                      : "Hide from launcher  ·  h"
                    onClicked: root.toggleHidden(row.modelData)
                  }

                  PanelActionButton {
                    iconText: Model.GLYPH.trash
                    foreground: root.dim
                    hoverColor: Color.urgent
                    enabled: root.busyId === ""
                    tooltipText: "Delete the file  ·  Del"
                    onClicked: root.askDelete(row.modelData)
                  }
                }
              }
            }
          }

          PanelSeparator {
            width: parent.width
            visible: root.rowCount > 0
            foreground: root.foreground
          }

          Row {
            id: footer
            width: parent.width
            spacing: Style.spacing.xs
            leftPadding: Style.spacing.rowPaddingX

            FooterButton {
              cursorIndex: root.syncIndex
              iconText: Model.GLYPH.refresh
              tooltipText: "Sync now  ·  s"
              onClicked: root.syncNow()
            }

            FooterButton {
              cursorIndex: root.folderIndex
              iconText: Model.GLYPH.folder
              tooltipText: "Open folder  ·  o"
              onClicked: root.openFolder()
            }
          }

          Text {
            width: parent.width
            text: "↑↓ move   ⏎ run   r rename   h hide   ⌦ delete   s sync   o folder"
            color: root.faint
            elide: Text.ElideRight
            topPadding: Style.spacing.xs
            leftPadding: Style.spacing.rowPaddingX
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }
    }

    ConfirmDialog {
      id: deleteConfirm
      anchors.fill: parent
      opened: root.confirmOpened
      // Starts on Cancel, not the component's own default -- a stray Enter
      // must never be the thing that deletes a file.
      selectedIndex: 0
      message: "Delete " + root.confirmName + "? The AppImage file is removed from disk."
      cancelText: "Cancel"
      confirmText: "Delete"
      foreground: root.foreground
      fontFamily: root.fontFamily
      onCanceled: root.cancelDelete()
      onConfirmed: root.confirmDelete()
    }

    Item {
      id: confirmKeys
      anchors.fill: parent
      visible: root.confirmOpened
      focus: root.confirmOpened
      Keys.onPressed: function(event) { if (deleteConfirm.handleKey(event)) event.accepted = true }
    }
  }

  onConfirmOpenedChanged: {
    if (root.confirmOpened) Qt.callLater(function() { if (root.confirmOpened) confirmKeys.forceActiveFocus() })
    else Qt.callLater(function() { if (root.opened) keyCatcher.forceActiveFocus() })
  }
}
