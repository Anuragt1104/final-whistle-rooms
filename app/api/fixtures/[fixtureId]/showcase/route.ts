import { NextResponse } from "next/server";
import { buildView, getRoomRuntime, joinShowcaseReplay } from "@/lib/store/rooms";

export const dynamic = "force-dynamic";

export async function POST(
  req: Request,
  { params }: { params: Promise<{ fixtureId: string }> },
) {
  const { fixtureId } = await params;
  const body = await req.json().catch(() => ({}));
  const result = await joinShowcaseReplay(fixtureId, {
    name: String(body.name ?? "Fan"),
    walletPubkey: body.walletPubkey ? String(body.walletPubkey) : undefined,
    actionId: body.actionId ? String(body.actionId) : undefined,
  });
  if ("error" in result) return NextResponse.json(result, { status: 400 });
  const runtime = getRoomRuntime(result.roomId);
  if (!runtime) return NextResponse.json({ error: "Showcase session unavailable" }, { status: 500 });
  const room = buildView(runtime);
  return NextResponse.json({
    ...result,
    fixtureId,
    lifecycle: "replay",
    replayState: room.replayState,
    inviteCode: room.code,
  });
}
