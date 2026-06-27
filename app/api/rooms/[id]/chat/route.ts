import { NextResponse } from "next/server";
import { postChat } from "@/lib/store/rooms";

export const dynamic = "force-dynamic";

export async function POST(req: Request, ctx: { params: Promise<{ id: string }> }) {
  const { id } = await ctx.params;
  const body = await req.json().catch(() => ({}));
  const text = String(body?.text ?? "").trim();
  if (!text) return NextResponse.json({ error: "Empty message" }, { status: 400 });
  const kind = body?.kind === "reaction" ? "reaction" : "chat";
  const ok = postChat(id, String(body?.memberId ?? ""), text, kind);
  if (!ok) return NextResponse.json({ error: "Could not post" }, { status: 400 });
  return NextResponse.json({ ok: true });
}
