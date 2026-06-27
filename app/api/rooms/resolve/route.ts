import { NextResponse } from "next/server";
import { findByCode } from "@/lib/store/rooms";

export const dynamic = "force-dynamic";

/** Resolve a share code (e.g. from an invite link) to a room id. */
export async function GET(req: Request) {
  const code = new URL(req.url).searchParams.get("code") ?? "";
  if (!code) return NextResponse.json({ error: "code required" }, { status: 400 });
  const rt = findByCode(code);
  if (!rt) return NextResponse.json({ error: "Room not found" }, { status: 404 });
  return NextResponse.json({ id: rt.id });
}
