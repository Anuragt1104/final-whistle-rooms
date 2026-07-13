import { NextRequest, NextResponse } from "next/server";
import { getDuel, playTrumpRound } from "@/lib/cards/duel";
import type { Axis } from "@/lib/cards/types";
import { EARN, earn } from "@/lib/platform/ledger";
import { addXp, XP } from "@/lib/platform/pass";

export const dynamic = "force-dynamic";

export async function GET(
  _req: Request,
  { params }: { params: Promise<{ id: string }> },
) {
  const { id } = await params;
  const duel = getDuel(id);
  if (!duel) return NextResponse.json({ error: "Duel not found" }, { status: 404 });
  return NextResponse.json(duel);
}

/** POST /api/duels/:id/play */
export async function POST(
  req: NextRequest,
  { params }: { params: Promise<{ id: string }> },
) {
  const { id } = await params;
  const body = await req.json().catch(() => ({}));
  const result = playTrumpRound({
    duelId: id,
    fanId: String(body.fanId ?? ""),
    axis: body.axis as Axis,
    cardId: String(body.cardId ?? ""),
    skillId: body.skillId ? String(body.skillId) : undefined,
    botCardId: body.opponentCardId ? String(body.opponentCardId) : undefined,
    botSkillId: body.opponentSkillId ? String(body.opponentSkillId) : undefined,
  });
  if ("error" in result) return NextResponse.json(result, { status: 400 });
  // duel just finished on this round → settle platform rewards (fires once)
  if (result.status === "finished") {
    const players = [result.challengerId, result.opponentId].filter(
      (p): p is string => !!p && p !== "bot",
    );
    for (const p of players) {
      const won = result.winnerId === p;
      earn(p, won ? EARN.duelWin : EARN.duelLoss, won ? "duel win" : "duel played");
      addXp(p, won ? XP.duelWin : XP.duelLoss, "duel");
    }
  }
  return NextResponse.json(result);
}
