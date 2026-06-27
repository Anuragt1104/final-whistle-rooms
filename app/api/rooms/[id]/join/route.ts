import { NextResponse } from "next/server";
import { joinRoom } from "@/lib/store/rooms";

export const dynamic = "force-dynamic";

export async function POST(req: Request, ctx: { params: Promise<{ id: string }> }) {
  const { id } = await ctx.params;
  const body = await req.json().catch(() => ({}));
  const result = joinRoom(id, {
    name: String(body?.name ?? "Fan"),
    walletPubkey: body?.walletPubkey ? String(body.walletPubkey) : undefined,
  });
  if ("error" in result) return NextResponse.json(result, { status: 404 });
  return NextResponse.json(result);
}
