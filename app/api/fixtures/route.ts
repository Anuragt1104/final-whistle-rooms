import { NextResponse } from "next/server";
import { getSource } from "@/lib/txline/source";

export const dynamic = "force-dynamic";

export async function GET() {
  try {
    const fixtures = await getSource().listFixtures();
    return NextResponse.json({ fixtures });
  } catch (e) {
    return NextResponse.json({ error: String(e), fixtures: [] }, { status: 500 });
  }
}
