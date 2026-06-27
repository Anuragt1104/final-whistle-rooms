"use client";

import type { WinChance } from "@/lib/engine/pulse";

export function WinBar({ win, homeCode, awayCode }: { win: WinChance; homeCode: string; awayCode: string }) {
  return (
    <div>
      <div className="mb-1 flex items-center justify-between text-[10px] uppercase tracking-wider text-[var(--color-mut)]">
        <span>Win chance</span>
        <span className="normal-case text-[var(--color-mut)]">live odds, in plain English</span>
      </div>
      <div className="flex h-6 overflow-hidden rounded-lg text-[10px] font-bold">
        <Seg w={win.home} label={`${homeCode} ${win.home}%`} color="var(--color-home)" />
        <Seg w={win.draw} label={`X ${win.draw}%`} color="#5b6b82" />
        <Seg w={win.away} label={`${win.away}% ${awayCode}`} color="var(--color-away)" />
      </div>
    </div>
  );
}

function Seg({ w, label, color }: { w: number; label: string; color: string }) {
  return (
    <div
      className="grid place-items-center overflow-hidden whitespace-nowrap text-[#08111f] transition-all duration-700"
      style={{ width: `${Math.max(w, 6)}%`, background: color }}
    >
      <span className="px-1">{w >= 12 ? label : ""}</span>
    </div>
  );
}
