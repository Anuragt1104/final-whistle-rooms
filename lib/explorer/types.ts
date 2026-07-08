/**
 * Feed Explorer types — the RAW TxODDS scores-feed record, verbatim.
 *
 * Unlike lib/txline (which normalizes records for the product), the explorer's
 * whole point is to show the wire format untouched, so this type mirrors the
 * PascalCase envelope exactly as observed from /api/scores/snapshot|updates.
 */

export interface RawClock {
  Running?: boolean;
  Seconds?: number;
}

/** Per-period stat block: {Goals?, YellowCards?, RedCards?, Corners?} */
export type PeriodScore = Record<string, number>;

/** Periods observed: H1, HT, H2, ET1, ET2, ETTotal, PE, Total */
export type ParticipantScore = Record<string, PeriodScore>;

export interface RawRecord {
  Action?: string;
  Clock?: RawClock;
  CompetitionId?: number;
  Confirmed?: boolean;
  ConnectionId?: number;
  CountryId?: number;
  CoverageSecondaryData?: boolean;
  CoverageType?: string;
  Data?: Record<string, unknown> | null;
  FixtureGroupId?: number;
  FixtureId?: number;
  GameState?: string;
  Id?: number;
  IsTeam?: boolean;
  Participant?: number | null;
  Participant1Id?: number;
  Participant2Id?: number;
  Participant1IsHome?: boolean;
  PlayerStats?: Record<string, Record<string, Record<string, number>>> | null;
  PossibleEvent?: Record<string, unknown> | null;
  Score?: { Participant1?: ParticipantScore; Participant2?: ParticipantScore } | null;
  Seq?: number;
  SportId?: number;
  StartTime?: number;
  Stats?: Record<string, number> | null;
  StatusId?: number;
  Ts?: number;
  Type?: string;
  [key: string]: unknown; // future-proof: show fields we haven't catalogued too
}

export interface RawFixture {
  FixtureId: number;
  Participant1?: string;
  Participant2?: string;
  Participant1Id?: number;
  Participant2Id?: number;
  Participant1IsHome?: boolean;
  StartTime?: number;
  Competition?: string;
  CompetitionId?: number;
  Ts?: number;
  [key: string]: unknown;
}

export type FixtureState = "upcoming" | "live" | "finished";

export interface FixtureLite {
  fixtureId: number;
  home: string;
  away: string;
  startTime: number;
  state: FixtureState;
  score?: { home: number; away: number; minute: number };
}

export interface LogResponse {
  fixtureId: number;
  count: number;
  actionCounts: Record<string, number>;
  records: RawRecord[];
}
