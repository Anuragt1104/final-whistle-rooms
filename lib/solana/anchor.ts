/**
 * On-chain anchor for the room proof (server-side).
 *
 * Writes the room's Merkle root into an SPL Memo transaction so the "what data
 * the room reacted to" fingerprint is timestamped on Solana. This mirrors
 * TxLINE's own on-chain verification model and turns trust into a fan-visible
 * feature. Proofs verify locally without it; anchoring adds a public, immutable
 * timestamp anyone can look up on Solana Explorer.
 *
 * Anchoring has its OWN cluster (default devnet) independent of the wallet
 * cluster (NEXT_PUBLIC_SOLANA_CLUSTER, which may be mainnet for the live oracle
 * subscription) — so the anchor tx and the explorer link always agree, and the
 * demo never spends mainnet SOL unless explicitly configured to.
 */
import {
  Connection,
  Keypair,
  PublicKey,
  Transaction,
  TransactionInstruction,
  sendAndConfirmTransaction,
} from "@solana/web3.js";
import { base58Decode } from "@/lib/util/base58";

const MEMO_PROGRAM_ID = new PublicKey("MemoSq4gqABAXKb96qnH8TysNcWxMyWCqXgDLGmfcHr");

export function anchorConfigured(): boolean {
  return !!process.env.SOLANA_ANCHOR_SECRET_KEY;
}

/** The cluster the anchor tx is submitted to (independent of the wallet cluster). */
export function anchorCluster(): string {
  return process.env.SOLANA_ANCHOR_CLUSTER ?? "devnet";
}

export function clusterUrl(): string {
  if (process.env.SOLANA_ANCHOR_RPC) return process.env.SOLANA_ANCHOR_RPC;
  switch (anchorCluster()) {
    case "mainnet-beta":
    case "mainnet":
      return "https://api.mainnet-beta.solana.com";
    case "testnet":
      return "https://api.testnet.solana.com";
    default:
      return "https://api.devnet.solana.com";
  }
}

function payer(): Keypair {
  const raw = process.env.SOLANA_ANCHOR_SECRET_KEY as string;
  const bytes = raw.trim().startsWith("[")
    ? Uint8Array.from(JSON.parse(raw) as number[])
    : base58Decode(raw.trim());
  return Keypair.fromSecretKey(bytes);
}

/** The anchor wallet's public key (for diagnostics / funding). */
export function anchorPublicKey(): string | null {
  if (!anchorConfigured()) return null;
  try {
    return payer().publicKey.toBase58();
  } catch {
    return null;
  }
}

/** Anchor a Merkle root via a memo tx. `tag` labels the memo (room id or fixture). */
export async function anchorRoot(tag: string, root: string): Promise<string> {
  if (!anchorConfigured()) throw new Error("SOLANA_ANCHOR_SECRET_KEY not set");
  const connection = new Connection(clusterUrl(), "confirmed");
  const kp = payer();
  const memo = `FWR:${tag}:${root}`;
  const ix = new TransactionInstruction({
    keys: [{ pubkey: kp.publicKey, isSigner: true, isWritable: true }],
    programId: MEMO_PROGRAM_ID,
    data: Buffer.from(memo, "utf8"),
  });
  const tx = new Transaction().add(ix);
  const sig = await sendAndConfirmTransaction(connection, tx, [kp], {
    commitment: "confirmed",
  });
  return sig;
}

export function explorerTxUrl(sig: string): string {
  return `https://explorer.solana.com/tx/${sig}?cluster=${anchorCluster()}`;
}
