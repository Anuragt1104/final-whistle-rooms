/**
 * Question Engine V2 — typed contracts for Live Calls.
 * Shared per fixture; answers/tallies stay room-member-specific.
 */
import type { SwingOption, SwingResolver } from "@/lib/game/nextswing";
import type { GamePhase, ScoreSnapshot, StatPair } from "@/lib/txline/types";
import type { WinChance } from "@/lib/engine/pulse";

export const RULE_VERSION = 1;
export const ENGINE_VERSION = "qe-v2.1";

export type QuestionLane = "main" | "quick" | "break" | "hydration";
export type QuestionCategory =
  | "next-event"
  | "scoreboard"
  | "discipline"
  | "set-piece"
  | "market"
  | "player"
  | "fan-buzz";

export type QuestionStatus =
  | "scheduled"
  | "open"
  | "locked"
  | "settled"
  | "void"
  | "corrected";

export type FeedFreshness = "waiting" | "fresh" | "stale" | "paused";

export interface QuestionOption extends SwingOption {
  points?: number;
}

export interface ResolverSpec {
  kind: SwingResolver["kind"] | string;
  payload: SwingResolver | Record<string, unknown>;
}

export interface QuestionSpec {
  id: string;
  fixtureId: string;
  ruleId: string;
  ruleVersion: number;
  lane: QuestionLane;
  category: QuestionCategory;
  question: string;
  options: QuestionOption[];
  resolver: SwingResolver;
  basePoints: number;
  reason: string;
  urgency: number;
  openedClockSec: number;
  locksAtMinute: number;
  answerClosesAt?: number;
  resolutionDeadlineClockSec: number;
  status: QuestionStatus;
  winningKey?: string;
  createdAt: number;
  openedAtMinute?: number;
  openedAtSeq?: number;
  lockState?: { goals: StatPair; corners: StatPair; cards: StatPair };
  feedFreshness?: FeedFreshness;
  sourceAttribution?: string;
  rewardPreview?: string;
  fanBuzzUrl?: string;
  fanBuzzFact?: string;
}

export interface QuestionCandidate {
  ruleId: string;
  lane: QuestionLane;
  category: QuestionCategory;
  question: string;
  options: QuestionOption[];
  resolver: SwingResolver;
  basePoints: number;
  reason: string;
  urgency: number;
  locksAtMinute: number;
  resolutionDeadlineMinute: number;
  /** Higher = preferred by ranker before novelty. */
  priority: number;
  cooldownKey: string;
  requiresSecondary?: boolean;
  requiresOnPitchPlayerId?: string;
  noveltyKey: string;
}

export interface MatchContext {
  fixtureId: string;
  homeCode: string;
  awayCode: string;
  homeName: string;
  awayName: string;
  score: ScoreSnapshot;
  win: WinChance;
  feedFreshness: FeedFreshness;
  coverageSecondary: boolean;
  lineupConfirmed: boolean;
  onPitchPlayerIds: Set<string>;
  history?: HistorySnapshot | null;
  majorEvent?: boolean;
  goalsLast10Min?: number;
  cardsLast5Min?: number;
  redCardActive?: boolean;
  isComeback?: boolean;
  flurrySummary?: string;
  lastScorer?: string;
  lastGoalMinute?: number;
  atHalftime?: boolean;
  waterBreakActive?: boolean;
  clockSec: number;
  phase: GamePhase;
}

export interface HistoryBand {
  label: string;
  goalRate: number;
  cardRate: number;
  cornerRate: number;
  sampleSize: number;
}

export interface HistorySnapshot {
  fixtureId: string;
  cutoffKickoff: string;
  bands15: HistoryBand[];
  firstHalf: HistoryBand;
  secondHalf: HistoryBand;
  lateGoalRate: number;
  sourceFixtureIds: string[];
  sampleSize: number;
}

export type EngineCommand =
  | { type: "open"; question: QuestionSpec }
  | { type: "lock"; questionId: string; lockState: NonNullable<QuestionSpec["lockState"]> }
  | { type: "settle"; questionId: string; winningKey: string }
  | { type: "void"; questionId: string; reason: string }
  | { type: "correct"; questionId: string; winningKey: string }
  | { type: "metric"; name: string; value: number; detail?: string };

export interface CoordinatorSnapshot {
  fixtureId: string;
  openSeq: number;
  questions: QuestionSpec[];
  lastOpenClockSec: number;
  cooldownUntil: Record<string, number>;
  metrics: { evalMs: number; emptyIntervals: number; voidRate: number };
}

export interface QuestionEngineMode {
  mode: "off" | "shadow" | "on";
}
