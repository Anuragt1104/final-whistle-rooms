import { NextRequest, NextResponse } from "next/server";
import { grantPackWeight } from "@/lib/cards/economy";
import { claimReward } from "@/lib/platform/pass";

export const dynamic = "force-dynamic";

/** POST /api/pass/claim { fanId, tier, lane } */
export async function POST(req: NextRequest) {
  const body = await req.json().catch(() => ({}));
  const fanId = String(body.fanId ?? "");
  const tier = Number(body.tier ?? 0);
  const lane = body.lane === "premium" ? "premium" : "free";
  if (!fanId || !tier) return NextResponse.json({ error: "fanId and tier required" }, { status: 400 });
  const result = claimReward(fanId, tier, lane);
  if ("error" in result) return NextResponse.json(result, { status: 400 });
  if (result.reward.kind === "pack") {
    // bonus packs land as pack-weight in the card economy
    grantPackWeight(fanId, 0.25 * (result.reward.amount ?? 1));
  }
  return NextResponse.json(result);
}
