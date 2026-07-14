import { NextResponse } from "next/server";
import { getTeamTournamentView } from "@/lib/txline/intelligence-service";

export const dynamic = "force-dynamic";

export async function GET(
  _req: Request,
  { params }: { params: Promise<{ teamId: string }> },
) {
  const { teamId } = await params;
  try {
    const team = await getTeamTournamentView(teamId);
    if (!team) return NextResponse.json({ error: "Team not found" }, { status: 404 });
    return NextResponse.json({ team });
  } catch (error) {
    return NextResponse.json({ error: String(error) }, { status: 503 });
  }
}

