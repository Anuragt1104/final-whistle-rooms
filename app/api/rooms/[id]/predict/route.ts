import { NextResponse } from "next/server";
import { submitPrediction } from "@/lib/store/rooms";

export const dynamic = "force-dynamic";

export async function POST(req: Request, ctx: { params: Promise<{ id: string }> }) {
  const { id } = await ctx.params;
  const body = await req.json().catch(() => ({}));
  const actionId = body?.actionId != null && body.actionId !== ""
    ? String(body.actionId)
    : undefined;
  const result = submitPrediction(
    id,
    String(body?.memberId ?? ""),
    String(body?.promptId ?? ""),
    String(body?.optionKey ?? ""),
    actionId,
  );
  if (result.error) return NextResponse.json(result, { status: 400 });
  return NextResponse.json(result);
}
