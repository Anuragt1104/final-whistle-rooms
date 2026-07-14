"use client";

import { useRouter } from "next/navigation";
import type { Fixture } from "@/lib/txline/types";
import { relativeKickoff } from "@/lib/util/format";
import { api } from "@/lib/client/api";

function StatusChip({ status }: { status: Fixture["status"] }) {
  if (status === "live")
    return (
      <span className="chip border-[var(--color-lime)]/40 text-[var(--color-lime)]">
        <span className="live-dot inline-block h-1.5 w-1.5 rounded-full bg-[var(--color-lime)]" /> LIVE
      </span>
    );
  if (status === "finished") return <span className="chip">FT</span>;
  return <span className="chip">{/* upcoming */}Upcoming</span>;
}

export function FixtureRow({ fixture }: { fixture: Fixture }) {
  const router = useRouter();
  async function watch() {
    try {
      const { roomId } = await api.watch(fixture.id, { name: "Fan" });
      router.push(`/room/${roomId}`);
    } catch {
      /* fixture not watchable yet */
    }
  }
  return (
    <div className="card flex items-center justify-between gap-3 p-3">
      <div className="min-w-0 flex-1">
        <div className="mb-1 flex items-center gap-2">
          <StatusChip status={fixture.status} />
          <span className="truncate text-[11px] text-[var(--color-mut)]">{fixture.stage}</span>
        </div>
        <div className="flex items-center gap-2 text-sm font-semibold">
          <span className="text-lg leading-none">{fixture.home.flag}</span>
          <span>{fixture.home.code}</span>
          <span className="text-[var(--color-mut)]">vs</span>
          <span className="text-lg leading-none">{fixture.away.flag}</span>
          <span>{fixture.away.code}</span>
          <span className="ml-1 text-[11px] font-normal text-[var(--color-mut)]">
            {fixture.status === "finished" ? "" : relativeKickoff(fixture.kickoff)}
          </span>
        </div>
      </div>
      <button onClick={watch} className="btn btn-ghost px-3 py-1.5 text-xs whitespace-nowrap">
        {fixture.status === "finished" ? "Watch replay" : "Watch"}
      </button>
    </div>
  );
}
