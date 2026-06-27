import { NextResponse } from "next/server";
import { createRoom, listRooms } from "@/lib/store/rooms";

export const dynamic = "force-dynamic";

export async function GET() {
  return NextResponse.json({ rooms: listRooms() });
}

export async function POST(req: Request) {
  const body = await req.json().catch(() => ({}));
  const { name, fixtureId, modes, hostName, hostWallet, visibility, reactionPack, voice, spoilerSafe } = body ?? {};
  if (!fixtureId) return NextResponse.json({ error: "fixtureId required" }, { status: 400 });
  const result = await createRoom({
    name: String(name ?? ""),
    fixtureId: String(fixtureId),
    modes: {
      draft: modes?.draft !== false,
      nextSwing: modes?.nextSwing !== false,
    },
    hostName: String(hostName ?? "Host"),
    hostWallet: hostWallet ? String(hostWallet) : undefined,
    visibility: visibility === "invite" ? "invite" : "public",
    reactionPack: typeof reactionPack === "string" ? reactionPack : "classic",
    voice: voice === true,
    spoilerSafe: spoilerSafe === true,
  });
  if ("error" in result) return NextResponse.json(result, { status: 400 });
  return NextResponse.json(result);
}
