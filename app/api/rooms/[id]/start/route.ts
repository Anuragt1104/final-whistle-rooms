import { NextResponse } from "next/server";
import { startMatch } from "@/lib/store/rooms";

export const dynamic = "force-dynamic";

export async function POST(req: Request, ctx: { params: Promise<{ id: string }> }) {
  const { id } = await ctx.params;
  const body = await req.json().catch(() => ({}));
  const result = await startMatch(id, String(body?.memberId ?? ""));
  if (result.error) return NextResponse.json(result, { status: 400 });
  return NextResponse.json(result);
}
