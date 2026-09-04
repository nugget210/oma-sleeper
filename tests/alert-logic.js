// Behavioural tests for the alert logic in Panel.qml.
//
// The functions under test are extracted from Panel.qml itself rather than
// reimplemented here, so these tests exercise the shipped source and keep
// working across refactors that leave the behaviour intact.
//
// QML_SOURCE is prepended by tests/test-alert-logic.sh.

function extractFunction(name) {
  const marker = "\n  function " + name + "(";
  const start = QML_SOURCE.indexOf(marker);
  if (start < 0) throw new Error("function not found in Panel.qml: " + name);
  let depth = 0;
  for (let i = QML_SOURCE.indexOf("{", start); i < QML_SOURCE.length; i++) {
    if (QML_SOURCE[i] === "{") depth++;
    else if (QML_SOURCE[i] === "}") {
      depth--;
      if (depth === 0) return QML_SOURCE.slice(start + "\n  function ".length, i + 1);
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
];

// Stand-ins for the QML objects the functions touch.
const alertProc = { running: false, soundPath: "" };
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
};
for (const name of FUNCTIONS) eval("root." + name + " = function " + extractFunction(name));

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

console.log(failures === 0 ? "\nAlert logic tests passed" : "\n" + failures + " FAILURES");
if (failures > 0) throw new Error(failures + " alert logic failures");
