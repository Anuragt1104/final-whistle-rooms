import { NextResponse } from "next/server";
import { fetchFixturesForDay, fetchRawSnapshot } from "@/lib/explorer/txodds";
import type { FixtureLite, FixtureState, RawFixture } from "@/lib/explorer/types";

export const dynamic = "force-dynamic";
export const runtime = "nodejs";

/**
 * Real fixtures around today (epochDay −2..+2), classified
 * upcoming / live / finished so the explorer can offer every kind of match.
 */
let cached: { at: number; body: { fixtures: FixtureLite[] } } | null = null;
const TTL = 20_000;

async function classify(f: RawFixture): Promise<FixtureLite> {
  const startTime = f.StartTime ?? 0;
  let state: FixtureState = "upcoming";
  let score: FixtureLite["score"];
  if (startTime <= Date.now()) {
    state = "finished";
    try {
      const records = await fetchRawSnapshot(f.FixtureId);
      // newest record that actually carries a Score block (meta records don't)
      let best: (typeof records)[number] | undefined;
      for (const r of records) {
        if (r.Score && (!best || (r.Ts ?? 0) > (best.Ts ?? 0))) best = r;
      }
      // live = the clock is running and the feed spoke recently
      const running = records.some((r) => r.Clock?.Running === true && Date.now() - (r.Ts ?? 0) < 10 * 60_000);
      if (running) state = "live";
      if (best?.Score) {
        const secs = records.reduce((m, r) => Math.max(m, r.Clock?.Seconds ?? 0), 0);
        score = {
          home: best.Score.Participant1?.Total?.Goals ?? 0,
          away: best.Score.Participant2?.Total?.Goals ?? 0,
          minute: Math.floor(secs / 60),
        };
      }
    } catch {
      /* no scores yet — treat as upcoming (e.g. kickoff moments away) */
      state = "upcoming";
    }
  }
  return {
    fixtureId: f.FixtureId,
    home: f.Participant1 ?? "P1",
    away: f.Participant2 ?? "P2",
    startTime,
    state,
    score,
  };
}

export async function GET() {
  if (cached && Date.now() - cached.at < TTL) return NextResponse.json(cached.body);
  try {
    const today = Math.floor(Date.now() / 86_400_000);
    const days = await Promise.all([-2, -1, 0, 1, 2].map((off) => fetchFixturesForDay(today + off)));
    const seen = new Map<number, RawFixture>();
    for (const list of days) {
      for (const f of list) {
        if (f?.FixtureId) seen.set(f.FixtureId, f);
      }
    }
    const fixtures = await Promise.all([...seen.values()].map(classify));
    fixtures.sort((a, b) => a.startTime - b.startTime);
    const body = { fixtures };
    cached = { at: Date.now(), body };
    return NextResponse.json(body);
  } catch (e) {
    return NextResponse.json({ error: String(e) }, { status: 502 });
  }
}
