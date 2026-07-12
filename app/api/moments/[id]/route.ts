import { NextResponse } from "next/server";
import { getMoment, momentProof } from "@/lib/cards/economy";

export const dynamic = "force-dynamic";

export async function GET(
  _req: Request,
  { params }: { params: Promise<{ id: string }> },
) {
  const { id } = await params;
  const moment = getMoment(id);
  if (!moment) return NextResponse.json({ error: "Moment not found" }, { status: 404 });
  const proof = momentProof(id);
  return NextResponse.json({ moment, proof });
}
