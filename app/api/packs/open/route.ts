import { NextRequest, NextResponse } from "next/server";
import { openPack } from "@/lib/cards/economy";
import { EARN, earn } from "@/lib/platform/ledger";
import { addXp, XP } from "@/lib/platform/pass";

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
  earn(fanId, EARN.packOpened, "pack opened");
  addXp(fanId, XP.packOpened, "pack opened");
  return NextResponse.json(result);
}
