import { NextResponse } from "next/server";
import { listRooms } from "@/lib/store/rooms";

export const dynamic = "force-dynamic";

// Rooms are auto-managed Official Match Hubs — one global room per fixture,
// joined via POST /api/fixtures/[fixtureId]/watch. There is no manual create.
export async function GET() {
  return NextResponse.json({ rooms: listRooms() });
}
