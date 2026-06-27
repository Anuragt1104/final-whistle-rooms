import { NextResponse } from "next/server";
import { buildView, getRoomRuntime } from "@/lib/store/rooms";

export const dynamic = "force-dynamic";

export async function GET(_req: Request, ctx: { params: Promise<{ id: string }> }) {
  const { id } = await ctx.params;
  const rt = getRoomRuntime(id);
  if (!rt) return NextResponse.json({ error: "Room not found" }, { status: 404 });
  return NextResponse.json({ room: buildView(rt) });
}
