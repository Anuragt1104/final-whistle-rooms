import { NextResponse } from "next/server";
import { getSource, sourceMode } from "@/lib/txline/source";
import { GamePhase, isLivePhase, type Fixture, type ScoreSnapshot } from "@/lib/txline/types";
import { canonicalizeTournamentFixtures } from "@/lib/txline/catalog";

export const dynamic = "force-dynamic";

const CATALOG_TTL_MS = 5 * 60_000;
const LIVE_SCORE_TTL_MS = 15_000;
let cache: { at: number; fixtures: Fixture[] } | null = null;
const scoreCache = new Map<string, { at: number; terminal: boolean; score: ScoreSnapshot }>();

async function mapLimit<T>(items: T[], limit: number, fn: (item: T) => Promise<void>) {
  let cursor = 0;
  await Promise.all(
    Array.from({ length: Math.min(limit, items.length) }, async () => {
      while (cursor < items.length) {
        const item = items[cursor++];
        await fn(item);
      }
    }),
  );
}

export async function GET() {
  try {
    if (cache && Date.now() - cache.at < CATALOG_TTL_MS) {
      return NextResponse.json({ fixtures: cache.fixtures });
    }
    const source = getSource();
    const sourceFixtures = await source.listFixtures();
    let fixtures = sourceFixtures;

    if (sourceMode() === "live") {
      const canonical = canonicalizeTournamentFixtures(sourceFixtures);
      if (!canonical.ok) {
        if (cache?.fixtures.length === 104) {
          return NextResponse.json({
            fixtures: cache.fixtures,
            stale: true,
            catalogWarning: canonical.reason,
          });
        }
        return NextResponse.json(
          { error: canonical.reason, fixtures: [] },
          { status: 503 },
        );
      }
      fixtures = canonical.fixtures;
    }

    // attach live/final scores so the Fixtures tab is a real results board
    if (sourceMode() === "live") {
      const getScore = (source as unknown as {
        getScoreSnapshot?: (f: Fixture) => Promise<ScoreSnapshot>;
      }).getScoreSnapshot?.bind(source);
      if (getScore) {
        await mapLimit(
          fixtures.filter((f) => f.status !== "scheduled"),
          8,
          async (f) => {
              try {
                const prior = scoreCache.get(f.id);
                const canReuse = prior && (prior.terminal || Date.now() - prior.at < LIVE_SCORE_TTL_MS);
                const s = canReuse ? prior.score : await getScore(f);
                const ageMs = Date.now() - (s.updatedAt || 0);
                const fresh = ageMs < 10 * 60_000; // updated within 10 min = actively live
                f.score = {
                  home: s.goals.home,
                  away: s.goals.away,
                  minute: s.minute,
                  clockSeconds: s.clockSeconds,
                  running: s.running && fresh,
                };
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
                scoreCache.set(f.id, {
                  at: Date.now(),
                  terminal: f.status === "finished",
                  score: s,
                });
              } catch {
                const prior = scoreCache.get(f.id);
                if (prior) {
                  const s = prior.score;
                  f.score = { home: s.goals.home, away: s.goals.away, minute: s.minute, clockSeconds: s.clockSeconds, running: false };
                }
              }
          },
        );
      }
    }

    cache = { at: Date.now(), fixtures };
    return NextResponse.json({ fixtures });
  } catch (e) {
    return NextResponse.json({ error: String(e), fixtures: [] }, { status: 500 });
  }
}
