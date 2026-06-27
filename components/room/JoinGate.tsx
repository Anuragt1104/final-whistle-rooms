"use client";

import { useState } from "react";
import { api } from "@/lib/client/api";
import { useIdentity, setMemberId } from "@/lib/client/identity";
import type { Fixture } from "@/lib/txline/types";

export function JoinGate({
  roomId,
  roomName,
  fixture,
  onJoined,
}: {
  roomId: string;
  roomName: string;
  fixture: Fixture;
  onJoined: (memberId: string) => void;
}) {
  const { identity, name, connect } = useIdentity();
  const [draft, setDraft] = useState(name);
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState("");

  async function join() {
    setErr("");
    setBusy(true);
    try {
      const id = identity ?? connect(draft.trim() || "Fan");
      const { memberId } = await api.join(roomId, {
        name: draft.trim() || "Fan",
        walletPubkey: id.pubkey,
      });
      setMemberId(roomId, memberId);
      onJoined(memberId);
    } catch (e) {
      setErr(String(e instanceof Error ? e.message : e));
      setBusy(false);
    }
  }

  return (
    <div className="fixed inset-0 z-40 flex items-end justify-center bg-black/70 p-3 sm:items-center">
      <div className="card w-full max-w-[440px] animate-pulse-in p-5">
        <div className="mb-1 text-center text-3xl">
          {fixture.home.flag} vs {fixture.away.flag}
        </div>
        <h2 className="text-center text-lg font-extrabold">{roomName}</h2>
        <p className="mt-1 text-center text-sm text-[var(--color-mut)]">
          {fixture.home.name} vs {fixture.away.name}
        </p>

        <label className="mt-4 mb-1 block text-xs font-semibold uppercase tracking-wide text-[var(--color-mut)]">
          Your name
        </label>
        <input
          autoFocus
          className="input"
          placeholder="e.g. Sam"
          value={draft}
          onChange={(e) => setDraft(e.target.value)}
          onKeyDown={(e) => e.key === "Enter" && join()}
        />
        {err && <p className="mt-2 text-xs text-[var(--color-away)]">{err}</p>}
        <button className="btn btn-primary mt-4 w-full" onClick={join} disabled={busy}>
          {busy ? "Joining…" : "◎ Continue with Solana & join"}
        </button>
        <p className="mt-2 text-center text-[11px] text-[var(--color-mut)]">
          No wallet or funds needed — a secure on-device identity is created for you.
        </p>
      </div>
    </div>
  );
}
