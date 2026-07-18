/**
 * Pre-match history priors from completed tournament fixtures (TxLINE tapes).
 * Cutoff = fixture kickoff — never peek at future results.
 */
import type { HistoryBand, HistorySnapshot } from "./types";

export interface TapeSummary {
  fixtureId: string;
  kickoff: string;
  /** Goals scored in each 15' band (0-15, 15-30, …, 75-90). */
  goalsByBand: number[];
  cardsByBand: number[];
  cornersByBand: number[];
  firstHalfGoals: number;
  secondHalfGoals: number;
  lateGoals: number; // 75'+
}

const BAND_LABELS = ["0-15", "15-30", "30-45", "45-60", "60-75", "75-90"];

function emptyBand(label: string): HistoryBand {
  return { label, goalRate: 0, cardRate: 0, cornerRate: 0, sampleSize: 0 };
}

function rate(sum: number, n: number): number {
  return n <= 0 ? 0 : sum / n;
}

/**
 * Build history snapshot for `fixtureId` using only tapes with kickoff < cutoff.
 */
export function buildHistorySnapshot(
  fixtureId: string,
  cutoffKickoff: string,
  tapes: TapeSummary[],
): HistorySnapshot {
  const cutoff = Date.parse(cutoffKickoff);
  const prior = tapes.filter((t) => {
    if (t.fixtureId === fixtureId) return false;
    const k = Date.parse(t.kickoff);
    return Number.isFinite(k) && Number.isFinite(cutoff) && k < cutoff;
  });

  const bands15 = BAND_LABELS.map((label, i) => {
    let g = 0, c = 0, cor = 0;
    for (const t of prior) {
      g += t.goalsByBand[i] ?? 0;
      c += t.cardsByBand[i] ?? 0;
      cor += t.cornersByBand[i] ?? 0;
    }
    const n = prior.length;
    return {
      label,
      goalRate: rate(g, n),
      cardRate: rate(c, n),
      cornerRate: rate(cor, n),
      sampleSize: n,
    };
  });

  let fhG = 0, shG = 0, late = 0;
  for (const t of prior) {
    fhG += t.firstHalfGoals;
    shG += t.secondHalfGoals;
    late += t.lateGoals;
  }
  const n = prior.length;

  return {
    fixtureId,
    cutoffKickoff,
    bands15: bands15.length ? bands15 : BAND_LABELS.map(emptyBand),
    firstHalf: {
      label: "1H",
      goalRate: rate(fhG, n),
      cardRate: 0,
      cornerRate: 0,
      sampleSize: n,
    },
    secondHalf: {
      label: "2H",
      goalRate: rate(shG, n),
      cardRate: 0,
      cornerRate: 0,
      sampleSize: n,
    },
    lateGoalRate: rate(late, n),
    sourceFixtureIds: prior.map((t) => t.fixtureId),
    sampleSize: n,
  };
}

/** Summarize a flat event tape (minute + kind) into TapeSummary bands. */
export function summarizeTape(
  fixtureId: string,
  kickoff: string,
  events: { minute: number; kind: string }[],
): TapeSummary {
  const goalsByBand = [0, 0, 0, 0, 0, 0];
  const cardsByBand = [0, 0, 0, 0, 0, 0];
  const cornersByBand = [0, 0, 0, 0, 0, 0];
  let firstHalfGoals = 0;
  let secondHalfGoals = 0;
  let lateGoals = 0;

  for (const e of events) {
    const band = Math.min(5, Math.max(0, Math.floor(e.minute / 15)));
    if (e.kind === "goal") {
      goalsByBand[band]++;
      if (e.minute < 45) firstHalfGoals++;
      else secondHalfGoals++;
      if (e.minute >= 75) lateGoals++;
    } else if (e.kind === "yellow" || e.kind === "red") {
      cardsByBand[band]++;
    } else if (e.kind === "corner") {
      cornersByBand[band]++;
    }
  }

  return {
    fixtureId,
    kickoff,
    goalsByBand,
    cardsByBand,
    cornersByBand,
    firstHalfGoals,
    secondHalfGoals,
    lateGoals,
  };
}
