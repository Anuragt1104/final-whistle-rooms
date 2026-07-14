import { NextResponse } from "next/server";
import { getTournamentOverview } from "@/lib/txline/intelligence-service";

export const dynamic = "force-dynamic";

export async function GET() {
  try {
    return NextResponse.json(await getTournamentOverview());
  } catch (error) {
    return NextResponse.json({ error: String(error) }, { status: 503 });
  }
}

