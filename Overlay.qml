import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.Commons
import qs.Ui

// Close Guard: the "Are you sure you want to close?" modal.
//
// Super+W summons this overlay (see hypr/close-guard.lua) instead of closing
// the focused window. The window to close is captured when the overlay opens,
// so focus moving afterwards can never redirect the close to another window.
// "No" is selected on every open; only an explicit "Yes" closes anything.
Item {
  id: root
  property string omarchyPath: ""
  property var shell: null
  property var manifest: null

  readonly property string pluginId: (manifest && manifest.id) || "io.github.ayandexyz.close-guard"

  property bool opened: false
  // 0 = No, 1 = Yes.
  property int selected: 0

  // The window this prompt is about, frozen at open time. The toplevel object
  // itself is kept so the close can be refused if that window is gone, even if
  // Hyprland has since reused its address for a new window.
  property var targetToplevel: null
  property string targetAddress: ""
  property string targetTitle: ""
  property string targetApp: ""
  property string targetMonitor: ""
  property string targetIcon: ""
  // The app's own name from its desktop entry, e.g. "Chromium" for "chromium".
  property string targetAppName: ""

  // A window address that was not in Quickshell's list yet; retried once.
  property string pendingAddress: ""

  function open(payloadJson) {
    // Pressed again while already asking: keep asking about the same window.
    if (root.opened && root.targetAddress !== "") return

    // The keybinding passes the focused window's address. It is only ever used
    // to look the window up in Hyprland's own list, never trusted on its own.
    var payload = ({})
    var encoded = String(payloadJson || "{}")
    if (encoded.length <= 4096) {
      try { payload = JSON.parse(encoded) || ({}) } catch (error) { payload = ({}) }
    }
    var address = root.safeAddress(payload.address)

    if (address === "") {
      // Opened without a target (e.g. by hand over IPC): use the focused window.
      root.show(Hyprland.activeToplevel)
      return
    }
    var toplevel = root.findToplevel(address)
    if (toplevel) {
      root.show(toplevel)
      return
    }
    // A window that opened a moment ago may not be listed yet.
    root.pendingAddress = address
    Hyprland.refreshToplevels()
    retryLookup.restart()
  }

  Timer {
    id: retryLookup
    interval: 150
    onTriggered: {
      var toplevel = root.findToplevel(root.pendingAddress)
      root.pendingAddress = ""
      root.show(toplevel)
    }
  }

  function findToplevel(address) {
    var wanted = root.safeAddress(address).toLowerCase()
    if (wanted === "") return null
    var toplevels = Hyprland.toplevels ? Hyprland.toplevels.values : []
    for (var i = 0; i < toplevels.length; i++) {
      if (root.safeAddress(toplevels[i].address).toLowerCase() === wanted) return toplevels[i]
    }
    return null
  }

  function stillOpen(toplevel) {
    var toplevels = Hyprland.toplevels ? Hyprland.toplevels.values : []
    for (var i = 0; i < toplevels.length; i++) if (toplevels[i] === toplevel) return true
    return false
  }

  function show(toplevel) {
    var address = toplevel ? root.safeAddress(toplevel.address) : ""
    if (address === "") {
      // Nothing focused, nothing to close.
      root.dismiss()
      return
    }

    var ipc = toplevel.lastIpcObject || ({})
    var windowClass = String(ipc.class || ipc.initialClass || (toplevel.wayland ? toplevel.wayland.appId : "") || "")
    var entry = root.desktopEntryFor(windowClass)

    root.targetToplevel = toplevel
    root.targetAddress = address
    root.targetTitle = root.clip(toplevel.title || ipc.title)
    root.targetApp = root.clip(windowClass)
    root.targetMonitor = toplevel.monitor ? String(toplevel.monitor.name || "") : ""
    root.targetAppName = root.clip(entry && entry.name ? entry.name : windowClass)
    root.targetIcon = entry && entry.icon ? root.iconFor(entry.icon) : ""
    root.selected = 0
    root.opened = true
  }

  // Called by the host (`omarchy-shell shell hide <id>`); must not call back.
  function close() {
    retryLookup.stop()
    root.pendingAddress = ""
    root.opened = false
    root.targetToplevel = null
    root.targetAddress = ""
  }

  // Closing on our own initiative, so the host's bookkeeping agrees.
  function dismiss() {
    root.close()
    if (root.shell && typeof root.shell.hide === "function") root.shell.hide(root.pluginId)
  }

  function confirm() {
    var toplevel = root.targetToplevel
    var address = root.targetAddress
    root.dismiss()
    // Re-check right before closing: the exact window asked about must still
    // exist, and still carry the address that was shown.
    if (address === "" || !toplevel || !root.stillOpen(toplevel)
        || root.safeAddress(toplevel.address) !== address) return
    // Under Hyprland's Lua config a dispatch is a Lua expression, so only a
    // shape-checked hex address is ever interpolated into it.
    Hyprland.dispatch(Hyprland.usingLua
      ? "hl.dsp.window.close({ window = \"address:" + address + "\" })"
      : "closewindow address:" + address)
  }

  function choose(index) {
    if (index === 1) root.confirm()
    else root.dismiss()
  }

  // HyprlandToplevel.address is bare hex; dispatchers want "0x…".
  function safeAddress(value) {
    var text = String(value || "")
    var bare = text.indexOf("0x") === 0 ? text.slice(2) : text
    return /^[0-9a-fA-F]{1,16}$/.test(bare) ? "0x" + bare.toLowerCase() : ""
  }

  function desktopEntryFor(windowClass) {
    var name = String(windowClass || "")
    if (name === "" || typeof DesktopEntries.heuristicLookup !== "function") return null
    return DesktopEntries.heuristicLookup(name)
  }

  function iconFor(icon) {
    var value = String(icon || "")
    if (value.charAt(0) === "/") return "file://" + value
    return Quickshell.iconPath(value, true)
  }

  function clip(value) {
    var text = String(value || "").replace(/\s+/g, " ").trim()
    return text.length > 80 ? text.slice(0, 79) + "…" : text
  }

  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: window
      required property var modelData
      screen: modelData

      // Only the monitor the user is looking at shows the prompt.
      readonly property bool active: root.opened
        && (root.targetMonitor === "" || modelData.name === root.targetMonitor)

      visible: active
      anchors { top: true; bottom: true; left: true; right: true }
      color: "transparent"
      WlrLayershell.namespace: "io-github-ayandexyz-close-guard"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: active ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
      exclusionMode: ExclusionMode.Ignore

      Rectangle { anchors.fill: parent; color: Color.menu.scrim }
      // A click outside the card is a "No".
      MouseArea { anchors.fill: parent; onClicked: root.dismiss() }

      BorderSurface {
        id: card
        width: Math.min(parent.width - Style.space(48), Style.space(440))
        height: content.implicitHeight + card.padding * 2
        anchors.centerIn: parent
        color: Color.menu.background
        radius: Style.cornerRadius
        borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border, 1)
        padding: Style.spacing.panelPadding

        // A quick settle-in, so the prompt reads as a response to the keypress.
        opacity: window.active ? 1 : 0
        scale: window.active ? 1 : 0.96
        Behavior on opacity { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

        // Swallow clicks on the card so they do not reach the scrim.
        MouseArea { anchors.fill: parent }

        Column {
          id: content
          anchors.fill: parent
          anchors.margins: card.padding
          spacing: Style.space(14)
          focus: window.active

          Keys.onPressed: function(event) {
            switch (event.key) {
            case Qt.Key_Escape:
            case Qt.Key_N:
              root.dismiss(); break
            case Qt.Key_Y:
              root.confirm(); break
            case Qt.Key_Return:
            case Qt.Key_Enter:
            case Qt.Key_Space:
              root.choose(root.selected); break
            case Qt.Key_Left:
            case Qt.Key_H:
              root.selected = 0; break
            case Qt.Key_Right:
            case Qt.Key_L:
              root.selected = 1; break
            case Qt.Key_Tab:
            case Qt.Key_Backtab:
              root.selected = 1 - root.selected; break
            default:
              return
            }
            event.accepted = true
          }

          Text {
            textFormat: Text.PlainText
            width: parent.width
            text: "Are you sure you want to close?"
            color: Color.menu.text
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.heading
            font.bold: true
            wrapMode: Text.Wrap
          }

          // The window this is about: app icon, title, and app name.
          Rectangle {
            width: parent.width
            height: Style.space(48)
            radius: Style.cornerRadius
            color: Util.alpha(Color.menu.text, 0.05)
            border.width: 1
            border.color: Util.alpha(Color.menu.text, 0.08)

            Image {
              id: appIcon
              anchors.left: parent.left
              anchors.leftMargin: Style.space(12)
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(26)
              height: width
              sourceSize.width: width
              sourceSize.height: height
              asynchronous: true
              source: root.targetIcon
              visible: status === Image.Ready
            }

            Column {
              anchors.left: appIcon.visible ? appIcon.right : parent.left
              anchors.leftMargin: Style.space(12)
              anchors.right: parent.right
              anchors.rightMargin: Style.space(12)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)

              Text {
              textFormat: Text.PlainText
                width: parent.width
                text: root.targetTitle || root.targetApp
                color: Color.menu.text
                font.family: Style.font.menuFamily
                font.pixelSize: Style.font.body
                elide: Text.ElideRight
              }

              Text {
              textFormat: Text.PlainText
                width: parent.width
                visible: root.targetAppName !== "" && root.targetAppName !== root.targetTitle
                text: root.targetAppName
                color: Color.menu.text
                opacity: 0.55
                font.family: Style.font.menuFamily
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
              }
            }
          }

          Item {
            width: parent.width
            height: buttons.height

            Text {
              textFormat: Text.PlainText
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              text: "Enter to choose · Esc to cancel"
              color: Color.menu.text
              opacity: 0.45
              font.family: Style.font.menuFamily
              font.pixelSize: Style.font.caption
            }

            Row {
              id: buttons
              anchors.right: parent.right
              spacing: Style.space(8)

              Repeater {
                model: [
                  { label: "No", key: "N" },
                  { label: "Yes", key: "Y" }
                ]

                Rectangle {
                  id: button
                  required property var modelData
                  required property int index
                  readonly property bool isSelected: root.selected === index
                  // "Yes" closes something, so it wears the theme's warning colour.
                  readonly property color tone: index === 1 ? Color.urgent : Color.menu.selectedText

                  width: Style.space(92)
                  height: Style.space(34)
                  radius: Style.cornerRadius
                  // Hover only tints the button; it never moves the selection, so a
                  // pointer resting where "Yes" appears cannot make Enter close.
                  color: isSelected
                    ? Util.alpha(tone, 0.16)
                    : (buttonMouse.containsMouse ? Util.alpha(Color.menu.text, 0.06) : "transparent")
                  border.width: isSelected ? 2 : 1
                  border.color: isSelected ? tone : Color.menu.border

                  Behavior on color { ColorAnimation { duration: 90 } }

                  Row {
                    anchors.centerIn: parent
                    spacing: Style.space(8)

                    Text {
              textFormat: Text.PlainText
                      anchors.verticalCenter: parent.verticalCenter
                      text: button.modelData.label
                      color: button.isSelected ? button.tone : Color.menu.text
                      font.family: Style.font.menuFamily
                      font.pixelSize: Style.font.body
                      font.bold: button.isSelected
                    }

                    Text {
              textFormat: Text.PlainText
                      anchors.verticalCenter: parent.verticalCenter
                      text: button.modelData.key
                      color: Color.menu.text
                      opacity: 0.4
                      font.family: Style.font.menuFamily
                      font.pixelSize: Style.font.caption
                    }
                  }

                  MouseArea {
                    id: buttonMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.choose(button.index)
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
