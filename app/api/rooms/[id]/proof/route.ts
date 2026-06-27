import { NextResponse } from "next/server";
import { getProofData, getRoomRuntime, setAnchor } from "@/lib/store/rooms";
import { buildMerkleTree, verifyMerkleProof } from "@/lib/util/merkle";
import { anchorConfigured, anchorRoot, explorerTxUrl } from "@/lib/solana/anchor";

export const dynamic = "force-dynamic";

/** Inspect the room proof: Merkle root + a live inclusion-proof demonstration. */
export async function GET(_req: Request, ctx: { params: Promise<{ id: string }> }) {
  const { id } = await ctx.params;
  const rt = getRoomRuntime(id);
  if (!rt) return NextResponse.json({ error: "Room not found" }, { status: 404 });
  const data = getProofData(id);
  if (!data) return NextResponse.json({ error: "No proof data" }, { status: 404 });

  const tree = buildMerkleTree(data.leaves);
  // demonstrate inclusion of the most recent reacted-to event
  let sample = null as null | {
    leaf: string;
    index: number;
    proof: ReturnType<typeof tree.proof>;
    verified: boolean;
  };
  if (data.leaves.length > 0) {
    const index = data.leaves.length - 1;
    const proof = tree.proof(index);
    sample = {
      leaf: data.leaves[index],
      index,
      proof,
      verified: verifyMerkleProof(data.leaves[index], proof, tree.root),
    };
  }

  return NextResponse.json({
    root: tree.root,
    leafCount: data.leaves.length,
    leaves: data.leaves.slice(-12),
    sample,
    anchored: rt.anchored,
    anchorSignature: rt.anchorSignature,
    anchorAvailable: anchorConfigured(),
    cluster: process.env.NEXT_PUBLIC_SOLANA_CLUSTER ?? "devnet",
  });
}

/** Anchor the current root on Solana (devnet memo). Optional — host action. */
export async function POST(_req: Request, ctx: { params: Promise<{ id: string }> }) {
  const { id } = await ctx.params;
  const data = getProofData(id);
  if (!data) return NextResponse.json({ error: "Room not found" }, { status: 404 });
  if (!anchorConfigured()) {
    return NextResponse.json(
      { error: "On-chain anchoring not configured (set SOLANA_ANCHOR_SECRET_KEY)." },
      { status: 400 },
    );
  }
  try {
    const sig = await anchorRoot(id, data.root);
    setAnchor(id, sig);
    return NextResponse.json({ signature: sig, explorerUrl: explorerTxUrl(sig) });
  } catch (e) {
    return NextResponse.json({ error: String(e) }, { status: 500 });
  }
}
