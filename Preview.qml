import QtQuick
import QtMultimedia
import qs.Commons

Rectangle {
  id: root

  property string videoPath: ""
  property bool active: false
  property bool soundEnabled: false
  property int volumePercent: 70
  property int introDurationMs: 2500
  property real entryX: 0.5
  property real entryY: 0.68
  property bool entryVisible: false
  property bool frameReady: false
  property bool playbackFailed: false

  signal introFinished()

  readonly property int targetEnd: player.duration > 0
    ? Math.min(player.duration, introDurationMs)
    : introDurationMs
  readonly property real scaleFactor: width / 1920

  function replay() {
    if (videoPath === "") return
    entryVisible = false
    playbackFailed = false
    player.pause()
    player.position = 0
    player.play()
  }

  function finishIntro() {
    if (entryVisible) return
    player.pause()
    if (player.seekable && targetEnd > 1) player.position = targetEnd - 1
    entryVisible = true
    introFinished()
  }

  onVideoPathChanged: {
    frameReady = false
    entryVisible = false
    playbackFailed = false
    player.stop()
    player.source = videoPath === "" ? "" : Util.fileUrl(videoPath)
    if (active && videoPath !== "") player.play()
  }

  onActiveChanged: {
    if (!active) player.pause()
    else if (videoPath !== "" && !entryVisible) player.play()
  }

  implicitHeight: Math.round(width * 9 / 16)
  radius: Style.cornerRadius
  clip: true
  color: "#05070b"

  VideoOutput {
    id: output
    anchors.fill: parent
    fillMode: VideoOutput.PreserveAspectCrop
    visible: root.videoPath !== "" && !root.playbackFailed
  }

  MediaPlayer {
    id: player
    videoOutput: output
    audioOutput: AudioOutput {
      muted: !root.soundEnabled
      volume: root.volumePercent / 100.0
    }
    loops: MediaPlayer.Once

    onPositionChanged: {
      if (!root.entryVisible && root.targetEnd > 0 && position >= root.targetEnd - 70)
        root.finishIntro()
    }
    onMediaStatusChanged: function(status) {
      if (status === MediaPlayer.EndOfMedia) root.finishIntro()
      else if (status === MediaPlayer.InvalidMedia) {
        root.playbackFailed = true
        root.entryVisible = true
      }
    }
    onErrorOccurred: function(error, errorString) {
      console.warn("Luks Live preview:", errorString)
      root.playbackFailed = true
      root.entryVisible = true
    }
  }

  Connections {
    target: output.videoSink
    function onVideoFrameChanged() { root.frameReady = true }
  }

  Column {
    anchors.centerIn: parent
    visible: root.videoPath === ""
    spacing: Style.space(8)

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: "LIVE BOOT"
      color: "#ffffff"
      font.family: Style.font.family
      font.pixelSize: Style.font.heading
      font.bold: true
      font.letterSpacing: 4
    }
    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: "Choose a video to preview the LUKS transition"
      color: "#9aa4b5"
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
    }
  }

  Rectangle {
    anchors.left: parent.left
    anchors.top: parent.top
    anchors.margins: Style.space(10)
    width: phaseLabel.implicitWidth + Style.space(14)
    height: phaseLabel.implicitHeight + Style.space(8)
    radius: height / 2
    color: "#99000000"

    Text {
      id: phaseLabel
      anchors.centerIn: parent
      text: root.entryVisible ? "LUKS READY" : (player.playbackState === MediaPlayer.PlayingState ? "INTRO" : "PREVIEW")
      color: root.entryVisible ? "#9ece6a" : "#ffffff"
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      font.bold: true
      font.letterSpacing: 1.5
    }
  }

  Row {
    id: passwordRow
    x: Math.max(8, Math.min(parent.width - width - 8, parent.width * root.entryX - width / 2))
    y: Math.max(8, Math.min(parent.height - height - 8, parent.height * root.entryY - height / 2))
    spacing: 15 * root.scaleFactor
    opacity: root.entryVisible ? 1 : 0
    visible: opacity > 0

    Behavior on opacity { NumberAnimation { duration: 180 } }

    Image {
      source: "/usr/share/plymouth/themes/omarchy/lock.png"
      width: 34 * root.scaleFactor
      height: 38 * root.scaleFactor
      fillMode: Image.PreserveAspectFit
      anchors.verticalCenter: parent.verticalCenter
    }

    Item {
      width: entryImage.width
      height: entryImage.height

      Image {
        id: entryImage
        source: "/usr/share/plymouth/themes/omarchy/entry.png"
        width: 286 * root.scaleFactor
        height: 48 * root.scaleFactor
      }

      Row {
        anchors.left: parent.left
        anchors.leftMargin: 20 * root.scaleFactor
        anchors.verticalCenter: parent.verticalCenter
        spacing: 5 * root.scaleFactor

        Repeater {
          model: 4
          Image {
            source: "/usr/share/plymouth/themes/omarchy/bullet.png"
            width: 7 * root.scaleFactor
            height: 7 * root.scaleFactor
          }
        }
      }
    }
  }

  MouseArea {
    anchors.fill: parent
    cursorShape: root.videoPath === "" ? Qt.ArrowCursor : Qt.PointingHandCursor
    onClicked: root.replay()
  }
}
