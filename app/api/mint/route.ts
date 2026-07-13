import { createHash } from "node:crypto";
import { NextRequest, NextResponse } from "next/server";
import { getCard, inventoryOf } from "@/lib/cards/economy";
import { anchorConfigured, anchorRoot, explorerTxUrl } from "@/lib/solana/anchor";
import { recordRevenue } from "@/lib/platform/ledger";
import { addXp, XP } from "@/lib/platform/pass";

export const dynamic = "force-dynamic";

/**
 * Mint a card on Solana (Revenue Layer 4). Most cards stay off-chain; owners
 * mint the ones that matter. Demo rail: the card's canonical leaf is committed
 * in a REAL devnet memo tx (same anchor infra as room proofs) and the mint fee
 * split is recorded — ◎0.02 total, platform keeps ◎0.005. The mainnet upgrade
 * swaps the memo for a Metaplex cNFT mint; fee model unchanged.
 */
const MINT_FEE_LAMPORTS = 20_000_000; // ◎0.02
const PLATFORM_SHARE_LAMPORTS = 5_000_000; // ◎0.005

const minted = new Map<string, { signature: string; explorerUrl: string; at: number }>();

export async function POST(req: NextRequest) {
  const body = await req.json().catch(() => ({}));
  const fanId = String(body.fanId ?? "");
  const cardId = String(body.cardId ?? "");
  if (!fanId || !cardId) return NextResponse.json({ error: "fanId and cardId required" }, { status: 400 });

  const card = getCard(cardId);
  if (!card) return NextResponse.json({ error: "Unknown card" }, { status: 404 });
  const inv = inventoryOf(fanId);
  const owned = [...inv.moments, ...inv.players, ...inv.skills].some((c) => c.id === cardId);
  if (!owned) return NextResponse.json({ error: "You don't own that card" }, { status: 403 });

  const prior = minted.get(cardId);
  if (prior) return NextResponse.json({ ...prior, cached: true, feeLamports: MINT_FEE_LAMPORTS, platformLamports: PLATFORM_SHARE_LAMPORTS });

  if (!anchorConfigured()) {
    return NextResponse.json({ error: "On-chain minting not configured on this server." }, { status: 501 });
  }
  try {
    const signature = await anchorRoot(`mint-${cardId.slice(0, 18)}`, hex64(card.leafData));
    const entry = { signature, explorerUrl: explorerTxUrl(signature), at: Date.now() };
    minted.set(cardId, entry);
    recordRevenue("mint-fee", PLATFORM_SHARE_LAMPORTS, "lamports", `mint ${cardId.slice(0, 14)}…`, fanId);
    addXp(fanId, XP.cardMintedOnChain, "mint");
    return NextResponse.json({ ...entry, cached: false, feeLamports: MINT_FEE_LAMPORTS, platformLamports: PLATFORM_SHARE_LAMPORTS });
  } catch (e) {
    return NextResponse.json({ error: String(e) }, { status: 502 });
  }
}

/** GET /api/mint?cardId= — mint status. */
export async function GET(req: NextRequest) {
  const cardId = req.nextUrl.searchParams.get("cardId") ?? "";
  const entry = minted.get(cardId);
  return NextResponse.json(entry ? { minted: true, ...entry } : { minted: false });
}

/** anchorRoot expects a 64-hex root — hash the card leaf into one. */
function hex64(leaf: string): string {
  return createHash("sha256").update(leaf, "utf8").digest("hex");
}
