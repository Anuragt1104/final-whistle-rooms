"use client";
import { ACTION_BY_ID, CATEGORY_COLORS, COMMON_FIELDS, COMMON_STRUCTURES, realExample, type FieldSpec } from "@/lib/explorer/spec";
import type { RawRecord } from "@/lib/explorer/types";
import { useState } from "react";
import JsonView from "./JsonView";

function FieldTable({ fields }: { fields: FieldSpec[] }) {
  return (
    <table className="w-full text-[13px] border-collapse">
      <thead>
        <tr className="text-left text-[11px] tracking-wider text-[#8aa0bd]">
          <th className="py-1.5 pr-3 font-semibold">FIELD</th>
          <th className="py-1.5 pr-3 font-semibold">TYPE</th>
          <th className="py-1.5 font-semibold">MEANING</th>
        </tr>
      </thead>
      <tbody>
        {fields.map((f) => (
          <tr key={f.name} className="border-t border-[#243650] align-top">
            <td className="py-1.5 pr-3 font-mono whitespace-nowrap">
              {f.name}
              {f.required && <span className="text-[#ff6b6b]">*</span>}
            </td>
            <td className="py-1.5 pr-3 text-[#4aa3ff] whitespace-nowrap">{f.type}</td>
            <td className="py-1.5 text-[#c8d5e8]">
              {f.meaning}
              {f.enumValues && (
                <div className="mt-1 flex flex-wrap gap-1">
                  {f.enumValues.map((v) => (
                    <code key={v} className="text-[11px] bg-[#141f33] border border-[#243650] rounded px-1.5 py-0.5">
                      {v}
                    </code>
                  ))}
                </div>
              )}
            </td>
          </tr>
        ))}
      </tbody>
    </table>
  );
}

export default function ActionDetail({
  action,
  count,
  instances,
  onJumpTo,
}: {
  action: string;
  count: number;
  instances: RawRecord[];
  onJumpTo: (seq: number) => void;
}) {
  const spec = ACTION_BY_ID[action];
  const [showEnvelope, setShowEnvelope] = useState(false);
  if (!spec) return null;
  const example = realExample(action) ?? instances[0] ?? null;
  return (
    <div className="p-5 overflow-y-auto h-full">
      <div className="flex items-center gap-3">
        <h2 className="text-xl font-bold">{spec.title}</h2>
        <code className="text-[12px] bg-[#141f33] border border-[#243650] rounded px-2 py-0.5">{spec.action}</code>
        <span className="text-[11px] font-bold tracking-wider" style={{ color: CATEGORY_COLORS[spec.category] }}>
          {spec.category.toUpperCase()}
        </span>
      </div>
      <p className="mt-2 text-[14px] text-[#c8d5e8] max-w-3xl">{spec.description}</p>
      <div className="mt-2 flex gap-2 text-[11px]">
        {spec.autoConfirmed && (
          <span className="bg-[#141f33] border border-[#243650] rounded px-2 py-0.5 text-[#8aa0bd]">confirmed automatically — no follow-up</span>
        )}
        {!spec.observed && (
          <span className="bg-[#141f33] border border-[#243650] rounded px-2 py-0.5 text-[#ffd24a]">documented in the PDF, not yet observed in captured matches</span>
        )}
      </div>
      {spec.notes && <p className="mt-2 text-[12.5px] text-[#8aa0bd] max-w-3xl">Note: {spec.notes}</p>}

      <h3 className="mt-5 mb-1 text-[12px] tracking-widest font-bold text-[#8aa0bd]">DATA PAYLOAD</h3>
      {spec.dataFields.length > 0 ? (
        <FieldTable fields={spec.dataFields} />
      ) : (
        <p className="text-[13px] text-[#8aa0bd]">No action-specific Data fields — the meaning is carried by the envelope (Participant, Clock, Score, Stats…).</p>
      )}

      <button onClick={() => setShowEnvelope((s) => !s)} className="mt-5 text-[12px] tracking-widest font-bold text-[#8aa0bd] hover:text-[#eaf1fb]">
        ENVELOPE FIELDS (SHARED BY EVERY RECORD) {showEnvelope ? "▾" : "▸"}
      </button>
      {showEnvelope && <FieldTable fields={COMMON_FIELDS} />}

      {example && (
        <>
          <h3 className="mt-5 mb-1 text-[12px] tracking-widest font-bold text-[#8aa0bd]">
            REAL RESPONSE {realExample(action) ? "(captured from the live feed)" : "(from this match)"}
          </h3>
          <div className="font-mono text-[12px] bg-[#0f1828] border border-[#243650] rounded-xl p-3 overflow-x-auto">
            <JsonView value={example} />
          </div>
        </>
      )}

      {count > 0 && (
        <>
          <h3 className="mt-5 mb-1 text-[12px] tracking-widest font-bold text-[#8aa0bd]">
            SEEN {count}× IN THIS MATCH
          </h3>
          <div className="flex flex-wrap gap-1.5">
            {instances.slice(0, 40).map((r) => (
              <button
                key={r.Seq}
                onClick={() => onJumpTo(r.Seq ?? 0)}
                className="text-[11px] font-mono bg-[#141f33] border border-[#243650] rounded px-2 py-0.5 hover:border-[#c7f24d]"
                title="jump to this record in the timeline"
              >
                #{r.Seq} · {Math.floor((r.Clock?.Seconds ?? 0) / 60)}&apos;
              </button>
            ))}
            {instances.length > 40 && <span className="text-[11px] text-[#8aa0bd] self-center">+{instances.length - 40} more</span>}
          </div>
        </>
      )}
    </div>
  );
}

export function StructureDetail({ id }: { id: string }) {
  const s = COMMON_STRUCTURES.find((x) => x.id === id);
  if (!s) return null;
  return (
    <div className="p-5 overflow-y-auto h-full">
      <h2 className="text-xl font-bold">{s.title}</h2>
      <p className="mt-2 text-[14px] text-[#c8d5e8] max-w-3xl">{s.description}</p>
      <h3 className="mt-5 mb-1 text-[12px] tracking-widest font-bold text-[#8aa0bd]">FIELDS</h3>
      <FieldTable fields={s.fields} />
    </div>
  );
}
