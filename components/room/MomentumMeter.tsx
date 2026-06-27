"use client";

export function MomentumMeter({
  value,
  homeCode,
  awayCode,
}: {
  value: number; // -100 (away) .. +100 (home)
  homeCode: string;
  awayCode: string;
}) {
  const homeShare = Math.max(0, Math.min(100, (value + 100) / 2));
  return (
    <div>
      <div className="mb-1 flex items-center justify-between text-[10px] uppercase tracking-wider text-[var(--color-mut)]">
        <span>{awayCode}</span>
        <span>Momentum</span>
        <span>{homeCode}</span>
      </div>
      <div className="relative h-2 overflow-hidden rounded-full bg-[var(--color-pitch-800)]">
        <div className="absolute inset-y-0 left-1/2 w-px bg-white/20" />
        <div
          className="absolute inset-y-0 rounded-full transition-all duration-700"
          style={{
            left: value >= 0 ? "50%" : `${homeShare}%`,
            right: value >= 0 ? `${100 - homeShare}%` : "50%",
            background:
              value >= 0
                ? "linear-gradient(90deg, rgba(74,163,255,0.35), var(--color-home))"
                : "linear-gradient(90deg, var(--color-away), rgba(255,107,107,0.35))",
          }}
        />
      </div>
    </div>
  );
}
