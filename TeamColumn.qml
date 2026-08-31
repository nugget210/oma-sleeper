import QtQuick
import qs.Commons

Column {
  id: root
  property string teamName: ""
  property real teamScore: 0
  property var projectedScore: null
  property real opponentScore: 0
  property var game: null
  property var bar: null
  property string colorMode: "theme"
  property string playerDisplayMode: "full"
  readonly property bool plainScores: playerDisplayMode === "scores"
  readonly property bool hasScore: teamScore > 0 || opponentScore > 0
  readonly property bool leading: hasScore && teamScore > opponentScore
  readonly property bool trailing: hasScore && teamScore < opponentScore
  readonly property bool hasProjectedScore: projectedScore !== null && isFinite(Number(projectedScore))
  readonly property color positive: colorMode === "performance" ? "#86b875" : Color.accent
  readonly property color negative: colorMode === "performance" ? Color.urgent : Color.muted
  readonly property color emphasis: plainScores || colorMode === "minimal" || !hasScore ? bar.foreground : (leading ? positive : (trailing ? negative : bar.foreground))
  readonly property real share: (teamScore + opponentScore) > 0 ? teamScore / (teamScore + opponentScore) : .5
  spacing: Style.space(8)

  Rectangle {
    width: parent.width; height: root.plainScores ? 0 : Style.space(3); radius: height/2
    visible: !root.plainScores
    color: Qt.rgba(root.bar.foreground.r,root.bar.foreground.g,root.bar.foreground.b,.08)
    Rectangle { width: parent.width * root.share; height: parent.height; radius: height/2; color: root.colorMode === "minimal" ? root.bar.foreground : root.emphasis; opacity: root.hasScore ? 1 : .35 }
  }
  Row {
    width: parent.width
    Text { width: parent.width-scoreGroup.width-Style.space(8); text: (!root.plainScores && root.leading && root.colorMode !== "minimal" ? "▲ " : (!root.plainScores && root.trailing && root.colorMode !== "minimal" ? "▼ " : "")) + root.teamName; elide: Text.ElideRight; color: root.emphasis; font.family: root.bar.fontFamily; font.pixelSize: Style.font.title; font.bold: true }
    Row {
      id: scoreGroup; spacing: Style.space(6)
      Text { anchors.baseline: currentScoreText.baseline; text: root.hasProjectedScore ? Number(root.projectedScore).toFixed(2) : "—"; color: Qt.darker(root.bar.foreground,1.45); font.family: root.bar.fontFamily; font.pixelSize: Style.font.body }
      Text { id: currentScoreText; text: Number(root.teamScore||0).toFixed(1); color: root.emphasis; font.family: root.bar.fontFamily; font.pixelSize: Style.font.title; font.bold: true }
    }
  }
  Text { text: "STARTERS"; color: Qt.darker(root.bar.foreground,1.5); font.family: root.bar.fontFamily; font.pixelSize: Style.font.bodySmall; font.letterSpacing: 1 }
  Repeater { model: root.game ? root.game.starters : []; PlayerRow { required property var modelData; width: root.width; player: modelData; bar: root.bar; colorMode: root.colorMode; displayMode: root.playerDisplayMode } }
  Text { text: "BENCH"; topPadding: Style.space(8); color: Qt.darker(root.bar.foreground,1.5); font.family: root.bar.fontFamily; font.pixelSize: Style.font.bodySmall; font.letterSpacing: 1 }
  Repeater { model: root.game ? root.game.bench : []; PlayerRow { required property var modelData; width: root.width; player: modelData; bar: root.bar; colorMode: root.colorMode; displayMode: root.playerDisplayMode } }
}
