/**
 * Card Economy domain types (ADR-0001 / CONTEXT.md).
 * Moments are collectibles; Player/Skill cards are playable in Duels.
 */

export type Axis = "finishing" | "chaos" | "clutch" | "marketShock" | "aura";

export const AXES: Axis[] = ["finishing", "chaos", "clutch", "marketShock", "aura"];

export type AxisStats = Record<Axis, number>;

export type MomentKind = "goal" | "red" | "yellow" | "corner" | "market-swing" | "chaos";

export type RarityStars = 1 | 2 | 3 | 4 | 5;

export interface OddsSandwich {
  before: { home: number; draw: number; away: number };
  after: { home: number; draw: number; away: number };
}

export interface Moment {
  id: string;
  type: "moment";
  ownerId: string;
  fixtureId: string;
  matchLabel: string;
  kind: MomentKind;
  side?: "home" | "away";
  minute: number;
  label: string;
  sourceEventId?: string;
  playerId?: string;
  playerName?: string;
  teamCode?: string;
  imageUrl?: string;
  artKey?: string;
  rarity: RarityStars;
  oddsSandwich: OddsSandwich;
  calledIt: boolean;
  leafData: string;
  roomId?: string;
  createdAt: number;
}

export interface PlayerCard {
  id: string;
  type: "player";
  ownerId: string;
  playerId: string;
  name: string;
  teamCode: string;
  teamName: string;
  position: string;
  imageUrl?: string;
  axes: AxisStats;
  lineageMomentId?: string;
  leafData: string;
  createdAt: number;
}

export type SkillEffect =
  | { kind: "axisBoost"; axis: Axis; amount: number }
  | { kind: "swapAttacker" }
  | { kind: "doubleAura" };

export interface SkillCard {
  id: string;
  type: "skill";
  ownerId: string;
  name: string;
  description: string;
  effect: SkillEffect;
  leafData: string;
  createdAt: number;
}

export type Card = Moment | PlayerCard | SkillCard;

export interface PackGrant {
  id: string;
  ownerId: string;
  weight: number;
  momentIds: string[];
  opened: boolean;
  cards: Card[];
  createdAt: number;
  roomId?: string;
}

export interface FanInventory {
  fanId: string;
  moments: Moment[];
  players: PlayerCard[];
  skills: SkillCard[];
  packs: PackGrant[];
  packWeightBonus: number;
}

export type DuelStatus = "open" | "ready" | "playing" | "finished";

export interface DuelRound {
  round: number;
  attackerId: string;
  axis: Axis;
  aCardId: string;
  bCardId: string;
  aSkillId?: string;
  bSkillId?: string;
  aValue: number;
  bValue: number;
  winnerId: string | null; // null = draw
}

export interface TrumpDuel {
  id: string;
  code: string;
  mode: "trump" | "arena";
  status: DuelStatus;
  challengerId: string;
  opponentId: string | null; // null until joined; "bot" for vs-bot
  challengerHand: string[];
  opponentHand: string[];
  attackerId: string;
  rounds: DuelRound[];
  winnerId?: string;
  seedMomentId?: string;
  createdAt: number;
}

export interface MintContext {
  fanId: string;
  fixtureId: string;
  matchLabel: string;
  roomId?: string;
  partyMultiplier?: number;
  event: {
    kind: MomentKind;
    side?: "home" | "away";
    minute: number;
    seq: number;
    label: string;
    sourceEventId?: string;
    playerId?: string;
    playerName?: string;
    teamCode?: string;
    imageUrl?: string;
    artKey?: string;
  };
  oddsSandwich: OddsSandwich;
  /** Implied home win % before event (0..1) for rarity. */
  priorHomeProb: number;
}
