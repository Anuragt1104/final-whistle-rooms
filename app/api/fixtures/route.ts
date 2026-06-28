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
                // refine status from the AUTHORITATIVE game phase, not the
                // 2.5h kickoff heuristic — so an ended match stops reading "LIVE"
                if (s.phase === GamePhase.FullTime || s.phase === GamePhase.Finished || s.phase === GamePhase.Abandoned) {
                  f.status = "finished";
                } else if (isLivePhase(s.phase) || s.phase === GamePhase.HalfTime) {
                  f.status = "live";
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
