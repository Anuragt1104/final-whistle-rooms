"use client";
import { ACTION_BY_ID, clockDisplay, decodeParticipant, decodeStatKey, decodeStatus, summarize, tsDisplay } from "@/lib/explorer/spec";
import type { RawRecord } from "@/lib/explorer/types";
import { useState } from "react";
import JsonView from "./JsonView";

function Row({ k, raw, decoded }: { k: string; raw: React.ReactNode; decoded?: React.ReactNode }) {
  return (
    <div className="py-1.5 border-t border-[#243650] grid grid-cols-[130px_1fr] gap-2 text-[12.5px]">
      <div className="font-mono text-[#ffd24a]">{k}</div>
      <div>
        <span className="font-mono text-[#c8d5e8] break-all">{raw}</span>
        {decoded && <div className="text-[#8aa0bd] mt-0.5">→ {decoded}</div>}
      </div>
    </div>
  );
}

export default function RecordDetail({ record, onViewSpec }: { record: RawRecord | null; onViewSpec: (a: string) => void }) {
  const [rawMode, setRawMode] = useState(false);
  if (!record) {
    return (
      <div className="p-5 text-[13px] text-[#8aa0bd]">
        Select any record in the timeline to see every field decoded — StatusId, Clock, Stats keys, per-period Score, the works.
      </div>
    );
  }
  const spec = ACTION_BY_ID[record.Action ?? ""];
  const p1h = record.Participant1IsHome !== false;
  return (
    <div className="p-4 overflow-y-auto h-full">
      <div className="flex items-center gap-2">
        <h3 className="font-bold text-[15px]">{spec?.title ?? record.Action}</h3>
        <code className="text-[11px] bg-[#141f33] border border-[#243650] rounded px-1.5 py-0.5">#{record.Seq}</code>
        <button onClick={() => setRawMode((s) => !s)} className="ml-auto text-[11px] text-[#8aa0bd] hover:text-[#eaf1fb]">
          {rawMode ? "annotated" : "raw JSON"}
        </button>
      </div>
      <div className="text-[12.5px] text-[#c8d5e8] mt-1">{summarize(record)}</div>
      {spec && (
        <button onClick={() => onViewSpec(spec.action)} className="mt-1 text-[11.5px] text-[#4aa3ff] hover:underline">
          View message spec →
        </button>
      )}

      {rawMode ? (
        <div className="mt-3 font-mono text-[11.5px] bg-[#0f1828] border border-[#243650] rounded-xl p-3 overflow-x-auto">
          <JsonView value={record} />
        </div>
      ) : (
        <div className="mt-3">
          <Row k="Action" raw={record.Action} decoded={spec ? `${spec.title} — ${spec.category}` : undefined} />
          <Row k="Id / Seq" raw={`${record.Id} / ${record.Seq}`} decoded="action id (shared by updates to the same action) / feed order" />
          <Row k="Ts" raw={record.Ts} decoded={tsDisplay(record.Ts)} />
          <Row k="Confirmed" raw={String(record.Confirmed)} decoded={record.Confirmed ? "the action actually happened" : "preliminary — confirmation may follow under the same Id"} />
          <Row k="StatusId" raw={record.StatusId} decoded={decodeStatus(record.StatusId)} />
          {record.GameState && <Row k="GameState" raw={record.GameState} decoded="fixture-level state string (demo feed says 'scheduled' even in play — trust StatusId)" />}
          {record.Clock && <Row k="Clock" raw={JSON.stringify(record.Clock)} decoded={clockDisplay(record.Clock)} />}
          {record.Participant != null && <Row k="Participant" raw={record.Participant} decoded={decodeParticipant(record.Participant, p1h)} />}
          {record.Data != null && Object.keys(record.Data).length > 0 && (
            <Row k="Data" raw={<JsonView value={record.Data} />} />
          )}
          {record.Score && (
            <Row
              k="Score"
              raw={<ScoreGrid score={record.Score} />}
              decoded="current score-line by period (not the delta)"
            />
          )}
          {record.Stats && Object.keys(record.Stats).length > 0 && (
            <Row
              k="Stats"
              raw={
                <table className="text-[11.5px] mt-1">
                  <tbody>
                    {Object.entries(record.Stats).map(([k, v]) => (
                      <tr key={k}>
                        <td className="pr-2 font-mono text-[#4aa3ff]">{k}</td>
                        <td className="pr-2 tabular-nums">{v}</td>
                        <td className="text-[#8aa0bd]">{decodeStatKey(k)}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              }
              decoded="(period×1000)+base — the exact values committed to TxODDS' on-chain Merkle roots"
            />
          )}
          {record.PlayerStats && Object.keys(record.PlayerStats).length > 0 && <Row k="PlayerStats" raw={<JsonView value={record.PlayerStats} />} decoded="per-player counters, indexed by player id" />}
          {record.PossibleEvent && Object.keys(record.PossibleEvent).length > 0 && <Row k="PossibleEvent" raw={<JsonView value={record.PossibleEvent} />} />}
          <Row k="Coverage" raw={`${record.CoverageType ?? "—"} · secondary=${String(record.CoverageSecondaryData ?? "—")}`} decoded="how the match is being covered" />
        </div>
      )}
    </div>
  );
}

function ScoreGrid({ score }: { score: NonNullable<RawRecord["Score"]> }) {
  const periods = Array.from(
    new Set([...Object.keys(score.Participant1 ?? {}), ...Object.keys(score.Participant2 ?? {})]),
  );
  const order = ["H1", "HT", "H2", "ET1", "ET2", "ETTotal", "PE", "Total"];
  periods.sort((a, b) => order.indexOf(a) - order.indexOf(b));
  const stats = ["Goals", "YellowCards", "RedCards", "Corners"];
  return (
    <table className="text-[11.5px] mt-1 border-collapse">
      <thead>
        <tr>
          <th className="pr-2 text-left text-[#8aa0bd] font-normal"></th>
          {periods.map((p) => (
            <th key={p} className="px-2 text-[#8aa0bd] font-semibold">{p}</th>
          ))}
        </tr>
      </thead>
      <tbody>
        {stats.map((s) => (
          <tr key={s} className="border-t border-[#243650]">
            <td className="pr-2 text-[#8aa0bd]">{s}</td>
            {periods.map((p) => (
              <td key={p} className="px-2 text-center tabular-nums">
                {(score.Participant1?.[p]?.[s] ?? 0)}–{(score.Participant2?.[p]?.[s] ?? 0)}
              </td>
            ))}
          </tr>
        ))}
      </tbody>
    </table>
  );
}
