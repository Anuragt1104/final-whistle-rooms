"use client";

import { useEffect, useState } from "react";
import { Brand } from "@/components/Brand";
import { Modal } from "@/components/Modal";
import { useIdentity } from "@/lib/client/identity";
import { api, type AppConfig } from "@/lib/client/api";

export function TopBar({ small }: { small?: boolean }) {
  const { identity, name, short, connect } = useIdentity();
  const [config, setConfig] = useState<AppConfig | null>(null);
  const [open, setOpen] = useState(false);
  const [draftName, setDraftName] = useState("");

  useEffect(() => {
    api.config().then(setConfig).catch(() => {});
  }, []);

  function doConnect() {
    const n = draftName.trim() || "Fan";
    connect(n);
    setOpen(false);
  }

  return (
    <header className="sticky top-0 z-30 flex items-center justify-between gap-2 border-b border-[var(--color-line)] bg-[rgba(7,11,20,0.72)] px-4 py-3 backdrop-blur">
      <Brand small={small} />
      <div className="flex items-center gap-2">
        {config && (
          <span
            className="chip"
            title={
              config.mode === "live"
                ? "Live TxLINE feed"
                : "Deterministic TxLINE-shaped replay — judge-friendly, always works"
            }
          >
            <span
              className={`live-dot inline-block h-1.5 w-1.5 rounded-full ${config.mode === "live" ? "bg-[var(--color-lime)]" : "bg-[var(--color-gold)]"}`}
            />
            {config.mode === "live" ? "Live TxLINE" : "Replay"}
          </span>
        )}
        {identity ? (
          <button className="chip" title={identity.pubkey} onClick={() => setOpen(true)}>
            <span>◎</span>
            <span className="text-white">{name || short}</span>
          </button>
        ) : (
          <button className="btn btn-primary px-3 py-1.5 text-xs" onClick={() => setOpen(true)}>
            ◎ Continue with Solana
          </button>
        )}
      </div>

      <Modal open={open} onClose={() => setOpen(false)} title="Continue with Solana">
        <p className="mb-3 text-sm text-[var(--color-mut)]">
          We create a secure on-device Solana identity for you — no wallet extension, no funds, no
          friction. Power users can connect an external wallet later.
        </p>
        <label className="mb-1 block text-xs font-semibold text-[var(--color-mut)]">Display name</label>
        <input
          autoFocus
          className="input mb-3"
          placeholder="e.g. Ana"
          defaultValue={name}
          onChange={(e) => setDraftName(e.target.value)}
          onKeyDown={(e) => e.key === "Enter" && doConnect()}
        />
        {identity && (
          <div className="mb-3 rounded-lg border border-[var(--color-line)] bg-black/30 p-2 text-xs text-[var(--color-mut)]">
            Address <span className="text-white">{short}</span>
          </div>
        )}
        <button className="btn btn-primary w-full" onClick={doConnect}>
          {identity ? "Update identity" : "Create identity & continue"}
        </button>
      </Modal>
    </header>
  );
}
