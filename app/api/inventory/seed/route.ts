import { NextRequest, NextResponse } from "next/server";
import { seedDemoInventory } from "@/lib/cards/economy";

export const dynamic = "force-dynamic";

/** POST /api/inventory/seed { fanId } — fill empty inventory with demo cards. */
export async function POST(req: NextRequest) {
  const body = await req.json().catch(() => ({}));
  const fanId = String(body.fanId ?? "");
  if (!fanId) return NextResponse.json({ error: "fanId required" }, { status: 400 });
  const result = seedDemoInventory(fanId);
  return NextResponse.json(result);
}
