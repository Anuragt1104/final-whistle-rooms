"use client";

import { useState } from "react";
import type { RoomView } from "@/lib/store/types";

export function HostBar({
  room,
  isHost,
  onStart,
}: {
  room: RoomView;
  isHost: boolean;
  onStart: () => void;
}) {
  const [copied, setCopied] = useState(false);

  function share() {
    const url = typeof window !== "undefined" ? window.location.href : "";
    if (navigator.share) {
      navigator.share({ title: room.name, text: `Join my World Cup room: ${room.code}`, url }).catch(() => {});
    } else {
      navigator.clipboard?.writeText(`${url} (code ${room.code})`);
      setCopied(true);
      setTimeout(() => setCopied(false), 1500);
    }
  }

  return (
    <div className="card flex items-center justify-between gap-2 p-3">
      <div className="min-w-0">
        <div className="text-[10px] uppercase tracking-wider text-[var(--color-mut)]">Invite code</div>
        <div className="font-mono text-lg font-extrabold tracking-[0.18em] text-[var(--color-lime)]">
          {room.code}
        </div>
      </div>
      <div className="flex items-center gap-2">
        <button className="btn btn-ghost px-3 py-1.5 text-xs" onClick={share}>
          {copied ? "Copied ✓" : "Share"}
        </button>
        {isHost && room.status === "lobby" && (
          <button className="btn btn-primary px-3 py-1.5 text-xs" onClick={onStart}>
            ▶ Start match
          </button>
        )}
      </div>
    </div>
  );
}
