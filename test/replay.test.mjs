import assert from "node:assert/strict";
import test from "node:test";

import { canonicalizeHistoricalScores } from "../lib/txline/historical.ts";
import { GamePhase } from "../lib/txline/types.ts";
import { diffScoreToEvents } from "../lib/store/rooms.ts";

const pair = (home, away) => ({ home, away });
const periods = {
  firstHalf: { goals: pair(0, 0), yellow: pair(0, 0), red: pair(0, 0), corners: pair(0, 0) },
  secondHalf: { goals: pair(0, 0), yellow: pair(0, 0), red: pair(0, 0), corners: pair(0, 0) },
};
const snap = (seq, minute, phase, home, away, running = false) => ({
  fixtureId: "18222446",
  seq,
  ts: new Date(1_000_000 + seq * 1000).toISOString(),
  updatedAt: 1_000_000 + seq * 1000,
  phase,
  minute,
  clockSeconds: minute * 60,
  running,
  goals: pair(home, away),
  yellow: pair(0, 0),
  red: pair(0, 0),
  corners: pair(0, 0),
  periods,
});

test("canonical replay ignores KO resets and provisional 1-1 FT before extra time", () => {
  const result = canonicalizeHistoricalScores([
    snap(1, 0, GamePhase.PreMatch, 0, 0),
    snap(2, 12, GamePhase.FirstHalf, 1, 0, true),
    snap(3, 0, GamePhase.PreMatch, 1, 0),
    snap(4, 90, GamePhase.FullTime, 1, 1),
    snap(5, 106, GamePhase.ExtraTimeSecondHalf, 1, 1, true),
    snap(6, 113, GamePhase.ExtraTimeSecondHalf, 2, 1, true),
    snap(7, 111, GamePhase.ExtraTimeSecondHalf, 2, 1, true),
    snap(8, 122, GamePhase.ExtraTimeSecondHalf, 3, 1, true),
    snap(9, 0, GamePhase.PreMatch, 3, 1),
  ]);

  assert.equal(result.filter((s) => s.phase === GamePhase.Finished).length, 1);
  assert.equal(result.at(-1).phase, GamePhase.Finished);
  assert.deepEqual(result.at(-1).goals, { home: 3, away: 1 });
  assert.ok(result.slice(1).every((s) => !(s.phase === GamePhase.PreMatch && s.minute === 0)));
  assert.ok(result.every((s, i) => i === 0 || s.minute >= result[i - 1].minute));
  assert.ok(result.some((s) => s.minute > 90 && s.goals.home === 1 && s.goals.away === 1));
});

test("score corrections never remint goals or cards", () => {
  const highWater = {
    goals: pair(0, 0),
    yellow: pair(0, 0),
    red: pair(0, 0),
    corners: pair(0, 0),
  };
  const events = [
    ...diffScoreToEvents(highWater, { ...snap(1, 20, GamePhase.FirstHalf, 1, 0, true), yellow: pair(1, 0) }),
    ...diffScoreToEvents(highWater, { ...snap(2, 21, GamePhase.FirstHalf, 1, 0, true), yellow: pair(0, 0) }),
    ...diffScoreToEvents(highWater, { ...snap(3, 22, GamePhase.FirstHalf, 1, 0, true), yellow: pair(1, 0) }),
    ...diffScoreToEvents(highWater, { ...snap(4, 23, GamePhase.FirstHalf, 1, 0, true), yellow: pair(2, 0) }),
  ];

  assert.equal(events.filter((e) => e.kind === "goal").length, 1);
  assert.equal(events.filter((e) => e.kind === "yellow").length, 2);
});
