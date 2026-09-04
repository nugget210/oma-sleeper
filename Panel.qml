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
  property string pendingFetchLeagueId: ""
  property var scoreSnapshot: ({})
  property bool scoreWatchReady: false
  property double leadMargin: 0
  property bool leadWatchReady: false
  property var selectedPlayer: null
  property string photoPath: ""
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
  readonly property string scoreSound: soundChoice(setting("scoreSound", "ding"))
  readonly property bool leadAlert: setting("leadAlert", true) === true
  readonly property bool notifyAlerts: setting("notifyAlerts", true) === true
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

  onLeagueIdChanged: resetAlertWatch()
  onSelectedRosterIdChanged: resetAlertWatch()

  function score(value) { return Number(value || 0).toFixed(1) }
  function soundChoice(value) {
    var name = String(value || "")
    return name === "off" || name === "ding" || name === "chime" || name === "blip" ? name : "ding"
  }
  function pluginFile(relativePath) {
    return decodeURIComponent(Qt.resolvedUrl(relativePath).toString()).replace("file://", "")
  }
  function starterPoints(game) {
    var snapshot = {}
    if (!game || !Array.isArray(game.starters)) return snapshot
    for (var i = 0; i < game.starters.length; i++) {
      var player = game.starters[i]
      // Key by slot and player so empty slots cannot collide, and a lineup
      // change simply drops the old baseline instead of reading as a score.
      if (player)
        snapshot[String(i) + ":" + String(player.id || player.name || "")] =
          {points:Number(player.points || 0), name:root.boundedLabel(player.name)}
    }
    return snapshot
  }
  // Only the first widget for this module alerts, so a multi-monitor bar raises
  // one alert per event rather than one per screen.
  function isAlertingPanel() {
    if (!root.hostWidget || typeof root.hostWidget.siblingWidgets !== "function") return true
    var widgets = root.hostWidget.siblingWidgets()
    return !widgets || widgets.length === 0 || widgets[0] === root.hostWidget
  }
  function resetAlertWatch() {
    root.scoreSnapshot = ({})
    root.scoreWatchReady = false
    root.leadMargin = 0
    root.leadWatchReady = false
  }
  function gameInResult(result, rosterId) {
    if (!result || !Array.isArray(result.games)) return null
    for (var i = 0; i < result.games.length; i++)
      if (result.games[i] && result.games[i].roster_id === rosterId) return result.games[i]
    return null
  }
  function opponentInResult(result, game) {
    if (!game || !result || !Array.isArray(result.games)) return null
    for (var i = 0; i < result.games.length; i++)
      if (result.games[i] && result.games[i].matchup_id === game.matchup_id
          && result.games[i].roster_id !== game.roster_id) return result.games[i]
    return null
  }
  // Starters whose points rose since the previous refresh. A slot with no prior
  // baseline (first refresh, or a lineup change) is skipped rather than counted.
  function scoringPlays(snapshot) {
    var plays = []
    if (!root.scoreWatchReady) return plays
    for (var key in snapshot) {
      var previous = root.scoreSnapshot[key]
      if (previous === undefined) continue
      var gain = snapshot[key].points - previous.points
      if (gain > 0.01) plays.push({name:snapshot[key].name, gain:gain})
    }
    return plays
  }
  // A lead change is the margin crossing zero. The epsilon keeps floating-point
  // noise from registering, and a tie counts as neutral ground to cross.
  function leadChange(margin) {
    if (!root.leadWatchReady) return ""
    if (root.leadMargin < 0.005 && margin > 0.005) return "gained"
    if (root.leadMargin > -0.005 && margin < -0.005) return "lost"
    return ""
  }
  function playSummary(plays) {
    if (plays.length === 1) return plays[0].name + " +" + root.score(plays[0].gain)
    var total = 0
    for (var i = 0; i < plays.length; i++) total += plays[i].gain
    return plays.length + " scoring plays +" + root.score(total)
  }
  function scoreLine(mine, theirs) {
    return (root.shortName || "MY") + " " + root.score(mine) + " – " + root.score(theirs) + " " + root.opponentShort
  }
  // Compare this refresh against the previous one and alert on scoring plays and
  // lead changes. The first refresh only seeds the baseline, so opening the panel
  // never alerts for points already on the board.
  function reviewScoring(result) {
    var game = root.gameInResult(result, root.selectedRosterId)
    var opponent = root.opponentInResult(result, game)
    var snapshot = root.starterPoints(game)
    var plays = root.scoringPlays(snapshot)
    var mine = game ? Number(game.points || 0) : 0
    var theirs = opponent ? Number(opponent.points || 0) : 0
    var margin = mine - theirs
    var flip = game && opponent ? root.leadChange(margin) : ""

    root.scoreSnapshot = snapshot
    root.scoreWatchReady = true
    if (game && opponent) {
      root.leadMargin = margin
      root.leadWatchReady = true
    }
    if (!root.isAlertingPanel()) return

    // A lead change is the more significant event, so it takes the tone when
    // both happen on the same refresh; the notifications still report both.
    if (flip !== "" && root.leadAlert) root.playSound(flip === "gained" ? "lead-up" : "lead-down")
    else if (plays.length > 0) root.playAlert(root.scoreSound)

    if (!root.notifyAlerts) return
    // One notification per refresh, so a scoring play that also flips the lead
    // reads as a single event rather than two stacked popups.
    var line = root.scoreLine(mine, theirs)
    var scored = plays.length > 0 ? root.playSummary(plays) : ""
    if (flip !== "" && root.leadAlert)
      root.notify(flip === "gained" ? "Took the lead" : "Lost the lead",
                  scored === "" ? line : scored + " · " + line)
    else if (scored !== "") root.notify(scored, line)
  }
  function showPlayer(player) {
    if (!player) return
    root.selectedPlayer = player
    root.photoPath = ""
    root.loadPhoto(player)
  }
  function closePlayer() {
    root.selectedPlayer = null
    root.photoPath = ""
  }
  // Sleeper's CDN keys headshots by numeric player id, and team defences by the
  // team abbreviation that stands in for their id.
  function photoSubject(player) {
    var subject = String(player && player.id !== undefined ? player.id : "")
    return /^[0-9]{1,10}$/.test(subject) || /^[A-Z]{2,4}$/.test(subject) ? subject : ""
  }
  function loadPhoto(player) {
    var subject = root.photoSubject(player)
    if (subject === "" || photoProc.running) return
    photoProc.subject = subject
    photoProc.running = true
  }
  function statNumber(value) {
    var number = Number(value || 0)
    return number === Math.floor(number) ? String(number) : number.toFixed(1)
  }
  // Emits only the box-score entries this player actually has, so one ordered
  // table covers every position without per-position layouts.
  function statRows(player) {
    var stats = player && player.stats ? player.stats : {}
    var definitions = [
      ["Completions", "pass_cmp"], ["Attempts", "pass_att"], ["Passing yards", "pass_yd"],
      ["Passing TD", "pass_td"], ["Interceptions thrown", "pass_int"],
      ["Carries", "rush_att"], ["Rushing yards", "rush_yd"], ["Rushing TD", "rush_td"],
      ["Longest run", "rush_lng"],
      ["Targets", "rec_tgt"], ["Receptions", "rec"], ["Receiving yards", "rec_yd"],
      ["Receiving TD", "rec_td"], ["Longest catch", "rec_lng"],
      ["Field goals", "fgm"], ["FG attempts", "fga"], ["Extra points", "xpm"], ["XP attempts", "xpa"],
      ["Sacks", "def_sack"], ["Interceptions", "def_int"], ["Defensive TD", "def_td"],
      ["Fumbles recovered", "fum_rec"], ["Fumbles lost", "fum_lost"], ["Points allowed", "pts_allow"],
      ["Snaps", "off_snp"]
    ]
    var rows = []
    for (var i = 0; i < definitions.length; i++) {
      var value = stats[definitions[i][1]]
      if (value === undefined || value === null) continue
      rows.push({label: definitions[i][0], value: root.statNumber(value)})
    }
    return rows
  }
  function heightText(value) {
    var inches = parseInt(value, 10)
    if (!isFinite(inches) || inches <= 0) return String(value || "")
    return Math.floor(inches / 12) + "'" + (inches % 12) + "\""
  }
  function bioRows(player) {
    var bio = player && player.bio ? player.bio : {}
    var rows = []
    if (bio.age) rows.push({label: "Age", value: String(bio.age)})
    if (bio.height && bio.weight)
      rows.push({label: "Size", value: root.heightText(bio.height) + ", " + bio.weight + " lb"})
    if (bio.college) rows.push({label: "College", value: root.boundedText(bio.college, 48)})
    if (bio.years_exp !== undefined && bio.years_exp !== null)
      rows.push({label: "Experience", value: Number(bio.years_exp) === 0 ? "Rookie" : bio.years_exp + " seasons"})
    if (bio.depth_chart_position)
      rows.push({label: "Depth chart", value: root.boundedText(bio.depth_chart_position, 16)
        + (bio.depth_chart_order ? " · #" + bio.depth_chart_order : "")})
    return rows
  }
  function boundedText(value, limit) {
    return String(value || "").replace(/[\u0000-\u001f\u007f]/g, " ").trim().slice(0, limit)
  }
  function injuryText(player) {
    var bio = player && player.bio ? player.bio : {}
    var status = root.boundedText(bio.injury_status, 24)
    if (status === "") return ""
    var part = root.boundedText(bio.injury_body_part, 24)
    return part === "" ? status : status + " · " + part
  }
  function seasonAverage(player) {
    var season = player && player.season ? player.season : null
    return season && season.average !== null && season.average !== undefined && Number(season.gp) > 0
      ? Number(season.average).toFixed(1) : "—"
  }
  function seasonGames(player) {
    var season = player && player.season ? player.season : null
    return season && Number(season.gp) > 0 ? Number(season.gp) + " games" : "No games played"
  }
  function notify(summary, body) {
    if (notifyProc.running) return
    notifyProc.summary = String(summary || "")
    notifyProc.body = String(body || "")
    notifyProc.running = true
  }
  function soundFile(name) {
    var known = ["ding", "chime", "blip", "lead-up", "lead-down"]
    return known.indexOf(String(name || "")) < 0 ? "" : root.pluginFile("assets/sounds/" + name + ".wav")
  }
  function playSound(name) {
    var file = root.soundFile(name)
    if (file === "" || alertProc.running) return
    alertProc.soundPath = file
    alertProc.running = true
  }
  function playAlert(name) {
    var sound = root.soundChoice(name)
    if (sound !== "off") root.playSound(sound)
  }
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
    pendingFetchLeagueId = leagueId
    loading = true; errorText = ""
    fetchProc.running = true
  }
  function open() { if (leagueId === "") settingsOpen = true; controller.show(); refresh(false) }
  function close() { settingsOpen = false; controller.hide() }
  // Persist the settings entry. Every value is read from live panel state, and
  // `changes` overrides only the keys a caller is actually changing, so adding a
  // setting never means threading another argument through every call site.
  // Validation is applied after the merge, so an override cannot bypass it.
  function saveEntry(changes) {
    var entry = {id:root.moduleName,
                 leagueId:root.leagueId,
                 rosterId:root.selectedRosterId,
                 shortName:labelField.text,
                 refreshMinutes:root.refreshMinutes,
                 colorMode:root.colorMode,
                 playerDisplayMode:root.playerDisplayMode,
                 opponentName:opponentField.text,
                 scoreSound:root.scoreSound,
                 leadAlert:root.leadAlert,
                 notifyAlerts:root.notifyAlerts}
    var overrides = changes || {}
    for (var key in overrides)
      if (entry.hasOwnProperty(key)) entry[key] = overrides[key]
    entry.shortName = root.boundedLabel(entry.shortName)
    entry.opponentName = root.boundedLabel(entry.opponentName)
    entry.scoreSound = root.soundChoice(entry.scoreSound)
    entry.leadAlert = entry.leadAlert === true
    entry.notifyAlerts = entry.notifyAlerts === true
    if (root.hostWidget && typeof root.hostWidget.publishSettings === "function")
      root.hostWidget.publishSettings(entry)
    else root.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }
  function persist(rosterId) { saveEntry({rosterId:rosterId}) }
  function setColorMode(mode) { saveEntry({colorMode:mode}) }
  function setPlayerDisplayMode(mode) { saveEntry({playerDisplayMode:mode}) }
  function setLeadAlert(enabled) {
    saveEntry({leadAlert:enabled === true})
    if (enabled === true) root.playSound("lead-up")
  }
  function setNotifyAlerts(enabled) { saveEntry({notifyAlerts:enabled === true}) }
  // Preview the choice as it is made, so the sounds can be compared by ear.
  function setScoreSound(sound) {
    saveEntry({scoreSound:sound})
    root.playAlert(sound)
  }
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
    saveEntry({leagueId:id, rosterId:0})
    Qt.callLater(function() { refresh(true) })
  }
  function openSleeper() {
    if (root.bar && /^\d{10,24}$/.test(root.leagueId))
      root.bar.run("xdg-open 'https://sleeper.com/leagues/" + root.leagueId + "/matchup'")
  }

  Process {
    id: fetchProc
    command: [root.pluginFile("bin/sleeper-matchup"), root.leagueId, "auto", root.forceMetadataRefresh ? "force" : "normal"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var payload = String(text)
          if (payload.length > root.maxPayloadCharacters) throw new Error("Matchup response is too large")
          var result = root.boundedResult(JSON.parse(payload))
          if (root.hostWidget && typeof root.hostWidget.publishData === "function") root.hostWidget.publishData(result)
          else root.data = result
          root.reviewScoring(result)
          root.errorText = ""
          if (root.settingsOpen) root.settingsMessage = "League synced — choose your fantasy team"
        }
        catch(e) {
          console.warn("Sleeper matchup: discarding fetch result -", e.message)
          if (e.message !== "Mismatched league ID") root.errorText = "Could not read matchup data"
        }
      }
    }
    onExited: function(code) {
      root.loading = false
      root.forceMetadataRefresh = false
      // A response for a league we've since navigated away from is stale either way
      // (success or failure) — drop it and refetch for whichever league is current now.
      if (root.leagueId === "" || root.leagueId !== root.pendingFetchLeagueId) {
        if (root.leagueId !== "") root.refresh(true)
        return
      }
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
  Process {
    id: alertProc
    property string soundPath: ""
    command: [root.pluginFile("bin/play-alert"), soundPath]
  }
  Process {
    id: notifyProc
    property string summary: ""
    property string body: ""
    command: [root.pluginFile("bin/notify-alert"), summary, body]
  }
  Process {
    id: photoProc
    property string subject: ""
    command: [root.pluginFile("bin/sleeper-matchup"), "--photo", subject]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        // The helper prints one cache path. Anything else leaves the card on
        // its position-badge placeholder rather than loading an unknown file.
        var path = String(text).trim()
        if (/^\/[^\n]{1,4096}\.(jpg|png)$/.test(path)) root.photoPath = path
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
      onCloseRequested: { if (root.selectedPlayer !== null) root.closePlayer(); else root.close() }
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
            Text { text: "Score alert"; textFormat: Text.PlainText; color: root.bar.foreground; font.family: root.bar.fontFamily; font.pixelSize: Style.font.body }
            Row {
              spacing: Style.space(8)
              Repeater {
                model: [{id:"off",label:"Off"},{id:"ding",label:"Ding"},{id:"chime",label:"Chime"},{id:"blip",label:"Blip"}]
                Rectangle {
                  required property var modelData
                  width: soundLabel.implicitWidth + Style.space(24); height: Style.space(32); radius: Style.cornerRadius
                  color: modelData.id === root.scoreSound ? Style.selectedFillFor(root.bar.foreground, Color.accent) : (soundArea.containsMouse ? Style.hoverFillFor(root.bar.foreground, Color.accent) : "transparent")
                  border.width: 1
                  border.color: modelData.id === root.scoreSound ? Color.accent : Qt.rgba(root.bar.foreground.r,root.bar.foreground.g,root.bar.foreground.b,.18)
                  Text { id: soundLabel; anchors.centerIn: parent; text: modelData.label; textFormat: Text.PlainText; color: modelData.id === root.scoreSound ? Style.selectedStateColor(root.bar.foreground,Color.accent) : root.bar.foreground; font.family: root.bar.fontFamily; font.pixelSize: Style.font.bodySmall }
                  MouseArea { id: soundArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.setScoreSound(modelData.id) }
                }
              }
            }
            Text {
              width: parent.width; wrapMode: Text.WordWrap; textFormat: Text.PlainText
              text: root.scoreSound === "off" ? "Scoring plays are silent." : "Plays a short tone when one of your starters gains points."
              color: Qt.darker(root.bar.foreground,1.4); font.family: root.bar.fontFamily; font.pixelSize: Style.font.bodySmall
            }
            Text { text: "Lead change alert"; textFormat: Text.PlainText; color: root.bar.foreground; font.family: root.bar.fontFamily; font.pixelSize: Style.font.body }
            Row {
              spacing: Style.space(8)
              Repeater {
                model: [{on:false,label:"Off"},{on:true,label:"On"}]
                Rectangle {
                  required property var modelData
                  width: leadLabel.implicitWidth + Style.space(24); height: Style.space(32); radius: Style.cornerRadius
                  color: modelData.on === root.leadAlert ? Style.selectedFillFor(root.bar.foreground, Color.accent) : (leadArea.containsMouse ? Style.hoverFillFor(root.bar.foreground, Color.accent) : "transparent")
                  border.width: 1
                  border.color: modelData.on === root.leadAlert ? Color.accent : Qt.rgba(root.bar.foreground.r,root.bar.foreground.g,root.bar.foreground.b,.18)
                  Text { id: leadLabel; anchors.centerIn: parent; text: modelData.label; textFormat: Text.PlainText; color: modelData.on === root.leadAlert ? Style.selectedStateColor(root.bar.foreground,Color.accent) : root.bar.foreground; font.family: root.bar.fontFamily; font.pixelSize: Style.font.bodySmall }
                  MouseArea { id: leadArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.setLeadAlert(modelData.on) }
                }
              }
            }
            Text {
              width: parent.width; wrapMode: Text.WordWrap; textFormat: Text.PlainText
              text: "A rising three-note tone when you take the lead, falling when you lose it. Distinct from the scoring tone."
              color: Qt.darker(root.bar.foreground,1.4); font.family: root.bar.fontFamily; font.pixelSize: Style.font.bodySmall
            }
            Text { text: "Desktop notifications"; textFormat: Text.PlainText; color: root.bar.foreground; font.family: root.bar.fontFamily; font.pixelSize: Style.font.body }
            Row {
              spacing: Style.space(8)
              Repeater {
                model: [{on:false,label:"Off"},{on:true,label:"On"}]
                Rectangle {
                  required property var modelData
                  width: notifyLabel.implicitWidth + Style.space(24); height: Style.space(32); radius: Style.cornerRadius
                  color: modelData.on === root.notifyAlerts ? Style.selectedFillFor(root.bar.foreground, Color.accent) : (notifyArea.containsMouse ? Style.hoverFillFor(root.bar.foreground, Color.accent) : "transparent")
                  border.width: 1
                  border.color: modelData.on === root.notifyAlerts ? Color.accent : Qt.rgba(root.bar.foreground.r,root.bar.foreground.g,root.bar.foreground.b,.18)
                  Text { id: notifyLabel; anchors.centerIn: parent; text: modelData.label; textFormat: Text.PlainText; color: modelData.on === root.notifyAlerts ? Style.selectedStateColor(root.bar.foreground,Color.accent) : root.bar.foreground; font.family: root.bar.fontFamily; font.pixelSize: Style.font.bodySmall }
                  MouseArea { id: notifyArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.setNotifyAlerts(modelData.on) }
                }
              }
            }
            Text {
              width: parent.width; wrapMode: Text.WordWrap; textFormat: Text.PlainText
              text: "Names the scorer and the points gained, so you can read the play without opening the panel."
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
                  MouseArea { id: teamArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.persist(modelData.roster_id) }
                }
              }
            }
            Rectangle {
              width: Style.space(90); height: Style.space(32); radius: Style.cornerRadius; color: saveArea.containsMouse ? Color.accent : Style.hoverFillFor(root.bar.foreground, Color.accent)
              Text { anchors.centerIn: parent; text: "Save"; textFormat: Text.PlainText; color: root.bar.foreground; font.family: root.bar.fontFamily; font.pixelSize: Style.font.body }
              MouseArea { id: saveArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { root.persist(root.selectedRosterId); root.settingsOpen=false } }
            }
          }

          Text { visible: root.errorText !== ""; text: root.errorText; textFormat: Text.PlainText; color: "#ef5350"; font.family: root.bar.fontFamily; font.pixelSize: Style.font.body }

          Row {
            visible: !root.settingsOpen && root.myGame && root.opponentGame
            width: parent.width; spacing: Style.space(16)
            TeamColumn { width: (parent.width-parent.spacing)/2; teamName: root.teamName(root.myGame ? root.myGame.roster_id : 0); teamScore: root.myGame ? root.myGame.points : 0; projectedScore: root.projectedScore(root.myGame); opponentScore: root.opponentGame ? root.opponentGame.points : 0; game: root.myGame; bar: root.bar; colorMode: root.colorMode; playerDisplayMode: root.playerDisplayMode; onPlayerActivated: function(player) { root.showPlayer(player) } }
            TeamColumn { width: (parent.width-parent.spacing)/2; teamName: root.teamName(root.opponentGame ? root.opponentGame.roster_id : 0); teamScore: root.opponentGame ? root.opponentGame.points : 0; projectedScore: root.projectedScore(root.opponentGame); opponentScore: root.myGame ? root.myGame.points : 0; game: root.opponentGame; bar: root.bar; colorMode: root.colorMode; playerDisplayMode: root.playerDisplayMode; onPlayerActivated: function(player) { root.showPlayer(player) } }
          }
        }
      }

      // Player detail, drawn over the panel content rather than in a window of
      // its own so it needs no surface, focus handling, or positioning logic.
      Item {
        id: playerCard
        anchors.fill: parent
        visible: root.selectedPlayer !== null
        readonly property var player: root.selectedPlayer || ({})
        readonly property string injury: root.injuryText(root.selectedPlayer)

        Rectangle {
          anchors.fill: parent
          color: Color.menu.scrim
          MouseArea { anchors.fill: parent; onClicked: root.closePlayer() }
        }

        Rectangle {
          anchors.centerIn: parent
          width: Math.min(parent.width - Style.space(48), Style.space(400))
          height: Math.min(parent.height - Style.space(32), cardBody.implicitHeight + Style.space(32))
          radius: Style.cornerRadius * 2
          color: Color.popups.background
          border.width: 1
          border.color: Color.popups.border
          // Clicks on the card must not reach the dismissing scrim beneath it.
          MouseArea { anchors.fill: parent }

          Flickable {
            anchors.fill: parent; anchors.margins: Style.space(16)
            contentWidth: width; contentHeight: cardBody.implicitHeight
            clip: true; boundsBehavior: Flickable.StopAtBounds

            Column {
              id: cardBody
              width: parent.width
              spacing: Style.space(12)

              Item {
                width: parent.width; height: Style.space(72)
                Rectangle {
                  id: photoFrame
                  width: Style.space(72); height: width; radius: Style.cornerRadius
                  anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                  color: Qt.rgba(root.bar.foreground.r,root.bar.foreground.g,root.bar.foreground.b,.08)
                  clip: true
                  Image {
                    id: photoImage
                    anchors.fill: parent
                    source: root.photoPath === "" ? "" : "file://" + root.photoPath
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    visible: status === Image.Ready
                  }
                  Text {
                    anchors.centerIn: parent
                    visible: photoImage.status !== Image.Ready
                    text: String(playerCard.player.position || "—")
                    textFormat: Text.PlainText
                    color: Qt.darker(root.bar.foreground,1.4)
                    font.family: root.bar.fontFamily; font.pixelSize: Style.font.title; font.bold: true
                  }
                }
                Column {
                  anchors.left: photoFrame.right; anchors.leftMargin: Style.space(12)
                  anchors.right: closeCard.left; anchors.rightMargin: Style.space(8)
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(4)
                  Text {
                    width: parent.width; elide: Text.ElideRight
                    text: String(playerCard.player.name || "")
                    textFormat: Text.PlainText; color: root.bar.foreground
                    font.family: root.bar.fontFamily; font.pixelSize: Style.font.title; font.bold: true
                  }
                  Text {
                    width: parent.width; elide: Text.ElideRight
                    text: [String(playerCard.player.position || ""), String(playerCard.player.nfl_team || ""),
                           playerCard.player.bio && playerCard.player.bio.number ? "#" + playerCard.player.bio.number : ""]
                          .filter(function(part) { return part !== "" }).join(" · ")
                    textFormat: Text.PlainText; color: Qt.darker(root.bar.foreground,1.4)
                    font.family: root.bar.fontFamily; font.pixelSize: Style.font.bodySmall
                  }
                  Text {
                    width: parent.width; elide: Text.ElideRight
                    visible: playerCard.injury !== ""
                    text: playerCard.injury
                    textFormat: Text.PlainText; color: Color.urgent
                    font.family: root.bar.fontFamily; font.pixelSize: Style.font.bodySmall
                  }
                }
                Rectangle {
                  id: closeCard
                  width: Style.space(26); height: width; radius: Style.cornerRadius
                  anchors.right: parent.right; anchors.top: parent.top
                  color: closeArea.containsMouse ? Style.hoverFillFor(root.bar.foreground, Color.accent) : "transparent"
                  Text { anchors.centerIn: parent; text: "✕"; textFormat: Text.PlainText; color: root.bar.foreground; font.family: root.bar.fontFamily; font.pixelSize: Style.font.bodySmall }
                  MouseArea { id: closeArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.closePlayer() }
                }
              }

              Rectangle { width: parent.width; height: 1; color: root.bar.foreground; opacity: .12 }

              Row {
                width: parent.width; spacing: Style.space(8)
                Repeater {
                  model: [
                    {label: "POINTS", value: root.score(playerCard.player.points)},
                    {label: "PROJECTED", value: playerCard.player.projected === null || playerCard.player.projected === undefined
                                                ? "—" : root.score(playerCard.player.projected)},
                    {label: "SEASON AVG", value: root.seasonAverage(root.selectedPlayer)}
                  ]
                  Rectangle {
                    required property var modelData
                    width: (cardBody.width - Style.space(16)) / 3; height: Style.space(52); radius: Style.cornerRadius
                    color: Qt.rgba(root.bar.foreground.r,root.bar.foreground.g,root.bar.foreground.b,.06)
                    Column {
                      anchors.centerIn: parent; spacing: Style.space(2)
                      Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.value; textFormat: Text.PlainText; color: root.bar.foreground; font.family: root.bar.fontFamily; font.pixelSize: Style.font.title; font.bold: true }
                      Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.label; textFormat: Text.PlainText; color: Qt.darker(root.bar.foreground,1.5); font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; font.letterSpacing: 1 }
                    }
                  }
                }
              }

              Text {
                text: "THIS WEEK"; textFormat: Text.PlainText
                color: Qt.darker(root.bar.foreground,1.5)
                font.family: root.bar.fontFamily; font.pixelSize: Style.font.bodySmall; font.letterSpacing: 1
              }
              Text {
                width: parent.width; wrapMode: Text.WordWrap; textFormat: Text.PlainText
                visible: root.statRows(root.selectedPlayer).length === 0
                text: "No box score recorded yet."
                color: Qt.darker(root.bar.foreground,1.4)
                font.family: root.bar.fontFamily; font.pixelSize: Style.font.bodySmall
              }
              Column {
                width: parent.width
                Repeater {
                  model: root.statRows(root.selectedPlayer)
                  Item {
                    required property var modelData
                    width: cardBody.width; height: Style.space(22)
                    Text { anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; text: modelData.label; textFormat: Text.PlainText; color: Qt.darker(root.bar.foreground,1.3); font.family: root.bar.fontFamily; font.pixelSize: Style.font.body }
                    Text { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; text: modelData.value; textFormat: Text.PlainText; color: root.bar.foreground; font.family: root.bar.fontFamily; font.pixelSize: Style.font.body }
                  }
                }
              }

              Text {
                text: "SEASON"; textFormat: Text.PlainText
                color: Qt.darker(root.bar.foreground,1.5)
                font.family: root.bar.fontFamily; font.pixelSize: Style.font.bodySmall; font.letterSpacing: 1
              }
              Item {
                width: parent.width; height: Style.space(22)
                Text { anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; text: root.seasonGames(root.selectedPlayer); textFormat: Text.PlainText; color: Qt.darker(root.bar.foreground,1.3); font.family: root.bar.fontFamily; font.pixelSize: Style.font.body }
                Text {
                  anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                  text: root.selectedPlayer && root.selectedPlayer.season && root.selectedPlayer.season.points !== null
                        && Number(root.selectedPlayer.season.gp) > 0
                        ? root.score(root.selectedPlayer.season.points) + " pts" : "—"
                  textFormat: Text.PlainText; color: root.bar.foreground
                  font.family: root.bar.fontFamily; font.pixelSize: Style.font.body
                }
              }

              Text {
                visible: root.bioRows(root.selectedPlayer).length > 0
                text: "PLAYER"; textFormat: Text.PlainText
                color: Qt.darker(root.bar.foreground,1.5)
                font.family: root.bar.fontFamily; font.pixelSize: Style.font.bodySmall; font.letterSpacing: 1
              }
              Column {
                width: parent.width
                Repeater {
                  model: root.bioRows(root.selectedPlayer)
                  Item {
                    required property var modelData
                    width: cardBody.width; height: Style.space(22)
                    Text { anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; text: modelData.label; textFormat: Text.PlainText; color: Qt.darker(root.bar.foreground,1.3); font.family: root.bar.fontFamily; font.pixelSize: Style.font.body }
                    Text { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; text: modelData.value; textFormat: Text.PlainText; color: root.bar.foreground; font.family: root.bar.fontFamily; font.pixelSize: Style.font.body }
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
