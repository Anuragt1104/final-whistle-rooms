import { NextRequest, NextResponse } from "next/server";
import { inventoryOf } from "@/lib/cards/economy";

export const dynamic = "force-dynamic";

/** GET /api/inventory?fanId= */
export async function GET(req: NextRequest) {
  const fanId = req.nextUrl.searchParams.get("fanId");
  if (!fanId) return NextResponse.json({ error: "fanId required" }, { status: 400 });
  const inv = inventoryOf(fanId);
  return NextResponse.json(inv);
}
