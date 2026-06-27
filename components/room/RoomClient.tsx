"use client";

import { useEffect, useMemo, useState } from "react";
import Link from "next/link";
import { TopBar } from "@/components/TopBar";
import { ScoreRail } from "@/components/room/ScoreRail";
import { PulseFeed } from "@/components/room/PulseFeed";
import { NextSwingCard } from "@/components/room/NextSwingCard";
import { Leaderboard } from "@/components/room/Leaderboard";
import { ChatDock } from "@/components/room/ChatDock";
import { RecapCard } from "@/components/room/RecapCard";
import { ProofModal } from "@/components/room/ProofModal";
import { HostBar } from "@/components/room/HostBar";
import { SidePicker } from "@/components/room/SidePicker";
import { JoinGate } from "@/components/room/JoinGate";
import { useRoomStream } from "@/lib/client/useRoomStream";
import { api } from "@/lib/client/api";
import { getMemberId } from "@/lib/client/identity";
import type { RoomView } from "@/lib/store/types";

type Tab = "watch" | "board" | "chat";

export function RoomClient({ id }: { id: string }) {
  const { room: streamed } = useRoomStream(id);
  const [initial, setInitial] = useState<RoomView | null>(null);
  const [notFound, setNotFound] = useState(false);
  const [memberId, setMemberIdState] = useState<string | null>(null);
  const [tab, setTab] = useState<Tab>("watch");
  const [proofOpen, setProofOpen] = useState(false);
  const [myPicks, setMyPicks] = useState<Record<string, string>>({});
  const [aiOn, setAiOn] = useState(false);

  const room = streamed ?? initial;

  // bootstrap: membership, picks, initial snapshot, config
  useEffect(() => {
    setMemberIdState(getMemberId(id));
    try {
      const raw = window.localStorage.getItem(`fwr.picks.${id}`);
      if (raw) setMyPicks(JSON.parse(raw));
    } catch {}
    api.room(id).then((r) => setInitial(r.room)).catch(() => setNotFound(true));
    api.config().then((c) => setAiOn(c.recapAI)).catch(() => {});
  }, [id]);

  const me = useMemo(
    () => room?.members.find((m) => m.id === memberId) ?? null,
    [room, memberId],
  );
  const joined = !!me;
  const isHost = !!room && room.hostId === memberId;

  function persistPicks(next: Record<string, string>) {
    setMyPicks(next);
    try {
      window.localStorage.setItem(`fwr.picks.${id}`, JSON.stringify(next));
    } catch {}
  }

  async function handlePick(promptId: string, optionKey: string) {
    if (!memberId) return;
    const next = { ...myPicks, [promptId]: optionKey };
    persistPicks(next);
    try {
      await api.predict(id, memberId, promptId, optionKey);
    } catch {
      /* window may have just locked — leave local pick as-is */
    }
  }

  async function handleSide(side: "home" | "away") {
    if (!memberId) return;
    await api.pickSide(id, memberId, side).catch(() => {});
  }

  async function handleStart() {
    if (!memberId) return;
    await api.start(id, memberId).catch(() => {});
  }

  async function handleChat(text: string) {
    if (!memberId) return;
    await api.chat(id, memberId, text, "chat").catch(() => {});
  }
  async function handleReact(emoji: string) {
    if (!memberId) return;
    await api.chat(id, memberId, emoji, "reaction").catch(() => {});
  }

  if (notFound) {
    return (
      <div className="p-6 text-center">
        <TopBar small />
        <p className="mt-10 text-sm text-[var(--color-mut)]">This room doesn&apos;t exist anymore.</p>
        <Link href="/" className="btn btn-primary mt-4 inline-flex">
          Back home
        </Link>
      </div>
    );
  }

  if (!room) {
    return (
      <div>
        <TopBar small />
        <div className="space-y-3 p-4">
          <div className="card h-40 shimmer" />
          <div className="card h-24 shimmer" />
        </div>
      </div>
    );
  }

  const latestRecap = room.recaps[room.recaps.length - 1];
  const showSwing = room.modes.nextSwing && (room.status === "live" || room.prompts.length > 0);
  const showDraft =
    room.modes.draft && joined && !me?.side && room.status !== "finished";

  return (
    <div className="pb-24">
      <TopBar small />

      <main className="px-4">
        {/* title + proof */}
        <div className="mt-3 flex items-center justify-between gap-2">
          <div className="min-w-0">
            <h1 className="truncate text-lg font-extrabold">{room.name}</h1>
            <p className="text-[11px] text-[var(--color-mut)]">{room.fixture.stage}</p>
          </div>
          <button className="chip shrink-0 text-[var(--color-lime)]" onClick={() => setProofOpen(true)}>
            🛡️ Verified {room.proof.anchored ? "· ⛓ on-chain" : `· ${room.proof.leafCount}`}
          </button>
        </div>

        <div className="mt-3 space-y-3">
          <HostBar room={room} isHost={isHost} onStart={handleStart} />

          <div className="sticky top-[56px] z-20">
            <ScoreRail room={room} />
          </div>

          {room.status === "lobby" && (
            <div className="card p-4 text-center text-sm text-[var(--color-mut)]">
              {isHost ? (
                <>You&apos;re the host. Share the code, draft a side, then <b className="text-white">start the match</b>.</>
              ) : (
                <>Waiting for the host to kick things off. Draft your side while you wait 👇</>
              )}
            </div>
          )}

          {/* tabs */}
          <div className="grid grid-cols-3 gap-1 rounded-xl bg-black/30 p-1 text-sm font-semibold">
            {(["watch", "board", "chat"] as Tab[]).map((t) => (
              <button
                key={t}
                onClick={() => setTab(t)}
                className={`rounded-lg py-2 transition ${tab === t ? "bg-[var(--color-pitch-700)] text-white" : "text-[var(--color-mut)]"}`}
              >
                {t === "watch" ? "⚡ Watch" : t === "board" ? "🏆 Board" : "💬 Chat"}
              </button>
            ))}
          </div>

          {tab === "watch" && (
            <div className="space-y-3">
              {latestRecap && <RecapCard recap={latestRecap} aiOn={aiOn} />}
              {showDraft && <SidePicker fixture={room.fixture} onPick={handleSide} />}
              {showSwing && (
                <NextSwingCard prompts={room.prompts} myPicks={myPicks} onPick={handlePick} />
              )}
              <PulseFeed pulse={room.pulse} />
            </div>
          )}

          {tab === "board" && (
            <div className="space-y-3">
              <Leaderboard room={room} meId={memberId} />
              {room.recaps.length > 0 && (
                <div className="space-y-2">
                  {[...room.recaps].reverse().map((r) => (
                    <RecapCard key={r.id} recap={r} aiOn={aiOn} />
                  ))}
                </div>
              )}
            </div>
          )}

          {tab === "chat" && (
            <ChatDock chat={room.chat} onSend={handleChat} onReact={handleReact} disabled={!joined} />
          )}
        </div>
      </main>

      <ProofModal roomId={id} open={proofOpen} onClose={() => setProofOpen(false)} isHost={isHost} />

      {!joined && (
        <JoinGate
          roomId={id}
          roomName={room.name}
          fixture={room.fixture}
          onJoined={(mid) => setMemberIdState(mid)}
        />
      )}
    </div>
  );
}
