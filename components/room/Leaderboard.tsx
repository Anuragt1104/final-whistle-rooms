"use client";

import type { MemberView, RoomView } from "@/lib/store/types";

export function Leaderboard({ room, meId }: { room: RoomView; meId: string | null }) {
  const { members, fixture } = room;
  const sideFlag = (m: MemberView) =>
    m.side === "home" ? fixture.home.flag : m.side === "away" ? fixture.away.flag : "";

  return (
    <div className="card overflow-hidden">
      <div className="flex items-center justify-between border-b border-[var(--color-line)] px-4 py-2">
        <span className="text-sm font-bold">🏆 Room leaderboard</span>
        <span className="text-[10px] uppercase tracking-wider text-[var(--color-mut)]">
          {members.length} {members.length === 1 ? "fan" : "fans"}
        </span>
      </div>
      <div className="divide-y divide-[var(--color-line)]">
        {members.map((m, i) => {
          const isMe = m.id === meId;
          return (
            <div
              key={m.id}
              className={`flex items-center gap-3 px-4 py-2.5 ${isMe ? "bg-[var(--color-lime)]/10" : ""}`}
            >
              <span
                className={`w-5 text-center text-sm font-black ${
                  i === 0 ? "text-[var(--color-gold)]" : "text-[var(--color-mut)]"
                }`}
              >
                {i + 1}
              </span>
              <span className="text-xl leading-none">{m.avatar}</span>
              <div className="min-w-0 flex-1">
                <div className="flex items-center gap-1.5">
                  <span className="truncate text-sm font-semibold">{m.name}</span>
                  {sideFlag(m) && <span className="text-xs">{sideFlag(m)}</span>}
                  {m.isHost && <span className="chip px-1.5 py-0 text-[9px]">HOST</span>}
                  {isMe && <span className="chip px-1.5 py-0 text-[9px] text-[var(--color-lime)]">YOU</span>}
                </div>
                <div className="text-[10px] text-[var(--color-mut)]">
                  {m.correct} correct{m.bestStreak >= 2 ? ` · best ${m.bestStreak}🔥` : ""}
                </div>
              </div>
              <div className="text-right">
                <div className="text-sm font-extrabold tabular-nums">{m.points}</div>
                {m.streak >= 2 && <div className="text-[10px] text-[var(--color-gold)]">🔥 {m.streak}</div>}
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
}
