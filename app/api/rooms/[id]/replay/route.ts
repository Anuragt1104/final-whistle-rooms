import { NextResponse } from "next/server";
import { controlReplay } from "@/lib/store/rooms";

export const dynamic = "force-dynamic";

export async function POST(req: Request, ctx: { params: Promise<{ id: string }> }) {
  const { id } = await ctx.params;
  const body = await req.json().catch(() => ({}));
  const result = controlReplay(id, {
    action: String(body?.action ?? ""),
    minute: body?.minute != null ? Number(body.minute) : undefined,
    speed: body?.speed != null ? Number(body.speed) : undefined,
  });
  if (result.error) return NextResponse.json(result, { status: 400 });
  return NextResponse.json(result);
}
