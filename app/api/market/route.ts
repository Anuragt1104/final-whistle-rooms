import { NextRequest, NextResponse } from "next/server";
import { browse, cancelListing, listCard, MARKET_FEE, myListings } from "@/lib/platform/market";

export const dynamic = "force-dynamic";

/** GET /api/market[?fanId=] — browse open listings (+ your own when fanId given). */
export async function GET(req: NextRequest) {
  const fanId = req.nextUrl.searchParams.get("fanId");
  return NextResponse.json({
    feePct: MARKET_FEE * 100,
    listings: browse(),
    mine: fanId ? myListings(fanId) : [],
  });
}

/** POST /api/market { fanId, sellerName, cardId, priceFC } — create a listing. */
export async function POST(req: NextRequest) {
  const body = await req.json().catch(() => ({}));
  const fanId = String(body.fanId ?? "");
  const cardId = String(body.cardId ?? "");
  const priceFC = Number(body.priceFC ?? 0);
  if (!fanId || !cardId || !priceFC) {
    return NextResponse.json({ error: "fanId, cardId, priceFC required" }, { status: 400 });
  }
  const result = listCard(fanId, String(body.sellerName ?? "fan"), cardId, priceFC);
  if ("error" in result) return NextResponse.json(result, { status: 400 });
  return NextResponse.json({ listing: result });
}

/** DELETE /api/market?fanId=&listingId= — cancel your listing. */
export async function DELETE(req: NextRequest) {
  const fanId = req.nextUrl.searchParams.get("fanId") ?? "";
  const listingId = req.nextUrl.searchParams.get("listingId") ?? "";
  if (!cancelListing(fanId, listingId)) {
    return NextResponse.json({ error: "Cannot cancel" }, { status: 400 });
  }
  return NextResponse.json({ ok: true });
}
