import QtQuick
import qs.Commons

Item {
  id: root
  property var player: ({})
  property var bar: null
  property string colorMode: "theme"
  height: Style.space(28)
  Rectangle { id: slotBadge; width: Style.space(34); height: Style.space(20); anchors.verticalCenter: parent.verticalCenter; radius: Style.cornerRadius; color: root.colorMode === "minimal" ? "transparent" : Qt.rgba(Color.accent.r,Color.accent.g,Color.accent.b,.09)
    Text { anchors.centerIn: parent; text: root.player.slot; color: Qt.darker(root.bar.foreground,1.45); font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption }
  }
  Text { anchors.left: slotBadge.right; anchors.leftMargin: Style.space(4); anchors.right: pts.left; anchors.rightMargin: Style.space(8); anchors.verticalCenter: parent.verticalCenter; text: root.player.name + (root.player.nfl_team ? " · " + root.player.nfl_team : ""); elide: Text.ElideRight; color: root.player.slot === "BN" ? Color.muted : root.bar.foreground; font.family: root.bar.fontFamily; font.pixelSize: Style.font.body }
  Text { id: pts; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; text: Number(root.player.points||0).toFixed(1); color: root.bar.foreground; font.family: root.bar.fontFamily; font.pixelSize: Style.font.body }
}
