/**
 * THE CATALOG — every message type and structure of the TxODDS Scores Product
 * soccer feed (v1.0, 20 April 2026), with descriptions transcribed from the
 * official PDF and Data-field tables verified against real captured records
 * (see ./action-examples.json — one real record per action type).
 */
import rawExamples from "./action-examples.json";
import type { RawRecord } from "./types";

/* ------------------------------------------------------------------ */
/* Types                                                               */
/* ------------------------------------------------------------------ */

export interface FieldSpec {
  name: string;
  required?: boolean;
  type: string;
  meaning: string;
  enumValues?: string[];
}

export type Category =
  | "Match flow"
  | "Scoring"
  | "Set pieces & play"
  | "Possession"
  | "Discipline & VAR"
  | "Players & lineups"
  | "Conditions & venue"
  | "Data quality & meta";

export const CATEGORIES: Category[] = [
  "Match flow",
  "Scoring",
  "Set pieces & play",
  "Possession",
  "Discipline & VAR",
  "Players & lineups",
  "Conditions & venue",
  "Data quality & meta",
];

export interface ActionSpec {
  action: string; // wire value, e.g. "goal"
  title: string; // PDF message name, e.g. "Goal"
  category: Category;
  description: string; // from the PDF
  dataFields: FieldSpec[]; // the action-specific Data payload
  notes?: string;
  observed: boolean; // seen in real captured matches
  autoConfirmed?: boolean; // PDF: "confirmed automatically", no follow-up
}

/* ------------------------------------------------------------------ */
/* Envelope — fields every record shares                               */
/* ------------------------------------------------------------------ */

export const COMMON_FIELDS: FieldSpec[] = [
  { name: "Action", required: true, type: "enum", meaning: "Action type — which message this record is (the catalog on the left)." },
  { name: "Id", required: true, type: "number", meaning: "Action ID. Messages for the same action share the ID — e.g. an unconfirmed action followed by its confirmation, or an amend." },
  { name: "Seq", required: true, type: "number", meaning: "Update sequence number for the fixture — total order of the feed." },
  { name: "Ts", required: true, type: "number", meaning: "Timestamp of the update (Unix ms)." },
  { name: "Confirmed", required: true, type: "boolean", meaning: "Whether the action actually happened (vs a preliminary report). Final confirmation can arrive later under the same Id." },
  { name: "StatusId", required: true, type: "number", meaning: "Current game period — see the StatusId table." },
  { name: "GameState", type: "string", meaning: "Fixture-level state string (e.g. \"scheduled\") — note: the demo feed labels running matches \"scheduled\"; trust StatusId + Clock instead." },
  { name: "Clock", type: "Clock", meaning: "Game clock — see Clock structure." },
  { name: "Participant", type: "number|null", meaning: "Which team the action belongs to: 1 = Participant1, 2 = Participant2 (map to home/away via Participant1IsHome)." },
  { name: "Data", type: "object|null", meaning: "Action-specific payload — the fields documented per message type." },
  { name: "Score", type: "Score", meaning: "Current score-line by period (NOT the delta) — present on actions that can modify the score." },
  { name: "Stats", type: "map<string,number>", meaning: "Numeric stat map: key = (period×1000) + base key. Base 1..8 = P1/P2 Goals, Yellow, Red, Corners." },
  { name: "PlayerStats", type: "object|null", meaning: "Player statistics for both participants, indexed by player id (e.g. {goals: 1})." },
  { name: "PossibleEvent", type: "object|null", meaning: "Possible-event flags in play for the game/team — see PossiblePartyEvent." },
  { name: "FixtureId", required: true, type: "number", meaning: "Normative id of the fixture." },
  { name: "FixtureGroupId", type: "number", meaning: "Grouping id for the fixture (tournament grouping)." },
  { name: "CompetitionId", type: "number", meaning: "Competition id (World Cup demo = 72)." },
  { name: "CountryId", type: "number", meaning: "Country id of the competition." },
  { name: "SportId", type: "number", meaning: "Sport id (soccer = 1)." },
  { name: "Type", required: true, type: "enum", meaning: "Sport type — \"Soccer\"." },
  { name: "StartTime", type: "number", meaning: "Scheduled kickoff (Unix ms)." },
  { name: "Participant1Id / Participant2Id", type: "number", meaning: "Normative team ids." },
  { name: "Participant1IsHome", type: "boolean", meaning: "Whether Participant1 is the home side — the home/away decoder key." },
  { name: "IsTeam", type: "boolean", meaning: "Team-sport flag." },
  { name: "ConnectionId", type: "number", meaning: "Reporter/analyst connection id that produced the record." },
  { name: "CoverageType", type: "string", meaning: "How the match is covered — e.g. \"TV/Stream\", in-venue scout." },
  { name: "CoverageSecondaryData", type: "boolean", meaning: "Whether secondary data (possession tiers, shots…) is covered." },
  { name: "VirtualFixture", type: "boolean|null", meaning: "True for virtual fixtures that replay an existing fixture's events for test purposes." },
];

/* ------------------------------------------------------------------ */
/* Decoders                                                            */
/* ------------------------------------------------------------------ */

export const STATUS_IDS: Record<number, { code: string; label: string; description: string }> = {
  1: { code: "NS", label: "Not started", description: "Status before the match is started" },
  2: { code: "H1", label: "1st half", description: "Match in play during 1st half" },
  3: { code: "HT", label: "Half-time", description: "Half-time of the match" },
  4: { code: "H2", label: "2nd half", description: "Match in play during 2nd half" },
  5: { code: "F", label: "Full-time", description: "Match ends after the 2nd half of regular time" },
  6: { code: "WET", label: "Waiting for extra time", description: "Break after second half before the first extra-time half" },
  7: { code: "ET1", label: "ET 1st half", description: "Extra time, first half in play" },
  8: { code: "HTET", label: "ET half-time", description: "Extra-time half-time" },
  9: { code: "ET2", label: "ET 2nd half", description: "Extra time, second half in play" },
  10: { code: "FET", label: "Ended after ET", description: "Match ends after extra time" },
  11: { code: "WPE", label: "Waiting for penalties", description: "Break before the penalty shootout" },
  12: { code: "PE", label: "Penalty shootout", description: "Penalty shootout in progress" },
  13: { code: "FPE", label: "Ended after penalties", description: "Match ends after the penalty shootout" },
  14: { code: "I", label: "Interrupted", description: "Match interrupted" },
  15: { code: "A", label: "Abandoned", description: "Match abandoned" },
  16: { code: "C", label: "Cancelled", description: "Match cancelled" },
  17: { code: "TXCC", label: "Coverage cancelled", description: "TX coverage cancelled" },
  18: { code: "TXCS", label: "Coverage suspended", description: "TX coverage suspended" },
  19: { code: "P", label: "Postponed", description: "Match postponed" },
};

const STAT_BASE: Record<number, string> = {
  1: "P1 Goals",
  2: "P2 Goals",
  3: "P1 Yellow cards",
  4: "P2 Yellow cards",
  5: "P1 Red cards",
  6: "P2 Red cards",
  7: "P1 Corners",
  8: "P2 Corners",
};

const STAT_PERIOD: Record<number, string> = {
  0: "Total",
  1: "H1",
  2: "H2",
  3: "ET1",
  4: "ET2",
  5: "PE",
  6: "ET Total",
  7: "HT",
};

/** Decode a numeric Stats key: (period×1000) + base. */
export function decodeStatKey(key: string | number): string {
  const n = Number(key);
  if (!Number.isFinite(n)) return String(key);
  const base = n % 1000;
  const period = Math.floor(n / 1000);
  const baseName = STAT_BASE[base] ?? `stat ${base}`;
  const periodName = STAT_PERIOD[period] ?? `period ${period}`;
  return `${baseName} · ${periodName}`;
}

export function decodeStatus(statusId?: number): string {
  if (statusId == null) return "—";
  const s = STATUS_IDS[statusId];
  return s ? `${statusId} · ${s.code} · ${s.label}` : `${statusId} · unknown`;
}

export function clockDisplay(clock?: { Running?: boolean; Seconds?: number }): string {
  if (!clock || clock.Seconds == null) return "—";
  const m = Math.floor(clock.Seconds / 60);
  const s = clock.Seconds % 60;
  return `${m}:${String(s).padStart(2, "0")}${clock.Running ? " ▶" : " ⏸"}`;
}

export function decodeParticipant(p: number | null | undefined, p1IsHome = true): string {
  if (p == null) return "neutral / whole game";
  const side = p === 1 ? (p1IsHome ? "home" : "away") : p1IsHome ? "away" : "home";
  return `Participant${p} (${side})`;
}

export function tsDisplay(ts?: number): string {
  if (!ts) return "—";
  return new Date(ts).toLocaleTimeString();
}

/* ------------------------------------------------------------------ */
/* Common structures (the PDF's "Common" section)                      */
/* ------------------------------------------------------------------ */

export interface StructureSpec {
  id: string;
  title: string;
  description: string;
  fields: FieldSpec[];
}

export const COMMON_STRUCTURES: StructureSpec[] = [
  {
    id: "clock",
    title: "Clock",
    description: "Game clock. Seconds count up through the match; Running indicates whether the ball is in play.",
    fields: [
      { name: "Running", required: true, type: "boolean", meaning: "Whether the clock is currently running." },
      { name: "Seconds", required: true, type: "number", meaning: "Elapsed seconds of the match clock (minute = Seconds ÷ 60)." },
    ],
  },
  {
    id: "score",
    title: "Score / Score for Participant in Period",
    description:
      "Score information referencing the CURRENT score of the game (not the change caused by the action). Provided on actions that can modify the score-line. Per participant, per period.",
    fields: [
      { name: "Participant1 / Participant2", required: true, type: "map<period, PeriodScore>", meaning: "Period keys: H1, HT, H2, ET1, ET2, ETTotal, PE, Total." },
      { name: "→ Goals", type: "number", meaning: "Goals in the period." },
      { name: "→ YellowCards", type: "number", meaning: "Yellow cards in the period." },
      { name: "→ RedCards", type: "number", meaning: "Red cards in the period." },
      { name: "→ Corners", type: "number", meaning: "Corners in the period." },
    ],
  },
  {
    id: "statusid",
    title: "Status Id",
    description:
      "Most events carry a StatusId — the current phase of the game. All 19 values, from the official table.",
    fields: Object.entries(STATUS_IDS).map(([id, s]) => ({
      name: `${id} · ${s.code}`,
      type: "phase",
      meaning: `${s.label} — ${s.description}`,
    })),
  },
  {
    id: "stats",
    title: "Stats (numeric map)",
    description:
      "Deterministic encoding for on-chain validation: key = (period×1000) + base key. Base keys 1–8 = P1/P2 Goals, Yellow cards, Red cards, Corners. Period offsets: 0 Total, 1000 H1, 2000 H2, 3000 ET1, 4000 ET2, 5000 PE (e.g. 2007 = P1 Corners in H2). These are the values committed to TxODDS' on-chain Merkle roots.",
    fields: Object.entries(STAT_BASE).map(([k, v]) => ({ name: `base ${k}`, type: "counter", meaning: v })),
  },
  {
    id: "kickoffdetails",
    title: "Kickoff Details",
    description: "Kick-off information.",
    fields: [
      { name: "Team", required: true, type: "number|null", meaning: "Team that does the kick-off (1 = Participant1, 2 = Participant2; map to home/away via Participant1IsHome)." },
    ],
  },
  {
    id: "lineupdata",
    title: "Lineup Data",
    description: "Lineup information for a team.",
    fields: [
      { name: "normativeId", required: true, type: "number", meaning: "Team normative id." },
      { name: "preferredName", required: true, type: "string", meaning: "Team name." },
      { name: "sportId", required: true, type: "string", meaning: "Sport id (UUID)." },
      { name: "players", type: "map<id, PlayerLineupData>", meaning: "Player lineup information." },
    ],
  },
  {
    id: "playerlineupdata",
    title: "Player Lineup Data",
    description: "Lineup information for one player in a team.",
    fields: [
      { name: "fixturePlayerId", type: "number", meaning: "Player id in the fixture — the id events reference (goal PlayerId, substitution PlayerInId…)." },
      { name: "player", type: "PlayerData", meaning: "Player information — see Player Data." },
      { name: "positionId", required: true, type: "number", meaning: "Position id in the fixture." },
      { name: "rosterNumber", type: "string|null", meaning: "Shirt number." },
      { name: "starter", required: true, type: "boolean", meaning: "Part of the starting team." },
      { name: "statusId", required: true, type: "number", meaning: "Player status." },
      { name: "unitId", required: true, type: "number", meaning: "Unit (GK/DF/MF/FW grouping)." },
    ],
  },
  {
    id: "playerdata",
    title: "Player Data",
    description: "Data about a player in a team.",
    fields: [
      { name: "country", type: "string|null", meaning: "Player country of origin." },
      { name: "dateOfBirth", type: "string|null", meaning: "Player date of birth (YYYY-MM-DD)." },
      { name: "entityStatus", type: "string|null", meaning: "Player entity status." },
      { name: "…name fields", type: "string", meaning: "Player names as provided by the feed." },
    ],
  },
  {
    id: "playersonpitch",
    title: "Players on Pitch",
    description: "Players on pitch for both participants.",
    fields: [
      { name: "Participant1 / Participant2", required: true, type: "map<playerId, 1|-1>", meaning: "Flag is 1 if the player is on the pitch, −1 if not." },
    ],
  },
  {
    id: "playerstatistics",
    title: "Player Statistics",
    description: "Player statistics for both participants, usually indexed by player id (e.g. {\"418175\": {\"goals\": 1}}).",
    fields: [
      { name: "Participant1 / Participant2", type: "map<playerId, stats>", meaning: "Per-player counters (goals, …)." },
    ],
  },
  {
    id: "possiblepartyevent",
    title: "Possible Party / Neutral Event",
    description: "Possible-event flags — what might be about to happen, per team or game-wide.",
    fields: [
      { name: "Corner", type: "boolean", meaning: "A corner may be awarded." },
      { name: "Goal", type: "boolean", meaning: "A goal may have occurred / be imminent." },
      { name: "Penalty", type: "boolean", meaning: "A penalty may be awarded." },
    ],
  },
  {
    id: "participantstate",
    title: "Participant State",
    description: "Information about a team during this game.",
    fields: [
      { name: "PossibleEvent", type: "PossiblePartyEvent", meaning: "Possible events in the game for this team." },
    ],
  },
];

/* ------------------------------------------------------------------ */
/* Action messages                                                     */
/* ------------------------------------------------------------------ */

const A = (spec: Omit<ActionSpec, "observed"> & { observed?: boolean }): ActionSpec => ({
  observed: true,
  ...spec,
});

export const ACTIONS: ActionSpec[] = [
  // ---- Match flow -------------------------------------------------
  A({
    action: "kickoff",
    title: "Kickoff",
    category: "Match flow",
    description: "The actual kickoff. Clock and Type can be modified via action amend. Can be followed up with updates — new messages with the same action id update this action.",
    dataFields: [{ name: "KickoffDetails", type: "Kickoff Details", meaning: "Which team kicks off — see Kickoff Details." }],
  }),
  A({
    action: "kickoff_team",
    title: "Kickoff Team",
    category: "Match flow",
    description: "The team that will kick off the game. Can be followed up with updates.",
    dataFields: [{ name: "Team", type: "number|null", meaning: "1 = Participant1, 2 = Participant2." }],
  }),
  A({
    action: "standby",
    title: "Standby",
    category: "Match flow",
    description: "Sent just before the start of the game and additional periods.",
    dataFields: [],
    autoConfirmed: true,
  }),
  A({
    action: "status",
    title: "Status",
    category: "Match flow",
    description: "Sets the current game status/period. It can be deleted/cancelled. Overtime is signalled with an additional field included only during overtime.",
    dataFields: [
      { name: "StatusId", required: true, type: "number", meaning: "The new game period — see the StatusId table.", enumValues: Object.entries(STATUS_IDS).map(([k, v]) => `${k} (${v.code})`) },
      { name: "StatusName", type: "string", meaning: "Name for the status id — \"NS\", \"H1\", \"H2\", \"ET1\", \"F\"…" },
      { name: "Overtime", type: "boolean", meaning: "Present only during overtime." },
    ],
  }),
  A({
    action: "additional_time",
    title: "Additional Time",
    category: "Match flow",
    description: "How much additional time is added to the current period, at the end of the regular minutes. Can be followed up with updates.",
    dataFields: [{ name: "Minutes", type: "number|null", meaning: "Minutes added to the current period (e.g. 1, 2, 6)." }],
  }),
  A({
    action: "clock_adjustment",
    title: "Clock Adjustment",
    category: "Match flow",
    description: "Amends the clock value with corrected seconds and whether it is running or not.",
    dataFields: [],
    notes: "The corrected values arrive in the envelope Clock field.",
    autoConfirmed: true,
  }),
  A({
    action: "halftime_finalised",
    title: "Halftime Finalised",
    category: "Match flow",
    description: "Marks the half-time stats as finalised/verified by the analyst.",
    dataFields: [],
    autoConfirmed: true,
  }),
  A({
    action: "game_finalised",
    title: "Game Finalised",
    category: "Match flow",
    description: "Marks the full-game stats as finalised/verified — the definitive end-of-coverage marker.",
    dataFields: [],
    autoConfirmed: true,
  }),

  // ---- Scoring ----------------------------------------------------
  A({
    action: "goal",
    title: "Goal",
    category: "Scoring",
    description: "Indicates a Goal. Can be followed up with updates — new messages with the same action id can update this action (e.g. an unconfirmed goal, then confirmation with the scorer).",
    dataFields: [
      { name: "GoalType", type: "enum|null", meaning: "Type of goal.", enumValues: ["Shot", "Head", "Own", "Other"] },
      { name: "PlayerId", type: "number|null", meaning: "External id of the player that scored, if known (references fixturePlayerId in the lineups)." },
    ],
    notes: "Also carries Score (new score-line), PlayerStats (scorer counters), Stats and sometimes KickoffDetails (who restarts).",
  }),
  A({
    action: "penalty",
    title: "Penalty Attempt",
    category: "Scoring",
    description: "Indicates a Penalty awarded to a team. Can be followed up with updates.",
    dataFields: [],
    notes: "Participant = the team taking the penalty. The result arrives as penalty_outcome.",
  }),
  A({
    action: "penalty_outcome",
    title: "Penalty Outcome",
    category: "Scoring",
    description: "Indicates the outcome of a Penalty. Can be followed up with updates.",
    dataFields: [
      { name: "Outcome", type: "enum|null", meaning: "Outcome of the penalty.", enumValues: ["Scored", "Missed", "Retake"] },
      { name: "PlayerId", type: "number|null", meaning: "External id of the player that took the penalty, if known." },
    ],
    notes: "Carries PlayerStats when scored.",
  }),
  A({
    action: "penalty_shootout_team",
    title: "Penalty Shootout Team",
    category: "Scoring",
    description: "The team that will start the penalty shootout. Can be followed up with updates.",
    dataFields: [{ name: "Team", type: "number|null", meaning: "1 = Participant1, 2 = Participant2." }],
    observed: false,
  }),
  A({
    action: "score_adjustment",
    title: "Score Adjustment",
    category: "Scoring",
    description: "In cases of missed scoring updates (e.g. goals) or coverage gaps, a score adjustment updates ONLY the main score for a given half or period. Other stats in that half may no longer be accurate.",
    dataFields: [],
    notes: "The corrected score-line arrives in the envelope Score field.",
    autoConfirmed: true,
  }),
  A({
    action: "shot",
    title: "Shot",
    category: "Scoring",
    description: "Indicates a shot attempt by a player. Can be followed up with updates.",
    dataFields: [
      { name: "Outcome", type: "enum|null", meaning: "Outcome of the shot.", enumValues: ["OnTarget", "OffTarget", "Woodwork", "Blocked"] },
    ],
  }),
  A({
    action: "possible",
    title: "Possible",
    category: "Scoring",
    description: "Indicates a possible event, either in-game or for a specific participant — the feed's early-warning signal (a goal/corner/penalty may be about to be confirmed).",
    dataFields: [
      { name: "Corner", type: "boolean", meaning: "A corner may be awarded." },
      { name: "Goal", type: "boolean", meaning: "A goal may have occurred." },
      { name: "Penalty", type: "boolean", meaning: "A penalty may be awarded." },
    ],
    autoConfirmed: true,
  }),

  // ---- Set pieces & play ------------------------------------------
  A({
    action: "corner",
    title: "Corner",
    category: "Set pieces & play",
    description: "Indicates a Corner taking place. Can be followed up with updates.",
    dataFields: [],
    notes: "Participant = the team taking the corner; Stats/Score carry the updated corner counts.",
  }),
  A({
    action: "free_kick",
    title: "Free Kick",
    category: "Set pieces & play",
    description: "Indicates a Free Kick taking place. Can be followed up with updates.",
    dataFields: [
      { name: "FreeKickType", type: "enum|null", meaning: "The danger zone associated to the free kick.", enumValues: ["Safe", "Attack", "Danger", "HighDanger", "Offside"] },
    ],
  }),
  A({
    action: "throw_in",
    title: "Throw In",
    category: "Set pieces & play",
    description: "Indicates a Throw In. Can be followed up with updates.",
    dataFields: [
      { name: "ThrowInType", type: "enum|null", meaning: "The danger zone associated to the throw-in.", enumValues: ["Safe", "Attack", "Danger"] },
    ],
  }),
  A({
    action: "goal_kick",
    title: "Goal Kick",
    category: "Set pieces & play",
    description: "A team does a goal-kick to restart play.",
    dataFields: [],
    autoConfirmed: true,
  }),

  // ---- Possession --------------------------------------------------
  A({
    action: "possession",
    title: "Possession",
    category: "Possession",
    description: "The participant takes possession of the ball.",
    dataFields: [],
    autoConfirmed: true,
  }),
  A({
    action: "safe_possession",
    title: "Safe Possession",
    category: "Possession",
    description: "The participant has the ball in the safe possession area.",
    dataFields: [],
    autoConfirmed: true,
  }),
  A({
    action: "attack_possession",
    title: "Attack Possession",
    category: "Possession",
    description: "The participant has the ball in the attacking area.",
    dataFields: [],
    autoConfirmed: true,
  }),
  A({
    action: "danger_possession",
    title: "Danger Possession",
    category: "Possession",
    description: "The participant has the ball in the attack and is creating danger for the opposition. Scoring is possible.",
    dataFields: [],
    autoConfirmed: true,
  }),
  A({
    action: "high_danger_possession",
    title: "High Danger Possession",
    category: "Possession",
    description: "The participant has the ball in the attack and is creating chances. Scoring is likely.",
    dataFields: [],
    autoConfirmed: true,
  }),

  // ---- Discipline & VAR --------------------------------------------
  A({
    action: "yellow_card",
    title: "Yellow Card",
    category: "Discipline & VAR",
    description: "A player has received a Yellow card. Can be followed up with updates.",
    dataFields: [{ name: "PlayerId", type: "number|null", meaning: "External id of the booked player, if known." }],
  }),
  A({
    action: "red_card",
    title: "Red Card",
    category: "Discipline & VAR",
    description: "A player has received a Red card. Can be followed up with updates.",
    dataFields: [{ name: "PlayerId", type: "number|null", meaning: "External id of the sent-off player, if known." }],
    observed: false,
  }),
  A({
    action: "injury",
    title: "Injury",
    category: "Discipline & VAR",
    description: "Reports a player injury situation for a team. Can be followed up with updates.",
    dataFields: [
      { name: "Participant", type: "number", meaning: "Team of the injured player." },
      { name: "PlayerId", type: "number|null", meaning: "External id of the injured player, if known." },
    ],
  }),
  A({
    action: "var",
    title: "VAR",
    category: "Discipline & VAR",
    description: "A VAR (Video Assistant Referee) review has started. Can be followed up with updates.",
    dataFields: [
      { name: "Type", type: "enum|null", meaning: "What is being reviewed (e.g. \"CornerKick\", goal, penalty — see examples)." },
    ],
  }),
  A({
    action: "var_end",
    title: "VAR End",
    category: "Discipline & VAR",
    description: "A VAR review has ended. Can be followed up with updates.",
    dataFields: [
      { name: "Outcome", type: "enum|null", meaning: "Outcome of the VAR review.", enumValues: ["Stands", "Overturned"] },
    ],
  }),

  // ---- Players & lineups -------------------------------------------
  A({
    action: "lineups",
    title: "Lineups",
    category: "Players & lineups",
    description: "Team lineups (pre-game) — both teams' full player lists with positions, shirt numbers, starters.",
    dataFields: [
      { name: "Participant1 / Participant2", type: "Lineup Data", meaning: "Per-team lineup — see Lineup Data / Player Lineup Data / Player Data structures." },
    ],
  }),
  A({
    action: "lineup",
    title: "Lineup",
    category: "Players & lineups",
    description: "Sent when the lineup is confirmed.",
    dataFields: [],
    observed: false,
  }),
  A({
    action: "players_warming_up",
    title: "Players Warming Up",
    category: "Players & lineups",
    description: "Sent pre-game when the players are doing their warm-up routines.",
    dataFields: [],
  }),
  A({
    action: "players_on_the_pitch",
    title: "Players on the Pitch",
    category: "Players & lineups",
    description: "Sent when the players come out onto the pitch before the game.",
    dataFields: [
      { name: "Participant1 / Participant2", type: "map<playerId, 1|-1>", meaning: "1 = on pitch, −1 = not — see Players on Pitch." },
    ],
  }),
  A({
    action: "players_on_the_pitch_adjustment",
    title: "Players on the Pitch Adjustment",
    category: "Players & lineups",
    description: "Adjustment message for players currently on the pitch.",
    dataFields: [],
    observed: false,
    autoConfirmed: true,
  }),
  A({
    action: "substitution",
    title: "Substitution",
    category: "Players & lineups",
    description: "Sent when a team makes a substitution. Can be followed up with updates.",
    dataFields: [
      { name: "Participant", type: "number", meaning: "Team making the substitution." },
      { name: "PlayerInId", type: "number|null", meaning: "External id of the player coming on." },
      { name: "PlayerOutId", type: "number|null", meaning: "External id of the player going off." },
    ],
  }),
  A({
    action: "player_stats_adjustment",
    title: "Player Stats Adjustment",
    category: "Players & lineups",
    description: "Player stats adjustment message.",
    dataFields: [],
    observed: false,
    autoConfirmed: true,
  }),
  A({
    action: "jersey",
    title: "Jersey",
    category: "Players & lineups",
    description: "Color of a team's jerseys for the given participant in this fixture.",
    dataFields: [
      { name: "Color", type: "enum|null", meaning: "Jersey color.", enumValues: ["red", "navyblue", "skyblue", "green", "white", "black", "yellow", "orange", "grey", "burgundy", "brown", "purple", "blue", "olive", "aqua", "gold"] },
    ],
    autoConfirmed: true,
  }),

  // ---- Conditions & venue ------------------------------------------
  A({
    action: "weather",
    title: "Weather",
    category: "Conditions & venue",
    description: "Current weather at the venue — sent ~30 minutes before start and during the game if conditions change.",
    dataFields: [
      { name: "Conditions", type: "array<enum>|null", meaning: "Weather conditions — usually 'Day' or 'Night' plus one other value (rain, etc.)." },
    ],
    autoConfirmed: true,
  }),
  A({
    action: "pitch",
    title: "Pitch",
    category: "Conditions & venue",
    description: "Pitch conditions at the venue.",
    dataFields: [{ name: "Conditions", type: "array<enum>|null", meaning: "Pitch condition values." }],
    autoConfirmed: true,
  }),
  A({
    action: "venue",
    title: "Venue",
    category: "Conditions & venue",
    description: "Confirms whether the game is being played at the home team's venue, the away team's, or a neutral venue.",
    dataFields: [{ name: "Type", type: "enum|null", meaning: "Venue type.", enumValues: ["home", "away", "neutral"] }],
    autoConfirmed: true,
  }),

  // ---- Data quality & meta -----------------------------------------
  A({
    action: "connected",
    title: "Connected",
    category: "Data quality & meta",
    description: "A reporter/analyst connection has been established.",
    dataFields: [{ name: "ConnectionType", type: "enum", meaning: "Type of user that connected.", enumValues: ["reporter", "analyst"] }],
  }),
  A({
    action: "disconnected",
    title: "Disconnected",
    category: "Data quality & meta",
    description: "A reporter/analyst connection has been terminated.",
    dataFields: [{ name: "ConnectionType", type: "enum", meaning: "Type of user that disconnected.", enumValues: ["reporter", "analyst"] }],
  }),
  A({
    action: "coverage_update",
    title: "Coverage Update",
    category: "Data quality & meta",
    description: "Updates how the match is covered (CoverageType / CoverageSecondaryData in the envelope).",
    dataFields: [],
  }),
  A({
    action: "comment",
    title: "Comment",
    category: "Data quality & meta",
    description: "A message sent by the reporter — pre-made messages or custom text.",
    dataFields: [{ name: "Text", type: "string", meaning: "The comment text (see example)." }],
    autoConfirmed: true,
  }),
  A({
    action: "action_amend",
    title: "Action Amend",
    category: "Data quality & meta",
    description:
      "Amends an action that was previously sent. The Id matches the action to amend; the Action name matches its type. Previous is the prior payload, New contains the replacement values — the payload varies with the amended action (Goal amends carry GoalType/PlayerId, Shot amends carry Outcome, Substitution amends carry PlayerIn/OutId, etc.).",
    dataFields: [
      { name: "Action", type: "string", meaning: "The action type being amended (e.g. \"goal\")." },
      { name: "Previous", type: "object", meaning: "The previous payload for that action." },
      { name: "New", type: "object", meaning: "The new payload replacing it." },
    ],
  }),
  A({
    action: "action_discarded",
    title: "Action Discarded",
    category: "Data quality & meta",
    description: "Discards a previously added action — the one whose Id matches the Id field. E.g. a possible goal that VAR chalked off.",
    dataFields: [],
    autoConfirmed: true,
  }),
  A({
    action: "unreliable_corners",
    title: "Unreliable Corners",
    category: "Data quality & meta",
    description: "The corner counts for both teams may be unreliable — being verified.",
    dataFields: [],
    autoConfirmed: true,
  }),
  A({
    action: "unreliable_yellow_cards",
    title: "Unreliable Yellow Cards",
    category: "Data quality & meta",
    description: "The yellow/red card counts for both teams may be unreliable — being verified.",
    dataFields: [],
    autoConfirmed: true,
  }),
  A({
    action: "suspend",
    title: "Suspend",
    category: "Data quality & meta",
    description:
      "Sets the game to unreliable (and back to reliable) due to serious unforeseen situations with coverage or stats. If no suspend was sent, Reliable is assumed.",
    dataFields: [{ name: "Reliable", type: "boolean|null", meaning: "True if the match information is reliable." }],
    observed: false,
    autoConfirmed: true,
  }),
];

/* ------------------------------------------------------------------ */
/* Real examples                                                       */
/* ------------------------------------------------------------------ */

const EXAMPLES = rawExamples as Record<string, RawRecord>;

/** A real captured record for the action, if one was observed. */
export function realExample(action: string): RawRecord | null {
  return EXAMPLES[action] ?? null;
}

export const ACTION_BY_ID: Record<string, ActionSpec> = Object.fromEntries(ACTIONS.map((a) => [a.action, a]));

/**
 * Category → accent color. Derived from the app's brand tokens; validated with
 * the dataviz palette checker (chroma + contrast pass; CVD 9.0 sits in the
 * labeled-floor band — every use of these colors carries the action name text,
 * so identity is never color-alone).
 */
export const CATEGORY_COLORS: Record<Category, string> = {
  "Match flow": "#c7f24d",
  Scoring: "#ff9f43",
  "Set pieces & play": "#4aa3ff",
  Possession: "#3fd68c",
  "Discipline & VAR": "#ff6b6b",
  "Players & lineups": "#c792ea",
  "Conditions & venue": "#35c5dd",
  "Data quality & meta": "#ffd24a",
};

/** One-line human summary for a raw record (timeline rows). */
export function summarize(r: RawRecord): string {
  const d = (r.Data ?? {}) as Record<string, unknown>;
  switch (r.Action) {
    case "goal":
      return `GOAL${d.GoalType ? ` (${d.GoalType})` : ""}${d.PlayerId ? ` · player ${d.PlayerId}` : ""} → ${r.Score?.Participant1?.Total?.Goals ?? 0}-${r.Score?.Participant2?.Total?.Goals ?? 0}`;
    case "shot":
      return `Shot${d.Outcome ? ` · ${d.Outcome}` : ""}`;
    case "free_kick":
      return `Free kick${d.FreeKickType ? ` · ${d.FreeKickType}` : ""}`;
    case "throw_in":
      return `Throw-in${d.ThrowInType ? ` · ${d.ThrowInType}` : ""}`;
    case "penalty_outcome":
      return `Penalty ${d.Outcome ?? "outcome pending"}`;
    case "status":
      return `Status → ${decodeStatus((d.StatusId as number) ?? r.StatusId)}`;
    case "additional_time":
      return d.Minutes != null ? `+${d.Minutes} min added` : "Additional time";
    case "substitution":
      return `Sub · in ${d.PlayerInId ?? "?"} / out ${d.PlayerOutId ?? "?"}`;
    case "yellow_card":
      return `Yellow card${d.PlayerId ? ` · player ${d.PlayerId}` : ""}`;
    case "red_card":
      return `Red card${d.PlayerId ? ` · player ${d.PlayerId}` : ""}`;
    case "var":
      return `VAR review${d.Type ? ` · ${d.Type}` : ""}`;
    case "var_end":
      return `VAR ended${d.Outcome ? ` · ${d.Outcome}` : ""}`;
    case "possible":
      return `Possible: ${["Goal", "Corner", "Penalty"].filter((k) => d[k]).join(", ") || "—"}`;
    case "jersey":
      return `Jersey · ${d.Color ?? "?"}`;
    case "weather":
    case "pitch":
      return `${r.Action === "weather" ? "Weather" : "Pitch"} · ${Array.isArray(d.Conditions) ? (d.Conditions as unknown[]).join(", ") : "—"}`;
    case "venue":
      return `Venue · ${d.Type ?? "?"}`;
    case "action_amend":
      return `Amend → ${d.Action ?? "?"}`;
    case "comment":
      return typeof d.Text === "string" ? `"${(d.Text as string).slice(0, 60)}"` : "Reporter comment";
    default: {
      const spec = ACTION_BY_ID[r.Action ?? ""];
      return spec?.title ?? r.Action ?? "record";
    }
  }
}
