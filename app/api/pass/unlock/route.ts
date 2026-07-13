import { NextRequest, NextResponse } from "next/server";
import { unlockPremium } from "@/lib/platform/pass";

export const dynamic = "force-dynamic";

/**
 * POST /api/pass/unlock { fanId } — demo purchase of the premium World Cup
 * Pass ($15 concept price; StoreKit/Play Billing in production). Records the
 * revenue event.
 */
export async function POST(req: NextRequest) {
  const body = await req.json().catch(() => ({}));
  const fanId = String(body.fanId ?? "");
  if (!fanId) return NextResponse.json({ error: "fanId required" }, { status: 400 });
  return NextResponse.json({ state: unlockPremium(fanId) });
}
