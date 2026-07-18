import assert from "node:assert/strict";
import test from "node:test";

import {
  __resetRoomsForTests,
  buildView,
  getRoomRuntime,
  joinOfficialHubForFixture,
} from "../lib/store/rooms.ts";

const fixture = {
  id: "18237038",
  competition: "World Cup",
  stage: "Semi-final",
  kickoff: "2026-07-14T19:00:00.000Z",
  venue: "—",
  status: "scheduled",
  home: { id: "1530", name: "France", code: "FRA", flag: "🇫🇷", rating: 75 },
  away: { id: "1535", name: "Spain", code: "ESP", flag: "🇪🇸", rating: 75 },
};

test("Official Match Hub is concurrency-safe and wallet-idempotent", async () => {
  __resetRoomsForTests();
  const [first, retry, friend] = await Promise.all([
    joinOfficialHubForFixture(fixture, { name: "Anurag", walletPubkey: "wallet-a" }, { autoStart: false }),
    joinOfficialHubForFixture(fixture, { name: "Anurag", walletPubkey: "wallet-a" }, { autoStart: false }),
    joinOfficialHubForFixture(fixture, { name: "Friend", walletPubkey: "wallet-b" }, { autoStart: false }),
  ]);

  assert.equal(first.roomId, retry.roomId);
  assert.equal(first.roomId, friend.roomId);
  assert.equal(first.memberId, retry.memberId);
  assert.notEqual(first.memberId, friend.memberId);

  const room = getRoomRuntime(first.roomId);
  assert.ok(room);
  const view = buildView(room);
  assert.equal(view.kind, "official");
  assert.equal(view.autoManaged, true);
  assert.equal(view.lifecycle, "pregame");
  assert.equal(view.status, "lobby");
  assert.equal(view.prompts.length, 0);
  assert.equal(view.members.length, 2);
  assert.ok(view.members.every((m) => m.isHost === false));
});
