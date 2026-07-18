import { NextResponse } from "next/server";
import { issueNonce } from "@/lib/auth/session";

export const dynamic = "force-dynamic";

export async function POST(request: Request) {
  const body = await request.json().catch(() => ({}));
  try {
    return NextResponse.json(issueNonce(String(body.wallet ?? "")));
  } catch {
    return NextResponse.json({ error: "valid Solana wallet required" }, { status: 400 });
  }
}
