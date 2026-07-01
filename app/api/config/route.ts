import { NextResponse } from "next/server";
import { sourceMode } from "@/lib/txline/source";
import { anchorConfigured, anchorCluster } from "@/lib/solana/anchor";

export const dynamic = "force-dynamic";

export async function GET() {
  return NextResponse.json({
    mode: sourceMode(),
    anchorConfigured: anchorConfigured(),
    anchorCluster: anchorCluster(),
    recapAI: !!process.env.ANTHROPIC_API_KEY,
    cluster: process.env.NEXT_PUBLIC_SOLANA_CLUSTER ?? "devnet",
  });
}
