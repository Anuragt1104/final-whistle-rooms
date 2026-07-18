import { NextResponse } from "next/server";
import { buildView, getRoomRuntime, joinOfficialHub } from "@/lib/store/rooms";

export const dynamic = "force-dynamic";

export async function POST(
  req: Request,
  { params }: { params: Promise<{ fixtureId: string }> },
) {
  const { fixtureId } = await params;
  const body = await req.json().catch(() => ({}));
  const result = await joinOfficialHub(fixtureId, {
    name: String(body.name ?? "Fan"),
    walletPubkey: body.walletPubkey ? String(body.walletPubkey) : undefined,
  });
  if ("error" in result) return NextResponse.json(result, { status: 400 });
  const runtime = getRoomRuntime(result.roomId);
  const lifecycle = runtime ? buildView(runtime).lifecycle : "pregame";
  return NextResponse.json({ ...result, kind: "official", autoManaged: true, lifecycle });
}
