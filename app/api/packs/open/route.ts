import { NextRequest, NextResponse } from "next/server";
import { openPack } from "@/lib/cards/economy";

export const dynamic = "force-dynamic";

/** POST /api/packs/open { fanId, packId } */
export async function POST(req: NextRequest) {
  const body = await req.json().catch(() => ({}));
  const fanId = String(body.fanId ?? "");
  const packId = String(body.packId ?? "");
  if (!fanId || !packId) {
    return NextResponse.json({ error: "fanId and packId required" }, { status: 400 });
  }
  const result = openPack(fanId, packId);
  if ("error" in result) return NextResponse.json(result, { status: 400 });
  return NextResponse.json(result);
}
