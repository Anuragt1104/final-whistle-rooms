import type {
  Axis,
  AxisStats,
  LineageSnapshot,
  Moment,
  SkillEffect,
} from "@/lib/cards/types";

export type DuelMode = "stadium" | "arena";
export type OpponentType = "house" | "friend";
export type DuelPhase =
  | "waitingForOpponent"
  | "axisSelection"
  | "cardSelection"
  | "resolving"
  | "roundComplete"
  | "finished";

export interface DuelPlayerSnapshot {
  id: string;
  playerId: string;
  ownerId: string;
  name: string;
  teamCode: string;
  axes: AxisStats;
  lineage?: LineageSnapshot;
}

export interface DuelSkillSnapshot {
  id: string;
  ownerId: string;
  name: string;
  effect: SkillEffect;
}

export interface DuelParticipant {
  fanId: string;
  cards: DuelPlayerSnapshot[];
  skills: DuelSkillSnapshot[];
  usedCardIds: string[];
  usedSkillIds: string[];
}

export interface HiddenSubmission {
  cardId: string;
  skillId?: string;
  autoPlayed?: boolean;
}

export interface CardCommitment {
  index: number;
  hash: string;
  cardId?: string;
  salt?: string;
}

export interface ScoreBreakdown {
  base: number;
  resonance: number;
  calledIt: number;
  skill: number;
  total: number;
}

export interface DuelRoundResolution {
  round: number;
  axis: Axis;
  attackerId: string;
  aFanId: string;
  bFanId: string;
  aCard: DuelPlayerSnapshot;
  bCard: DuelPlayerSnapshot;
  aSkill?: DuelSkillSnapshot;
  bSkill?: DuelSkillSnapshot;
  aScore: ScoreBreakdown;
  bScore: ScoreBreakdown;
  winnerId: string | null;
  aAutoPlayed: boolean;
  bAutoPlayed: boolean;
  houseReveal?: { index: number; cardId: string; salt: string };
}

export interface ArenaContext {
  moment: Pick<
    Moment,
    | "id"
    | "fixtureId"
    | "kind"
    | "teamCode"
    | "minute"
    | "sourceEventId"
    | "oddsSandwich"
    | "rarity"
  >;
  proofVerified: boolean;
  script: Axis[];
}

export interface DuelState {
  id: string;
  code: string;
  mode: DuelMode;
  opponentType: OpponentType;
  phase: DuelPhase;
  version: number;
  challengerId: string;
  opponentId: string | null;
  participants: Record<string, DuelParticipant>;
  house?: DuelParticipant;
  attackerId: string;
  axis?: Axis;
  submissions: Record<string, HiddenSubmission>;
  rounds: DuelRoundResolution[];
  wins: Record<string, number>;
  winnerId?: string | null;
  commitments: CardCommitment[];
  arena?: ArenaContext;
  turnStartedAt: number;
  turnDeadlineAt: number;
  createdAt: number;
  updatedAt: number;
}

export type DuelCommand =
  | { type: "choose_axis"; axis: Axis; actionId: string }
  | { type: "submit_card"; cardId: string; skillId?: string; actionId: string }
  | { type: "acknowledge_round"; actionId: string }
  | { type: "rematch"; actionId: string };

export interface DuelView {
  id: string;
  code: string;
  mode: DuelMode;
  opponentType: OpponentType;
  phase: DuelPhase;
  version: number;
  actorId: string;
  attackerId: string;
  axis?: Axis;
  scores: Record<string, number>;
  winnerId?: string | null;
  rounds: DuelRoundResolution[];
  hand: DuelPlayerSnapshot[];
  skills: DuelSkillSnapshot[];
  usedCardIds: string[];
  usedSkillIds: string[];
  hasSubmitted: boolean;
  opponent: { id: string | null; submitted: boolean; cardsRemaining: number };
  timer: { startedAt: number; deadlineAt: number; graceEndsAt: number };
  commitments: CardCommitment[];
  arena?: ArenaContext;
}
