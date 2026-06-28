import { NextResponse } from "next/server";
import { getSource, sourceMode } from "@/lib/txline/source";
import { GamePhase, isLivePhase, type Fixture, type ScoreSnapshot } from "@/lib/txline/types";

export const dynamic = "force-dynamic";

// Enriching every live/finished fixture with its score means a TxLINE call per
// match, so cache the whole board briefly — the schedule doesn't need to be
// fresher than this and it keeps /api/fixtures snappy under polling.
const TTL_MS = 20_000;
let cache: { at: number; fixtures: Fixture[] } | null = null;

export async function GET() {
  try {
    if (cache && Date.now() - cache.at < TTL_MS) {
      return NextResponse.json({ fixtures: cache.fixtures });
    }
    const source = getSource();
    const fixtures = await source.listFixtures();

    // attach live/final scores so the Fixtures tab is a real results board
    if (sourceMode() === "live") {
      const getScore = (source as unknown as {
        getScoreSnapshot?: (f: Fixture) => Promise<ScoreSnapshot>;
      }).getScoreSnapshot?.bind(source);
      if (getScore) {
        await Promise.all(
          fixtures
            .filter((f) => f.status !== "scheduled")
            .map(async (f) => {
              try {
                const s = await getScore(f);
                f.score = { home: s.goals.home, away: s.goals.away, minute: s.minute };
                const ageMs = Date.now() - (s.updatedAt || 0);
                const fresh = ageMs < 10 * 60_000; // updated within 10 min = actively live
                // refine status from the AUTHORITATIVE clock + freshness, not the
                // 2.5h kickoff heuristic — so frozen replays stop reading "LIVE"
                if (s.phase === GamePhase.FullTime || s.phase === GamePhase.Finished || s.phase === GamePhase.Abandoned) {
                  f.status = "finished";
                } else if ((isLivePhase(s.phase) || s.phase === GamePhase.HalfTime) && fresh) {
                  f.status = "live";
                } else if (s.phase === GamePhase.PreMatch || s.minute <= 0) {
                  // clock at 0 = NOT in play. Scheduled if kickoff is still
                  // ahead, otherwise it's a finished/reset replay — never "live".
                  f.status = new Date(f.kickoff).getTime() > Date.now() ? "scheduled" : "finished";
                } else if (!fresh) {
                  // had a clock but the feed went silent — it's over, not live
                  f.status = "finished";
                }
              } catch {
                /* leave this one unscored — best effort */
              }
            }),
        );
      }
    }

    cache = { at: Date.now(), fixtures };
    return NextResponse.json({ fixtures });
  } catch (e) {
    return NextResponse.json({ error: String(e), fixtures: [] }, { status: 500 });
  }
}
