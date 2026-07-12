import { NextRequest, NextResponse } from "next/server";
import {
  createMomentArena,
  createTrumpDuel,
  joinTrumpDuel,
  listDuelsForFan,
} from "@/lib/cards/duel";

export const dynamic = "force-dynamic";

/** GET /api/duels?fanId= */
export async function GET(req: NextRequest) {
  const fanId = req.nextUrl.searchParams.get("fanId");
  if (!fanId) return NextResponse.json({ error: "fanId required" }, { status: 400 });
  return NextResponse.json({ duels: listDuelsForFan(fanId) });
}

/** POST /api/duels — create trump (vsBot) or arena, or join by code */
export async function POST(req: NextRequest) {
  const body = await req.json().catch(() => ({}));
  const action = String(body.action ?? "create");

  if (action === "join") {
    const result = joinTrumpDuel(String(body.code ?? ""), String(body.fanId ?? ""), body.hand ?? []);
    if ("error" in result) return NextResponse.json(result, { status: 400 });
    return NextResponse.json(result);
  }

  if (action === "arena") {
    const result = createMomentArena({
      challengerId: String(body.fanId ?? ""),
      seedMomentId: String(body.seedMomentId ?? ""),
      hand: body.hand ?? [],
    });
    if ("error" in result) return NextResponse.json(result, { status: 400 });
    return NextResponse.json(result);
  }

  const result = createTrumpDuel({
    challengerId: String(body.fanId ?? ""),
    hand: body.hand ?? [],
    vsBot: body.vsBot !== false,
  });
  if ("error" in result) return NextResponse.json(result, { status: 400 });
  return NextResponse.json(result);
}
