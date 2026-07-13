import { NextRequest, NextResponse } from "next/server";
import { passOf, TRACK, TIER_COUNT, XP_PER_TIER, PASS_PRICE_USD } from "@/lib/platform/pass";

export const dynamic = "force-dynamic";

/** GET /api/pass?fanId= — pass state + the full reward track. */
export async function GET(req: NextRequest) {
  const fanId = req.nextUrl.searchParams.get("fanId");
  if (!fanId) return NextResponse.json({ error: "fanId required" }, { status: 400 });
  return NextResponse.json({
    state: passOf(fanId),
    track: TRACK,
    tierCount: TIER_COUNT,
    xpPerTier: XP_PER_TIER,
    priceUsd: PASS_PRICE_USD,
  });
}
