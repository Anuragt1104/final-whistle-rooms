import { NextRequest, NextResponse } from "next/server";
import { walletOf } from "@/lib/platform/ledger";
import { passOf } from "@/lib/platform/pass";

export const dynamic = "force-dynamic";

/** GET /api/platform/wallet?fanId= — FC balance + pass summary in one call. */
export async function GET(req: NextRequest) {
  const fanId = req.nextUrl.searchParams.get("fanId");
  if (!fanId) return NextResponse.json({ error: "fanId required" }, { status: 400 });
  const pass = passOf(fanId);
  return NextResponse.json({
    wallet: walletOf(fanId),
    pass: { season: pass.season, xp: pass.xp, tier: pass.tier, premium: pass.premium, proTickets: pass.proTickets, deckSlots: pass.deckSlots },
  });
}
