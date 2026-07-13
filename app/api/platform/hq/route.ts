import { NextResponse } from "next/server";
import { hqView } from "@/lib/platform/ledger";

export const dynamic = "force-dynamic";

/** GET /api/platform/hq — the revenue-by-layer investor dashboard feed. */
export async function GET() {
  return NextResponse.json(hqView());
}
