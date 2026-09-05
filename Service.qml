import QtQuick
import Quickshell
import Quickshell.Io

// Headless half of the plugin: keeps the launcher in step with the AppImage
// folder whether or not the bar widget is on screen, and whether or not its
// popup is open. That is the whole point of the plugin, so it cannot live in
// the widget -- a bar widget is instantiated once per monitor, and a two-head
// setup would run every sync twice.
//
// The watch is event-driven via inotifywait, the same tool and the same
// restart-on-exit shape the shell's own PluginRegistry uses to watch
// ~/.config/omarchy/plugins.
Item {
  id: service

  // Injected by the host's service loader.
  property var shell: null
  property var manifest: null

  readonly property string binPath: String(Qt.resolvedUrl("bin/appimages")).replace(/^file:\/\//, "")

  // Empty until the bootstrap resolves it. Everything downstream keys off
  // this, so nothing watches or syncs before the folder is known to exist.
  property string watchDir: ""
  property string lastError: ""

  // A watcher that dies the moment it starts means something is wrong that
  // retrying cannot fix -- inotify-tools missing, the watch limit reached. At
  // a flat two seconds that would re-run a full sync forever, so a run too
  // short to be real backs the retry off instead.
  property int watcherStartedAt: 0
  property int retryDelay: 2000
  readonly property int retryDelayMax: 60000

  function sync() {
    if (syncProc.running) return
    syncProc.command = [service.binPath, "sync", "--quiet"]
    syncProc.running = true
  }

  // One process resolves the configured folder, creates it, and does the
  // first sync, so startup costs a single fork instead of three round trips.
  // Rerun whenever the watcher dies, which is also how a deleted folder gets
  // recreated rather than spinning on a watch that can never attach.
  function bootstrap() {
    if (bootstrapProc.running) return
    bootstrapProc.command = ["bash", "-c",
      'dir=$("$0" dir) && mkdir -p "$dir" && "$0" sync --quiet && printf %s "$dir"',
      service.binPath]
    bootstrapProc.running = true
  }

  Component.onCompleted: service.bootstrap()

  Process {
    id: bootstrapProc
    property string outText: ""
    property string errText: ""
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: bootstrapProc.outText = text }
    stderr: StdioCollector { waitForEnd: true; onStreamFinished: bootstrapProc.errText = text }
    onExited: function(code) {
      if (code === 0 && bootstrapProc.outText.trim() !== "") {
        service.watchDir = bootstrapProc.outText.trim()
        service.retryDelay = 2000
        watcher.running = true
      } else {
        service.lastError = bootstrapProc.errText.trim() || "appimages bootstrap failed"
        // A folder that cannot be created will not become creatable in two
        // seconds, so this backs off exactly like a watcher that will not stay
        // up -- otherwise a typo in `directory` costs a sync every two seconds
        // for as long as the session lasts.
        service.retryDelay = Math.min(service.retryDelay * 3, service.retryDelayMax)
        console.warn("io.github.hpolthof.appimages: " + service.lastError)
        watcherRestart.restart()
      }
      bootstrapProc.outText = ""
      bootstrapProc.errText = ""
    }
  }

  Process {
    id: syncProc
    property string errText: ""
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { waitForEnd: true; onStreamFinished: syncProc.errText = text }
    onExited: function(code) {
      service.lastError = code === 0 ? "" : (syncProc.errText.trim() || "sync failed")
      if (code !== 0) console.warn("io.github.hpolthof.appimages: " + service.lastError)
      syncProc.errText = ""
    }
  }

  Process {
    id: watcher
    running: false
    command: [
      "inotifywait",
      "-m",
      "-q",
      "-e",
      "close_write,create,delete,move",
      "--format",
      "%w%f",
      service.watchDir
    ]
    // A browser writes a download under a temporary name and renames it into
    // place, so several events land for one arriving file. Coalesce them, and
    // ignore paths that are not AppImages at all.
    stdout: SplitParser {
      onRead: function(path) {
        if (/\.appimage$/i.test(String(path))) settle.restart()
      }
    }
    onRunningChanged: if (running) service.watcherStartedAt = Date.now()
    onExited: {
      var lived = Date.now() - service.watcherStartedAt
      if (lived < 5000) {
        service.retryDelay = Math.min(service.retryDelay * 3, service.retryDelayMax)
        if (service.lastError === "") {
          service.lastError = "watcher exited immediately; is inotify-tools installed?"
          console.warn("io.github.hpolthof.appimages: " + service.lastError)
        }
      } else {
        service.retryDelay = 2000
      }
      watcherRestart.restart()
    }
  }

  Timer {
    id: settle
    interval: 750
    onTriggered: service.sync()
  }

  // The watcher is only trustworthy once it has survived a while; that is also
  // the moment a previous failure stops being worth reporting.
  Timer {
    interval: 10000
    running: watcher.running
    onTriggered: {
      service.retryDelay = 2000
      service.lastError = ""
    }
  }

  Timer {
    id: watcherRestart
    interval: service.retryDelay
    onTriggered: service.bootstrap()
  }

  IpcHandler {
    target: "appimages"
    function sync(): void { service.sync() }
    function directory(): string { return service.watchDir }
    function status(): string { return service.lastError === "" ? "ok" : service.lastError }
  }
}
