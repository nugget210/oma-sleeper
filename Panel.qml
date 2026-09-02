import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "nugget210.oma-sleeper"
  ipcTarget: "nugget210.oma-sleeper"
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
  readonly property int maxTeams: 64
  readonly property int maxPlayersPerSection: 32
  readonly property int maxPayloadCharacters: 2097152
  readonly property int maxLabelLength: 24
  readonly property string leagueId: String(setting("leagueId", ""))
  readonly property int selectedRosterId: parseInt(setting("rosterId", 0), 10) || 0
  readonly property string shortName: boundedLabel(setting("shortName", ""))
  readonly property string opponentLabel: boundedLabel(setting("opponentName", ""))
  readonly property string colorMode: String(setting("colorMode", "theme"))
  readonly property string playerDisplayMode: String(setting("playerDisplayMode", "full"))
  readonly property int refreshMinutes: Math.max(1, parseInt(setting("refreshMinutes", 2), 10) || 2) // retained for settings compatibility
  readonly property string syncState: data && data.sync_state ? String(data.sync_state) : "idle"
  readonly property int adaptiveIntervalMs: data && Number(data.next_refresh_seconds) > 0 ? Number(data.next_refresh_seconds) * 1000 : 900000
  readonly property var myGame: gameFor(selectedRosterId)
  readonly property var opponentGame: opponentFor(myGame)
  readonly property real widestPlayerLabel: widestLineupLabel(myGame, opponentGame)
  readonly property bool reservesProgressSpace: playerDisplayMode === "full" || playerDisplayMode === "progress"
  readonly property real desiredPanelWidth: Math.max(Style.space(620),
    Style.space(16) + 2 * (Style.space(34 + 4 + 4 + 42 + 8) + widestPlayerLabel
      + (reservesProgressSpace ? Style.space(52) : 0)))
  readonly property string opponentName: opponentLabel || (opponentGame ? teamName(opponentGame.roster_id) : "OPP")
  readonly property string opponentShort: opponentLabel || abbreviation(opponentName)
  readonly property string matchupState: calculateMatchupState(myGame, opponentGame)
  readonly property string barStatusSuffix: matchupState === "live" ? " · ● LIVE" : (matchupState === "upcoming" ? " · UPCOMING" : "")
  readonly property string barText: leagueId === "" ? "NFL SETUP" : (loading && !data ? "NFL …" :
    (myGame && opponentGame ? (shortName || "MY") + " " + score(myGame.points) + " – " + score(opponentGame.points) + " " + opponentShort + barStatusSuffix : "NFL SETUP"))
  readonly property bool hasLiveScore: myGame && opponentGame && (Number(myGame.points) > 0 || Number(opponentGame.points) > 0)
  readonly property color positiveColor: colorMode === "performance" ? "#86b875" : Color.accent
  readonly property color negativeColor: colorMode === "performance" ? Color.urgent : Color.muted
  readonly property color barColor: colorMode === "minimal" || !hasLiveScore ? (bar ? bar.foreground : Color.foreground) :
    (Number(myGame.points) > Number(opponentGame.points) ? positiveColor :
     (Number(myGame.points) < Number(opponentGame.points) ? negativeColor : (bar ? bar.foreground : Color.foreground)))

  function score(value) { return Number(value || 0).toFixed(1) }
  function boundedLabel(value) {
    return String(value || "").replace(/[\u0000-\u001f\u007f]/g, " ").trim().slice(0, root.maxLabelLength)
  }
  function projectedScore(game) {
    if (!game || !game.starters) return null
    var total = 0
    var projectedPlayers = 0
    var roundStarted = false
    for (var s = 0; s < game.starters.length; s++) {
      var starterStatus = game.starters[s].game_status || {}
      if (starterStatus.state === "in" || Number(game.starters[s].points || 0) !== 0) {
        roundStarted = true
        break
      }
    }
    for (var i = 0; i < game.starters.length; i++) {
      var player = game.starters[i]
      var projection = player.projected
      if (projection === null || projection === undefined || !isFinite(Number(projection))) continue
      projectedPlayers++
      var status = player.game_status || {}
      var progress = Math.max(0, Math.min(1, Number(status.progress || 0)))
      if (status.state === "post" && roundStarted) total += Number(player.points || 0)
      else if (status.state === "in") total += Number(player.points || 0) + Number(projection) * (1 - progress)
      else total += Number(projection)
    }
    return projectedPlayers > 0 ? total : null
  }
  function widestLineupLabel(first, second) {
    var widest = 0
    var games = [first, second]
    for (var g = 0; g < games.length; g++) {
      if (!games[g]) continue
      var players = (games[g].starters || []).concat(games[g].bench || [])
      for (var i = 0; i < players.length; i++) {
        var label = String(players[i].name || "")
          + (players[i].nfl_team ? " · " + players[i].nfl_team : "")
        widest = Math.max(widest, playerFontMetrics.advanceWidth(label))
      }
    }
    return widest
  }

  FontMetrics {
    id: playerFontMetrics
    font.family: root.bar ? root.bar.fontFamily : ""
    font.pixelSize: Style.font.body
  }

  function calculateMatchupState(first, second) {
    if (!first || !second) return "idle"
    var players = (first.starters || []).concat(second.starters || [])
    var live = 0, upcoming = 0, completed = 0
    for (var i = 0; i < players.length; i++) {
      var state = players[i].game_status ? players[i].game_status.state : "idle"
      if (state === "in") live++
      else if (state === "pre") upcoming++
      else if (state === "post") completed++
    }
    if (live > 0) return "live"
    if (upcoming > 0) return "upcoming"
    if (completed > 0) return "final"
    return "idle"
  }
  function gameFor(id) {
    if (!data || !data.games) return null
    for (var i=0; i<data.games.length; i++) if (data.games[i].roster_id === id) return data.games[i]
    return null
  }
  function opponentFor(game) {
    if (!game || !data) return null
    for (var i=0; i<data.games.length; i++)
      if (data.games[i].matchup_id === game.matchup_id && data.games[i].roster_id !== game.roster_id) return data.games[i]
    return null
  }
  function teamName(id) {
    if (!data || !data.teams) return "Roster " + id
    for (var i=0; i<data.teams.length; i++) if (data.teams[i].roster_id === id) return data.teams[i].name
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
  function saveEntry(leagueId, rosterId, label, mode, displayMode, opponentName) {
    var entry = {id:root.moduleName, leagueId:leagueId, rosterId:rosterId,
                 shortName:root.boundedLabel(label), refreshMinutes:root.refreshMinutes,
                 colorMode:mode || root.colorMode,
                 playerDisplayMode:displayMode || root.playerDisplayMode,
                 opponentName:root.boundedLabel(opponentName)}
    if (root.hostWidget && typeof root.hostWidget.publishSettings === "function")
      root.hostWidget.publishSettings(entry)
    else root.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }
  function persist(rosterId, label) { saveEntry(root.leagueId, rosterId, label, root.colorMode, root.playerDisplayMode, opponentField.text.trim()) }
  function setColorMode(mode) { saveEntry(root.leagueId, root.selectedRosterId, labelField.text.trim(), mode, root.playerDisplayMode, opponentField.text.trim()) }
  function setPlayerDisplayMode(mode) { saveEntry(root.leagueId, root.selectedRosterId, labelField.text.trim(), root.colorMode, mode, opponentField.text.trim()) }
  function leagueIdFromInput(value) {
    var text = String(value || "").trim()
    if (/^\d{10,24}$/.test(text)) return text
    var match = text.match(/\/leagues\/(\d{10,24})(?:\/|$)/)
    return match ? match[1] : ""
  }
  function boundedResult(result) {
    if (!result || typeof result !== "object") throw new Error("Invalid result")
    if (!/^\d{10,24}$/.test(String(result.league_id || ""))) throw new Error("Invalid league ID")
    if (String(result.league_id) !== root.leagueId) throw new Error("Mismatched league ID")
    var week = Number(result.week)
    if (!Number.isInteger(week) || week < 1 || week > 18) throw new Error("Invalid week")
    if (!Array.isArray(result.teams) || result.teams.length > root.maxTeams) throw new Error("Too many teams")
    if (!Array.isArray(result.games) || result.games.length > root.maxTeams) throw new Error("Too many games")
    result.teams = result.teams.slice(0, root.maxTeams)
    result.games = result.games.slice(0, root.maxTeams)
    for (var i = 0; i < result.games.length; i++) {
      var game = result.games[i]
      if (!game || typeof game !== "object") throw new Error("Invalid game")
      if (!Array.isArray(game.starters) || game.starters.length > root.maxPlayersPerSection)
        throw new Error("Too many starters")
      if (!Array.isArray(game.bench) || game.bench.length > root.maxPlayersPerSection)
        throw new Error("Too many bench players")
      game.starters = game.starters.slice(0, root.maxPlayersPerSection)
      game.bench = game.bench.slice(0, root.maxPlayersPerSection)
    }
    return result
  }
  function updateLeague() {
    var id = leagueIdFromInput(leagueField.text)
    if (!id) {
      settingsMessage = ""
      errorText = "No league ID found — paste a Sleeper league URL or numeric league ID"
      return
    }
    errorText = ""
    settingsMessage = "Syncing league…"
    data = null
    saveEntry(id, 0, labelField.text.trim(), root.colorMode, root.playerDisplayMode, opponentField.text.trim())
    Qt.callLater(function() { refresh(true) })
  }
  function openSleeper() {
    if (root.bar && /^\d{10,24}$/.test(root.leagueId))
      root.bar.run("xdg-open 'https://sleeper.com/leagues/" + root.leagueId + "/matchup'")
  }

  Process {
    id: fetchProc
    command: [Qt.resolvedUrl("bin/sleeper-matchup").toString().replace("file://", ""), root.leagueId, "auto", root.forceMetadataRefresh ? "force" : "normal"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var payload = String(text)
          if (payload.length > root.maxPayloadCharacters) throw new Error("Matchup response is too large")
          var result = root.boundedResult(JSON.parse(payload))
          if (root.hostWidget && typeof root.hostWidget.publishData === "function") root.hostWidget.publishData(result)
          else root.data = result
          root.errorText = ""
          if (root.settingsOpen) root.settingsMessage = "League synced — choose your fantasy team"
        }
        catch(e) { root.errorText = "Could not read matchup data" }
      }
    }
    onExited: function(code) {
      root.loading = false
      root.forceMetadataRefresh = false
      if (code === 44) {
        root.settingsMessage = ""
        root.errorText = "League not found — check the URL, ID, or current season"
      } else if (code === 124) {
        root.settingsMessage = ""
        root.errorText = "Refresh timed out — check your connection and try again"
      } else if (code !== 0) {
        root.settingsMessage = ""
        root.errorText = "Sleeper is unavailable — check your connection and try again"
      }
    }
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
    contentWidth: fittedContentWidth(root.desiredPanelWidth)
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
            Text { anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; text: root.data ? root.data.league_name + " · Week " + root.data.week : "Sleeper matchup"; textFormat: Text.PlainText; color: root.bar.foreground; font.family: root.bar.fontFamily; font.pixelSize: Style.font.title; font.bold: true }
            Row {
              anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; spacing: Style.space(8)
              Repeater {
                model: [{icon:"󰒓", tip:"Settings"}, {icon:"󰏌", tip:"Open Sleeper"}, {icon:root.loading?"󰦖":"󰑐", tip:"Refresh"}]
                Rectangle {
                  required property var modelData; required property int index
                  width: Style.space(28); height: width; radius: Style.cornerRadius; color: area.containsMouse ? Style.hoverFillFor(root.bar.foreground, Color.accent) : "transparent"
                  Text { anchors.centerIn: parent; text: modelData.icon; textFormat: Text.PlainText; color: root.bar.foreground; font.family: root.bar.fontFamily; font.pixelSize: Style.font.body }
                  MouseArea { id: area; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { if (index===0) root.settingsOpen=!root.settingsOpen; else if(index===1) root.openSleeper(); else root.refresh(true) } }
                }
              }
            }
          }

          Rectangle { width: parent.width; height: 1; color: root.bar.foreground; opacity: .12 }

          Column {
            visible: root.settingsOpen; width: parent.width; spacing: Style.space(12)
            Text { text: "SETTINGS"; textFormat: Text.PlainText; color: Qt.darker(root.bar.foreground,1.4); font.family: root.bar.fontFamily; font.pixelSize: Style.font.bodySmall; font.letterSpacing: 1 }
            Text { text: "Sleeper league URL or ID"; textFormat: Text.PlainText; color: root.bar.foreground; font.family: root.bar.fontFamily; font.pixelSize: Style.font.body }
            Row {
              width: parent.width; spacing: Style.space(10)
              TextField {
                id: leagueField
                width: parent.width - updateLeagueButton.width - parent.spacing
                text: root.leagueId === "" ? "" : "https://sleeper.com/leagues/" + root.leagueId + "/matchup"
                placeholderText: "Sleeper league URL or ID"
                maximumLength: 128
                foreground: root.bar.foreground
                font.family: root.bar.fontFamily
              }
              Rectangle {
                id: updateLeagueButton
                width: Style.space(92); height: Style.space(34); radius: Style.cornerRadius
                color: updateLeagueArea.containsMouse ? Color.accent : Style.hoverFillFor(root.bar.foreground, Color.accent)
                Text { anchors.centerIn: parent; text: root.loading ? "Syncing…" : "Update"; textFormat: Text.PlainText; color: root.bar.foreground; font.family: root.bar.fontFamily; font.pixelSize: Style.font.body }
                MouseArea { id: updateLeagueArea; anchors.fill: parent; enabled: !root.loading; hoverEnabled: true; cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor; onClicked: root.updateLeague() }
              }
            }
            Text { visible: root.settingsMessage !== ""; text: root.settingsMessage; textFormat: Text.PlainText; color: Qt.darker(root.bar.foreground,1.35); font.family: root.bar.fontFamily; font.pixelSize: Style.font.bodySmall }
            Row {
              spacing: Style.space(12)
              Text { width: Style.space(110); text: "Home Team Name"; textFormat: Text.PlainText; color: root.bar.foreground; font.family: root.bar.fontFamily; font.pixelSize: Style.font.body; anchors.verticalCenter: parent.verticalCenter }
              TextField { id: labelField; width: Style.space(120); text: root.shortName; maximumLength: root.maxLabelLength; placeholderText: "MY"; foreground: root.bar.foreground; font.family: root.bar.fontFamily }
              Text { width: Style.space(110); text: "Opposition Name"; textFormat: Text.PlainText; color: root.bar.foreground; font.family: root.bar.fontFamily; font.pixelSize: Style.font.body; anchors.verticalCenter: parent.verticalCenter }
              TextField { id: opponentField; width: Style.space(180); text: root.opponentLabel; maximumLength: root.maxLabelLength; placeholderText: "Auto-detect"; foreground: root.bar.foreground; font.family: root.bar.fontFamily }
            }
            Text { text: "Scoreboard colours"; textFormat: Text.PlainText; color: root.bar.foreground; font.family: root.bar.fontFamily; font.pixelSize: Style.font.body }
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
                  Text { id: modeLabel; anchors.centerIn: parent; text: modelData.label; textFormat: Text.PlainText; color: modelData.id === root.colorMode ? Style.selectedStateColor(root.bar.foreground,Color.accent) : root.bar.foreground; font.family: root.bar.fontFamily; font.pixelSize: Style.font.bodySmall }
                  MouseArea { id: modeArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.setColorMode(modelData.id) }
                }
              }
            }
            Text { text: root.colorMode === "theme" ? "Uses the active Omarchy accent and muted colours." : (root.colorMode === "performance" ? "Adds green for leading and urgent colour for trailing." : "Keeps the scoreboard monochrome."); textFormat: Text.PlainText; color: Qt.darker(root.bar.foreground,1.4); font.family: root.bar.fontFamily; font.pixelSize: Style.font.bodySmall }
            Text { text: "Score detail"; textFormat: Text.PlainText; color: root.bar.foreground; font.family: root.bar.fontFamily; font.pixelSize: Style.font.body }
            Flow {
              width: parent.width; spacing: Style.space(8)
              Repeater {
                model: [{id:"full",label:"Full"},{id:"scores",label:"Scores only"},{id:"progress",label:"Game progress"},{id:"pace",label:"Pace only"}]
                Rectangle {
                  required property var modelData
                  width: detailLabel.implicitWidth + Style.space(24); height: Style.space(32); radius: Style.cornerRadius
                  color: modelData.id === root.playerDisplayMode ? Style.selectedFillFor(root.bar.foreground, Color.accent) : (detailArea.containsMouse ? Style.hoverFillFor(root.bar.foreground, Color.accent) : "transparent")
                  border.width: 1
                  border.color: modelData.id === root.playerDisplayMode ? Color.accent : Qt.rgba(root.bar.foreground.r,root.bar.foreground.g,root.bar.foreground.b,.18)
                  Text { id: detailLabel; anchors.centerIn: parent; text: modelData.label; textFormat: Text.PlainText; color: modelData.id === root.playerDisplayMode ? Style.selectedStateColor(root.bar.foreground,Color.accent) : root.bar.foreground; font.family: root.bar.fontFamily; font.pixelSize: Style.font.bodySmall }
                  MouseArea { id: detailArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.setPlayerDisplayMode(modelData.id) }
                }
              }
            }
            Text {
              width: parent.width; wrapMode: Text.WordWrap; textFormat: Text.PlainText
              text: root.playerDisplayMode === "scores" ? "Plain names and scores, with progress rails, pace colours, and symbols hidden." : (root.playerDisplayMode === "progress" ? "Shows neutral live clocks and game-progress rails without pace styling." : (root.playerDisplayMode === "pace" ? "Shows pace colours and symbols without live clocks or progress rails." : "Shows live game progress and pace indicators together."))
              color: Qt.darker(root.bar.foreground,1.4); font.family: root.bar.fontFamily; font.pixelSize: Style.font.bodySmall
            }
            Text { text: "Fantasy team"; textFormat: Text.PlainText; color: root.bar.foreground; font.family: root.bar.fontFamily; font.pixelSize: Style.font.body }
            Column {
              width: parent.width
              Repeater {
                model: root.data ? root.data.teams : []
                Rectangle {
                  required property var modelData
                  width: parent.width; height: Style.space(34); radius: Style.cornerRadius
                  color: modelData.roster_id === root.selectedRosterId ? Style.hoverFillFor(root.bar.foreground, Color.accent) : (teamArea.containsMouse ? Qt.rgba(1,1,1,.04) : "transparent")
                  Text { anchors.left: parent.left; anchors.leftMargin: Style.space(10); anchors.verticalCenter: parent.verticalCenter; text: (modelData.roster_id === root.selectedRosterId ? "●  " : "○  ") + modelData.name; textFormat: Text.PlainText; color: root.bar.foreground; font.family: root.bar.fontFamily; font.pixelSize: Style.font.body }
                  MouseArea { id: teamArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.persist(modelData.roster_id, labelField.text.trim()) }
                }
              }
            }
            Rectangle {
              width: Style.space(90); height: Style.space(32); radius: Style.cornerRadius; color: saveArea.containsMouse ? Color.accent : Style.hoverFillFor(root.bar.foreground, Color.accent)
              Text { anchors.centerIn: parent; text: "Save"; textFormat: Text.PlainText; color: root.bar.foreground; font.family: root.bar.fontFamily; font.pixelSize: Style.font.body }
              MouseArea { id: saveArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { root.persist(root.selectedRosterId,labelField.text.trim()); root.settingsOpen=false } }
            }
          }

          Text { visible: root.errorText !== ""; text: root.errorText; textFormat: Text.PlainText; color: "#ef5350"; font.family: root.bar.fontFamily; font.pixelSize: Style.font.body }

          Row {
            visible: !root.settingsOpen && root.myGame && root.opponentGame
            width: parent.width; spacing: Style.space(16)
            TeamColumn { width: (parent.width-parent.spacing)/2; teamName: root.teamName(root.myGame ? root.myGame.roster_id : 0); teamScore: root.myGame ? root.myGame.points : 0; projectedScore: root.projectedScore(root.myGame); opponentScore: root.opponentGame ? root.opponentGame.points : 0; game: root.myGame; bar: root.bar; colorMode: root.colorMode; playerDisplayMode: root.playerDisplayMode }
            TeamColumn { width: (parent.width-parent.spacing)/2; teamName: root.teamName(root.opponentGame ? root.opponentGame.roster_id : 0); teamScore: root.opponentGame ? root.opponentGame.points : 0; projectedScore: root.projectedScore(root.opponentGame); opponentScore: root.myGame ? root.myGame.points : 0; game: root.opponentGame; bar: root.bar; colorMode: root.colorMode; playerDisplayMode: root.playerDisplayMode }
          }
        }
      }
    }
  }
}
