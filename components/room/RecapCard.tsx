"use client";

import type { RecapView } from "@/lib/store/types";

export function RecapCard({ recap, aiOn }: { recap: RecapView; aiOn: boolean }) {
  return (
    <div className="card border-l-4 border-l-[var(--color-lime)] p-4">
      <div className="mb-1 flex items-center gap-2">
        <span className="chip text-[var(--color-lime)]">
          {recap.scope === "half-time" ? "HALF-TIME" : "FULL-TIME"} RECAP
        </span>
        <span className="chip">{aiOn ? "✨ AI pundit" : "✨ Auto recap"}</span>
      </div>
      <p className="text-sm leading-relaxed">{recap.text}</p>
      {recap.topMember && (
        <p className="mt-2 text-[11px] text-[var(--color-mut)]">
          Room leader: <span className="font-semibold text-[var(--color-gold)]">{recap.topMember}</span>
        </p>
      )}
    </div>
  );
}
