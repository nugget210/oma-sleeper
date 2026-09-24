// Behavioural tests for the alert logic in Panel.qml.
//
// The functions under test are extracted from Panel.qml itself rather than
// reimplemented here, so these tests exercise the shipped source and keep
// working across refactors that leave the behaviour intact.
//
// QML_SOURCE is prepended by tests/test-alert-logic.sh.

function extractFunctionFrom(source, label, name) {
  const marker = "\n  function " + name + "(";
  const start = source.indexOf(marker);
  if (start < 0) throw new Error("function not found in " + label + ": " + name);
  let depth = 0;
  for (let i = source.indexOf("{", start); i < source.length; i++) {
    if (source[i] === "{") depth++;
    else if (source[i] === "}") {
      depth--;
      if (depth === 0) return source.slice(start + "\n  function ".length, i + 1);
    }
  }
  throw new Error("unbalanced braces reading: " + name);
}
function extractFunction(name) { return extractFunctionFrom(QML_SOURCE, "Panel.qml", name); }

// Object-literal properties are read the same way as the functions above, by
// balancing braces from the declaration, so the tests exercise the shipped
// table rather than a copy that can drift from it.
function extractObject(name) {
  const marker = "\n  readonly property var " + name + ": (";
  const start = QML_SOURCE.indexOf(marker);
  if (start < 0) throw new Error("property not found in Panel.qml: " + name);
  let depth = 0;
  for (let i = QML_SOURCE.indexOf("{", start); i < QML_SOURCE.length; i++) {
    if (QML_SOURCE[i] === "{") depth++;
    else if (QML_SOURCE[i] === "}") {
      depth--;
      if (depth === 0) return eval("(" + QML_SOURCE.slice(QML_SOURCE.indexOf("{", start), i + 1) + ")");
    }
  }
  throw new Error("unbalanced braces reading: " + name);
}

const FUNCTIONS = [
  "score", "boundedLabel", "boundedText", "soundChoice", "soundFile", "playSound",
  "playAlert", "starterPoints", "isAlertingPanel", "resetAlertWatch", "gameInResult",
  "opponentInResult", "scoringPlays", "leadChange", "playSummary", "scoreLine",
  "notify", "reviewScoring",
  "photoSubject", "statNumber", "statRows", "heightText", "bioRows", "injuryText",
  "seasonAverage", "seasonGames",
  "gameStatusText", "playerById",
  "projectedScore",
  "scoringLabel", "scoringRate", "scoringRows",
  "opponentFor", "calculateMatchupState",
  "isPrimaryPanel", "refreshIfDue", "refreshIfAbandoned",
  "buildLeagueMatchups", "buildLeagueStandings", "recordText", "viewMatchup",
  "showView", "gameFor",
];

const ROW_FUNCTIONS = ["paceAgainst"];

// Stand-ins for the QML objects the functions touch.
const alertProc = { running: false, soundPath: "" };
// Stand-ins for the scheduled-refresh machinery.
const standbyTimer = { running: false, restarted: 0, restart() { this.running = true; this.restarted++ } };
const notifyProc = { running: false, summary: "", body: "" };
const root = {
  maxLabelLength: 24,
  selectedRosterId: 7,
  shortName: "MY",
  opponentShort: "OPP",
  scoreSound: "ding",
  leadAlert: true,
  notifyAlerts: true,
  hostWidget: null,
  scoreSnapshot: {},
  scoreWatchReady: false,
  leadMargin: 0,
  leadWatchReady: false,
  pluginFile: (relative) => "/plugin/" + relative,
  maxPlayersPerSection: 32,
  scoringLabels: extractObject("scoringLabels"),
};
for (const name of FUNCTIONS) eval("root." + name + " = function " + extractFunction(name));
// The scoreboard row carries its own pace maths, so it is extracted the same way.
const row = {};
for (const name of ROW_FUNCTIONS)
  eval("row." + name + " = function " + extractFunctionFrom(PLAYER_ROW_SOURCE, "PlayerRow.qml", name));

let failures = 0;
function assert(label, condition, detail) {
  if (!condition) {
    failures++;
    console.log("FAIL  " + label + (detail ? "  [" + detail + "]" : ""));
  } else {
    console.log("PASS  " + label);
  }
}

// Runs one refresh and reports what the panel did, with the process stubs reset
// so each event is observed independently.
function refresh(games) {
  alertProc.running = false;
  alertProc.soundPath = "";
  notifyProc.running = false;
  notifyProc.summary = "";
  notifyProc.body = "";
  root.reviewScoring({ games: games });
  return {
    sound: alertProc.soundPath.replace("/plugin/assets/sounds/", "").replace(".wav", ""),
    summary: notifyProc.summary,
    body: notifyProc.body,
  };
}

// roster 7 is ours, roster 8 the opponent; both share matchup 1.
function board(mine, theirs, starters) {
  return [
    { roster_id: 7, matchup_id: 1, points: mine, starters: starters || [] },
    { roster_id: 8, matchup_id: 1, points: theirs, starters: [] },
  ];
}
function lineup(points, names) {
  return points.map((p, i) => ({ id: "p" + i, name: (names && names[i]) || "Player " + i, points: p }));
}

// --- scoring detection ------------------------------------------------------
// These keep the opponent far ahead so a scoring play never also flips the
// lead, leaving the two kinds of event independently observable.
function behind(mine, starters) { return board(mine, 500, starters); }

root.resetAlertWatch();
let out = refresh(behind(10, lineup([5, 5])));
assert("first refresh only seeds the baseline", out.sound === "" && out.summary === "");

out = refresh(behind(10, lineup([5, 5])));
assert("unchanged points stay silent", out.sound === "" && out.summary === "");

out = refresh(behind(16.4, lineup([11.4, 5], ["Ja'Marr Chase", "Bijan Robinson"])));
assert("a scoring play plays the chosen tone", out.sound === "ding", out.sound);
assert("the notification names the scorer and gain", out.summary === "Ja'Marr Chase +6.4", out.summary);
assert("the notification body carries the score line", out.body === "MY 16.4 – 500.0 OPP", out.body);

out = refresh(behind(16.405, lineup([11.405, 5])));
assert("floating-point noise stays silent", out.sound === "" && out.summary === "");

out = refresh(behind(14, lineup([9, 5])));
assert("a downward stat correction stays silent", out.sound === "" && out.summary === "");

out = refresh(behind(24, lineup([12, 12])));
assert("two scorers report as a combined summary", out.summary === "2 scoring plays +10.0", out.summary);

root.resetAlertWatch();
refresh(behind(10, lineup([5, 5])));
out = refresh(behind(99, [{ id: "pNEW", name: "Sub", points: 94 }, { id: "p1", name: "Player 1", points: 5 }]));
assert("a lineup change is not read as a score", out.sound === "" && out.summary === "");

// --- lead changes -----------------------------------------------------------
root.resetAlertWatch();
refresh(board(50, 60, lineup([10])));
out = refresh(board(50, 60, lineup([10])));
assert("trailing without change stays silent", out.sound === "" && out.summary === "");

out = refresh(board(70, 60, lineup([10])));
assert("taking the lead plays the rising tone", out.sound === "lead-up", out.sound);
assert("taking the lead notifies", out.summary === "Took the lead", out.summary);

out = refresh(board(75, 60, lineup([10])));
assert("extending a lead does not re-alert", out.sound === "" && out.summary === "");

out = refresh(board(75, 90, lineup([10])));
assert("losing the lead plays the falling tone", out.sound === "lead-down", out.sound);
assert("losing the lead notifies", out.summary === "Lost the lead", out.summary);

// A tie is neutral ground: crossing it is one lead change, not two.
root.resetAlertWatch();
refresh(board(50, 60, lineup([10])));
out = refresh(board(60, 60, lineup([10])));
assert("drawing level is not a lead change", out.sound === "" && out.summary === "");
out = refresh(board(61, 60, lineup([10])));
assert("moving ahead from a tie is a lead change", out.sound === "lead-up", out.sound);

// --- both events on one refresh --------------------------------------------
root.resetAlertWatch();
refresh(board(50, 60, lineup([10], ["Puka Nacua"])));
out = refresh(board(70, 60, lineup([30], ["Puka Nacua"])));
assert("lead change takes tone priority over scoring", out.sound === "lead-up", out.sound);
assert("one notification reports both events", out.summary === "Took the lead", out.summary);
assert("the body includes the scoring play", out.body === "Puka Nacua +20.0 · MY 70.0 – 60.0 OPP", out.body);

// --- settings gating --------------------------------------------------------
root.scoreSound = "off";
root.resetAlertWatch();
refresh(board(50, 60, lineup([10])));
out = refresh(board(55, 60, lineup([15])));
assert("scoreSound=off silences scoring tones", out.sound === "", out.sound);
assert("scoreSound=off still notifies", out.summary !== "", out.summary);
out = refresh(board(70, 60, lineup([15])));
assert("scoreSound=off leaves lead tones audible", out.sound === "lead-up", out.sound);
root.scoreSound = "chime";
root.resetAlertWatch();
refresh(board(50, 60, lineup([10])));
out = refresh(board(55, 60, lineup([15])));
assert("the selected scoring tone is used", out.sound === "chime", out.sound);

root.leadAlert = false;
out = refresh(board(70, 60, lineup([15])));
assert("leadAlert=off silences lead tones", out.sound !== "lead-up", out.sound);
assert("leadAlert=off suppresses the lead notification", out.summary !== "Took the lead", out.summary);
root.leadAlert = true;

root.notifyAlerts = false;
root.resetAlertWatch();
refresh(board(50, 60, lineup([10])));
out = refresh(board(55, 60, lineup([15])));
assert("notifyAlerts=off suppresses notifications", out.summary === "");
assert("notifyAlerts=off leaves sound working", out.sound === "chime", out.sound);
root.notifyAlerts = true;

// --- multi-monitor ----------------------------------------------------------
const otherWidget = {};
root.hostWidget = { siblingWidgets: () => [otherWidget, root.hostWidget] };
root.resetAlertWatch();
refresh(board(50, 60, lineup([10])));
out = refresh(board(55, 60, lineup([15])));
assert("a non-primary panel raises no alert", out.sound === "" && out.summary === "");
root.hostWidget = null;

// --- malformed payloads must not throw --------------------------------------
root.resetAlertWatch();
let threw = "";
try {
  root.reviewScoring(null);
  root.reviewScoring({});
  root.reviewScoring({ games: [{ roster_id: 7, starters: null }] });
  root.reviewScoring({ games: [{ roster_id: 99, starters: [{ id: "x", points: 9 }] }] });
  root.reviewScoring({ games: [null, undefined] });
} catch (e) {
  threw = String(e);
}
assert("malformed payloads are handled without throwing", threw === "", threw);

// --- input validation -------------------------------------------------------
assert("soundChoice keeps valid names",
  ["off", "ding", "chime", "blip"].every((v) => root.soundChoice(v) === v));
assert("soundChoice rejects unknown names",
  ["", null, undefined, "evil", "../../etc/passwd"].every((v) => root.soundChoice(v) === "ding"));
assert("soundFile rejects unknown names",
  ["", "nope", "../../../etc/passwd", "ding.wav"].every((v) => root.soundFile(v) === ""));
assert("soundFile resolves every bundled tone",
  ["ding", "chime", "blip", "lead-up", "lead-down"]
    .every((v) => root.soundFile(v) === "/plugin/assets/sounds/" + v + ".wav"));
assert("boundedLabel strips control characters",
  root.boundedLabel("a\u0001b\u0002c\u007fd") === "a b c d",
  root.boundedLabel("a\u0001b\u0002c\u007fd"));
assert("boundedLabel bounds the length",
  root.boundedLabel("x".repeat(200)).length === 24);

// --- player detail card -----------------------------------------------------
// Only Sleeper's own id shapes may reach the photo helper: a numeric player id,
// or the team abbreviation that stands in as a team defence's id.
assert("photoSubject accepts a numeric player id", root.photoSubject({ id: "7564" }) === "7564");
assert("photoSubject accepts a team defence", root.photoSubject({ id: "MIN" }) === "MIN");
assert("photoSubject rejects anything else",
  [{ id: "" }, { id: "0/../etc" }, { id: "../../etc/passwd" }, { id: "lowercase" },
   { id: "99999999999" }, {}, null].every((p) => root.photoSubject(p) === ""),
  JSON.stringify([{ id: "0/../etc" }, { id: "lowercase" }].map((p) => root.photoSubject(p))));

assert("statNumber keeps whole numbers whole", root.statNumber(7) === "7", root.statNumber(7));
assert("statNumber gives one decimal otherwise", root.statNumber(7.25) === "7.3", root.statNumber(7.25));

const receiver = {
  stats: { rec: 6, rec_tgt: 9, rec_yd: 84, rec_td: 1, off_snp: 45 },
  season: { gp: 16, points: 313.6, average: 19.6 },
  bio: { age: 26, height: "72", weight: "205", college: "LSU", years_exp: 5,
         depth_chart_position: "LWR", depth_chart_order: 1,
         injury_status: "Questionable", injury_body_part: "Knee" },
};
const statLabels = root.statRows(receiver).map((r) => r.label + " " + r.value);
assert("statRows emits only the stats present",
  statLabels.join(", ") === "Targets 9, Receptions 6, Receiving yards 84, Receiving TD 1, Snaps 45",
  statLabels.join(", "));
assert("statRows is empty when no box score exists", root.statRows({ stats: {} }).length === 0);
assert("statRows tolerates a player with no stats key", root.statRows({}).length === 0);

// A quarterback and a defence must render from the same ordered table.
const passerLabels = root.statRows({ stats: { pass_cmp: 22, pass_att: 31, pass_yd: 268, pass_td: 3, pass_int: 1 } })
  .map((r) => r.label);
assert("statRows covers passing lines",
  passerLabels.join(",") === "Completions,Attempts,Passing yards,Passing TD,Interceptions thrown",
  passerLabels.join(","));
const defenceLabels = root.statRows({ stats: { def_sack: 3, def_int: 2, pts_allow: 17 } }).map((r) => r.label);
assert("statRows covers defensive lines",
  defenceLabels.join(",") === "Sacks,Interceptions,Points allowed", defenceLabels.join(","));

assert("heightText converts inches to feet", root.heightText("72") === "6'0\"", root.heightText("72"));
assert("heightText handles a remainder", root.heightText("74") === "6'2\"", root.heightText("74"));
assert("heightText passes through unusable input", root.heightText("") === "");

const bioLabels = root.bioRows(receiver).map((r) => r.label + " " + r.value);
assert("bioRows renders size, college and depth chart",
  bioLabels.join(" | ") === "Age 26 | Size 6'0\", 205 lb | College LSU | Experience 5 seasons | Depth chart LWR · #1",
  bioLabels.join(" | "));
assert("bioRows calls a first-year player a rookie",
  root.bioRows({ bio: { years_exp: 0 } }).some((r) => r.value === "Rookie"));
assert("bioRows is empty for an unknown player", root.bioRows({}).length === 0);

assert("injuryText joins status and body part",
  root.injuryText(receiver) === "Questionable · Knee", root.injuryText(receiver));
assert("injuryText is empty for a healthy player",
  root.injuryText({ bio: { injury_status: "", injury_body_part: "" } }) === "");
assert("injuryText strips control characters from remote text",
  root.injuryText({ bio: { injury_status: "Out", injury_body_part: "" } }) === "Out",
  root.injuryText({ bio: { injury_status: "Out", injury_body_part: "" } }));

assert("seasonAverage formats to one decimal", root.seasonAverage(receiver) === "19.6");
assert("seasonAverage is a dash before any games",
  root.seasonAverage({ season: { gp: 0, points: 0, average: null } }) === "—");
assert("seasonAverage tolerates a missing season", root.seasonAverage({}) === "—");
assert("seasonGames counts games played", root.seasonGames(receiver) === "16 games");
assert("seasonGames reports an unplayed season",
  root.seasonGames({ season: { gp: 0 } }) === "No games played");
// The detail card repeats the scoreboard's game clock, so a score being read
// there is not mistaken for a final one while the quarter is still running.
assert("gameStatusText reports a live quarter and clock",
  root.gameStatusText({game_status: {state: "in", period: 3, clock: "4:12"}}) === "● LIVE · Q3 4:12");

assert("gameStatusText copes with a live game before the clock is known",
  root.gameStatusText({game_status: {state: "in", period: 0, clock: ""}}) === "● LIVE");

assert("gameStatusText marks a finished game",
  root.gameStatusText({game_status: {state: "post", period: 4, clock: "0:00"}}) === "FINAL");

assert("gameStatusText marks a game still to come",
  root.gameStatusText({game_status: {state: "pre", period: 0, clock: "0:00"}}) === "YET TO PLAY");

assert("gameStatusText says nothing without a game status",
  root.gameStatusText({}) === "" && root.gameStatusText(null) === ""
    && root.gameStatusText({game_status: {state: "idle"}}) === "");

assert("gameStatusText strips control characters out of the clock",
  root.gameStatusText({game_status: {state: "in", period: 2, clock: "4:1\u00072"}}) === "● LIVE · Q2 4:12");

assert("gameStatusText bounds an out-of-range quarter",
  root.gameStatusText({game_status: {state: "in", period: 99, clock: "1:00"}}) === "● LIVE · Q10 1:00");

// The card looks the player up in the current payload each refresh, so an open
// card follows the live score instead of freezing at the moment it opened.
root.data = {games: [{starters: [{id: "4046", points: 3}], bench: [{id: "7611", points: 9}]},
                     {starters: [{id: "NE", points: 12}], bench: []}]};
assert("playerById finds a starter in the current payload",
  root.playerById("4046").points === 3);
assert("playerById finds a bench player in the current payload",
  root.playerById("7611").points === 9);
assert("playerById finds a team defence by its abbreviation",
  root.playerById("NE").points === 12);
assert("playerById reports nothing for a player no longer rostered",
  root.playerById("9999") === null);
assert("playerById reports nothing without a selection or payload",
  root.playerById("") === null && root.playerById(null) === null);
root.data = null;
assert("playerById tolerates an empty payload",
  root.playerById("4046") === null);
// projectedScore mirrors how Sleeper composes a matchup projection: the points
// already banked, plus a projection for every player who has yet to kick off.
// These figures are a real week-1 matchup, checked against the Sleeper app.
function projectedStarter(points, projected, state, progress) {
  return {points: points, projected: projected,
          game_status: {state: state, progress: progress || 0}};
}
function projectedLineup(starters) { return {starters: starters}; }

const yetToPlay = [21.3386, 22.1, 15.944, 17.108, 12.477, 10.526, 12.281, 15.613, 6.53]
  .map(projected => projectedStarter(0, projected, "pre"));

assert("projectedScore banks a live player's actual points",
  root.projectedScore(projectedLineup(yetToPlay.concat([projectedStarter(12, 6.66, "in", .5261)]))).toFixed(2) === "145.92",
  root.projectedScore(projectedLineup(yetToPlay.concat([projectedStarter(12, 6.66, "in", .5261)]))));

assert("projectedScore ignores the unplayed remainder of a live projection",
  root.projectedScore(projectedLineup([projectedStarter(3, 20, "in", .25)])).toFixed(2) === "3.00");

assert("projectedScore uses projections while every game is still to come",
  root.projectedScore(projectedLineup(yetToPlay)).toFixed(2) === "133.92");

assert("projectedScore banks a finished player's actual points",
  root.projectedScore(projectedLineup([projectedStarter(0, 10, "pre"), projectedStarter(18.4, 12, "post")])).toFixed(2) === "28.40");

// A finished game carried over from the previous week sits inside the same
// scoreboard window, so a scoreless post state before this week's kickoff must
// not collapse the projection to zero.
assert("projectedScore keeps projections for a stale post state before kickoff",
  root.projectedScore(projectedLineup([projectedStarter(0, 10, "post"), projectedStarter(0, 14, "pre")])).toFixed(2) === "24.00");

assert("projectedScore skips players with no projection",
  root.projectedScore(projectedLineup([projectedStarter(0, null, "pre"), projectedStarter(0, 9, "pre")])).toFixed(2) === "9.00");

assert("projectedScore reports nothing when no starter is projected",
  root.projectedScore(projectedLineup([projectedStarter(0, null, "pre")])) === null);

assert("projectedScore tolerates a missing lineup",
  root.projectedScore(null) === null);

// The scoring breakdown teaches what earned a score, so it has to reconcile
// with the authoritative per-player total shown above it. These are the real
// week-1 figures for the NE defence, which Sleeper itemises as
// "0 PTS ALLOW, 2 SACK" against a 12.00 total.
const neDefense = {
  points: 12,
  scoring: [{stat: "pts_allow_0", count: 1, rate: 10, points: 10},
            {stat: "sack", count: 2, rate: 1, points: 2}],
};
const neRows = root.scoringRows(neDefense);

assert("scoringRows itemises every scoring rule the player triggered",
  neRows.length === 2, JSON.stringify(neRows));

assert("scoringRows names a shutout in plain English",
  neRows[0].label === "Shutout" && neRows[0].value === "10.0", JSON.stringify(neRows[0]));

assert("scoringRows shows the count and the league rate",
  neRows[0].detail === "1 × 10" && neRows[1].detail === "2 × 1",
  neRows[0].detail + " / " + neRows[1].detail);

assert("scoringRows adds up to the authoritative total",
  neRows.reduce((sum, row) => sum + Number(row.value), 0).toFixed(1) === "12.0");

assert("scoringRows carries a fractional rate without rounding it away",
  root.scoringRows({points: 9.8, scoring: [{stat: "pass_yd", count: 245, rate: .04, points: 9.8}]})[0].detail
    === "245 × 0.04");

// A live box score can lag the score Sleeper has already awarded.
const lagging = root.scoringRows({points: 18, scoring: [{stat: "rec_td", count: 1, rate: 6, points: 6}]});
assert("scoringRows reconciles a lagging box score with a remainder row",
  lagging.length === 2 && lagging[1].label === "Not yet itemised" && lagging[1].value === "12.0",
  JSON.stringify(lagging));

assert("scoringRows leaves a matching total unremarked",
  root.scoringRows({points: 6, scoring: [{stat: "rec_td", count: 1, rate: 6, points: 6}]}).length === 1);

assert("scoringRows reports nothing for a player yet to score",
  root.scoringRows({points: 0, scoring: []}).length === 0);

assert("scoringRows tolerates a player with no breakdown at all",
  root.scoringRows(null).length === 0 && root.scoringRows({points: 4}).length === 0);

assert("scoringRows drops a malformed entry",
  root.scoringRows({points: 0, scoring: [{stat: "sack", count: "two", rate: 1, points: 2}]}).length === 0);

assert("scoringLabel opens out a key it has never seen",
  root.scoringLabel("bonus_super_special") === "Bonus super special");

assert("scoringLabel keeps negative rules readable",
  root.scoringLabel("fum_lost") === "Fumble lost" && root.scoringLabel("pass_int") === "Interception thrown");

assert("scoringRate renders a whole rate without trailing zeros",
  root.scoringRate(6) === "6" && root.scoringRate(-1) === "-1");


// Pace measures a live score against the share of the projection the game has
// reached, so it says something from week one rather than waiting for two
// completed weeks of the player's own history.
assert("paceAgainst reports above pace",
  row.paceAgainst(14, 20, .5) === 1);
assert("paceAgainst reports below pace",
  row.paceAgainst(2, 20, .5) === -1);
assert("paceAgainst reports on pace inside the tolerance band",
  row.paceAgainst(10, 20, .5) === 2 && row.paceAgainst(12, 20, .5) === 2);

// The band is 15% of the projection, floored at two points so a small
// projection does not make every wobble look decisive.
// A projection of 6 gives 15% = 0.9, so the floor of 2 is what applies.
assert("paceAgainst floors the tolerance band at two points",
  row.paceAgainst(1.5, 6, 0) === 2 && row.paceAgainst(2.5, 6, 0) === 1);
assert("paceAgainst widens the band for a large projection",
  row.paceAgainst(4, 30, 0) === 2 && row.paceAgainst(6, 30, 0) === 1);

// A finished game compares the final score with the whole projection.
assert("paceAgainst compares a finished game with the full projection",
  row.paceAgainst(6, 6.66, 1) === 2 && row.paceAgainst(24, 15, 1) === 1
    && row.paceAgainst(2, 15, 1) === -1);

assert("paceAgainst says nothing without a usable projection",
  row.paceAgainst(9, 0, .5) === 0 && row.paceAgainst(9, null, .5) === 0
    && row.paceAgainst(9, undefined, .5) === 0 && row.paceAgainst(9, -4, .5) === 0);

// Unclamped, a progress of 5 would expect 100 points and -3 would expect -60,
// so both of these would read as decisive rather than on pace.
assert("paceAgainst bounds progress to the game",
  row.paceAgainst(21, 20, 5) === 2 && row.paceAgainst(0, 20, -3) === 2);

assert("paceAgainst treats a missing score as none scored",
  row.paceAgainst(null, 20, 1) === -1 && row.paceAgainst(undefined, 20, 0) === 2);

// Sleeper leaves matchup_id null for a roster with no matchup that week: a bye,
// an odd league, or a side outside the bracket once the playoffs begin. Two
// such rosters both hold null, so matching on equality alone paired them with
// each other and showed a matchup that is not being played.
root.data = {games: [
  {roster_id: 3, matchup_id: null},
  {roster_id: 7, matchup_id: null},
  {roster_id: 1, matchup_id: 2},
  {roster_id: 4, matchup_id: 2},
]};

assert("opponentFor pairs rosters that share a matchup",
  root.opponentFor({roster_id: 1, matchup_id: 2}).roster_id === 4);

assert("opponentFor reports no opponent for an unpaired roster",
  root.opponentFor({roster_id: 3, matchup_id: null}) === null);

assert("opponentFor does not pair two unpaired rosters with each other",
  root.opponentFor(root.data.games[0]) === null
    && root.opponentFor(root.data.games[1]) === null);

assert("opponentFor treats an absent matchup id as unpaired",
  root.opponentFor({roster_id: 3}) === null);

assert("opponentFor tolerates a missing game or payload",
  root.opponentFor(null) === null);
root.data = null;
assert("opponentFor tolerates an empty payload",
  root.opponentFor({roster_id: 1, matchup_id: 2}) === null);

// The bar still reports a live game when only one lineup is on screen.
function lineupOf(states) {
  return {starters: states.map(s => ({game_status: {state: s}}))};
}
assert("matchup state follows a lone lineup when there is no opponent",
  root.calculateMatchupState(lineupOf(["in", "pre"]), null) === "live");
assert("a lone lineup yet to play reports upcoming",
  root.calculateMatchupState(lineupOf(["pre", "pre"]), null) === "upcoming");
assert("a lone lineup that has finished reports final",
  root.calculateMatchupState(lineupOf(["post"]), null) === "final");
assert("two lineups are still combined",
  root.calculateMatchupState(lineupOf(["pre"]), lineupOf(["in"])) === "live");
assert("no lineups at all reports idle",
  root.calculateMatchupState(null, null) === "idle");

// A bar surface is built per monitor, so this panel exists once per screen.
// Left alone, every screen polled the API on its own timer: three machines'
// worth of traffic for one league, and the overlapping writes that caused the
// cache-snapshot race. Only the primary polls; its result reaches the rest.
function panelAt(index, count) {
  const widgets = [];
  for (let i = 0; i < count; i++) widgets.push({name: "w" + i});
  root.hostWidget = Object.assign(widgets[index], {siblingWidgets: () => widgets});
  return widgets;
}
let fetched = 0;
function scheduled(opts) {
  const o = opts || {};
  root.leagueId = o.leagueId === undefined ? "123" : o.leagueId;
  root.lastDataMs = o.lastDataMs || 0;
  root.adaptiveIntervalMs = o.interval || 60000;
  standbyTimer.running = false;
  standbyTimer.restarted = 0;
  fetched = 0;
  root.refresh = () => { fetched++ };
  root.refreshIfDue();
  return {fetched: fetched, waiting: standbyTimer.restarted};
}
function afterWaiting(opts) {
  scheduled(opts);
  fetched = 0;
  root.refreshIfAbandoned();
  return fetched;
}

panelAt(0, 3);
assert("the primary panel is the first live widget", root.isPrimaryPanel() === true);
panelAt(2, 3);
assert("another screen's panel is not primary", root.isPrimaryPanel() === false);
root.hostWidget = null;
assert("a lone panel with no siblings is primary", root.isPrimaryPanel() === true);
root.hostWidget = {siblingWidgets: () => []};
assert("a panel is primary when no widgets are listed", root.isPrimaryPanel() === true);

panelAt(0, 3);
assert("the primary panel polls on schedule",
  scheduled({lastDataMs: Date.now()}).fetched === 1);

// A secondary never polls on the scheduled tick: it only asks to look again.
panelAt(2, 3);
const tick = scheduled({lastDataMs: Date.now()});
assert("a secondary panel does not poll on its own tick",
  tick.fetched === 0 && tick.waiting === 1, JSON.stringify(tick));

assert("a secondary panel stands down once the primary has published",
  afterWaiting({lastDataMs: Date.now()}) === 0);

// The failsafe: if the primary leaves with its monitor, nothing publishes.
assert("a secondary panel takes over once shared data goes stale",
  afterWaiting({lastDataMs: Date.now() - 200000, interval: 60000}) === 1);

// At startup nothing has arrived yet, and the idle cadence is fifteen minutes,
// so waiting for a whole interval to re-check would strand a cold secondary.
assert("a secondary panel takes over if nothing ever arrives",
  afterWaiting({lastDataMs: 0, interval: 900000}) === 1);

// A panel promoted between the tick and the re-check fetches immediately.
scheduled({lastDataMs: Date.now()});
panelAt(0, 3);
fetched = 0;
root.refreshIfAbandoned();
assert("a panel promoted while waiting polls at once", fetched === 1);

panelAt(0, 3);
assert("no panel polls without a league",
  scheduled({leagueId: "", lastDataMs: 0}).fetched === 0);
panelAt(2, 3);
assert("no secondary takes over without a league",
  afterWaiting({leagueId: "", lastDataMs: 0}) === 0);

// Alerting and fetching are the same election, so one screen does both.
panelAt(1, 3);
assert("only the primary panel alerts", root.isAlertingPanel() === false);
panelAt(0, 3);
assert("the primary panel alerts", root.isAlertingPanel() === true);
root.hostWidget = null;

// The league list is one row per matchup, the user's own first, built from the
// games already in the payload. Rosters with no matchup are carried as a lone
// side so a bye or an eliminated team still appears.
root.maxTeams = 64;
root.selectedRosterId = 3;
root.data = {
  teams: [
    {roster_id: 1, name: "Zippers",  record: {wins: 1, losses: 1, ties: 0, points: 247.86, potential: 312.26}},
    {roster_id: 3, name: "Kareem",   record: {wins: 2, losses: 0, ties: 0, points: 283.74, potential: 291.34}},
    {roster_id: 6, name: "Loop",     record: {wins: 2, losses: 0, ties: 0, points: 300.00, potential: 330.00}},
    {roster_id: 9, name: "Byes",     record: {wins: 0, losses: 2, ties: 1, points: 100.00, potential: 150.00}},
  ],
  games: [
    {roster_id: 1, matchup_id: 1, points: 10, starters: [{game_status: {state: "pre"}}]},
    {roster_id: 6, matchup_id: 2, points: 30, starters: [{game_status: {state: "in"}}]},
    {roster_id: 3, matchup_id: 2, points: 20, starters: [{game_status: {state: "pre"}}]},
    {roster_id: 4, matchup_id: 1, points: 40, starters: [{game_status: {state: "pre"}}]},
    {roster_id: 9, matchup_id: null, points: 5, starters: [{game_status: {state: "pre"}}]},
  ],
};

const rows = root.buildLeagueMatchups();
assert("every matchup is listed once", rows.length === 3, JSON.stringify(rows.length));
assert("the user's own matchup is listed first", rows[0].mine === true);
assert("the user's own roster is on the left of their row",
  rows[0].home.roster_id === 3 && rows[0].away.roster_id === 6);
assert("other matchups are not marked as the user's",
  rows.slice(1).every(r => r.mine === false));
assert("a live matchup is reported as live", rows[0].state === "live");
assert("a matchup yet to start is reported as upcoming",
  rows.find(r => r.home.roster_id === 1 || r.away.roster_id === 1).state === "upcoming");

const lone = rows.find(r => r.away === null);
assert("a roster with no matchup is carried as a lone side",
  Boolean(lone) && lone.home.roster_id === 9, JSON.stringify(rows.map(r => [r.home.roster_id, r.away && r.away.roster_id])));

assert("buildLeagueMatchups tolerates an empty payload",
  (root.data = null, root.buildLeagueMatchups().length === 0));

// Standings order by record, then by points scored.
root.data = {teams: [
  {roster_id: 1, name: "B", record: {wins: 2, losses: 0, ties: 0, points: 100}},
  {roster_id: 2, name: "A", record: {wins: 2, losses: 0, ties: 0, points: 200}},
  {roster_id: 3, name: "C", record: {wins: 1, losses: 1, ties: 1, points: 900}},
  {roster_id: 4, name: "D", record: {wins: 1, losses: 2, ties: 0, points: 950}},
], games: []};
root.selectedRosterId = 3;
const table = root.buildLeagueStandings();
assert("standings lead with the best record",
  table.map(r => r.name).join("") === "ABCD", table.map(r => r.name).join(""));
assert("points break a tied record", table[0].name === "A" && table[1].name === "B");
assert("ties rank above a worse record", table[2].name === "C");
assert("the user's own team is marked in the standings",
  table[2].mine === true && table[0].mine === false);
assert("buildLeagueStandings tolerates an empty payload",
  (root.data = null, root.buildLeagueStandings().length === 0));

assert("a record reads without ties when there are none",
  root.recordText({wins: 2, losses: 1, ties: 0}) === "2-1");
assert("a record includes ties when there are any",
  root.recordText({wins: 2, losses: 1, ties: 1}) === "2-1-1");
assert("recordText tolerates a missing row", root.recordText(null) === "");

// Selecting a matchup only moves the panel body. Nothing that speaks for the
// user may follow it, or the bar and the alerts would change with the view.
root.view = "league";
root.viewMatchup(6);
assert("selecting a matchup shows the matchup view",
  root.viewedRosterId === 6 && root.view === "matchup");
assert("selecting the user's own roster still marks it as their own",
  (root.viewMatchup(3), root.viewedRosterId === 3));
assert("viewMatchup ignores a missing roster",
  (root.viewMatchup(null), root.viewedRosterId === 0));

assert("showView refuses a view that does not exist",
  (root.showView("nonsense"), root.view === "matchup"));
assert("showView accepts the league view",
  (root.showView("league"), root.view === "league"));
assert("showView accepts settings",
  (root.showView("settings"), root.view === "settings"));
root.view = "matchup";

console.log(failures === 0 ? "\nAlert logic tests passed" : "\n" + failures + " FAILURES");
if (failures > 0) throw new Error(failures + " alert logic failures");
