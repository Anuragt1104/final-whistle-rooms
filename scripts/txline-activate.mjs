/**
 * TxLINE activation — mints a real API token for the FREE World Cup tier and
 * wires it into .env.local so the backend serves live World Cup data.
 *
 * Flow (verified against github.com/txodds/tx-on-chain + worldcup docs):
 *   guest JWT -> on-chain `subscribe` (free tier, 0 TxL) -> signed activation
 *   -> API token. Then discovers the World Cup competitionId and verifies a
 *   live scores/odds fetch.
 *
 * RUN ON A MACHINE WITH INTERNET + a Solana wallet.
 *
 *   # Devnet (free, self-funds via airdrop, TEST data backend):
 *   NETWORK=devnet node scripts/txline-activate.mjs
 *
 *   # Mainnet (real live World Cup data; wallet needs ~0.02 SOL for fees+rent):
 *   NETWORK=mainnet SERVICE_LEVEL=12 WALLET_SECRET="$(cat ~/.config/solana/id.json)" \
 *     node scripts/txline-activate.mjs
 *
 * Env:
 *   NETWORK        devnet | mainnet            (default mainnet)
 *   SERVICE_LEVEL  1 (60s delay) | 12 (real-time)  (default 1)
 *   WEEKS          subscription weeks, multiple of 4 (default 4)
 *   WALLET_SECRET  JSON array | base58 | path to a Solana keypair file
 *                  (optional on devnet — a fresh wallet is generated + airdropped)
 */
import { readFileSync, existsSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";
import * as anchor from "@coral-xyz/anchor";
import { Connection, Keypair, PublicKey, SystemProgram } from "@solana/web3.js";
import {
  TOKEN_2022_PROGRAM_ID,
  ASSOCIATED_TOKEN_PROGRAM_ID,
  getOrCreateAssociatedTokenAccount,
  getAssociatedTokenAddressSync,
} from "@solana/spl-token";
import nacl from "tweetnacl";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const idl = JSON.parse(readFileSync(path.join(root, "idl", "txoracle.json"), "utf8"));

const NETWORK = process.env.NETWORK === "devnet" ? "devnet" : "mainnet";
const RPC =
  process.env.SOLANA_RPC ||
  (NETWORK === "mainnet" ? "https://api.mainnet-beta.solana.com" : "https://api.devnet.solana.com");
const API = NETWORK === "mainnet" ? "https://txline.txodds.com" : "https://txline-dev.txodds.com";
const SERVICE_LEVEL_ID = Number(process.env.SERVICE_LEVEL || 1); // 1 = 60s delay, 12 = real-time
const WEEKS = Number(process.env.WEEKS || 4); // multiple of 4
const SELECTED_LEAGUES = []; // [] = standard bundle = World Cup & Int Friendlies (free)

const B58 = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz";
function base58Decode(str) {
  const bytes = [0];
  for (const ch of str) {
    const v = B58.indexOf(ch);
    if (v < 0) throw new Error(`bad base58 char ${ch}`);
    let carry = v;
    for (let j = 0; j < bytes.length; j++) {
      carry += bytes[j] * 58;
      bytes[j] = carry & 0xff;
      carry >>= 8;
    }
    while (carry) {
      bytes.push(carry & 0xff);
      carry >>= 8;
    }
  }
  for (let k = 0; str[k] === "1"; k++) bytes.push(0);
  return Uint8Array.from(bytes.reverse());
}

function loadWallet() {
  let raw = process.env.WALLET_SECRET;
  if (raw && existsSync(raw)) raw = readFileSync(raw, "utf8");
  if (!raw) {
    if (NETWORK === "mainnet") throw new Error("WALLET_SECRET required on mainnet (a funded Solana keypair).");
    const kp = Keypair.generate();
    console.log("• generated a fresh devnet wallet");
    return kp;
  }
  raw = raw.trim();
  const bytes = raw.startsWith("[") ? Uint8Array.from(JSON.parse(raw)) : base58Decode(raw);
  return Keypair.fromSecretKey(bytes);
}

async function postJson(url, body, headers = {}) {
  const res = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json", ...headers },
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await res.text();
  if (!res.ok) throw new Error(`POST ${url} -> ${res.status}: ${text.slice(0, 300)}`);
  try {
    return JSON.parse(text);
  } catch {
    return text;
  }
}

function upsertEnv(updates) {
  const file = path.join(root, ".env.local");
  const lines = existsSync(file) ? readFileSync(file, "utf8").split("\n") : [];
  const map = new Map();
  for (const l of lines) {
    const m = l.match(/^([A-Z0-9_]+)=/);
    if (m) map.set(m[1], l);
  }
  for (const [k, v] of Object.entries(updates)) map.set(k, `${k}=${v}`);
  writeFileSync(file, [...map.values()].filter(Boolean).join("\n") + "\n");
  console.log(`• wrote ${file}`);
}

async function main() {
  console.log(`\nTxLINE activation — network=${NETWORK} service_level=${SERVICE_LEVEL_ID} weeks=${WEEKS}`);
  const wallet = loadWallet();
  console.log("• wallet:", wallet.publicKey.toBase58());

  const connection = new Connection(RPC, "confirmed");
  const bal = await connection.getBalance(wallet.publicKey);
  console.log("• balance:", (bal / 1e9).toFixed(4), "SOL");
  if (NETWORK === "devnet" && bal < 0.05e9) {
    console.log("• requesting devnet airdrop…");
    const sig = await connection.requestAirdrop(wallet.publicKey, 1e9);
    await connection.confirmTransaction(sig, "confirmed");
  } else if (NETWORK === "mainnet" && bal < 0.01e9) {
    throw new Error("Mainnet wallet needs ~0.02 SOL for the tx fee + ATA rent. Fund it and retry.");
  }

  const provider = new anchor.AnchorProvider(connection, new anchor.Wallet(wallet), { commitment: "confirmed" });
  anchor.setProvider(provider);
  const program = new anchor.Program(idl, provider);

  const TXLINE_MINT = new PublicKey(idl.constants.find((c) => c.name === "TXLINE_MINT").value);
  const [pricingMatrix] = PublicKey.findProgramAddressSync([Buffer.from("pricing_matrix")], program.programId);
  const [tokenTreasuryPda] = PublicKey.findProgramAddressSync([Buffer.from("token_treasury_v2")], program.programId);
  const tokenTreasuryVault = getAssociatedTokenAddressSync(TXLINE_MINT, tokenTreasuryPda, true, TOKEN_2022_PROGRAM_ID);

  console.log("• ensuring your TxL token account (TOKEN-2022)…");
  const userTokenAccount = await getOrCreateAssociatedTokenAccount(
    connection, wallet, TXLINE_MINT, wallet.publicKey, false, "confirmed", undefined, TOKEN_2022_PROGRAM_ID,
  );

  // 1) guest JWT
  const auth = await postJson(`${API}/auth/guest/start`);
  const jwt = auth.token || auth;
  console.log("• got guest JWT");

  // 2) on-chain subscribe (0 TxL for the free tier)
  console.log("• sending subscribe transaction…");
  const txSig = await program.methods
    .subscribe(SERVICE_LEVEL_ID, WEEKS)
    .accounts({
      user: wallet.publicKey,
      pricingMatrix,
      tokenMint: TXLINE_MINT,
      userTokenAccount: userTokenAccount.address,
      tokenTreasuryVault,
      tokenTreasuryPda,
      tokenProgram: TOKEN_2022_PROGRAM_ID,
      systemProgram: SystemProgram.programId,
      associatedTokenProgram: ASSOCIATED_TOKEN_PROGRAM_ID,
    })
    .rpc();
  console.log("• subscribe txSig:", txSig);

  // 3+4) bind message + Ed25519 detached sign + base64
  const messageString = `${txSig}:${SELECTED_LEAGUES.join(",")}:${jwt}`;
  const sig = nacl.sign.detached(new TextEncoder().encode(messageString), wallet.secretKey);
  const walletSignature = Buffer.from(sig).toString("base64");

  // 5) activate -> API token
  const activation = await postJson(
    `${API}/api/token/activate`,
    { txSig, walletSignature, leagues: SELECTED_LEAGUES },
    { Authorization: `Bearer ${jwt}` },
  );
  const apiToken = (activation && activation.token) || activation;
  console.log("• API TOKEN:", String(apiToken).slice(0, 16) + "…");

  // 6) verify live data + discover World Cup competitionId
  const headers = { Authorization: `Bearer ${jwt}`, "X-Api-Token": apiToken, Accept: "application/json" };
  let competitionId;
  try {
    const fx = await (await fetch(`${API}/api/fixtures/snapshot`, { headers })).json();
    const wc = (fx || []).find((f) => JSON.stringify(f).toLowerCase().includes("world cup"));
    competitionId = wc?.competitionId ?? wc?.CompetitionId;
    console.log(`• fixtures: ${fx?.length ?? 0} rows · World Cup competitionId: ${competitionId ?? "n/a"}`);
  } catch (e) {
    console.warn("• fixtures probe failed (token still saved):", String(e).slice(0, 120));
  }

  upsertEnv({
    TXLINE_MODE: "live",
    TXLINE_BASE_URL: API,
    TXLINE_API_TOKEN: apiToken,
    ...(competitionId ? { TXLINE_COMPETITION_ID: competitionId } : {}),
    NEXT_PUBLIC_SOLANA_CLUSTER: NETWORK === "mainnet" ? "mainnet-beta" : "devnet",
  });

  console.log("\n✅ Done. Start the backend: pnpm dev  (it now serves live TxLINE data)\n");
}

main().catch((e) => {
  console.error("\n❌ activation failed:", e?.message || e);
  process.exit(1);
});
