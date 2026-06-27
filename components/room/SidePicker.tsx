"use client";

import type { Fixture } from "@/lib/txline/types";

export function SidePicker({
  fixture,
  onPick,
}: {
  fixture: Fixture;
  onPick: (side: "home" | "away") => void;
}) {
  return (
    <div className="card p-4">
      <div className="mb-1 flex items-center gap-2">
        <span className="chip text-[var(--color-gold)]">🏆 Tournament Draft</span>
      </div>
      <p className="text-sm font-semibold">Draft your side</p>
      <p className="mb-3 text-[11px] text-[var(--color-mut)]">
        Earn points whenever your team scores, wins corners, or finishes ahead.
      </p>
      <div className="grid grid-cols-2 gap-2">
        {(["home", "away"] as const).map((side) => {
          const t = side === "home" ? fixture.home : fixture.away;
          const color = side === "home" ? "var(--color-home)" : "var(--color-away)";
          return (
            <button
              key={side}
              onClick={() => onPick(side)}
              className="card p-3 text-center transition hover:ring-2"
              style={{ ["--tw-ring-color" as string]: color }}
            >
              <div className="text-3xl">{t.flag}</div>
              <div className="mt-1 text-sm font-bold">{t.name}</div>
            </button>
          );
        })}
      </div>
    </div>
  );
}
