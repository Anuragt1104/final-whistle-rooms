import { NextRequest, NextResponse } from "next/server";
import { craft } from "@/lib/cards/economy";

export const dynamic = "force-dynamic";

/** POST /api/craft { fanId, momentIds: string[] } */
export async function POST(req: NextRequest) {
  const body = await req.json().catch(() => ({}));
  const fanId = String(body.fanId ?? "");
  const momentIds = Array.isArray(body.momentIds) ? body.momentIds.map(String) : [];
  if (!fanId || momentIds.length < 2) {
    return NextResponse.json({ error: "fanId and momentIds (≥2) required" }, { status: 400 });
  }
  const result = craft(fanId, momentIds);
  if ("error" in result) return NextResponse.json(result, { status: 400 });
  return NextResponse.json(result);
}
