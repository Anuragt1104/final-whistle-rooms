"use client";

import { useEffect, useState } from "react";
import { Modal } from "@/components/Modal";
import { api } from "@/lib/client/api";

type Proof = Awaited<ReturnType<typeof api.proof>>;

export function ProofModal({
  roomId,
  open,
  onClose,
  isHost,
}: {
  roomId: string;
  open: boolean;
  onClose: () => void;
  isHost: boolean;
}) {
  const [proof, setProof] = useState<Proof | null>(null);
  const [anchoring, setAnchoring] = useState(false);
  const [anchorUrl, setAnchorUrl] = useState<string | null>(null);
  const [err, setErr] = useState("");

  useEffect(() => {
    if (!open) return;
    setErr("");
    api.proof(roomId).then(setProof).catch((e) => setErr(String(e)));
  }, [open, roomId]);

  async function anchor() {
    setAnchoring(true);
    setErr("");
    try {
      const r = await api.anchor(roomId);
      setAnchorUrl(r.explorerUrl);
      const p = await api.proof(roomId);
      setProof(p);
    } catch (e) {
      setErr(String(e instanceof Error ? e.message : e));
    } finally {
      setAnchoring(false);
    }
  }

  return (
    <Modal open={open} onClose={onClose} title="Verified by TxLINE on Solana">
      <p className="mb-3 text-sm text-[var(--color-mut)]">
        Every match event this room reacted to is hashed into a Merkle tree. The{" "}
        <span className="text-white">root</span> is a tamper-evident fingerprint of the verified
        TxLINE data the room responded to — the same Merkle-proof model TxLINE uses for its feed,
        surfaced here as a fan-facing trust feature.
      </p>

      {!proof ? (
        <div className="h-24 shimmer rounded-lg" />
      ) : (
        <div className="space-y-3 text-sm">
          <Field label="Events anchored (Merkle leaves)">{proof.leafCount}</Field>
          <Field label="Merkle root (SHA-256)">
            <code className="break-all text-[11px] text-[var(--color-lime)]">{proof.root}</code>
          </Field>

          {proof.sample && (
            <div className="rounded-lg border border-[var(--color-line)] bg-black/30 p-3">
              <div className="mb-1 text-[11px] uppercase tracking-wide text-[var(--color-mut)]">
                Live inclusion proof — latest event
              </div>
              <code className="block break-all text-[11px] text-white/80">{proof.sample.leaf}</code>
              <div className="mt-2 text-xs">
                {proof.sample.verified ? (
                  <span className="text-[var(--color-lime)]">
                    ✓ Verified against the root with a {proof.sample.proof.length}-node proof
                  </span>
                ) : (
                  <span className="text-[var(--color-away)]">Verification failed</span>
                )}
              </div>
            </div>
          )}

          <div className="rounded-lg border border-[var(--color-line)] bg-black/30 p-3">
            <div className="mb-1 text-[11px] uppercase tracking-wide text-[var(--color-mut)]">
              On-chain anchor ({proof.cluster})
            </div>
            {proof.anchored && proof.anchorSignature ? (
              <a
                className="break-all text-[11px] text-[var(--color-home)] underline"
                href={`https://explorer.solana.com/tx/${proof.anchorSignature}?cluster=${proof.cluster}`}
                target="_blank"
                rel="noreferrer"
              >
                {proof.anchorSignature}
              </a>
            ) : proof.anchorAvailable ? (
              isHost ? (
                <button className="btn btn-ghost w-full text-xs" onClick={anchor} disabled={anchoring}>
                  {anchoring ? "Anchoring…" : "Anchor this root on Solana"}
                </button>
              ) : (
                <span className="text-[11px] text-[var(--color-mut)]">Host can anchor this root.</span>
              )
            ) : (
              <span className="text-[11px] text-[var(--color-mut)]">
                Proof verifies locally. Set SOLANA_ANCHOR_SECRET_KEY to also timestamp the root
                on-chain.
              </span>
            )}
            {anchorUrl && (
              <a className="mt-1 block text-[11px] text-[var(--color-home)] underline" href={anchorUrl} target="_blank" rel="noreferrer">
                View transaction ↗
              </a>
            )}
          </div>

          <p className="text-[11px] leading-relaxed text-[var(--color-mut)]">
            In production this maps to TxLINE&apos;s proof endpoints —{" "}
            <code className="text-white/70">/api/scores/stat-validation</code> and{" "}
            <code className="text-white/70">/api/odds/validation</code> — so any score or odds the
            room reacted to can be independently verified on Solana.
          </p>
        </div>
      )}

      {err && <p className="mt-2 text-xs text-[var(--color-away)]">{err}</p>}
    </Modal>
  );
}

function Field({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div>
      <div className="text-[11px] uppercase tracking-wide text-[var(--color-mut)]">{label}</div>
      <div className="mt-0.5">{children}</div>
    </div>
  );
}
