import { NextResponse } from "next/server";
import { fetchFullLog } from "@/lib/explorer/txodds";
import type { LogResponse } from "@/lib/explorer/types";

export const dynamic = "force-dynamic";
export const runtime = "nodejs";

/**
 * Full chronological raw match log — every record the feed ever sent for a
 * fixture (~1,100+ for a finished match). Parsed server-side from the
 * SSE-formatted /api/scores/updates text. Cached: finished logs are immutable.
 */
const cache = new Map<string, { at: number; body: LogResponse }>();
const TTL_LIVE = 60_000; // still-growing logs refresh quickly
const TTL_DONE = 60 * 60_000;
const MAX_ENTRIES = 5; // logs are ~1MB each — cap memory

function isFinished(body: LogResponse): boolean {
  return body.records.some((r) => r.Action === "game_finalised");
}

export async function GET(_req: Request, ctx: { params: Promise<{ fixtureId: string }> }) {
  const { fixtureId } = await ctx.params;
  if (!/^\d+$/.test(fixtureId)) {
    return NextResponse.json({ error: "fixtureId must be numeric" }, { status: 400 });
  }
  const hit = cache.get(fixtureId);
  if (hit && Date.now() - hit.at < (isFinished(hit.body) ? TTL_DONE : TTL_LIVE)) {
    return NextResponse.json(hit.body);
  }
  try {
    const body = await fetchFullLog(fixtureId);
    cache.set(fixtureId, { at: Date.now(), body });
    if (cache.size > MAX_ENTRIES) {
      const oldest = [...cache.entries()].sort((a, b) => a[1].at - b[1].at)[0];
      if (oldest) cache.delete(oldest[0]);
    }
    return NextResponse.json(body);
  } catch (e) {
    return NextResponse.json({ error: String(e) }, { status: 502 });
  }
}
