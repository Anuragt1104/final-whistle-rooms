import { NextRequest, NextResponse } from "next/server";
import { buyListing } from "@/lib/platform/market";

export const dynamic = "force-dynamic";

/** POST /api/market/buy { fanId, name, listingId } — settle a trade (2% platform fee). */
export async function POST(req: NextRequest) {
  const body = await req.json().catch(() => ({}));
  const fanId = String(body.fanId ?? "");
  const listingId = String(body.listingId ?? "");
  if (!fanId || !listingId) {
    return NextResponse.json({ error: "fanId and listingId required" }, { status: 400 });
  }
  const result = buyListing(fanId, String(body.name ?? "fan"), listingId);
  if ("error" in result) return NextResponse.json(result, { status: 400 });
  return NextResponse.json(result);
}
