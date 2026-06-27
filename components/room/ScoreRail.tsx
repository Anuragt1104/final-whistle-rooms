"use client";

import { GamePhase, PHASE_LABEL } from "@/lib/txline/types";
import type { RoomView } from "@/lib/store/types";
import { MomentumMeter } from "@/components/room/MomentumMeter";
import { WinBar } from "@/components/room/WinBar";

export function ScoreRail({ room }: { room: RoomView }) {
  const { fixture, score } = room;
  const goalsH = score?.goals.home ?? 0;
  const goalsA = score?.goals.away ?? 0;
  const phase = score?.phase ?? GamePhase.PreMatch;
  const live = room.status === "live";

  const clock =
    phase === GamePhase.HalfTime
      ? "HT"
      : phase === GamePhase.FullTime || room.status === "finished"
        ? "FT"
        : live && score
          ? `${score.minute}'`
          : "—";

  return (
    <div className="card p-4">
      <div className="grid grid-cols-[1fr_auto_1fr] items-center gap-2">
        <TeamCell flag={fixture.home.flag} code={fixture.home.code} name={fixture.home.name} align="start" />
        <div className="text-center">
          <div className="flex items-center justify-center gap-2 text-3xl font-black tabular-nums">
            <span className={goalsH > goalsA ? "text-white" : "text-[var(--color-mut)]"}>{goalsH}</span>
            <span className="text-[var(--color-mut)]">:</span>
            <span className={goalsA > goalsH ? "text-white" : "text-[var(--color-mut)]"}>{goalsA}</span>
          </div>
          <div className="mt-0.5 flex items-center justify-center gap-1 text-[11px] font-semibold">
            {live && phase !== GamePhase.HalfTime && (
              <span className="live-dot inline-block h-1.5 w-1.5 rounded-full bg-[var(--color-lime)]" />
            )}
            <span className={live ? "text-[var(--color-lime)]" : "text-[var(--color-mut)]"}>
              {clock} · {PHASE_LABEL[phase]}
            </span>
          </div>
        </div>
        <TeamCell flag={fixture.away.flag} code={fixture.away.code} name={fixture.away.name} align="end" />
      </div>

      {/* mini stat strip */}
      {score && (
        <div className="mt-3 grid grid-cols-3 gap-1 text-center text-[10px] text-[var(--color-mut)]">
          <Stat label="Corners" h={score.corners.home} a={score.corners.away} />
          <Stat label="Yellow" h={score.yellow.home} a={score.yellow.away} />
          <Stat label="Red" h={score.red.home} a={score.red.away} />
        </div>
      )}

      <div className="mt-4 space-y-3">
        <MomentumMeter value={room.momentum} homeCode={fixture.home.code} awayCode={fixture.away.code} />
        <WinBar win={room.win} homeCode={fixture.home.code} awayCode={fixture.away.code} />
      </div>
    </div>
  );
}

function TeamCell({ flag, code, name, align }: { flag: string; code: string; name: string; align: "start" | "end" }) {
  return (
    <div className={`flex flex-col ${align === "start" ? "items-start" : "items-end"}`}>
      <span className="text-3xl leading-none">{flag}</span>
      <span className="mt-1 text-sm font-extrabold">{code}</span>
      <span className="max-w-[90px] truncate text-[10px] text-[var(--color-mut)]">{name}</span>
    </div>
  );
}

function Stat({ label, h, a }: { label: string; h: number; a: number }) {
  return (
    <div className="rounded-md bg-black/20 py-1">
      <div className="font-bold text-white">
        {h} <span className="text-[var(--color-mut)]">·</span> {a}
      </div>
      <div className="uppercase tracking-wide">{label}</div>
    </div>
  );
}
