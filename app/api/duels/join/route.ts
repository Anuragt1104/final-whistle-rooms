import { NextResponse } from "next/server";
import { authenticatedFan } from "@/lib/auth/session";
import { DuelCommandService } from "@/lib/duel/service";

export const dynamic = "force-dynamic";

export async function POST(request: Request) {
  try {
    const fanId = authenticatedFan(request);
    const body = await request.json().catch(() => ({}));
    const view = await new DuelCommandService().join({
      fanId,
      code: String(body.code ?? "").toUpperCase(),
      hand: Array.isArray(body.hand) ? body.hand.map(String) : [],
      skillIds: Array.isArray(body.skillIds) ? body.skillIds.map(String) : [],
      actionId: String(body.actionId ?? ""),
    });
    return NextResponse.json(view);
  } catch (error) {
    return NextResponse.json(
      { error: error instanceof Error ? error.message : "join failed" },
      { status: 400 },
    );
  }
}
