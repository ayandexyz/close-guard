import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// The app picker: search installed apps and choose which ones ask before
// Super+W closes them.
//
// Choices are saved to $XDG_STATE_HOME/close-guard/apps, one lowercase window
// class per line. hypr/close-guard.lua reads that file on every Super+W: a
// window whose class is listed gets the prompt, any other closes at once.
// An empty list means every window asks.
Panel {
  id: root
  moduleName: "io.github.ayandexyz.close-guard"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null

  readonly property int pageSize: 10

  readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/close-guard"
  readonly property string listPath: stateDir + "/apps"

  // Lowercase window classes that ask first, as a set.
  property var guarded: ({})
  readonly property int guardedCount: Object.keys(guarded).length

  property string query: ""
  property int cursor: 0

  readonly property string summary: guardedCount === 0
    ? "Close Guard: every app asks before closing"
    : "Close Guard: " + root.guardedApps().length + " app" + (root.guardedApps().length === 1 ? "" : "s") + " ask before closing"

  function open() {
    root.query = ""
    searchField.text = ""
    root.cursor = 0
    root.load()
    root.controller.show()
  }

  function close() {
    root.controller.hide()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.hostWidget || root, direction)
    return false
  }

  // --- apps -----------------------------------------------------------------

  // Window classes an app's windows are likely to carry: its StartupWMClass,
  // and its desktop file id (which is what most apps use as their app id).
  function keysFor(entry) {
    var keys = []
    var candidates = [entry.startupClass, entry.id]
    for (var i = 0; i < candidates.length; i++) {
      var key = String(candidates[i] || "").replace(/\.desktop$/, "").toLowerCase()
      if (/^[a-z0-9._-]{1,128}$/.test(key) && keys.indexOf(key) === -1) keys.push(key)
    }
    return keys
  }

  function isGuarded(entry) {
    var keys = root.keysFor(entry)
    for (var i = 0; i < keys.length; i++) if (root.guarded[keys[i]]) return true
    return false
  }

  readonly property var apps: {
    var values = DesktopEntries.applications.values || []
    var seen = ({})
    var out = []
    for (var i = 0; i < values.length; i++) {
      var entry = values[i]
      if (!entry || entry.noDisplay || seen[entry.id]) continue
      if (root.keysFor(entry).length === 0) continue
      seen[entry.id] = true
      out.push(entry)
    }
    return out
  }

  function guardedApps() {
    var out = []
    for (var i = 0; i < root.apps.length; i++) if (root.isGuarded(root.apps[i])) out.push(root.apps[i])
    return out
  }

  // Matches for the search, guarded apps first, then by name.
  readonly property var matches: {
    var needle = root.query.trim().toLowerCase()
    var guardedSnapshot = root.guarded
    var out = []
    for (var i = 0; i < root.apps.length; i++) {
      var entry = root.apps[i]
      if (needle !== "") {
        var hay = (String(entry.name || "") + " " + String(entry.genericName || "") + " " + String(entry.id || "")).toLowerCase()
        if (hay.indexOf(needle) === -1) continue
      }
      out.push({ entry: entry, guarded: root.isGuarded(entry) })
    }
    out.sort(function(a, b) {
      if (a.guarded !== b.guarded) return a.guarded ? -1 : 1
      return String(a.entry.name || "").localeCompare(String(b.entry.name || ""))
    })
    return out
  }

  readonly property var visibleMatches: matches.slice(0, pageSize)

  onVisibleMatchesChanged: if (root.cursor >= visibleMatches.length) root.cursor = Math.max(0, visibleMatches.length - 1)

  function toggleApp(entry) {
    if (!entry) return
    var keys = root.keysFor(entry)
    var next = ({})
    for (var k in root.guarded) next[k] = true
    if (root.isGuarded(entry)) {
      for (var i = 0; i < keys.length; i++) delete next[keys[i]]
    } else {
      for (var j = 0; j < keys.length; j++) next[keys[j]] = true
    }
    root.guarded = next
    root.save()
  }

  // --- storage --------------------------------------------------------------

  function parse(text) {
    var next = ({})
    var lines = String(text || "").split("\n")
    for (var i = 0; i < lines.length && i < 4096; i++) {
      var line = lines[i].trim().toLowerCase()
      if (line === "" || line.charAt(0) === "#") continue
      if (/^[a-z0-9._-]{1,128}$/.test(line)) next[line] = true
    }
    return next
  }

  readonly property int maxListBytes: 65536

  function load() {
    if (!reader.running) reader.running = true
  }

  function save() {
    var keys = Object.keys(root.guarded).sort()
    writer.payload = "# Close Guard: window classes that ask before Super+W closes them.\n"
      + "# One per line. Empty means every window asks.\n"
      + (keys.length ? keys.join("\n") + "\n" : "")
    writer.running = true
  }

  // Reads at most maxListBytes + 1 bytes, and only from a regular file that is
  // not a symlink; a longer file is rejected rather than parsed truncated.
  Process {
    id: reader
    command: ["timeout", "2", "sh", "-c",
      "[ -f \"$1\" ] && [ ! -L \"$1\" ] || exit 0; head -c \"$2\" -- \"$1\"",
      "sh", root.listPath, String(root.maxListBytes + 1)]
    stdout: StdioCollector { id: readerOut }
    onExited: function(exitCode) {
      var text = readerOut.text
      root.guarded = exitCode === 0 && text.length <= root.maxListBytes ? root.parse(text) : ({})
    }
  }

  // Writes the whole list to a fresh private temp file next to it, then
  // renames it into place (a rename replaces a symlink instead of following it).
  Process {
    id: writer
    property string payload: ""
    command: ["sh", "-c",
      "umask 077; mkdir -p -- \"$1\" && tmp=$(mktemp -- \"$1/.apps.XXXXXX\") "
        + "&& printf '%s' \"$3\" > \"$tmp\" && mv -f -- \"$tmp\" \"$2\" || { rm -f -- \"$tmp\"; exit 1; }",
      "sh", root.stateDir, root.listPath, writer.payload]
  }

  // --- view -----------------------------------------------------------------

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.hostWidget || root
    bar: root.bar
    open: root.opened
    focusTarget: searchField
    contentWidth: panel.fittedContentWidth(Style.space(340))
    contentHeight: panel.fittedContentHeight(content.implicitHeight)

    Column {
      id: content
      width: parent.width
      spacing: Style.space(8)

      Text {
        textFormat: Text.PlainText
        width: parent.width
        text: "Ask before closing"
        color: root.barForeground
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.subtitle
        font.bold: true
      }

      Text {
        textFormat: Text.PlainText
        width: parent.width
        text: root.guardedCount === 0
          ? "No apps picked, so every window asks. Pick apps to only ask for those."
          : "Only the apps switched on ask. Everything else closes right away."
        color: root.barForeground
        opacity: 0.7
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.bodySmall
        wrapMode: Text.Wrap
      }

      TextField {
        id: searchField
        width: parent.width
        placeholderText: "Search apps"
        foreground: root.barForeground
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        onTextChanged: { root.query = text; root.cursor = 0 }

        Keys.onPressed: function(event) {
          switch (event.key) {
          case Qt.Key_Escape:
            root.close(); break
          case Qt.Key_Down:
            root.cursor = Math.min(root.cursor + 1, root.visibleMatches.length - 1); break
          case Qt.Key_Up:
            root.cursor = Math.max(root.cursor - 1, 0); break
          case Qt.Key_Return:
          case Qt.Key_Enter:
            if (root.visibleMatches[root.cursor]) root.toggleApp(root.visibleMatches[root.cursor].entry)
            break
          case Qt.Key_Tab:
          case Qt.Key_Backtab:
            root.switchPanel(event.key === Qt.Key_Backtab ? -1 : 1); break
          default:
            return
          }
          event.accepted = true
        }
      }

      Repeater {
        model: root.visibleMatches

        Rectangle {
          id: row
          required property var modelData
          required property int index
          readonly property bool current: root.cursor === index

          width: content.width
          height: Style.space(34)
          radius: Style.cornerRadius
          color: current || rowMouse.containsMouse ? Style.hoverFill : "transparent"

          Image {
            id: icon
            anchors.left: parent.left
            anchors.leftMargin: Style.space(6)
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(20)
            height: width
            sourceSize.width: width
            sourceSize.height: height
            asynchronous: true
            source: {
              var name = String(row.modelData.entry.icon || "")
              if (name.charAt(0) === "/") return "file://" + name
              return Quickshell.iconPath(name || "application-x-executable", true)
                || Quickshell.iconPath("application-x-executable", true)
            }
          }

          Text {
            textFormat: Text.PlainText
            anchors.left: icon.right
            anchors.leftMargin: Style.space(10)
            anchors.right: toggle.left
            anchors.rightMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            text: row.modelData.entry.name || row.modelData.entry.id
            color: root.barForeground
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.body
            elide: Text.ElideRight
          }

          MouseArea {
            id: rowMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: { root.cursor = row.index; root.toggleApp(row.modelData.entry) }
          }

          ToggleSwitch {
            id: toggle
            anchors.right: parent.right
            anchors.rightMargin: Style.space(4)
            anchors.verticalCenter: parent.verticalCenter
            checked: row.modelData.guarded
            cursorRing: false
            foreground: root.barForeground
            onToggled: { root.cursor = row.index; root.toggleApp(row.modelData.entry) }
          }
        }
      }

      Text {
        textFormat: Text.PlainText
        width: parent.width
        visible: text !== ""
        text: root.matches.length === 0
          ? "No apps match \"" + root.query.trim() + "\""
          : (root.matches.length > root.pageSize
            ? (root.matches.length - root.pageSize) + " more, type to narrow down"
            : "")
        color: root.barForeground
        opacity: 0.6
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.bodySmall
      }
    }
  }
}
