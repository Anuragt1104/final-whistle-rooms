import crypto from "crypto";
import nacl from "tweetnacl";
import { base58Decode } from "@/lib/util/base58";

const NONCE_TTL_MS = 5 * 60_000;
const SESSION_TTL_MS = 15 * 60_000;

type NonceRecord = { nonce: string; expiresAt: number; used: boolean };
const globalAuth = globalThis as unknown as {
  __fwr_auth_nonces?: Map<string, NonceRecord>;
};
const nonces = (globalAuth.__fwr_auth_nonces ??= new Map());

function b64url(value: string | Buffer): string {
  return Buffer.from(value).toString("base64url");
}

function secret(): string {
  return process.env.AUTH_SESSION_SECRET || "final-whistle-local-session-secret";
}

function sign(value: string): string {
  return crypto.createHmac("sha256", secret()).update(value).digest("base64url");
}

export function issueNonce(wallet: string, now = Date.now()) {
  const publicKey = base58Decode(wallet);
  if (publicKey.length !== nacl.sign.publicKeyLength) throw new Error("invalid wallet");
  const nonce = crypto.randomBytes(24).toString("base64url");
  const expiresAt = now + NONCE_TTL_MS;
  nonces.set(wallet, { nonce, expiresAt, used: false });
  return {
    nonce,
    expiresAt,
    message: `Final Whistle sign-in\nWallet: ${wallet}\nNonce: ${nonce}\nExpires: ${expiresAt}`,
  };
}

export function verifyWalletSignature(input: {
  wallet: string;
  signature: string;
  message: string;
  now?: number;
}): { token: string; fanId: string; expiresAt: number } {
  const now = input.now ?? Date.now();
  const record = nonces.get(input.wallet);
  if (!record || record.used || record.expiresAt < now) throw new Error("nonce expired or used");
  const expected = `Final Whistle sign-in\nWallet: ${input.wallet}\nNonce: ${record.nonce}\nExpires: ${record.expiresAt}`;
  if (input.message !== expected) throw new Error("message mismatch");
  const ok = nacl.sign.detached.verify(
    new TextEncoder().encode(input.message),
    base58Decode(input.signature),
    base58Decode(input.wallet),
  );
  if (!ok) throw new Error("invalid signature");
  record.used = true;
  const expiresAt = now + SESSION_TTL_MS;
  const payload = b64url(JSON.stringify({ sub: input.wallet, exp: expiresAt }));
  return { token: `${payload}.${sign(payload)}`, fanId: input.wallet, expiresAt };
}

export function verifySessionToken(token: string, now = Date.now()): string {
  const [payload, signature, extra] = token.split(".");
  if (!payload || !signature || extra || !crypto.timingSafeEqual(Buffer.from(signature), Buffer.from(sign(payload)))) {
    throw new Error("invalid bearer token");
  }
  const decoded = JSON.parse(Buffer.from(payload, "base64url").toString()) as {
    sub?: string;
    exp?: number;
  };
  if (!decoded.sub || !decoded.exp || decoded.exp < now) throw new Error("session expired");
  return decoded.sub;
}

export function authenticatedFan(request: Request): string {
  const value = request.headers.get("authorization");
  if (!value?.startsWith("Bearer ")) throw new Error("authentication required");
  return verifySessionToken(value.slice(7).trim());
}

export function __resetAuthForTests() {
  nonces.clear();
}
