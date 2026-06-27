"use client";

import type { PulseCard, PulseAccent } from "@/lib/engine/pulse";

const ACCENT: Record<PulseAccent, string> = {
  home: "border-l-[var(--color-home)]",
  away: "border-l-[var(--color-away)]",
  hot: "border-l-[var(--color-gold)]",
  good: "border-l-[var(--color-lime)]",
  bad: "border-l-[var(--color-away)]",
  neutral: "border-l-[var(--color-line)]",
};

export function PulseFeed({ pulse }: { pulse: PulseCard[] }) {
  const cards = [...pulse].reverse();
  if (cards.length === 0) {
    return (
      <div className="card p-5 text-center text-sm text-[var(--color-mut)]">
        The pulse feed lights up the moment the match kicks off — goals, cards, corners and odds
        swings, translated into plain English.
      </div>
    );
  }
  return (
    <div className="space-y-2">
      {cards.map((c) => (
        <div
          key={c.id}
          className={`card animate-pulse-in border-l-4 p-3 ${ACCENT[c.accent]} ${c.kind === "goal" ? "animate-flash" : ""}`}
        >
          <div className="flex items-start gap-3">
            <span className="text-xl leading-none">{c.emoji}</span>
            <div className="min-w-0 flex-1">
              <div className="flex items-center justify-between gap-2">
                <span className="text-sm font-bold">{c.headline}</span>
                <span className="shrink-0 text-[10px] text-[var(--color-mut)]">{c.minute}&apos;</span>
              </div>
              <p className="mt-0.5 text-[13px] leading-snug text-[var(--color-mut)]">{c.detail}</p>
            </div>
          </div>
        </div>
      ))}
    </div>
  );
}
