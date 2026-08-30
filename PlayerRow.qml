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
  readonly property bool evaluable: showPace && player.slot !== "BN" && (live || gameStatus.state === "post") && Number(player.expected_samples||0) >= 2 && Number(gameStatus.progress||0) >= .10
  readonly property real expectedPace: Number(player.expected||0) * Number(gameStatus.progress||0)
  readonly property real tolerance: Math.max(2, Number(player.expected||0) * .15)
  readonly property int pace: !evaluable ? 0 : (Number(player.points||0) > expectedPace+tolerance ? 1 : (Number(player.points||0) < expectedPace-tolerance ? -1 : 2))
  readonly property color paceColor: pace === 1 ? "#86b875" : (pace === -1 ? Color.urgent : (pace === 2 ? "#d6a34a" : root.bar.foreground))
  height: Style.space(28)
  Rectangle { id: slotBadge; width: Style.space(34); height: Style.space(20); anchors.verticalCenter: parent.verticalCenter; radius: Style.cornerRadius; color: root.colorMode === "minimal" ? "transparent" : Qt.rgba(Color.accent.r,Color.accent.g,Color.accent.b,.09)
    Text { anchors.centerIn: parent; text: root.player.slot; color: Qt.darker(root.bar.foreground,1.45); font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption }
  }
  Text { anchors.left: slotBadge.right; anchors.leftMargin: Style.space(4); anchors.right: gameProgress.left; anchors.rightMargin: Style.space(6); anchors.verticalCenter: parent.verticalCenter; text: root.player.name + (root.player.nfl_team ? " · " + root.player.nfl_team : ""); elide: Text.ElideRight; color: root.player.slot === "BN" ? Color.muted : root.bar.foreground; font.family: root.bar.fontFamily; font.pixelSize: Style.font.body }
  Item { id: gameProgress; width: root.live && root.showProgress ? Style.space(58) : 0; height: parent.height; anchors.right: pts.left; anchors.rightMargin: root.live && root.showProgress ? Style.space(7) : 0
    Text { anchors.top: parent.top; anchors.horizontalCenter: parent.horizontalCenter; text: "Q"+root.gameStatus.period+" "+root.gameStatus.clock; color: Color.muted; font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption }
    Rectangle { anchors.bottom: parent.bottom; anchors.bottomMargin: Style.space(3); width: parent.width; height: Style.space(3); radius: height/2; color: Qt.rgba(root.bar.foreground.r,root.bar.foreground.g,root.bar.foreground.b,.10)
      Rectangle { width: parent.width*Math.max(0,Math.min(1,Number(root.gameStatus.progress||0))); height: parent.height; radius: height/2; color: root.evaluable ? root.paceColor : Color.accent }
    }
  }
  Text { id: pts; width: Style.space(42); horizontalAlignment: Text.AlignRight; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; text: (root.pace===1?"▲ ":(root.pace===-1?"▼ ":(root.pace===2?"● ":""))) + Number(root.player.points||0).toFixed(1); color: root.colorMode === "minimal" || !root.evaluable ? root.bar.foreground : root.paceColor; font.family: root.bar.fontFamily; font.pixelSize: Style.font.body }
}
