"use client";
import { clockDisplay, decodeStatus } from "@/lib/explorer/spec";
import type { FixtureLite, RawRecord } from "@/lib/explorer/types";
import { useEffect, useMemo, useState } from "react";

const POSSESSION_TIERS = ["safe_possession", "possession", "attack_possession", "danger_possession", "high_danger_possession"] as const;
const TIER_LABEL: Record<string, string> = {
  safe_possession: "SAFE",
  possession: "POSSESSION",
  attack_possession: "ATTACK",
  danger_possession: "DANGER",
  high_danger_possession: "HIGH DANGER",
};

/**
 * The "what the feed tells you at a glance" strip — folded from every record
 * up to the cursor (replay) or the latest record (live).
 */
export default function LiveDashboard({ fixture, records, live }: { fixture: FixtureLite | null; records: RawRecord[]; live: boolean }) {
  const state = useMemo(() => {
    let score: RawRecord["Score"] | undefined;
    let clock: RawRecord["Clock"] | undefined;
    let statusId: number | undefined;
    let tier: string | null = null;
    let tierSide: number | null = null;
    let lastTs = 0;
    let coverage = "";
    for (const r of records) {
      if (r.Score) score = r.Score;
      if (r.Clock) clock = r.Clock;
      if (r.StatusId != null) statusId = r.StatusId;
      if (r.Action && (POSSESSION_TIERS as readonly string[]).includes(r.Action)) {
        tier = r.Action;
        tierSide = (r.Participant as number) ?? null;
      }
      if (r.Ts && r.Ts > lastTs) lastTs = r.Ts;
      if (r.CoverageType) coverage = r.CoverageType;
    }
    return { score, clock, statusId, tier, tierSide, lastTs, coverage };
  }, [records]);

  // "last update Xs ago" ticker — the free tier streams ~every 60s, so a quiet
  // stream must not look broken
  const [now, setNow] = useState(Date.now());
  useEffect(() => {
    const t = setInterval(() => setNow(Date.now()), 1000);
    return () => clearInterval(t);
  }, []);

  if (!fixture) return null;
  const g1 = state.score?.Participant1?.Total?.Goals ?? 0;
  const g2 = state.score?.Participant2?.Total?.Goals ?? 0;
  const tierIdx = state.tier ? POSSESSION_TIERS.indexOf(state.tier as (typeof POSSESSION_TIERS)[number]) : -1;
  const agoS = state.lastTs ? Math.max(0, Math.round((now - state.lastTs) / 1000)) : null;

  return (
    <div className="border-b border-[#243650] bg-[#0b1220] px-4 py-2.5 flex items-center gap-5 flex-wrap">
      <div className="flex items-baseline gap-2.5">
        <span className="text-[13px] font-semibold text-[#4aa3ff]">{fixture.home}</span>
        <span className="text-xl font-bold tabular-nums">
          {g1}–{g2}
        </span>
        <span className="text-[13px] font-semibold text-[#ff6b6b]">{fixture.away}</span>
      </div>
      <div className="text-[12.5px] text-[#c8d5e8] font-mono">{clockDisplay(state.clock)}</div>
      <div className="text-[11.5px] text-[#8aa0bd]">{decodeStatus(state.statusId)}</div>
      {/* possession tier meter — 5 labeled steps, current tier filled */}
      <div className="flex items-center gap-1" title="possession tier (from the *_possession actions)">
        {POSSESSION_TIERS.map((t, i) => (
          <div
            key={t}
            className="h-2.5 w-6 rounded-sm"
            style={{
              background: i <= tierIdx ? (i >= 3 ? "#ff6b6b" : i >= 2 ? "#ff9f43" : "#3fd68c") : "#141f33",
              border: "1px solid #243650",
            }}
          />
        ))}
        <span className="text-[10.5px] text-[#8aa0bd] ml-1">
          {state.tier ? `${TIER_LABEL[state.tier]}${state.tierSide ? ` · P${state.tierSide}` : ""}` : "—"}
        </span>
      </div>
      <div className="ml-auto flex items-center gap-3 text-[11px] text-[#8aa0bd]">
        {state.coverage && <span>{state.coverage}</span>}
        {live ? (
          <span className="flex items-center gap-1.5">
            <span className="w-2 h-2 rounded-full bg-[#c7f24d] animate-pulse" />
            LIVE{agoS != null && ` · last update ${agoS}s ago`}
          </span>
        ) : (
          <span>REPLAY · {records.length} records folded</span>
        )}
      </div>
    </div>
  );
}
