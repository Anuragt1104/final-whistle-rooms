import { NextResponse } from "next/server";
import { pickSide } from "@/lib/store/rooms";

export const dynamic = "force-dynamic";

export async function POST(req: Request, ctx: { params: Promise<{ id: string }> }) {
  const { id } = await ctx.params;
  const body = await req.json().catch(() => ({}));
  const memberId = String(body?.memberId ?? "");
  const side = body?.side === "away" ? "away" : "home";
  const ok = pickSide(id, memberId, side);
  if (!ok) return NextResponse.json({ error: "Could not set side" }, { status: 400 });
  return NextResponse.json({ ok: true });
}
