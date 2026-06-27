"use client";

import { useEffect, useMemo, useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import { TopBar } from "@/components/TopBar";
import { api } from "@/lib/client/api";
import { useIdentity, setMemberId } from "@/lib/client/identity";
import { relativeKickoff } from "@/lib/util/format";
import type { Fixture } from "@/lib/txline/types";

export function CreateClient() {
  const router = useRouter();
  const params = useSearchParams();
  const { identity, name, connect } = useIdentity();

  const [fixtures, setFixtures] = useState<Fixture[]>([]);
  const [fixtureId, setFixtureId] = useState(params.get("fixture") ?? "");
  const [hostName, setHostName] = useState("");
  const [roomName, setRoomName] = useState("");
  const [draft, setDraft] = useState(true);
  const [nextSwing, setNextSwing] = useState(true);
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState("");

  useEffect(() => {
    api.fixtures().then((r) => {
      setFixtures(r.fixtures);
      if (!fixtureId && r.fixtures[0]) setFixtureId(r.fixtures[0].id);
    });
  }, []); // eslint-disable-line react-hooks/exhaustive-deps

  useEffect(() => {
    if (name) setHostName(name);
  }, [name]);

  const fixture = useMemo(() => fixtures.find((f) => f.id === fixtureId), [fixtures, fixtureId]);

  useEffect(() => {
    if (fixture && !roomName) setRoomName(`${fixture.home.name} watch party`);
  }, [fixture]); // eslint-disable-line react-hooks/exhaustive-deps

  async function create() {
    setErr("");
    const finalName = hostName.trim() || "Host";
    if (!fixtureId) {
      setErr("Pick a match first");
      return;
    }
    setBusy(true);
    try {
      const id = identity ?? connect(finalName);
      const { roomId, hostId } = await api.createRoom({
        name: roomName.trim() || `${fixture?.home.name ?? "World Cup"} watch party`,
        fixtureId,
        modes: { draft, nextSwing },
        hostName: finalName,
        hostWallet: id.pubkey,
      });
      setMemberId(roomId, hostId);
      router.push(`/room/${roomId}`);
    } catch (e) {
      setErr(String(e instanceof Error ? e.message : e));
      setBusy(false);
    }
  }

  return (
    <div className="pb-16">
      <TopBar small />
      <main className="px-4">
        <h1 className="mt-4 text-xl font-extrabold">Create a room</h1>
        <p className="mt-1 text-sm text-[var(--color-mut)]">
          Spin up a private watch party. Share the code and your group joins on their phones.
        </p>

        {/* Match picker */}
        <label className="mt-5 mb-1 block text-xs font-semibold uppercase tracking-wide text-[var(--color-mut)]">
          Match
        </label>
        <div className="card max-h-56 overflow-auto p-1 no-scrollbar">
          {fixtures.map((f) => (
            <button
              key={f.id}
              onClick={() => setFixtureId(f.id)}
              className={`flex w-full items-center justify-between rounded-lg px-3 py-2 text-left text-sm ${
                fixtureId === f.id ? "bg-[var(--color-lime)]/15 ring-1 ring-[var(--color-lime)]/40" : "hover:bg-white/5"
              }`}
            >
              <span className="flex items-center gap-2">
                <span className="text-base">{f.home.flag}</span>
                <span className="font-semibold">{f.home.code}</span>
                <span className="text-[var(--color-mut)]">v</span>
                <span className="font-semibold">{f.away.code}</span>
                <span className="text-base">{f.away.flag}</span>
              </span>
              <span className="text-[11px] text-[var(--color-mut)]">
                {f.status === "live" ? "LIVE" : relativeKickoff(f.kickoff)}
              </span>
            </button>
          ))}
        </div>

        {/* Room name */}
        <label className="mt-5 mb-1 block text-xs font-semibold uppercase tracking-wide text-[var(--color-mut)]">
          Room name
        </label>
        <input className="input" value={roomName} onChange={(e) => setRoomName(e.target.value)} placeholder="Sunday squad" />

        {/* Your name */}
        <label className="mt-4 mb-1 block text-xs font-semibold uppercase tracking-wide text-[var(--color-mut)]">
          Your name
        </label>
        <input className="input" value={hostName} onChange={(e) => setHostName(e.target.value)} placeholder="e.g. Ana" />

        {/* Modes */}
        <label className="mt-5 mb-2 block text-xs font-semibold uppercase tracking-wide text-[var(--color-mut)]">
          Game modes
        </label>
        <div className="grid grid-cols-2 gap-2">
          <ModeCard
            active={draft}
            onClick={() => setDraft((v) => !v)}
            emoji="🏆"
            title="Tournament Draft"
            sub="Draft a side, earn points as they perform"
          />
          <ModeCard
            active={nextSwing}
            onClick={() => setNextSwing((v) => !v)}
            emoji="⚡"
            title="Next Swing"
            sub="Live micro-predictions on goals, corners, odds"
          />
        </div>

        {err && <p className="mt-3 text-sm text-[var(--color-away)]">{err}</p>}

        <button className="btn btn-primary mt-5 w-full" onClick={create} disabled={busy}>
          {busy ? "Creating…" : "Create room & invite friends"}
        </button>
        <p className="mt-2 text-center text-[11px] text-[var(--color-mut)]">
          A secure on-device Solana identity is created automatically.
        </p>
      </main>
    </div>
  );
}

function ModeCard({
  active,
  onClick,
  emoji,
  title,
  sub,
}: {
  active: boolean;
  onClick: () => void;
  emoji: string;
  title: string;
  sub: string;
}) {
  return (
    <button
      onClick={onClick}
      className={`card p-3 text-left transition ${
        active ? "ring-2 ring-[var(--color-lime)]/60" : "opacity-60 hover:opacity-100"
      }`}
    >
      <div className="flex items-center justify-between">
        <span className="text-xl">{emoji}</span>
        <span className={`h-4 w-4 rounded-full border ${active ? "border-[var(--color-lime)] bg-[var(--color-lime)]" : "border-[var(--color-line)]"}`} />
      </div>
      <div className="mt-2 text-sm font-bold">{title}</div>
      <div className="text-[11px] text-[var(--color-mut)]">{sub}</div>
    </button>
  );
}
