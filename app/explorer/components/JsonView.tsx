"use client";
import { useState } from "react";

/** Tiny syntax-highlighted, collapsible JSON viewer — no dependencies. */
export default function JsonView({ value, depth = 0 }: { value: unknown; depth?: number }) {
  if (value === null) return <span className="text-[#8aa0bd]">null</span>;
  if (typeof value === "boolean") return <span className="text-[#c792ea]">{String(value)}</span>;
  if (typeof value === "number") return <span className="text-[#4aa3ff]">{value}</span>;
  if (typeof value === "string") return <span className="text-[#3fd68c]">&quot;{value}&quot;</span>;
  if (Array.isArray(value)) return <Composite items={value.map((v, i) => [String(i), v] as const)} brackets="[]" depth={depth} skipKeys />;
  if (typeof value === "object") return <Composite items={Object.entries(value as Record<string, unknown>)} brackets="{}" depth={depth} />;
  return <span>{String(value)}</span>;
}

function Composite({
  items,
  brackets,
  depth,
  skipKeys = false,
}: {
  items: readonly (readonly [string, unknown])[];
  brackets: "[]" | "{}";
  depth: number;
  skipKeys?: boolean;
}) {
  const [open, setOpen] = useState(depth < 3);
  if (items.length === 0) return <span className="text-[#8aa0bd]">{brackets}</span>;
  if (!open) {
    return (
      <button className="text-[#8aa0bd] hover:text-[#eaf1fb]" onClick={() => setOpen(true)}>
        {brackets[0]}… {items.length} {brackets === "[]" ? "items" : "keys"} {brackets[1]}
      </button>
    );
  }
  return (
    <span>
      <button className="text-[#8aa0bd] hover:text-[#eaf1fb]" onClick={() => setOpen(false)}>
        {brackets[0]}
      </button>
      <div className="pl-4 border-l border-[#243650]">
        {items.map(([k, v]) => (
          <div key={k} className="leading-5">
            {!skipKeys && <span className="text-[#ffd24a]">&quot;{k}&quot;</span>}
            {!skipKeys && <span className="text-[#8aa0bd]">: </span>}
            <JsonView value={v} depth={depth + 1} />
          </div>
        ))}
      </div>
      <span className="text-[#8aa0bd]">{brackets[1]}</span>
    </span>
  );
}
