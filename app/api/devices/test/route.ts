import { NextResponse } from "next/server";
import { sendTestNotification } from "@/lib/push/goals";

export const dynamic = "force-dynamic";

export async function POST(req: Request) {
  const body = await req.json().catch(() => ({}));
  const token = typeof body.token === "string" ? body.token.trim() : "";
  if (!token) return NextResponse.json({ error: "token required" }, { status: 400 });
  try {
    const result = await sendTestNotification(token);
    if (!result.ok) return NextResponse.json({ error: result.error }, { status: 429 });
    return NextResponse.json(result);
  } catch (error) {
    return NextResponse.json({ error: String(error) }, { status: 503 });
  }
}
