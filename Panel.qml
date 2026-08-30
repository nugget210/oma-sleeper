import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "oma-sleeper"
  ipcTarget: "oma-sleeper"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root
  property var data: null
  property string errorText: ""
  property bool settingsOpen: false
  property bool loading: false
  property string settingsMessage: ""
  property bool forceMetadataRefresh: false
  property double lastHeartbeatMs: Date.now()
  property string previewScenario: "off"

  readonly property string leagueId: String(setting("leagueId", ""))
  readonly property int selectedRosterId: parseInt(setting("rosterId", 0), 10) || 0
  readonly property string shortName: String(setting("shortName", ""))
  readonly property string colorMode: String(setting("colorMode", "theme"))
  readonly property int refreshMinutes: Math.max(1, parseInt(setting("refreshMinutes", 2), 10) || 2) // retained for settings compatibility
  readonly property string syncState: data && data.sync_state ? String(data.sync_state) : "idle"
  readonly property int adaptiveIntervalMs: data && Number(data.next_refresh_seconds) > 0 ? Number(data.next_refresh_seconds) * 1000 : 900000
  readonly property var viewData: previewScenario === "off" ? data : buildPreviewData(data, previewScenario)
  readonly property var myGame: gameFor(selectedRosterId)
  readonly property var opponentGame: opponentFor(myGame)
  readonly property string opponentName: opponentGame ? teamName(opponentGame.roster_id) : "OPP"
  readonly property string opponentShort: abbreviation(opponentName)
  readonly property string barText: leagueId === "" ? "NFL SETUP" : (loading && !data ? "NFL …" :
    (myGame && opponentGame ? (shortName || "MY") + " " + score(myGame.points) + " – " + score(opponentGame.points) + " " + opponentShort : "NFL SETUP"))
  readonly property bool hasLiveScore: myGame && opponentGame && (Number(myGame.points) > 0 || Number(opponentGame.points) > 0)
  readonly property color positiveColor: colorMode === "performance" ? "#86b875" : Color.accent
  readonly property color negativeColor: colorMode === "performance" ? Color.urgent : Color.muted
  readonly property color barColor: colorMode === "minimal" || !hasLiveScore ? (bar ? bar.foreground : Color.foreground) :
    (Number(myGame.points) > Number(opponentGame.points) ? positiveColor :
     (Number(myGame.points) < Number(opponentGame.points) ? negativeColor : (bar ? bar.foreground : Color.foreground)))

  function score(value) { return Number(value || 0).toFixed(1) }
  function buildPreviewData(source, scenario) {
    if (!source || !source.games) return source
    var copy = JSON.parse(JSON.stringify(source))
    var mine = null
    var theirs = null
    for (var i = 0; i < copy.games.length; i++) {
      if (copy.games[i].roster_id === selectedRosterId) mine = copy.games[i]
    }
    if (!mine) return copy
    for (var j = 0; j < copy.games.length; j++) {
      if (copy.games[j].matchup_id === mine.matchup_id && copy.games[j].roster_id !== mine.roster_id) theirs = copy.games[j]
    }
    if (!theirs) return copy

    var high = [22.8,18.4,7.1,13.7,9.8,6.4,12.2,8.9,11.0,6.0]
    var low = [18.2,9.6,10.1,11.4,7.3,4.8,8.1,6.2,9.0,5.0]
    applyPreviewPoints(mine, scenario === "leading" ? high : low)
    applyPreviewPoints(theirs, scenario === "leading" ? low : high)
    copy.sync_state = "live"
    return copy
  }
  function applyPreviewPoints(game, points) {
    var total = 0
    for (var i = 0; i < game.starters.length; i++) {
      var value = i < points.length ? points[i] : 0
      game.starters[i].points = value
      total += value
    }
    for (var j = 0; j < game.bench.length; j++) game.bench[j].points = j < 2 ? [5.6,2.3][j] : 0
    game.points = Math.round(total * 10) / 10
  }
  function gameFor(id) {
    if (!viewData || !viewData.games) return null
    for (var i=0; i<viewData.games.length; i++) if (viewData.games[i].roster_id === id) return viewData.games[i]
    return null
  }
  function opponentFor(game) {
    if (!game || !viewData) return null
    for (var i=0; i<viewData.games.length; i++)
      if (viewData.games[i].matchup_id === game.matchup_id && viewData.games[i].roster_id !== game.roster_id) return viewData.games[i]
    return null
  }
  function teamName(id) {
    if (!viewData || !viewData.teams) return "Roster " + id
    for (var i=0; i<viewData.teams.length; i++) if (viewData.teams[i].roster_id === id) return viewData.teams[i].name
    return "Roster " + id
  }
  function abbreviation(name) {
    var words = String(name || "OPP").trim().split(/\s+/)
    if (words.length === 1) return words[0].slice(0,3).toUpperCase()
    var out = ""; for (var i=0; i<words.length && out.length<3; i++) out += words[i][0]
    return out.toUpperCase()
  }
  function refresh(forceMetadata) {
    if (leagueId === "") return
    if (fetchProc.running) return
    forceMetadataRefresh = forceMetadata === true
    loading = true; errorText = ""
    fetchProc.running = true
  }
  function open() { if (leagueId === "") settingsOpen = true; controller.show(); refresh(false) }
  function close() { settingsOpen = false; controller.hide() }
  function saveEntry(leagueId, rosterId, label, mode) {
    var entry = {id:root.moduleName, leagueId:leagueId, rosterId:rosterId,
                 shortName:label || "", refreshMinutes:root.refreshMinutes,
                 colorMode:mode || root.colorMode}
    root.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }
  function persist(rosterId, label) { saveEntry(root.leagueId, rosterId, label, root.colorMode) }
  function setColorMode(mode) { saveEntry(root.leagueId, root.selectedRosterId, labelField.text.trim(), mode) }
  function leagueIdFromInput(value) {
    var text = String(value || "").trim()
    var match = text.match(/(?:leagues\/)?(\d{10,})/)
    return match ? match[1] : ""
  }
  function updateLeague() {
    var id = leagueIdFromInput(leagueField.text)
    if (!id) {
      settingsMessage = "Enter a Sleeper league URL or numeric league ID"
      return
    }
    settingsMessage = "Syncing league…"
    data = null
    saveEntry(id, 0, labelField.text.trim(), root.colorMode)
    Qt.callLater(function() { refresh(true) })
  }
  function openSleeper() {
    if (root.bar && root.leagueId !== "") root.bar.run("xdg-open 'https://sleeper.com/leagues/" + root.leagueId + "/matchup'")
  }

  Process {
    id: fetchProc
    command: [Qt.resolvedUrl("bin/sleeper-matchup").toString().replace("file://", ""), root.leagueId, "auto", root.forceMetadataRefresh ? "force" : "normal"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try { root.data = JSON.parse(String(text)); root.errorText = ""; if (root.settingsOpen) root.settingsMessage = "League synced — choose your fantasy team" }
        catch(e) { root.errorText = "Could not read matchup data" }
      }
    }
    onExited: function(code) { root.loading = false; root.forceMetadataRefresh = false; if (code !== 0) root.errorText = "Sleeper is unavailable" }
  }
  Timer {
    id: refreshTimer
    interval: root.adaptiveIntervalMs
    repeat: true
    running: root.leagueId !== ""
    triggeredOnStart: true
    onTriggered: root.refresh(false)
  }
  SystemClock {
    id: heartbeat
    precision: SystemClock.Minutes
    onDateChanged: {
      var now = Date.now()
      // A large wall-clock jump means suspend/resume or a stalled session.
      if (now - root.lastHeartbeatMs > 150000) root.refresh(false)
      root.lastHeartbeatMs = now
    }
  }

  KeyboardPanel {
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: true
    focusTarget: keyCatcher
    contentWidth: fittedContentWidth(Style.space(620))
    // Request the complete two-roster layout. KeyboardPanel still clamps the
    // card to the physical output when a genuinely smaller display requires
    // it, but normal desktop screens no longer hide the last bench players.
    contentHeight: fittedContentHeight(content.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.settingsOpen
      onCloseRequested: root.close()
      onTabRequested: function(direction) { if (root.bar) root.bar.switchPanelFrom(root.barIdentity, direction) }

      Flickable {
        anchors.fill: parent; contentWidth: width; contentHeight: content.implicitHeight
        clip: true; boundsBehavior: Flickable.StopAtBounds

        Column {
          id: content
          width: parent.width
          spacing: Style.space(14)

          Item {
            width: parent.width; height: Style.space(32)
            Text { anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; text: root.data ? root.data.league_name + " · Week " + root.data.week + (root.previewScenario !== "off" ? " · LIVE PREVIEW" : "") : "Sleeper matchup"; color: root.bar.foreground; font.family: root.bar.fontFamily; font.pixelSize: Style.font.title; font.bold: true }
            Row {
              anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; spacing: Style.space(8)
              Repeater {
                model: [{icon:"󰒓", tip:"Settings"}, {icon:"󰏌", tip:"Open Sleeper"}, {icon:root.loading?"󰦖":"󰑐", tip:"Refresh"}]
                Rectangle {
                  required property var modelData; required property int index
                  width: Style.space(28); height: width; radius: Style.cornerRadius; color: area.containsMouse ? Style.hoverFillFor(root.bar.foreground, Color.accent) : "transparent"
                  Text { anchors.centerIn: parent; text: modelData.icon; color: root.bar.foreground; font.family: root.bar.fontFamily; font.pixelSize: Style.font.body }
                  MouseArea { id: area; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { if (index===0) root.settingsOpen=!root.settingsOpen; else if(index===1) root.openSleeper(); else root.refresh(true) } }
                }
              }
            }
          }

          Rectangle { width: parent.width; height: 1; color: root.bar.foreground; opacity: .12 }

          Column {
            visible: root.settingsOpen; width: parent.width; spacing: Style.space(12)
            Text { text: "SETTINGS"; color: Qt.darker(root.bar.foreground,1.4); font.family: root.bar.fontFamily; font.pixelSize: Style.font.bodySmall; font.letterSpacing: 1 }
            Text { text: "Sleeper league URL or ID"; color: root.bar.foreground; font.family: root.bar.fontFamily; font.pixelSize: Style.font.body }
            Row {
              width: parent.width; spacing: Style.space(10)
              TextField {
                id: leagueField
                width: parent.width - updateLeagueButton.width - parent.spacing
                text: root.leagueId === "" ? "" : "https://sleeper.com/leagues/" + root.leagueId + "/matchup"
                placeholderText: "Sleeper league URL or ID"
                foreground: root.bar.foreground
                font.family: root.bar.fontFamily
              }
              Rectangle {
                id: updateLeagueButton
                width: Style.space(92); height: Style.space(34); radius: Style.cornerRadius
                color: updateLeagueArea.containsMouse ? Color.accent : Style.hoverFillFor(root.bar.foreground, Color.accent)
                Text { anchors.centerIn: parent; text: root.loading ? "Syncing…" : "Update"; color: root.bar.foreground; font.family: root.bar.fontFamily; font.pixelSize: Style.font.body }
                MouseArea { id: updateLeagueArea; anchors.fill: parent; enabled: !root.loading; hoverEnabled: true; cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor; onClicked: root.updateLeague() }
              }
            }
            Text { visible: root.settingsMessage !== ""; text: root.settingsMessage; color: Qt.darker(root.bar.foreground,1.35); font.family: root.bar.fontFamily; font.pixelSize: Style.font.bodySmall }
            Row {
              spacing: Style.space(12)
              Text { width: Style.space(110); text: "Bar label"; color: root.bar.foreground; font.family: root.bar.fontFamily; font.pixelSize: Style.font.body; anchors.verticalCenter: parent.verticalCenter }
              TextField { id: labelField; width: Style.space(120); text: root.shortName; placeholderText: "MY"; foreground: root.bar.foreground; font.family: root.bar.fontFamily }
            }
            Text { text: "Scoreboard colours"; color: root.bar.foreground; font.family: root.bar.fontFamily; font.pixelSize: Style.font.body }
            Row {
              spacing: Style.space(8)
              Repeater {
                model: [{id:"theme",label:"Theme-aware"},{id:"performance",label:"Performance"},{id:"minimal",label:"Minimal"}]
                Rectangle {
                  required property var modelData
                  width: modeLabel.implicitWidth + Style.space(24); height: Style.space(32); radius: Style.cornerRadius
                  color: modelData.id === root.colorMode ? Style.selectedFillFor(root.bar.foreground, Color.accent) : (modeArea.containsMouse ? Style.hoverFillFor(root.bar.foreground, Color.accent) : "transparent")
                  border.width: 1
                  border.color: modelData.id === root.colorMode ? Color.accent : Qt.rgba(root.bar.foreground.r,root.bar.foreground.g,root.bar.foreground.b,.18)
                  Text { id: modeLabel; anchors.centerIn: parent; text: modelData.label; color: modelData.id === root.colorMode ? Style.selectedStateColor(root.bar.foreground,Color.accent) : root.bar.foreground; font.family: root.bar.fontFamily; font.pixelSize: Style.font.bodySmall }
                  MouseArea { id: modeArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.setColorMode(modelData.id) }
                }
              }
            }
            Text { text: root.colorMode === "theme" ? "Uses the active Omarchy accent and muted colours." : (root.colorMode === "performance" ? "Adds green for leading and urgent colour for trailing." : "Keeps the scoreboard monochrome."); color: Qt.darker(root.bar.foreground,1.4); font.family: root.bar.fontFamily; font.pixelSize: Style.font.bodySmall }
            Text { text: "Live-game preview"; color: root.bar.foreground; font.family: root.bar.fontFamily; font.pixelSize: Style.font.body }
            Row {
              spacing: Style.space(8)
              Repeater {
                model: [{id:"leading",label:"Leading"},{id:"trailing",label:"Trailing"},{id:"off",label:"Off"}]
                Rectangle {
                  required property var modelData
                  width: previewLabel.implicitWidth + Style.space(24); height: Style.space(32); radius: Style.cornerRadius
                  color: modelData.id === root.previewScenario ? Style.selectedFillFor(root.bar.foreground, Color.accent) : (previewArea.containsMouse ? Style.hoverFillFor(root.bar.foreground, Color.accent) : "transparent")
                  border.width: 1
                  border.color: modelData.id === root.previewScenario ? Color.accent : Qt.rgba(root.bar.foreground.r,root.bar.foreground.g,root.bar.foreground.b,.18)
                  Text { id: previewLabel; anchors.centerIn: parent; text: modelData.label; color: root.bar.foreground; font.family: root.bar.fontFamily; font.pixelSize: Style.font.bodySmall }
                  MouseArea { id: previewArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { root.previewScenario=modelData.id; if (modelData.id !== "off") root.settingsOpen=false } }
                }
              }
            }
            Text { text: "Preview scores are local, temporary, and never sent to Sleeper."; color: Qt.darker(root.bar.foreground,1.4); font.family: root.bar.fontFamily; font.pixelSize: Style.font.bodySmall }
            Text { text: "Fantasy team"; color: root.bar.foreground; font.family: root.bar.fontFamily; font.pixelSize: Style.font.body }
            Column {
              width: parent.width
              Repeater {
                model: root.data ? root.data.teams : []
                Rectangle {
                  required property var modelData
                  width: parent.width; height: Style.space(34); radius: Style.cornerRadius
                  color: modelData.roster_id === root.selectedRosterId ? Style.hoverFillFor(root.bar.foreground, Color.accent) : (teamArea.containsMouse ? Qt.rgba(1,1,1,.04) : "transparent")
                  Text { anchors.left: parent.left; anchors.leftMargin: Style.space(10); anchors.verticalCenter: parent.verticalCenter; text: (modelData.roster_id === root.selectedRosterId ? "●  " : "○  ") + modelData.name; color: root.bar.foreground; font.family: root.bar.fontFamily; font.pixelSize: Style.font.body }
                  MouseArea { id: teamArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.persist(modelData.roster_id, labelField.text.trim()) }
                }
              }
            }
            Rectangle {
              width: Style.space(90); height: Style.space(32); radius: Style.cornerRadius; color: saveArea.containsMouse ? Color.accent : Style.hoverFillFor(root.bar.foreground, Color.accent)
              Text { anchors.centerIn: parent; text: "Save"; color: root.bar.foreground; font.family: root.bar.fontFamily; font.pixelSize: Style.font.body }
              MouseArea { id: saveArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { root.persist(root.selectedRosterId,labelField.text.trim()); root.settingsOpen=false } }
            }
          }

          Text { visible: root.errorText !== ""; text: root.errorText; color: "#ef5350"; font.family: root.bar.fontFamily; font.pixelSize: Style.font.body }

          Row {
            visible: !root.settingsOpen && root.myGame && root.opponentGame
            width: parent.width; spacing: Style.space(24)
            TeamColumn { width: (parent.width-parent.spacing)/2; teamName: root.teamName(root.myGame ? root.myGame.roster_id : 0); teamScore: root.myGame ? root.myGame.points : 0; opponentScore: root.opponentGame ? root.opponentGame.points : 0; game: root.myGame; bar: root.bar; colorMode: root.colorMode }
            TeamColumn { width: (parent.width-parent.spacing)/2; teamName: root.teamName(root.opponentGame ? root.opponentGame.roster_id : 0); teamScore: root.opponentGame ? root.opponentGame.points : 0; opponentScore: root.myGame ? root.myGame.points : 0; game: root.opponentGame; bar: root.bar; colorMode: root.colorMode }
          }
        }
      }
    }
  }
}
