import assert from "node:assert/strict";
import test from "node:test";

import {
  canonicalizeHistoricalScores,
  eventsForReplayFrame,
  interpolateReplayCheckpoint,
  reconcileReplayScore,
  shouldPauseBeforeReplayFrame,
} from "../lib/txline/historical.ts";
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
    // Real TxLINE logs can label a reset with the surrounding ET phase rather
    // than PreMatch. It is still a clock-zero reset and must never become the
    // guided replay's start frame.
    snap(31, 0, GamePhase.ExtraTimeHalfTime, 1, 1),
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
  assert.ok(result.slice(1).every((s) => s.minute > 0 || s.clockSeconds > 0));
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

test("guided checkpoints consume every frame at an event minute before pausing", () => {
  assert.equal(shouldPauseBeforeReplayFrame(9, 9, 9), false);
  assert.equal(shouldPauseBeforeReplayFrame(9, 10, 9), true);
  assert.equal(shouldPauseBeforeReplayFrame(8, 10, 9), true);
  assert.equal(shouldPauseBeforeReplayFrame(120, 123, 120), true);
  const interpolated = interpolateReplayCheckpoint(
    snap(80, 8, GamePhase.FirstHalf, 0, 0, true),
    9,
  );
  assert.equal(interpolated.minute, 9);
  assert.equal(interpolated.clockSeconds, 540);
  assert.equal(interpolated.updatedAt, 1_080_000);
  assert.equal(interpolated.ts, new Date(1_080_000).toISOString());
  assert.deepEqual(interpolated.goals, { home: 0, away: 0 });
});

test("confirmed actions settle at their match minute even when source sequence follows the score frame", () => {
  const red = {
    fixtureId: "18222446",
    seq: 688,
    ts: new Date().toISOString(),
    minute: 71,
    phase: GamePhase.SecondHalf,
    kind: "red",
    side: "away",
    label: "Breel Embolo",
    sourceEventId: "tx:18222446:613",
  };
  const alvarez = {
    fixtureId: "18222446",
    seq: 1203,
    ts: new Date().toISOString(),
    minute: 111,
    phase: GamePhase.ExtraTimeSecondHalf,
    kind: "goal",
    side: "home",
    label: "Julián Álvarez",
    sourceEventId: "tx:18222446:1073",
  };
  assert.deepEqual(eventsForReplayFrame([red, alvarez], new Set(), 71), [red]);
  const laterRecordedEarlierAction = {
    ...red,
    seq: 1300,
    minute: 110,
    kind: "substitution",
    sourceEventId: "tx:18222446:sub-late-record",
  };
  const emitted = new Set([laterRecordedEarlierAction.sourceEventId]);
  assert.deepEqual(
    eventsForReplayFrame([laterRecordedEarlierAction, alvarez], emitted, 111),
    [alvarez],
  );

  const score = {
    ...snap(1199, 111, GamePhase.ExtraTimeSecondHalf, 1, 1, true),
    red: pair(0, 1),
  };
  const reconciled = reconcileReplayScore(score, [
    { ...alvarez, seq: 118, minute: 9 },
    { ...alvarez, seq: 663, minute: 66, side: "away" },
    alvarez,
  ]);
  assert.deepEqual(reconciled.goals, { home: 2, away: 1 });
});
