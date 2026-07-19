import assert from "node:assert/strict";
import test from "node:test";

import {
  __resetRoomsForTests,
  buildView,
  controlReplay,
  getRoomRuntime,
  joinOfficialHubForFixture,
  postChat,
} from "../lib/store/rooms.ts";

const fixture = {
  id: "hub-seams-fx-1",
  competition: "World Cup",
  stage: "Group",
  kickoff: "2026-06-14T19:00:00.000Z",
  venue: "—",
  status: "scheduled",
  home: { id: "1530", name: "France", code: "FRA", flag: "🇫🇷", rating: 75 },
  away: { id: "1535", name: "Spain", code: "ESP", flag: "🇪🇸", rating: 75 },
};

test("buildView exposes revision, reactionTally, and replayState seams", async () => {
  __resetRoomsForTests();
  const { roomId, memberId } = await joinOfficialHubForFixture(
    fixture,
    { name: "Anurag", walletPubkey: "wallet-hub-seams" },
    { autoStart: false },
  );
  const rt = getRoomRuntime(roomId);
  assert.ok(rt);

  postChat(roomId, memberId, "🔥", "reaction");
  postChat(roomId, memberId, "🔥", "reaction");
  postChat(roomId, memberId, "👏", "reaction");

  const first = buildView(rt);
  assert.ok(first.revision >= 1);
  assert.equal(first.reactionTally["🔥"], 2);
  assert.equal(first.reactionTally["👏"], 1);
  assert.equal(first.replayState, undefined);

  const second = buildView(rt);
  assert.ok(second.revision > first.revision);

  const replay = controlReplay(roomId, { action: "pause" });
  assert.ok(replay.error || replay.ok !== undefined);
});

test("controlReplay is exported for hub dock", () => {
  assert.equal(typeof controlReplay, "function");
});
