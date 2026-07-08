"use client";
import { ACTION_BY_ID, CATEGORY_COLORS, clockDisplay, summarize } from "@/lib/explorer/spec";
import type { RawRecord } from "@/lib/explorer/types";
import { useEffect, useMemo, useRef, useState } from "react";

const ROW_H = 34;

/** Windowed timeline of the full raw record log — 1,000+ rows stay smooth. */
export default function MatchInspector({
  records,
  selectedSeq,
  onSelect,
  scrollToSeq,
}: {
  records: RawRecord[];
  selectedSeq: number | null;
  onSelect: (r: RawRecord) => void;
  scrollToSeq: number | null;
}) {
  const [filters, setFilters] = useState<Set<string>>(new Set());
  const [q, setQ] = useState("");
  const [confirmedOnly, setConfirmedOnly] = useState(false);
  const scrollRef = useRef<HTMLDivElement>(null);
  const [scrollTop, setScrollTop] = useState(0);
  const [viewH, setViewH] = useState(600);

  const filtered = useMemo(() => {
    const query = q.trim().toLowerCase();
    return records.filter((r) => {
      if (filters.size > 0 && !filters.has(r.Action ?? "")) return false;
      if (confirmedOnly && r.Confirmed === false) return false;
      if (query && !JSON.stringify(r).toLowerCase().includes(query)) return false;
      return true;
    });
  }, [records, filters, q, confirmedOnly]);

  const actionsPresent = useMemo(() => {
    const set = new Map<string, number>();
    for (const r of records) set.set(r.Action ?? "?", (set.get(r.Action ?? "?") ?? 0) + 1);
    return [...set.entries()].sort((a, b) => b[1] - a[1]);
  }, [records]);

  // external jump (from ActionDetail instance chips)
  useEffect(() => {
    if (scrollToSeq == null || !scrollRef.current) return;
    const idx = filtered.findIndex((r) => r.Seq === scrollToSeq);
    if (idx >= 0) scrollRef.current.scrollTop = Math.max(0, idx * ROW_H - viewH / 2);
  }, [scrollToSeq, filtered, viewH]);

  useEffect(() => {
    const el = scrollRef.current;
    if (!el) return;
    const measure = () => setViewH(el.clientHeight);
    measure();
    window.addEventListener("resize", measure);
    return () => window.removeEventListener("resize", measure);
  }, []);

  const start = Math.max(0, Math.floor(scrollTop / ROW_H) - 8);
  const end = Math.min(filtered.length, Math.ceil((scrollTop + viewH) / ROW_H) + 8);

  return (
    <div className="flex flex-col h-full min-h-0">
      <div className="p-2.5 border-b border-[#243650] flex flex-wrap items-center gap-1.5">
        <input
          value={q}
          onChange={(e) => setQ(e.target.value)}
          placeholder="Search records…"
          className="rounded-lg bg-[#141f33] border border-[#243650] px-2.5 py-1 text-[12.5px] outline-none focus:border-[#c7f24d] w-44"
        />
        <label className="text-[11.5px] text-[#8aa0bd] flex items-center gap-1 mr-1">
          <input type="checkbox" checked={confirmedOnly} onChange={(e) => setConfirmedOnly(e.target.checked)} />
          confirmed only
        </label>
        {actionsPresent.slice(0, 14).map(([a, n]) => {
          const on = filters.has(a);
          const color = CATEGORY_COLORS[ACTION_BY_ID[a]?.category ?? "Data quality & meta"];
          return (
            <button
              key={a}
              onClick={() =>
                setFilters((f) => {
                  const next = new Set(f);
                  if (on) next.delete(a);
                  else next.add(a);
                  return next;
                })
              }
              className={`text-[11px] font-mono rounded-full px-2 py-0.5 border ${on ? "text-[#070b14]" : "text-[#c8d5e8]"}`}
              style={{ borderColor: color, background: on ? color : "transparent" }}
            >
              {a} {n}
            </button>
          );
        })}
        {filters.size > 0 && (
          <button onClick={() => setFilters(new Set())} className="text-[11px] text-[#8aa0bd] underline">
            clear
          </button>
        )}
        <span className="ml-auto text-[11.5px] text-[#8aa0bd] tabular-nums">
          {filtered.length}/{records.length} records
        </span>
      </div>
      <div ref={scrollRef} className="flex-1 overflow-y-auto min-h-0" onScroll={(e) => setScrollTop(e.currentTarget.scrollTop)}>
        <div style={{ height: filtered.length * ROW_H, position: "relative" }}>
          {filtered.slice(start, end).map((r, i) => {
            const idx = start + i;
            const spec = ACTION_BY_ID[r.Action ?? ""];
            const color = CATEGORY_COLORS[spec?.category ?? "Data quality & meta"];
            const sel = r.Seq === selectedSeq;
            return (
              <button
                key={`${r.Seq}-${r.Id}`}
                onClick={() => onSelect(r)}
                className={`absolute left-0 right-0 flex items-center gap-2 px-3 text-left text-[12.5px] border-b border-[#16223a] hover:bg-[#141f33] ${sel ? "bg-[#141f33]" : ""}`}
                style={{ top: idx * ROW_H, height: ROW_H }}
              >
                <span className="w-12 text-[#8aa0bd] font-mono tabular-nums shrink-0">#{r.Seq}</span>
                <span className="w-14 text-[#8aa0bd] font-mono tabular-nums shrink-0">{clockDisplay(r.Clock)}</span>
                <span className="font-mono px-1.5 rounded text-[11px] shrink-0" style={{ color, border: `1px solid ${color}55` }}>
                  {r.Action}
                </span>
                <span className="truncate text-[#c8d5e8]">{summarize(r)}</span>
                {r.Confirmed === false && <span className="ml-auto text-[10px] text-[#ffd24a] shrink-0">unconfirmed</span>}
              </button>
            );
          })}
        </div>
      </div>
    </div>
  );
}
