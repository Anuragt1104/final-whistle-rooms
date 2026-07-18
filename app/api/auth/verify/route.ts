import { NextResponse } from "next/server";
import { verifyWalletSignature } from "@/lib/auth/session";

export const dynamic = "force-dynamic";

export async function POST(request: Request) {
  const body = await request.json().catch(() => ({}));
  try {
    return NextResponse.json(
      verifyWalletSignature({
        wallet: String(body.wallet ?? ""),
        signature: String(body.signature ?? ""),
        message: String(body.message ?? ""),
      }),
    );
  } catch (error) {
    return NextResponse.json(
      { error: error instanceof Error ? error.message : "verification failed" },
      { status: 401 },
    );
  }
}
