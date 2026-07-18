import { NextResponse } from "next/server";
import { authenticatedFan } from "@/lib/auth/session";
import { duelRepository } from "@/lib/duel/repository";
import { registerDevice } from "@/lib/push/goals";

export const dynamic = "force-dynamic";

export async function POST(req: Request) {
  let fanId: string;
  try {
    fanId = authenticatedFan(req);
  } catch {
    return NextResponse.json({ error: "authentication required" }, { status: 401 });
  }
  let body: { token?: string; platform?: string; fixtureIds?: unknown };
  try {
    body = await req.json();
  } catch {
    return NextResponse.json({ error: "invalid json" }, { status: 400 });
  }
  const token = typeof body.token === "string" ? body.token.trim() : "";
  if (!token || token.length < 20) {
    return NextResponse.json({ error: "token required" }, { status: 400 });
  }
  const fixtureIds = Array.isArray(body.fixtureIds)
    ? body.fixtureIds.filter((id): id is string => typeof id === "string")
    : [];
  registerDevice(token, typeof body.platform === "string" ? body.platform : "unknown", fixtureIds);
  await duelRepository().registerDevice(
    fanId,
    token,
    typeof body.platform === "string" ? body.platform : "unknown",
    fixtureIds,
  );
  const { fcmConfigured } = await import("@/lib/push/goals");
  return NextResponse.json({ ok: true, pushConfigured: fcmConfigured() });
}
