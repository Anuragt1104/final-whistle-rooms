"use client";
import { useMemo, useState } from "react";
import { ACTIONS, CATEGORIES, CATEGORY_COLORS, COMMON_STRUCTURES, type ActionSpec } from "@/lib/explorer/spec";

export default function CatalogSidebar({
  counts,
  selectedAction,
  selectedStructure,
  onSelectAction,
  onSelectStructure,
}: {
  counts: Record<string, number>;
  selectedAction: string | null;
  selectedStructure: string | null;
  onSelectAction: (a: string) => void;
  onSelectStructure: (id: string) => void;
}) {
  const [q, setQ] = useState("");
  const grouped = useMemo(() => {
    const query = q.trim().toLowerCase();
    const match = (a: ActionSpec) =>
      !query || a.action.includes(query) || a.title.toLowerCase().includes(query) || a.description.toLowerCase().includes(query);
    return CATEGORIES.map((cat) => ({
      cat,
      actions: ACTIONS.filter((a) => a.category === cat && match(a)),
    })).filter((g) => g.actions.length > 0);
  }, [q]);

  return (
    <aside className="w-[270px] shrink-0 border-r border-[#243650] overflow-y-auto h-full">
      <div className="p-3 sticky top-0 bg-[#0b1220] z-10 border-b border-[#243650]">
        <input
          value={q}
          onChange={(e) => setQ(e.target.value)}
          placeholder="Search 49 message types…"
          className="w-full rounded-lg bg-[#141f33] border border-[#243650] px-3 py-1.5 text-sm outline-none focus:border-[#c7f24d]"
        />
      </div>
      {grouped.map(({ cat, actions }) => (
        <div key={cat} className="pb-1">
          <div className="px-3 pt-3 pb-1 text-[10px] tracking-widest font-bold" style={{ color: CATEGORY_COLORS[cat] }}>
            {cat.toUpperCase()}
          </div>
          {actions.map((a) => {
            const n = counts[a.action] ?? 0;
            const active = selectedAction === a.action;
            return (
              <button
                key={a.action}
                onClick={() => onSelectAction(a.action)}
                className={`w-full flex items-center gap-2 px-3 py-1.5 text-left text-[13px] hover:bg-[#141f33] ${active ? "bg-[#141f33] border-l-2" : "border-l-2 border-transparent"}`}
                style={active ? { borderLeftColor: CATEGORY_COLORS[a.category] } : undefined}
              >
                <span
                  className="w-1.5 h-1.5 rounded-full shrink-0"
                  style={{ background: a.observed ? CATEGORY_COLORS[a.category] : "transparent", outline: a.observed ? "none" : "1px solid #8aa0bd" }}
                  title={a.observed ? "observed in real matches" : "documented, not yet observed"}
                />
                <span className="font-mono flex-1 truncate">{a.action}</span>
                {n > 0 && <span className="text-[10px] text-[#8aa0bd] tabular-nums bg-[#141f33] rounded px-1.5 py-0.5">{n}</span>}
              </button>
            );
          })}
        </div>
      ))}
      <div className="pb-6">
        <div className="px-3 pt-4 pb-1 text-[10px] tracking-widest font-bold text-[#8aa0bd]">COMMON STRUCTURES</div>
        {COMMON_STRUCTURES.map((s) => (
          <button
            key={s.id}
            onClick={() => onSelectStructure(s.id)}
            className={`w-full px-3 py-1.5 text-left text-[13px] hover:bg-[#141f33] ${selectedStructure === s.id ? "bg-[#141f33] text-[#c7f24d]" : ""}`}
          >
            {s.title}
          </button>
        ))}
      </div>
    </aside>
  );
}
