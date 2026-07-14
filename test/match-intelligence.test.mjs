import assert from "node:assert/strict";
import test from "node:test";

import {
  aggregateTournamentLeaders,
  normalizeMatchRecords,
} from "../lib/txline/match-intelligence.ts";

const fixture = {
  id: "18222446",
  competition: "World Cup",
  stage: "Round of 16",
  kickoff: "2026-07-03T19:00:00.000Z",
  venue: "—",
  status: "finished",
  home: { id: "1489", name: "Argentina", code: "ARG", flag: "🇦🇷", rating: 75 },
  away: { id: "1558", name: "Switzerland", code: "SWI", flag: "🇨🇭", rating: 75 },
};

const player = (normativeId, name, positionId, number, starter = true) => ({
  fixturePlayerId: normativeId + 100000,
  statusId: 0,
  positionId,
  unitId: 0,
  rosterNumber: String(number),
  starter,
  player: {
    normativeId,
    preferredName: name,
    country: "Argentina",
    dateOfBirth: "2000-01-01",
  },
});

const argentina = [
  player(1, "Martinez, Damian Emiliano", 34, 23),
  player(2, "Molina, Nahuel", 35, 26),
  player(3, "Romero, Cristian", 35, 13),
  player(4, "Martinez, Lisandro", 35, 6),
  player(5, "Tagliafico, Nicolas", 35, 3),
  player(6, "De Paul, Rodrigo", 36, 7),
  player(7, "Fernandez, Enzo", 36, 24),
  player(8, "Mac Allister, Alexis", 36, 20),
  player(9, "Messi, Lionel", 37, 10),
  player(10, "Alvarez, Julian", 37, 9),
  player(11, "Martinez, Lautaro Javier", 37, 22),
  player(12, "Almada, Thiago", 37, 16, false),
];

const switzerland = Array.from({ length: 11 }, (_, i) =>
  player(101 + i, `Swiss, Player ${i + 1}`, i === 0 ? 34 : i < 5 ? 35 : i < 9 ? 36 : 37, i + 1),
);

const records = [
  {
    Action: "lineups",
    Id: 50,
    Seq: 50,
    Ts: 1_000,
    Confirmed: true,
    Participant1IsHome: true,
    Lineups: [
      { normativeId: 1489, preferredName: "Argentina", lineups: argentina },
      { normativeId: 1558, preferredName: "Switzerland", lineups: switzerland },
    ],
  },
  {
    Action: "goal",
    Id: 90,
    Seq: 90,
    Ts: 2_000,
    Confirmed: true,
    Participant: 1,
    Participant1IsHome: true,
    Clock: { Seconds: 9 * 60 },
    Data: { PlayerId: 10 },
  },
  {
    Action: "red_card",
    Id: 91,
    Seq: 91,
    Ts: 2_100,
    Confirmed: true,
    Participant: 2,
    Participant1IsHome: true,
    Clock: { Seconds: 52 * 60 },
    Data: { PlayerId: 101 },
  },
  {
    Action: "action_amend",
    Id: 92,
    Seq: 92,
    Ts: 2_200,
    Confirmed: true,
    Data: { ActionId: 91, New: { PlayerId: 102 } },
  },
  {
    Action: "yellow_card",
    Id: 93,
    Seq: 93,
    Ts: 2_300,
    Confirmed: true,
    Participant: 1,
    Participant1IsHome: true,
    Clock: { Seconds: 61 * 60 },
    Data: { PlayerId: 12 },
  },
  {
    Action: "action_discarded",
    Id: 94,
    Seq: 94,
    Ts: 2_400,
    Confirmed: true,
    Data: { ActionId: 93 },
  },
  {
    Action: "game_finalised",
    Id: 1306,
    Seq: 1306,
    Ts: 3_000,
    Confirmed: true,
    PlayerStats: {
      Participant1: {
        10: { goals: 1 },
        11: { goals: 1, yellowCards: 1 },
        8: { goals: 1 },
      },
      Participant2: { 102: { goals: 1, redCards: 1 } },
    },
  },
];

test("TxLINE intelligence returns confirmed starters, real player totals and corrected events", () => {
  const view = normalizeMatchRecords(fixture, records);

  assert.equal(view.lineupStatus, "confirmed");
  assert.equal(view.teams.home.players.filter((p) => p.starter).length, 11);
  assert.equal(view.teams.away.players.filter((p) => p.starter).length, 11);
  assert.equal(view.teams.home.formation, "4-3-3");

  const alvarez = view.teams.home.players.find((p) => p.id === "10");
  assert.equal(alvarez.name, "Julian Alvarez");
  assert.equal(alvarez.stats.goals, 1);

  assert.equal(view.events.filter((e) => e.kind === "goal").length, 1);
  assert.equal(view.events.find((e) => e.kind === "goal").playerName, "Julian Alvarez");
  assert.equal(view.events.find((e) => e.kind === "red").playerId, "102");
  assert.equal(view.events.some((e) => e.kind === "yellow"), false);
});

test("leader aggregation uses authoritative PlayerStats instead of generated ratings", () => {
  const view = normalizeMatchRecords(fixture, records);
  const leaders = aggregateTournamentLeaders([view]);

  assert.deepEqual(
    leaders.goals.slice(0, 3).map((p) => [p.name, p.value]),
    [
      ["Alexis Mac Allister", 1],
      ["Julian Alvarez", 1],
      ["Lautaro Javier Martinez", 1],
    ],
  );
  assert.equal(leaders.redCards[0].name, "Player 2 Swiss");
});

