import * as React from "react";
import { Leaderboard } from "final-whistle-rooms";
import { Frame, room, members } from "./mocks";

// Room standings: rank, avatar, name, drafted-side flag, HOST/YOU chips,
// correct-call count, best streak, points and live streak flame.
export function Standings() {
  return (
    <Frame>
      <Leaderboard room={room} meId="m3" />
    </Frame>
  );
}

export function JustStarted() {
  return (
    <Frame>
      <Leaderboard
        room={{
          ...room,
          members: members.map((m) => ({ ...m, points: 0, streak: 0, bestStreak: 0, correct: 0 })),
        }}
        meId="m1"
      />
    </Frame>
  );
}

export function SoloHost() {
  return (
    <Frame>
      <Leaderboard
        room={{ ...room, members: [members[0]] }}
        meId="m1"
      />
    </Frame>
  );
}
