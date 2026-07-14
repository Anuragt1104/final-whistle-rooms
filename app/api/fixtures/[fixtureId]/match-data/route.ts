import { NextResponse } from "next/server";
import { getFixtureMatchData } from "@/lib/txline/intelligence-service";

export const dynamic = "force-dynamic";

export async function GET(
  _req: Request,
  { params }: { params: Promise<{ fixtureId: string }> },
) {
  const { fixtureId } = await params;
  try {
    const match = await getFixtureMatchData(fixtureId);
    if (!match) return NextResponse.json({ error: "Fixture not found" }, { status: 404 });
    return NextResponse.json({ match });
  } catch (error) {
    return NextResponse.json({ error: String(error) }, { status: 503 });
  }
}

