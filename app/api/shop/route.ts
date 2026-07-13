import { NextRequest, NextResponse } from "next/server";
import { buyPack, SHOP } from "@/lib/platform/shop";

export const dynamic = "force-dynamic";

/** GET /api/shop — the pack tiers. */
export async function GET() {
  return NextResponse.json({ tiers: SHOP });
}

/** POST /api/shop { fanId, tierId } — buy a pack with Fan Credits. */
export async function POST(req: NextRequest) {
  const body = await req.json().catch(() => ({}));
  const fanId = String(body.fanId ?? "");
  const tierId = String(body.tierId ?? "");
  if (!fanId || !tierId) return NextResponse.json({ error: "fanId and tierId required" }, { status: 400 });
  const result = buyPack(fanId, tierId);
  if ("error" in result) return NextResponse.json(result, { status: 400 });
  return NextResponse.json(result);
}
