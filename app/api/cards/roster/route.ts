import { NextResponse } from "next/server";
import { ROSTER, SKILL_TEMPLATES } from "@/lib/cards/roster";

export const dynamic = "force-dynamic";

export async function GET() {
  return NextResponse.json({ roster: ROSTER, skills: SKILL_TEMPLATES });
}
