import { NextResponse } from "next/server";
import { fetchRawSnapshot } from "@/lib/explorer/txodds";

export const dynamic = "force-dynamic";
export const runtime = "nodejs";

/** Raw snapshot passthrough — the feed's "latest record per action type" view. */
export async function GET(_req: Request, ctx: { params: Promise<{ fixtureId: string }> }) {
  const { fixtureId } = await ctx.params;
  if (!/^\d+$/.test(fixtureId)) {
    return NextResponse.json({ error: "fixtureId must be numeric" }, { status: 400 });
  }
  try {
    const records = await fetchRawSnapshot(fixtureId);
    return NextResponse.json({ fixtureId: Number(fixtureId), count: records.length, records });
  } catch (e) {
    return NextResponse.json({ error: String(e) }, { status: 502 });
  }
}
