import * as React from "react";
import { ScoreRail } from "final-whistle-rooms";
import { Frame, room, fixture, score } from "./mocks";
import { GamePhase } from "@/lib/txline/types";

// The live match header: teams, score, clock/phase, mini stat strip, momentum
// meter and win-chance bar. Swept across the match-status axis it cares about.
export function Live() {
  return (
    <Frame>
      <ScoreRail room={room} />
    </Frame>
  );
}

export function HalfTime() {
  return (
    <Frame>
      <ScoreRail
        room={{
          ...room,
          score: { ...score, minute: 45, phase: GamePhase.HalfTime },
        }}
      />
    </Frame>
  );
}

export function FullTime() {
  return (
    <Frame>
      <ScoreRail
        room={{
          ...room,
          status: "finished",
          momentum: 12,
          win: { home: 100, draw: 0, away: 0 },
          score: { ...score, minute: 90, phase: GamePhase.FullTime, goals: { home: 2, away: 1 } },
        }}
      />
    </Frame>
  );
}

export function PreMatch() {
  return (
    <Frame>
      <ScoreRail
        room={{
          ...room,
          status: "lobby",
          momentum: 0,
          win: { home: 45, draw: 28, away: 27 },
          score: null,
          fixture: { ...fixture, status: "scheduled" },
        }}
      />
    </Frame>
  );
}
