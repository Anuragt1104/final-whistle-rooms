import assert from "node:assert/strict";
import test from "node:test";

import {
  __resetRoomsForTests,
  buildView,
  getRoomRuntime,
  joinRoom,
  joinShowcaseReplayForFixture,
  submitPrediction,
  __settlePromptForTests,
} from "../lib/store/rooms.ts";
import { __resetCardEconomyForTests, inventoryOf } from "../lib/cards/economy.ts";
import { createShowcasePrompt } from "../lib/showcase/replay.ts";

const fixture = {
  id: "18222446",
  competition: "World Cup",
  stage: "Round of 32",
  kickoff: "2026-07-04T19:00:00.000Z",
  venue: "—",
  status: "finished",
  score: {
    home: 3,
    away: 1,
    minute: 120,
    clockSeconds: 7200,
    running: false,
  },
  home: { id: "1529", name: "Argentina", code: "ARG", flag: "", rating: 75 },
  away: { id: "1540", name: "Switzerland", code: "SUI", flag: "", rating: 75 },
};

test("showcase replay is idempotent per fan while keeping judges isolated", async () => {
  __resetRoomsForTests();

  const [first, retry, otherJudge] = await Promise.all([
    joinShowcaseReplayForFixture(
      fixture,
      { name: "Anurag", walletPubkey: "wallet-presenter" },
      { autoStart: false, actionId: "start-1" },
    ),
    joinShowcaseReplayForFixture(
      fixture,
      { name: "Anurag", walletPubkey: "wallet-presenter" },
      { autoStart: false, actionId: "start-1" },
    ),
    joinShowcaseReplayForFixture(
      fixture,
      { name: "Judge", walletPubkey: "wallet-judge" },
      { autoStart: false, actionId: "judge-start" },
    ),
  ]);

  assert.equal(first.roomId, retry.roomId);
  assert.equal(first.memberId, retry.memberId);
  assert.notEqual(first.roomId, otherJudge.roomId);

  const runtime = getRoomRuntime(first.roomId);
  assert.ok(runtime);
  const view = buildView(runtime);
  assert.equal(view.kind, "party");
  assert.equal(view.replay, true);
  assert.equal(view.replayState?.mode, "showcase");
  assert.equal(view.replayState?.beat, 0);
  assert.equal(view.replayState?.nextBeatMinute, 7);
  assert.equal(view.replayState?.awaitingAction, true);
  assert.match(view.name, /verified replay/i);
});

test("presenter's invite code joins a second identity to the same showcase", async () => {
  __resetRoomsForTests();
  const owner = await joinShowcaseReplayForFixture(
    fixture,
    { name: "Anurag", walletPubkey: "wallet-owner" },
    { autoStart: false, actionId: "owner-start" },
  );
  const runtime = getRoomRuntime(owner.roomId);
  assert.ok(runtime);

  const friend = joinRoom(owner.roomId, {
    name: "Friend",
    walletPubkey: "wallet-friend",
  });
  assert.ok(!("error" in friend));
  assert.notEqual(friend.memberId, owner.memberId);

  const view = buildView(runtime);
  assert.equal(view.members.length, 2);
  assert.equal(view.code.length, 6);
  assert.equal(view.replayState?.mode, "showcase");
});

test("three recording Calls award exactly three Moments and three linked Packs", async () => {
  __resetRoomsForTests();
  __resetCardEconomyForTests();
  const joined = await joinShowcaseReplayForFixture(
    fixture,
    { name: "Anurag", walletPubkey: "showcase-rewards" },
    { autoStart: false, actionId: "reward-run" },
  );
  const runtime = getRoomRuntime(joined.roomId);
  assert.ok(runtime);

  const calls = [
    { minute: 7, winning: "home", event: { kind: "goal", side: "home", minute: 9, seq: 113, label: "Alexis Mac Allister", sourceEventId: "tx:18222446:113", playerName: "Alexis Mac Allister", teamCode: "ARG" } },
    { minute: 68, winning: "away", event: { kind: "red", side: "away", minute: 71, seq: 1040, label: "Breel Embolo", sourceEventId: "tx:18222446:1040", playerName: "Breel Embolo", teamCode: "SUI" } },
    { minute: 108, winning: "home", event: { kind: "goal", side: "home", minute: 111, seq: 1073, label: "Julián Álvarez", sourceEventId: "tx:18222446:1073", playerName: "Julián Álvarez", teamCode: "ARG" } },
  ];
  for (const call of calls) {
    const prompt = createShowcasePrompt(fixture, call.minute, call.event.seq - 1);
    assert.ok(prompt);
    runtime.prompts.set(prompt.id, prompt);
    runtime.recentMintables.push({
      event: call.event,
      oddsSandwich: {
        before: { home: 0.4, draw: 0.3, away: 0.3 },
        after: { home: 0.55, draw: 0.25, away: 0.2 },
      },
      priorHomeProb: 0.4,
    });
    assert.equal(submitPrediction(runtime.id, joined.memberId, prompt.id, call.winning).ok, true);
    __settlePromptForTests(runtime, prompt, call.winning);
    __settlePromptForTests(runtime, prompt, call.winning);
  }

  const inventory = inventoryOf("showcase-rewards");
  assert.equal(inventory.moments.length, 3);
  assert.equal(inventory.packs.length, 3);
  assert.equal(runtime.momentDrops.length, 3);
  assert.deepEqual(
    inventory.moments.map((moment) => moment.sourceEventId),
    ["tx:18222446:113", "tx:18222446:1040", "tx:18222446:1073"],
  );
  assert.ok(inventory.moments.every((moment) => moment.calledIt));
  assert.deepEqual(
    inventory.packs.map((pack) => pack.momentIds[0]),
    inventory.moments.map((moment) => moment.id),
  );
});
