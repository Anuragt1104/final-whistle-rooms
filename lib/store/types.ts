/** Serializable room view shared between the server store and the client. */
import type { Fixture, GamePhase, OddsMarket } from "@/lib/txline/types";
import type { PulseCard, WinChance } from "@/lib/engine/pulse";
import type { SwingOption } from "@/lib/game/nextswing";

export type RoomStatus = "lobby" | "live" | "finished";

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
  status: "open" | "locked" | "settled";
  winningKey?: string;
  /** how many room members picked each option key */
  tally: Record<string, number>;
  createdAt: number;
}

export interface ScoreView {
  minute: number;
  phase: GamePhase;
  statusNote?: string;
  goals: { home: number; away: number };
  yellow: { home: number; away: number };
  red: { home: number; away: number };
  corners: { home: number; away: number };
}

export interface RecapView {
  id: string;
  scope: "half-time" | "full-time";
  minute: number;
  text: string;
  topMember?: string;
  createdAt: number;
}

export interface RoomView {
  id: string;
  code: string;
  name: string;
  fixture: Fixture;
  modes: RoomModes;
  hostId: string;
  status: RoomStatus;
  momentum: number;
  win: WinChance;
  score: ScoreView | null;
  markets: OddsMarket[];
  members: MemberView[];
  chat: ChatView[];
  pulse: PulseCard[];
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
  createdAt: number;
}
