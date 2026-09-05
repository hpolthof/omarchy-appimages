import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Bar half of the plugin. Owns every read the panel displays and every rename
// it writes, both through bin/appimages, and mirrors that state into Panel.qml
// the way the docker plugin's widget does.
//
// The periodic folder watch lives in Service.qml, not here: this component is
// created once per monitor, so anything on a timer here would run twice on a
// two-head setup. What is left is cheap and read-only, and refreshing it twice
// costs nothing.
BarWidget {
  id: root
  moduleName: "io.github.hpolthof.appimages"

  readonly property string binPath: String(Qt.resolvedUrl("bin/appimages")).replace(/^file:\/\//, "")

  property var rows: []
  property string directory: ""
  property string listError: ""
  property string busyId: ""

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property string tooltip: root.listError !== ""
    ? Model.clean(root.listError)
    : Model.summary(root.rows, root.directory)

  readonly property var mirroredProperties: ["bar", "settings", "rows", "directory", "listError", "busyId"]

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

  // ---------------------------------------------------------------- reading

  function refresh() {
    if (listProc.running) return
    listProc.command = [root.binPath, "list"]
    listProc.running = true
  }

  function applyList(text, code) {
    if (code !== 0) {
      root.listError = Model.clean(text) || "appimages list failed"
      root.rows = []
    } else {
      root.listError = ""
      root.rows = Model.parseList(text)
    }
    root.injectPanel()
  }

  // ---------------------------------------------------------------- writing

  // An empty name clears the override, which puts the AppImage's own name
  // back. bin/appimages re-syncs itself, so the launcher entry is already
  // rewritten by the time this returns.
  function rename(id, name) {
    if (!id) return
    root.runAction(["rename", String(id), String(name)], id)
  }

  // Enter on a row means "put this app in front of me". If a window is
  // already open that is a focus, not a second copy; bin/appimages owns both,
  // including reporting a launch that dies on the spot.
  function activate(row) {
    if (!row) return
    Quickshell.execDetached([root.binPath, row.running ? "focus" : "run", String(row.id)])
    // Whether it focused or started, the running column is about to change.
    settleRefresh.restart()
  }

  function setHidden(id) {
    root.runAction(["hide", String(id)], id)
  }

  function remove(id) {
    root.runAction(["delete", String(id)], id)
  }

  // Shared path for the writes that change what `list` will say next, so the
  // panel is never left showing the state from before the click.
  function runAction(args, id) {
    if (root.busyId !== "" || actionProc.running) return
    root.busyId = String(id || "")
    root.injectPanel()
    actionProc.command = [root.binPath].concat(args)
    actionProc.running = true
  }

  function syncNow() {
    if (syncProc.running) return
    syncProc.command = [root.binPath, "sync", "--quiet"]
    syncProc.running = true
  }

  function openFolder() {
    if (root.directory === "") return
    Quickshell.execDetached(["uwsm-app", "--", "xdg-open", root.directory])
  }

  // -------------------------------------------------------------- lifecycle

  function open() {
    if (panelLoader.item) panelLoader.item.open()
    root.refresh()
  }

  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  Component.onCompleted: {
    dirProc.command = [root.binPath, "dir"]
    dirProc.running = true
    root.refresh()
  }
  onBarChanged: root.injectPanel()
  onSettingsChanged: root.injectPanel()
  onOpenedChanged: if (root.opened) root.refresh()

  Process {
    id: dirProc
    property string outText: ""
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: dirProc.outText = text }
    onExited: function(code) {
      if (code === 0) root.directory = dirProc.outText.trim()
      dirProc.outText = ""
      root.injectPanel()
    }
  }

  Process {
    id: listProc
    property string outText: ""
    property string errText: ""
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: listProc.outText = text }
    stderr: StdioCollector { waitForEnd: true; onStreamFinished: listProc.errText = text }
    onExited: function(code) {
      root.applyList(code === 0 ? listProc.outText : listProc.errText, code)
      listProc.outText = ""
      listProc.errText = ""
    }
  }

  Process {
    id: actionProc
    property string errText: ""
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { waitForEnd: true; onStreamFinished: actionProc.errText = text }
    onExited: function(code) {
      if (code !== 0) root.listError = Model.clean(actionProc.errText) || "action failed"
      actionProc.errText = ""
      root.busyId = ""
      root.refresh()
    }
  }

  // A window takes a moment to map, so the running column is read once the
  // dust has settled rather than immediately after the launch.
  Timer {
    id: settleRefresh
    interval: 1500
    onTriggered: root.refresh()
  }

  // Windows open and close while the panel is up, and only the panel cares.
  Timer {
    interval: 5000
    repeat: true
    running: root.opened
    onTriggered: root.refresh()
  }

  Process {
    id: syncProc
    stdout: StdioCollector { waitForEnd: true }
    onExited: root.refresh()
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      // `bar` and `settings` are injected by the host and can land after this.
      Qt.callLater(root.injectPanel)
    }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  IpcHandler {
    target: "io.github.hpolthof.appimages"
    function list(): string { return Model.summary(root.rows, root.directory) }
    function refresh(): void { root.broadcast("refresh") }
    function sync(): void { root.syncNow() }
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function rename(id: string, name: string): void { root.rename(id, name) }
    function run(id: string): void {
      for (var i = 0; i < root.rows.length; i++) {
        if (root.rows[i].id === id) { root.activate(root.rows[i]); return }
      }
    }
    // Not `hide`: that name already means "close the panel" on this target.
    function toggleHidden(id: string): void { root.setHidden(id) }
    function remove(id: string): void { root.remove(id) }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: Model.GLYPH.package
    fontSize: Style.font.icon
    active: root.listError !== ""
    dimmed: root.rows.length === 0 && root.listError === ""
    tooltipText: root.tooltip
    onPressed: function(mouseButton) {
      if (mouseButton === Qt.RightButton) {
        root.syncNow()
        return
      }
      root.toggle()
    }
  }
}
