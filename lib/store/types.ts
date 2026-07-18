/** Serializable room view shared between the server store and the client. */
import type { Fixture, GamePhase, OddsMarket } from "@/lib/txline/types";
import type { PulseCard, WinChance } from "@/lib/engine/pulse";
import type { SwingOption } from "@/lib/game/nextswing";

export type RoomStatus = "lobby" | "live" | "finished";
export type RoomKind = "official" | "party";
export type RoomLifecycle = "pregame" | "live" | "finished";

export interface RoomModes {
  draft: boolean;
  nextSwing: boolean;
}

export interface MemberView {
  id: string;
  name: string;
  avatar: string;
  walletShort?: string;
  side?: "home" | "away";
  points: number;
  streak: number;
  bestStreak: number;
  correct: number;
  isHost: boolean;
}

export interface ChatView {
  id: string;
  memberId: string;
  name: string;
  avatar: string;
  text: string;
  kind: "chat" | "reaction" | "system";
  ts: number;
}

export interface PromptView {
  id: string;
  question: string;
  options: SwingOption[];
  basePoints: number;
  locksAtMinute: number;
  status: "scheduled" | "open" | "locked" | "settled" | "void" | "corrected";
  /** Present only after settle / void / corrected — never while open/locked. */
  winningKey?: string;
  /** how many room members picked each option key */
  tally: Record<string, number>;
  createdAt: number;
  lane?: "main" | "quick" | "break" | "hydration";
  category?: string;
  ruleId?: string;
  reason?: string;
  urgency?: number;
  openedClockSec?: number;
  answerClosesAt?: number;
  resolutionDeadlineClockSec?: number;
  feedFreshness?: string;
  sourceAttribution?: string;
  rewardPreview?: string;
  fanBuzzUrl?: string;
  fanBuzzFact?: string;
}

export interface ScoreView {
  minute: number;
  clockSeconds: number;
  running: boolean;
  phase: GamePhase;
  statusNote?: string;
  goals: { home: number; away: number };
  yellow: { home: number; away: number };
  red: { home: number; away: number };
  corners: { home: number; away: number };
  /** Per-half breakdowns (from the feed's period-offset stat keys). */
  periods?: {
    firstHalf: { goals: { home: number; away: number }; yellow: { home: number; away: number }; red: { home: number; away: number }; corners: { home: number; away: number } };
    secondHalf: { goals: { home: number; away: number }; yellow: { home: number; away: number }; red: { home: number; away: number }; corners: { home: number; away: number } };
  };
}

export interface RecapView {
  id: string;
  scope: "half-time" | "full-time";
  minute: number;
  text: string;
  topMember?: string;
  createdAt: number;
}

export interface MomentDropView {
  id: string;
  memberId: string;
  kind: string;
  label: string;
  rarity: number;
  minute: number;
  matchLabel: string;
  createdAt: number;
  sourceEventId?: string;
  playerId?: string;
  playerName?: string;
  teamCode?: string;
  imageUrl?: string;
  artKey?: string;
}

export interface RoomView {
  id: string;
  code: string;
  name: string;
  kind: RoomKind;
  autoManaged: boolean;
  fixture: Fixture;
  modes: RoomModes;
  hostId: string;
  status: RoomStatus;
  lifecycle: RoomLifecycle;
  feedFreshness: "waiting" | "fresh" | "stale";
  lineupStatus: "unknown" | "announced";
  sourceUpdatedAt?: number;
  momentum: number;
  win: WinChance;
  /** Home win-chance sampled once per match-minute — the live momentum story. */
  winHistory: number[];
  score: ScoreView | null;
  markets: OddsMarket[];
  members: MemberView[];
  chat: ChatView[];
  pulse: PulseCard[];
  momentDrops: MomentDropView[];
  prompts: PromptView[];
  recaps: RecapView[];
  proof: {
    leafCount: number;
    root: string | null;
    anchored: boolean;
    anchorSignature?: string;
    cluster: string;
  };
  spoilerSafe: boolean;
  voice: boolean;
  reactionPack: string;
  replay: boolean;
  createdAt: number;
}
