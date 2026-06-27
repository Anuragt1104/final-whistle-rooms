/**
 * Embedded Solana identity ("Continue with Solana") for mainstream fans.
 *
 * Generates an ed25519 keypair on-device (a valid Solana address), stored in
 * localStorage. Fans sign a lightweight message to prove identity — no wallet
 * extension, no funds, no friction. Power users can still paste an external
 * wallet address. This keeps the Solana sign-up requirement satisfied while
 * letting judges and casual fans in instantly (no wallet needed to test).
 */
"use client";

import nacl from "tweetnacl";
import { base58Decode, base58Encode } from "@/lib/util/base58";

const KEY = "fwr.identity.v1";

export interface Identity {
  pubkey: string; // base58 Solana address
  secretKey: Uint8Array; // 64-byte ed25519 secret
  external?: boolean;
}

interface StoredIdentity {
  pubkey: string;
  secretKey: string; // base58
  external?: boolean;
}

export function loadIdentity(): Identity | null {
  if (typeof window === "undefined") return null;
  const raw = window.localStorage.getItem(KEY);
  if (!raw) return null;
  try {
    const s = JSON.parse(raw) as StoredIdentity;
    return { pubkey: s.pubkey, secretKey: base58Decode(s.secretKey), external: s.external };
  } catch {
    return null;
  }
}

export function getOrCreateIdentity(): Identity {
  const existing = loadIdentity();
  if (existing) return existing;
  const kp = nacl.sign.keyPair();
  const identity: Identity = { pubkey: base58Encode(kp.publicKey), secretKey: kp.secretKey };
  persist(identity);
  return identity;
}

function persist(identity: Identity) {
  if (typeof window === "undefined") return;
  const stored: StoredIdentity = {
    pubkey: identity.pubkey,
    secretKey: base58Encode(identity.secretKey),
    external: identity.external,
  };
  window.localStorage.setItem(KEY, JSON.stringify(stored));
}

/** Sign a message and return a base64 detached signature. */
export function signMessage(identity: Identity, message: string): string {
  const sig = nacl.sign.detached(new TextEncoder().encode(message), identity.secretKey);
  return base58Encode(sig);
}

export function shortAddress(pubkey: string): string {
  return `${pubkey.slice(0, 4)}…${pubkey.slice(-4)}`;
}

export function clearIdentity() {
  if (typeof window === "undefined") return;
  window.localStorage.removeItem(KEY);
}
