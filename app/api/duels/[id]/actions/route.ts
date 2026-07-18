import { NextResponse } from "next/server";
import { authenticatedFan } from "@/lib/auth/session";
import { DuelCommandService } from "@/lib/duel/service";
import type { DuelCommand } from "@/lib/duel/types";

export const dynamic = "force-dynamic";

export async function POST(
  request: Request,
  { params }: { params: Promise<{ id: string }> },
) {
  try {
    const fanId = authenticatedFan(request);
    const { id } = await params;
    const body = await request.json().catch(() => ({}));
    const command = {
      ...body,
      type: String(body.type ?? ""),
      actionId: String(body.actionId ?? ""),
    } as DuelCommand;
    if (!command.actionId) throw new Error("actionId is required");
    const view = await new DuelCommandService().action(id, fanId, command);
    return NextResponse.json(view);
  } catch (error) {
    const message = error instanceof Error ? error.message : "action failed";
    return NextResponse.json(
      { error: message },
      { status: message.includes("not found") ? 404 : message.includes("authentication") ? 401 : 400 },
    );
  }
}
