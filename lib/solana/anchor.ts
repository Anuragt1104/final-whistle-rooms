/**
 * Optional on-chain anchor for the room proof (server-side, devnet).
 *
 * Writes the room's Merkle root into an SPL Memo transaction so the "what data
 * the room reacted to" fingerprint is timestamped on Solana. This mirrors
 * TxLINE's own on-chain verification model and turns trust into a fan-visible
 * feature. Entirely optional: proofs verify locally without it, and the demo
 * works with no funded key.
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

export function clusterUrl(): string {
  return process.env.NEXT_PUBLIC_SOLANA_RPC ?? "https://api.devnet.solana.com";
}

function payer(): Keypair {
  const raw = process.env.SOLANA_ANCHOR_SECRET_KEY as string;
  const bytes = raw.trim().startsWith("[")
    ? Uint8Array.from(JSON.parse(raw) as number[])
    : base58Decode(raw.trim());
  return Keypair.fromSecretKey(bytes);
}

/** Anchor a room's Merkle root via a memo tx. Returns the tx signature. */
export async function anchorRoot(roomId: string, root: string): Promise<string> {
  if (!anchorConfigured()) throw new Error("SOLANA_ANCHOR_SECRET_KEY not set");
  const connection = new Connection(clusterUrl(), "confirmed");
  const kp = payer();
  const memo = `FWR:${roomId}:${root}`;
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
  const cluster = process.env.NEXT_PUBLIC_SOLANA_CLUSTER ?? "devnet";
  return `https://explorer.solana.com/tx/${sig}?cluster=${cluster}`;
}
