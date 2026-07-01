import { NextResponse } from "next/server";
import { anchorConfigured, anchorCluster, anchorRoot, explorerTxUrl } from "@/lib/solana/anchor";

export const dynamic = "force-dynamic";

/**
 * Stateless anchor endpoint — timestamps an arbitrary Merkle root on Solana.
 *
 * Solo (on-device) rooms have no server-side room, so they can't use
 * /api/rooms/[id]/proof to anchor. They compute their root on device and POST
 * it here; the operator key signs a memo tx and returns the signature + a
 * Solana Explorer link. Idempotent per root and rate-limited, since submitting
 * a real (devnet) transaction on every call would otherwise be abusable.
 */
const HEX64 = /^[0-9a-f]{64}$/;

// idempotency: a given root maps to one anchor tx (re-anchoring is a no-op)
const anchored = new Map<string, { sig: string; ts: number }>();
const CACHE_TTL = 6 * 60 * 60 * 1000; // 6h

// coarse global rate limit — protects the devnet key + RPC from spam
const RATE_MAX = 20;
const RATE_WINDOW = 60 * 1000;
let windowStart = 0;
let windowCount = 0;

function rateLimited(now: number): boolean {
  if (now - windowStart > RATE_WINDOW) {
    windowStart = now;
    windowCount = 0;
  }
  windowCount++;
  return windowCount > RATE_MAX;
}

export async function POST(req: Request) {
  if (!anchorConfigured()) {
    return NextResponse.json(
      { error: "On-chain anchoring is not configured on this server." },
      { status: 501 },
    );
  }

  let body: { root?: unknown; tag?: unknown };
  try {
    body = await req.json();
  } catch {
    return NextResponse.json({ error: "Invalid JSON body" }, { status: 400 });
  }

  const root = typeof body.root === "string" ? body.root.trim().toLowerCase() : "";
  if (!HEX64.test(root)) {
    return NextResponse.json({ error: "root must be a 64-char hex SHA-256 Merkle root" }, { status: 400 });
  }
  const tag = typeof body.tag === "string" ? body.tag.replace(/[^A-Za-z0-9_-]/g, "").slice(0, 24) || "solo" : "solo";

  const now = Date.now();

  // idempotent: same root -> same tx
  const hit = anchored.get(root);
  if (hit && now - hit.ts < CACHE_TTL) {
    return NextResponse.json({
      signature: hit.sig,
      explorerUrl: explorerTxUrl(hit.sig),
      cluster: anchorCluster(),
      cached: true,
    });
  }

  if (rateLimited(now)) {
    return NextResponse.json({ error: "Anchor rate limit reached — try again shortly." }, { status: 429 });
  }

  try {
    const sig = await anchorRoot(tag, root);
    anchored.set(root, { sig, ts: now });
    return NextResponse.json({
      signature: sig,
      explorerUrl: explorerTxUrl(sig),
      cluster: anchorCluster(),
      cached: false,
    });
  } catch (e) {
    return NextResponse.json({ error: String(e) }, { status: 500 });
  }
}
