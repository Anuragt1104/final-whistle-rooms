import assert from "node:assert/strict";
import test from "node:test";

import {
  __resetRoomsForTests,
  __settlePromptForTests,
  getRoomRuntime,
  joinOfficialHubForFixture,
  submitPrediction,
} from "../lib/store/rooms.ts";
import { inventoryOf, __resetCardEconomyForTests } from "../lib/cards/economy.ts";
import { validateRewrite } from "../lib/game/prompt-writer.ts";

const fixture = {
  id: "18193785",
  competition: "World Cup",
  stage: "Group",
  kickoff: "2026-07-01T19:00:00.000Z",
  venue: "—",
  status: "finished",
  home: { id: "1", name: "USA", code: "USA", flag: "🇺🇸", rating: 70 },
  away: { id: "2", name: "Belgium", code: "BEL", flag: "🇧🇪", rating: 78 },
};

function makePrompt() {
  return {
    id: "sw_test_1",
    question: "Who wins the next corner?",
    options: [
      { key: "home", label: "USA" },
      { key: "away", label: "Belgium" },
    ],
    resolver: { kind: "next-corner-side" },
    basePoints: 105,
    locksAtMinute: 30,
    status: "open",
    createdAt: Date.now(),
    openedAtMinute: 25,
    openedAtSeq: 900,
  };
}

test("finished fixtures share ONE global Official Hub (replay room)", async () => {
  __resetRoomsForTests();
  const a = await joinOfficialHubForFixture(fixture, { name: "A", walletPubkey: "w-a" }, { autoStart: false });
  const b = await joinOfficialHubForFixture(fixture, { name: "B", walletPubkey: "w-b" }, { autoStart: false });
  assert.equal(a.roomId, b.roomId);
  const rt = getRoomRuntime(a.roomId);
  assert.equal(rt.kind, "official");
  assert.equal(rt.members.size, 2);
});

test("moments + packs mint ONLY for correct answers", async () => {
  __resetRoomsForTests();
  __resetCardEconomyForTests();
  const right = await joinOfficialHubForFixture(fixture, { name: "Right", walletPubkey: "fan-right" }, { autoStart: false });
  const wrong = await joinOfficialHubForFixture(fixture, { name: "Wrong", walletPubkey: "fan-wrong" }, { autoStart: false });
  await joinOfficialHubForFixture(fixture, { name: "Silent", walletPubkey: "fan-silent" }, { autoStart: false });
  const rt = getRoomRuntime(right.roomId);

  const prompt = makePrompt();
  rt.prompts.set(prompt.id, prompt);
  rt.recentMintables.push({
    event: { kind: "goal", side: "away", minute: 28, seq: 990, label: "Goal — Belgium" },
    oddsSandwich: {
      before: { home: 0.3, draw: 0.3, away: 0.4 },
      after: { home: 0.2, draw: 0.25, away: 0.55 },
    },
    priorHomeProb: 0.3,
  });

  assert.ok(submitPrediction(rt.id, right.memberId, prompt.id, "away").ok);
  assert.ok(submitPrediction(rt.id, wrong.memberId, prompt.id, "home").ok);

  __settlePromptForTests(rt, prompt, "away");

  const invRight = inventoryOf("fan-right");
  const invWrong = inventoryOf("fan-wrong");
  const invSilent = inventoryOf("fan-silent");
  assert.equal(invRight.moments.length, 1, "correct answer earns exactly one Moment");
  assert.equal(invRight.packs.length, 1, "correct answer earns exactly one pack");
  assert.equal(invRight.moments[0].kind, "goal");
  assert.equal(invWrong.moments.length, 0, "wrong answer earns nothing");
  assert.equal(invWrong.packs.length, 0);
  assert.equal(invSilent.moments.length, 0, "unanswered earns nothing");
  assert.equal(invSilent.packs.length, 0);
  // and the drop is attributed to the right member
  assert.equal(rt.momentDrops.length, 1);
  assert.equal(rt.momentDrops[0].memberId, right.memberId);
  assert.equal(rt.momentDrops[0].calledIt, true);
  assert.equal(rt.momentDrops[0].promptId, prompt.id);
  assert.equal(rt.momentDrops[0].promptQuestion, prompt.question);
  assert.equal(rt.momentDrops[0].answerLabel, "Belgium");
  assert.equal(rt.momentDrops[0].proof?.sourceEventId, rt.momentDrops[0].sourceEventId);
});

test("correct answer still earns a fallback Moment with no recent event", async () => {
  __resetRoomsForTests();
  __resetCardEconomyForTests();
  const a = await joinOfficialHubForFixture(fixture, { name: "A", walletPubkey: "fan-a2" }, { autoStart: false });
  const rt = getRoomRuntime(a.roomId);
  const prompt = makePrompt();
  rt.prompts.set(prompt.id, prompt);
  assert.ok(submitPrediction(rt.id, a.memberId, prompt.id, "home").ok);
  __settlePromptForTests(rt, prompt, "home");
  const inv = inventoryOf("fan-a2");
  assert.equal(inv.moments.length, 1);
  assert.equal(inv.moments[0].kind, "market-swing");
  assert.equal(inv.moments[0].sourceEventId, `call:${prompt.id}`);
});

test("correct-call reward is windowed and retry-idempotent", async () => {
  __resetRoomsForTests();
  __resetCardEconomyForTests();
  const joined = await joinOfficialHubForFixture(fixture, { name: "A", walletPubkey: "fan-window" }, { autoStart: false });
  const rt = getRoomRuntime(joined.roomId);
  const prompt = makePrompt();
  rt.prompts.set(prompt.id, prompt);
  rt.recentMintables.push({ event: { kind: "goal", side: "home", minute: 20, seq: 899, sourceEventId: "old", label: "Old goal" }, oddsSandwich: { before: { home: .3, draw: .4, away: .3 }, after: { home: .4, draw: .3, away: .3 } }, priorHomeProb: .3 });
  assert.ok(submitPrediction(rt.id, joined.memberId, prompt.id, "home").ok);
  __settlePromptForTests(rt, prompt, "home");
  __settlePromptForTests(rt, prompt, "home");
  const inv = inventoryOf("fan-window");
  assert.equal(inv.moments.length, 1);
  assert.equal(inv.packs.length, 1);
  assert.equal(inv.moments[0].sourceEventId, `call:${prompt.id}`);
  assert.equal(rt.momentDrops.length, 1);
});

test("prompt-writer validator rejects malformed LLM output", () => {
  const prompt = makePrompt();
  // valid rewrite passes
  const ok = validateRewrite(prompt, {
    question: "Corner pressure builds at 28' — who forces the next one?",
    options: [
      { key: "home", label: "USA keep pushing" },
      { key: "away", label: "Belgium counter" },
    ],
  });
  assert.ok(ok);
  assert.equal(ok.labels.get("away"), "Belgium counter");
  // wrong keys rejected
  assert.equal(
    validateRewrite(prompt, {
      question: "Who forces the next corner in this game?",
      options: [
        { key: "hom", label: "USA" },
        { key: "away", label: "BEL" },
      ],
    }),
    null,
  );
  // missing option rejected
  assert.equal(
    validateRewrite(prompt, { question: "Who forces the next corner now?", options: [{ key: "home", label: "USA" }] }),
    null,
  );
  // over-long label rejected
  assert.equal(
    validateRewrite(prompt, {
      question: "Who forces the next corner in this game?",
      options: [
        { key: "home", label: "x".repeat(50) },
        { key: "away", label: "BEL" },
      ],
    }),
    null,
  );
  // garbage rejected
  assert.equal(validateRewrite(prompt, null), null);
  assert.equal(validateRewrite(prompt, { question: "short?" }), null);
});
