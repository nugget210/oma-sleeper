import QtQuick
import qs.Commons

Item {
  id: root
  property var player: ({})
  property var bar: null
  property string colorMode: "theme"
  property string displayMode: "full"
  readonly property bool showProgress: displayMode === "full" || displayMode === "progress"
  readonly property bool showPace: displayMode === "full" || displayMode === "pace"
  readonly property var gameStatus: player.game_status || ({state:"idle",progress:0})
  readonly property bool live: gameStatus.state === "in"
  // A row whose NFL game is on right now is tinted and edged so the lineup can
  // be scanned for "who is playing" without reading each row's clock. Minimal
  // colour mode keeps the theme foreground rather than introducing the accent.
  readonly property color liveTint: root.colorMode === "minimal" ? root.bar.foreground : Color.accent
  // Pace is measured against the share of the projection the game has reached:
  // at half time, half the projection. It was previously measured against a
  // rolling average of the player's own previous weeks, which needed two
  // completed weeks before it could say anything, so it showed nothing at all
  // for the first fortnight of a season. The projection is available from week
  // one and is the number the rest of the panel already reasons about.
  readonly property real benchmark: Number(player.projected)
  readonly property bool evaluable: showPace && player.slot !== "BN"
    && (live || gameStatus.state === "post")
    && isFinite(root.benchmark) && root.benchmark > 0
    && Number(gameStatus.progress||0) >= .10
  readonly property int pace: root.evaluable
    ? root.paceAgainst(player.points, root.benchmark, gameStatus.progress) : 0
  // 1 above pace, -1 below, 2 on pace, 0 when there is nothing to compare. The
  // tolerance band keeps ordinary variance from reading as decisive, and its
  // two-point floor stops a small projection making every wobble look like one.
  function paceAgainst(points, benchmark, progress) {
    var target = Number(benchmark)
    if (!isFinite(target) || target <= 0) return 0
    var reached = target * Math.max(0, Math.min(1, Number(progress) || 0))
    var tolerance = Math.max(2, target * .15)
    var scored = Number(points) || 0
    if (scored > reached + tolerance) return 1
    if (scored < reached - tolerance) return -1
    return 2
  }
  readonly property color paceColor: pace === 1 ? "#86b875" : (pace === -1 ? Color.urgent : (pace === 2 ? "#d6a34a" : root.bar.foreground))
  signal activated()
  // An empty lineup slot carries the placeholder id "0" and has nothing to show.
  readonly property bool selectable: Boolean(player.id) && String(player.id) !== "0"
  height: Style.space(28)
  Rectangle {
    id: liveHighlight
    anchors.fill: parent; anchors.leftMargin: -Style.space(4); anchors.rightMargin: -Style.space(4)
    radius: Style.cornerRadius
    visible: root.live
    color: Qt.rgba(root.liveTint.r,root.liveTint.g,root.liveTint.b,.14)
    Rectangle {
      anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom
      width: Style.space(3); radius: parent.radius
      color: root.liveTint
    }
    // The pulse only runs while the row is both live and actually on screen, so
    // a closed panel or a finished game leaves no animation running.
    SequentialAnimation on opacity {
      running: root.live && root.visible
      loops: Animation.Infinite
      NumberAnimation { from: 1; to: .5; duration: 1100; easing.type: Easing.InOutSine }
      NumberAnimation { from: .5; to: 1; duration: 1100; easing.type: Easing.InOutSine }
    }
  }
  Rectangle {
    anchors.fill: parent; anchors.leftMargin: -Style.space(4); anchors.rightMargin: -Style.space(4)
    radius: Style.cornerRadius
    visible: root.selectable && rowArea.containsMouse
    color: Qt.rgba(root.bar.foreground.r,root.bar.foreground.g,root.bar.foreground.b,.07)
  }
  Rectangle { id: slotBadge; width: Style.space(34); height: Style.space(20); anchors.verticalCenter: parent.verticalCenter; radius: Style.cornerRadius; color: root.colorMode === "minimal" ? "transparent" : Qt.rgba(Color.accent.r,Color.accent.g,Color.accent.b,.09)
    Text { anchors.centerIn: parent; text: root.player.slot; textFormat: Text.PlainText; color: Qt.darker(root.bar.foreground,1.45); font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption }
  }
  Item {
    id: playerLabel
    anchors.left: slotBadge.right; anchors.leftMargin: Style.space(4)
    anchors.right: gameProgress.left; anchors.rightMargin: Style.space(4)
    height: parent.height; clip: true
    Text {
      id: playerName
      anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
      text: root.player.name
      textFormat: Text.PlainText
      color: root.player.slot === "BN" && !root.live ? Color.muted : root.bar.foreground
      font.family: root.bar.fontFamily; font.pixelSize: Style.font.body
    }
    Text {
      visible: Boolean(root.player.nfl_team)
      anchors.left: playerName.right; anchors.leftMargin: Style.space(4)
      anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
      text: "· " + root.player.nfl_team; elide: Text.ElideRight
      textFormat: Text.PlainText
      color: root.player.slot === "BN" && !root.live ? Color.muted : root.bar.foreground
      font.family: root.bar.fontFamily; font.pixelSize: Style.font.body
    }
  }
  Item { id: gameProgress; visible: root.live && root.showProgress; width: visible ? Style.space(48) : 0; height: parent.height; anchors.right: pts.left; anchors.rightMargin: visible ? Style.space(4) : 0
    Text { anchors.top: parent.top; anchors.horizontalCenter: parent.horizontalCenter; text: "Q"+root.gameStatus.period+" "+root.gameStatus.clock; textFormat: Text.PlainText; color: Color.muted; font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption }
    Rectangle { anchors.bottom: parent.bottom; anchors.bottomMargin: Style.space(3); width: parent.width; height: Style.space(3); radius: height/2; color: Qt.rgba(root.bar.foreground.r,root.bar.foreground.g,root.bar.foreground.b,.10)
      Rectangle { width: parent.width*Math.max(0,Math.min(1,Number(root.gameStatus.progress||0))); height: parent.height; radius: height/2; color: root.evaluable ? root.paceColor : Color.accent }
    }
  }
  Text { id: pts; width: Style.space(42); horizontalAlignment: Text.AlignRight; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; text: (root.pace===1?"▲ ":(root.pace===-1?"▼ ":(root.pace===2?"● ":""))) + Number(root.player.points||0).toFixed(1); textFormat: Text.PlainText; color: root.colorMode === "minimal" || !root.evaluable ? root.bar.foreground : root.paceColor; font.family: root.bar.fontFamily; font.pixelSize: Style.font.body }
  MouseArea {
    id: rowArea
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: root.selectable ? Qt.PointingHandCursor : Qt.ArrowCursor
    onClicked: if (root.selectable) root.activated()
  }
}
