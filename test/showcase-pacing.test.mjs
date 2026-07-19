import assert from "node:assert/strict";
import test from "node:test";

import {
  SHOWCASE_REPLAY_BEATS,
  advanceShowcaseBeat,
  createShowcasePrompt,
  initialShowcaseReplayState,
  reachShowcaseBeat,
} from "../lib/showcase/replay.ts";

const fixture = {
  id: "18222446",
  home: { name: "Argentina", code: "ARG" },
  away: { name: "Switzerland", code: "SUI" },
};

test("guided replay exposes only the next ordered checkpoint", () => {
  const initial = initialShowcaseReplayState();
  assert.equal(initial.currentMinute, 0);
  assert.equal(initial.nextBeatMinute, 7);
  assert.equal(initial.awaitingAction, true);

  const moving = advanceShowcaseBeat(initial);
  assert.equal(moving.targetMinute, 7);
  assert.equal(moving.state.awaitingAction, false);
  assert.equal(moving.state.nextBeatMinute, 7);

  const reached = reachShowcaseBeat(moving.state, 7);
  assert.equal(reached.beat, 1);
  assert.equal(reached.currentMinute, 7);
  assert.equal(reached.nextBeatMinute, 9);
  assert.equal(reached.awaitingAction, true);

  // A stale callback cannot skip forward or reveal the 68' checkpoint.
  const stale = reachShowcaseBeat(reached, 6);
  assert.deepEqual(stale, reached);
  assert.equal(SHOWCASE_REPLAY_BEATS.map((beat) => beat.minute).join(","), "7,9,68,71,108,111,120");
});

test("recording Calls are deterministic, plain-language and source labelled", () => {
  const first = createShowcasePrompt(fixture, 7, 113);
  assert.equal(first?.question, "Who scores next before 15'?");
  assert.deepEqual(first?.options.map((option) => option.key), ["home", "away", "none"]);
  assert.deepEqual(first?.resolver, { kind: "next-goal-before", minute: 15 });

  const second = createShowcasePrompt(fixture, 68, 1040);
  assert.equal(second?.question, "Which team receives the next card?");
  assert.deepEqual(second?.resolver, { kind: "next-card-side" });

  const third = createShowcasePrompt(fixture, 108, 1068);
  assert.equal(third?.question, "Who scores next before 115'?");
  assert.deepEqual(third?.resolver, { kind: "next-goal-before", minute: 115 });
  for (const prompt of [first, second, third]) {
    assert.equal(prompt?.sourceAttribution, "TxLINE historical · known state only");
    assert.doesNotMatch(prompt?.question ?? "", /odds|clear by|stake|bet/i);
  }
});
