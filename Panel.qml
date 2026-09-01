import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "tenzin.luks-live"
  ipcTarget: "tenzin.luks-live"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  readonly property string home: Quickshell.env("HOME")
  readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME") || home + "/.config"
  readonly property string pluginDir: configHome + "/omarchy/plugins/tenzin.luks-live"
  readonly property string assetDir: pluginDir + "/assets"
  readonly property string listAssetsScript: pluginDir + "/scripts/list-assets.sh"
  readonly property string prepareScript: pluginDir + "/scripts/prepare.sh"
  readonly property string installScript: pluginDir + "/scripts/install.sh"
  readonly property string statusScript: pluginDir + "/scripts/status.sh"
  readonly property string preparedDir: (Quickshell.env("XDG_CACHE_HOME") || home + "/.cache") + "/omaliveboot/prepared"
  readonly property color contentForeground: bar ? bar.foreground : Color.foreground
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family

  property string videoPath: String(setting("videoPath", ""))
  property int durationMs: Number(setting("durationMs", 2500))
  property int frameRate: Number(setting("frameRate", 12))
  property bool soundEnabled: setting("soundEnabled", false) === true
  property int volumePercent: Number(setting("volumePercent", 70))
  property int entryXMilli: Number(setting("entryXMilli", 500))
  property int entryYMilli: Number(setting("entryYMilli", 680))

  property bool busy: false
  property bool installed: false
  property string activeTheme: "unknown"
  property string audioDevice: "checking"
  property string phase: "idle"
  property string logText: "Add videos to assets, select one, inspect the final frame, then apply."
  property var assetFiles: []

  function persist(values) {
    var entry = { id: root.moduleName }
    for (var existing in root.settings) if (existing !== "id") entry[existing] = root.settings[existing]
    for (var key in values) entry[key] = values[key]
    root.settings = entry
    if (root.hostWidget && "settings" in root.hostWidget) root.hostWidget.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function open() {
    refreshAssets()
    refreshStatus()
    controller.show()
    Qt.callLater(function() {
      if (opened) setCenterHoverRevealSuppressed(true)
    })
  }

  function close() {
    setCenterHoverRevealSuppressed(false)
    controller.hide()
  }

  function toggle() { opened ? close() : open() }

  function setCenterHoverRevealSuppressed(value) {
    if (bar && "centerHoverRevealSuppressed" in bar) bar.centerHoverRevealSuppressed = value
  }

  function selectVideo(path) {
    videoPath = path
    persist({ videoPath: path })
    preview.replay()
  }

  function assetName(path) {
    var parts = String(path).split("/")
    return parts.length > 0 ? parts[parts.length - 1] : String(path)
  }

  function refreshAssets() {
    if (assetsProc.running) return
    assetFiles = []
    assetsProc.running = true
  }

  function refreshStatus() {
    if (!statusProc.running) statusProc.running = true
  }

  function apply() {
    if (videoPath === "" || assetFiles.indexOf(videoPath) < 0) {
      logText = "Select a video from the assets folder before applying."
      return
    }
    busy = true
    phase = "preparing"
    logText = "Extracting optimized Plymouth frames" + (soundEnabled ? " and PCM sound" : "") + "..."
    prepareProc.command = [prepareScript, videoPath, String(durationMs), String(frameRate), "1280", "720",
                           String(entryXMilli), String(entryYMilli), soundEnabled ? "1" : "0", String(volumePercent)]
    prepareProc.running = true
  }

  function revert() {
    busy = true
    phase = "installing"
    logText = "Restoring the previous Plymouth configuration..."
    installProc.command = ["pkexec", installScript, "--revert"]
    installProc.running = true
  }

  Process {
    id: assetsProc
    command: [root.listAssetsScript]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var output = String(text || "").trim()
        var paths = output === "" ? [] : output.split("\n")
        root.assetFiles = paths

        if (paths.indexOf(root.videoPath) < 0) {
          root.videoPath = paths.length > 0 ? paths[0] : ""
          root.persist({ videoPath: root.videoPath })
        }
        if (root.videoPath !== "") preview.replay()
      }
    }
  }

  Process {
    id: openAssetsProc
    command: ["xdg-open", root.assetDir]
  }

  Process {
    id: statusProc
    command: [root.statusScript]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var lines = String(text || "").trim().split("\n")
        for (var i = 0; i < lines.length; i++) {
          var separator = lines[i].indexOf("=")
          if (separator < 0) continue
          var key = lines[i].substring(0, separator)
          var value = lines[i].substring(separator + 1)
          if (key === "installed") root.installed = value === "1"
          else if (key === "theme") root.activeTheme = value
          else if (key === "audio_device") root.audioDevice = value
        }
      }
    }
  }

  Process {
    id: prepareProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (String(text || "").trim() !== "") root.logText = String(text).trim()
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (String(text || "").trim() !== "") root.logText = String(text).trim()
    }
    onExited: function(exitCode, exitStatus) {
      if (exitCode !== 0) {
        root.busy = false
        root.phase = "error"
        return
      }
      root.phase = "installing"
      root.logText = "Publishing the theme and rebuilding the Omarchy UKI..."
      installProc.command = ["pkexec", root.installScript, "--apply", root.preparedDir]
      installProc.running = true
    }
  }

  Process {
    id: installProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (String(text || "").trim() !== "") root.logText = String(text).trim()
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (String(text || "").trim() !== "") root.logText = String(text).trim()
    }
    onExited: function(exitCode, exitStatus) {
      root.busy = false
      root.phase = exitCode === 0 ? "complete" : "error"
      root.refreshStatus()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: true
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(920))
    contentHeight: panel.fittedContentHeight(content.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
    }

    Column {
      id: content
      width: parent.width
      spacing: Style.space(10)

      Row {
        width: parent.width
        spacing: Style.space(12)

        Column {
          width: parent.width - statusBadge.width - parent.spacing
          spacing: Style.space(2)
          Text {
            text: "Luks Live"
            color: root.contentForeground
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.heading
            font.bold: true
            font.letterSpacing: 1
          }
          Text {
            text: "One-shot video, final-frame LUKS prompt, optional built-in-speaker sound"
            color: Qt.darker(root.contentForeground, 1.45)
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.bodySmall
          }
        }

        BorderSurface {
          id: statusBadge
          width: statusText.implicitWidth + Style.space(18)
          height: statusText.implicitHeight + Style.space(10)
          radius: height / 2
          color: root.installed ? Qt.rgba(0.62, 0.81, 0.42, 0.13) : Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.06)
          borderSpec: Border.flat(root.installed ? "#9ece6a" : Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.18), 1)
          Text {
            id: statusText
            anchors.centerIn: parent
            text: root.installed ? "INSTALLED" : "NOT INSTALLED"
            color: root.installed ? "#9ece6a" : root.contentForeground
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }
        }
      }

      PanelSeparator { foreground: root.contentForeground }

      Row {
        width: parent.width
        spacing: Style.space(14)

        Column {
          id: previewColumn
          width: Math.floor((parent.width - parent.spacing) * 0.62)
          spacing: Style.space(8)

          Row {
            width: parent.width
            spacing: Style.space(6)

            Dropdown {
              width: parent.width - openAssetsButton.width - refreshAssetsButton.width - parent.spacing * 2
              label: "Asset"
              value: root.videoPath
              options: root.assetFiles.map(function(path) {
                return { value: path, label: root.assetName(path) }
              })
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily
              onChanged: function(value) { root.selectVideo(value) }
            }
            Button {
              id: openAssetsButton
              text: "Open assets"
              enabled: !root.busy
              bordered: true
              foreground: root.contentForeground
              onClicked: openAssetsProc.running = true
            }
            Button {
              id: refreshAssetsButton
              text: "Refresh"
              enabled: !root.busy && !assetsProc.running
              bordered: true
              foreground: root.contentForeground
              onClicked: root.refreshAssets()
            }
          }

          Text {
            visible: root.assetFiles.length === 0
            width: parent.width
            text: "No videos found. Add one to assets, then refresh."
            color: Qt.darker(root.contentForeground, 1.45)
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.caption
          }

          Preview {
            id: preview
            width: parent.width
            active: root.opened
            videoPath: root.videoPath
            soundEnabled: root.soundEnabled
            volumePercent: root.volumePercent
            introDurationMs: root.durationMs
            entryX: root.entryXMilli / 1000.0
            entryY: root.entryYMilli / 1000.0
          }

          Row {
            spacing: Style.space(6)
            Button {
              text: "Replay preview"
              enabled: !root.busy && root.videoPath !== ""
              bordered: true
              foreground: root.contentForeground
              onClicked: preview.replay()
            }
          }

          Text {
            width: parent.width
            text: root.videoPath === "" ? "No video selected" : root.videoPath
            elide: Text.ElideMiddle
            color: Qt.darker(root.contentForeground, 1.5)
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.caption
          }
        }

        Column {
          width: parent.width - previewColumn.width - parent.spacing
          spacing: Style.space(8)

          PanelSectionHeader { width: parent.width; text: "Boot sequence" }

          Row {
            spacing: Style.space(10)
            NumberField {
              label: "Length (ms)"
              value: root.durationMs
              from: 1000
              to: 5000
              stepSize: 250
              foreground: root.contentForeground
              onModified: function(value) {
                root.durationMs = value
                root.persist({ durationMs: value })
                preview.replay()
              }
            }
            NumberField {
              label: "Frames / sec"
              value: root.frameRate
              from: 8
              to: 20
              foreground: root.contentForeground
              onModified: function(value) {
                root.frameRate = value
                root.persist({ frameRate: value })
              }
            }
          }

          Toggle {
            width: parent.width
            label: "Boot sound"
            description: root.audioDevice === "unavailable"
              ? "No built-in analog ALSA output detected; installation will fall back to silent."
              : "Opt-in PCM playback through " + root.audioDevice + "."
            checked: root.soundEnabled
            foreground: root.contentForeground
            onClicked: {
              root.soundEnabled = !root.soundEnabled
              root.persist({ soundEnabled: root.soundEnabled })
              preview.replay()
            }
          }

          NumberField {
            visible: root.soundEnabled
            label: "Sound volume (%)"
            value: root.volumePercent
            from: 0
            to: 100
            stepSize: 5
            foreground: root.contentForeground
            onModified: function(value) {
              root.volumePercent = value
              root.persist({ volumePercent: value })
            }
          }

          PanelSectionHeader { width: parent.width; text: "Password position" }

          Grid {
            columns: 3
            spacing: Style.space(4)
            Repeater {
              model: [
                { x: 250, y: 250 }, { x: 500, y: 250 }, { x: 750, y: 250 },
                { x: 250, y: 500 }, { x: 500, y: 500 }, { x: 750, y: 500 },
                { x: 250, y: 750 }, { x: 500, y: 750 }, { x: 750, y: 750 }
              ]
              Button {
                required property var modelData
                text: "."
                width: Style.space(42)
                bordered: true
                selected: root.entryXMilli === modelData.x && root.entryYMilli === modelData.y
                foreground: root.contentForeground
                onClicked: {
                  root.entryXMilli = modelData.x
                  root.entryYMilli = modelData.y
                  root.persist({ entryXMilli: modelData.x, entryYMilli: modelData.y })
                }
              }
            }
          }

          Text {
            width: parent.width
            text: "The LUKS input is not active until the intro and sound finish. Boot media is stored unencrypted in the UKI."
            wrapMode: Text.WordWrap
            color: Qt.darker(root.contentForeground, 1.45)
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }

      PanelSeparator { foreground: root.contentForeground }

      Row {
        width: parent.width
        spacing: Style.space(8)
        Button {
          id: applyButton
          text: root.busy
            ? (root.phase === "preparing" ? "Preparing..." : "Rebuilding UKI...")
            : "Apply to next boot"
          enabled: !root.busy && root.videoPath !== ""
          active: true
          foreground: root.contentForeground
          onClicked: root.apply()
        }
        Button {
          id: revertButton
          text: "Revert"
          enabled: !root.busy && root.installed
          bordered: true
          foreground: root.contentForeground
          onClicked: root.revert()
        }
        Text {
          width: parent.width - applyButton.width - revertButton.width - parent.spacing * 2
          anchors.verticalCenter: parent.verticalCenter
          text: root.logText
          elide: Text.ElideRight
          color: root.phase === "error" ? "#f7768e" : Qt.darker(root.contentForeground, 1.35)
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.bodySmall
        }
      }
    }
  }
}
