import type { SwingPrompt } from "@/lib/game/nextswing";
import type { ReplayStateView } from "@/lib/store/types";

export interface ShowcaseReplayBeat {
  minute: number;
  purpose: "call" | "event" | "full-time";
}

export const SHOWCASE_REPLAY_BEATS: readonly ShowcaseReplayBeat[] = [
  { minute: 7, purpose: "call" },
  { minute: 9, purpose: "event" },
  { minute: 68, purpose: "call" },
  { minute: 71, purpose: "event" },
  { minute: 108, purpose: "call" },
  { minute: 111, purpose: "event" },
  { minute: 120, purpose: "full-time" },
] as const;

export function initialShowcaseReplayState(): ReplayStateView {
  return {
    active: true,
    paused: true,
    currentMinute: 0,
    totalMinutes: 120,
    speed: 1,
    mode: "showcase",
    beat: 0,
    nextBeatMinute: SHOWCASE_REPLAY_BEATS[0].minute,
    awaitingAction: true,
  };
}

export function advanceShowcaseBeat(state: ReplayStateView): {
  state: ReplayStateView;
  targetMinute: number;
} {
  const beat = Math.max(0, state.beat ?? 0);
  const target = SHOWCASE_REPLAY_BEATS[beat]?.minute;
  if (target == null) {
    return {
      state: { ...state, paused: true, awaitingAction: false, nextBeatMinute: undefined },
      targetMinute: state.currentMinute,
    };
  }
  return {
    state: {
      ...state,
      paused: false,
      awaitingAction: false,
      nextBeatMinute: target,
    },
    targetMinute: target,
  };
}

export function reachShowcaseBeat(state: ReplayStateView, reachedMinute: number): ReplayStateView {
  const beat = Math.max(0, state.beat ?? 0);
  const target = SHOWCASE_REPLAY_BEATS[beat]?.minute;
  if (target == null || reachedMinute < target) return state;
  const nextBeat = beat + 1;
  const nextMinute = SHOWCASE_REPLAY_BEATS[nextBeat]?.minute;
  return {
    ...state,
    paused: true,
    currentMinute: reachedMinute,
    beat: nextBeat,
    nextBeatMinute: nextMinute,
    awaitingAction: nextMinute != null,
  };
}

type ShowcaseFixture = {
  id: string;
  home: { name: string; code: string };
  away: { name: string; code: string };
};

/**
 * The three recording prompts are deterministic rules over information visible
 * at the checkpoint. Their wording and deadlines do not encode the outcome.
 */
export function createShowcasePrompt(
  fixture: ShowcaseFixture,
  minute: number,
  openedAtSeq: number,
): SwingPrompt | null {
  const common = {
    id: `showcase:${fixture.id}:${minute}`,
    basePoints: 180,
    locksAtMinute: minute + 1,
    status: "open" as const,
    createdAt: Date.now(),
    openedAtMinute: minute,
    openedAtSeq,
    lane: "main" as const,
    category: "showcase",
    ruleId: `verified-showcase-${minute}`,
    reason: "Guided decision point from the verified historical tape.",
    urgency: 95,
    openedClockSec: minute * 60,
    answerClosesAt: (minute + 1) * 60,
    feedFreshness: "historical",
    sourceAttribution: "TxLINE historical · known state only",
    rewardPreview: "Correct Call · one Moment + one sealed Pack",
  };

  if (minute === 7 || minute === 108) {
    const deadline = minute === 7 ? 15 : 115;
    return {
      ...common,
      question: `Who scores next before ${deadline}'?`,
      options: [
        { key: "home", label: fixture.home.name },
        { key: "away", label: fixture.away.name },
        { key: "none", label: "No goal before the deadline" },
      ],
      resolver: { kind: "next-goal-before", minute: deadline },
      resolutionDeadlineClockSec: deadline * 60,
    };
  }
  if (minute === 68) {
    return {
      ...common,
      question: "Which team receives the next card?",
      options: [
        { key: "home", label: fixture.home.name },
        { key: "away", label: fixture.away.name },
      ],
      resolver: { kind: "next-card-side" },
      resolutionDeadlineClockSec: 75 * 60,
    };
  }
  return null;
}
