import { NextRequest, NextResponse } from "next/server";
import { craft } from "@/lib/cards/economy";
import { EARN, earn } from "@/lib/platform/ledger";
import { addXp, XP } from "@/lib/platform/pass";

export const dynamic = "force-dynamic";

/** POST /api/craft { fanId, momentIds, primaryMomentId?, actionId? } */
export async function POST(req: NextRequest) {
  const body = await req.json().catch(() => ({}));
  const fanId = String(body.fanId ?? "");
  const momentIds = Array.isArray(body.momentIds) ? body.momentIds.map(String) : [];
  if (!fanId || momentIds.length < 2) {
    return NextResponse.json({ error: "fanId and momentIds (≥2) required" }, { status: 400 });
  }
  const result = craft(fanId, momentIds, {
    primaryMomentId: body.primaryMomentId ? String(body.primaryMomentId) : undefined,
    actionId: body.actionId ? String(body.actionId) : undefined,
  });
  if ("error" in result) return NextResponse.json(result, { status: 400 });
  earn(fanId, EARN.craft, "craft");
  addXp(fanId, XP.craft, "craft");
  return NextResponse.json(result);
}
