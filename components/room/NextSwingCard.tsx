"use client";

import type { PromptView } from "@/lib/store/types";

export function NextSwingCard({
  prompts,
  myPicks,
  onPick,
}: {
  prompts: PromptView[];
  myPicks: Record<string, string>;
  onPick: (promptId: string, optionKey: string) => void;
}) {
  // newest active prompt = the one to play right now
  const active = prompts.find((p) => p.status === "open") ?? prompts.find((p) => p.status === "locked");
  const recent = prompts.filter((p) => p.status === "settled").slice(0, 3);

  return (
    <div className="card overflow-hidden">
      <div className="flex items-center justify-between border-b border-[var(--color-line)] px-4 py-2">
        <span className="flex items-center gap-1.5 text-sm font-bold">⚡ Next Swing</span>
        <span className="text-[10px] uppercase tracking-wider text-[var(--color-mut)]">
          skill · points only
        </span>
      </div>

      {active ? (
        <ActivePrompt prompt={active} myPick={myPicks[active.id]} onPick={onPick} />
      ) : (
        <div className="px-4 py-5 text-center text-sm text-[var(--color-mut)]">
          No open call right now — the next prompt drops as the match develops.
        </div>
      )}

      {recent.length > 0 && (
        <div className="border-t border-[var(--color-line)] px-4 py-2">
          <div className="mb-1 text-[10px] uppercase tracking-wider text-[var(--color-mut)]">Recent calls</div>
          <div className="space-y-1">
            {recent.map((p) => {
              const win = p.options.find((o) => o.key === p.winningKey);
              const mine = myPicks[p.id];
              const correct = mine && mine === p.winningKey;
              return (
                <div key={p.id} className="flex items-center justify-between text-xs">
                  <span className="truncate text-[var(--color-mut)]">{p.question}</span>
                  <span className="ml-2 flex shrink-0 items-center gap-1">
                    <span className="font-semibold text-white">{win?.label ?? "void"}</span>
                    {mine && (
                      <span className={correct ? "text-[var(--color-lime)]" : "text-[var(--color-away)]"}>
                        {correct ? "✓" : "✗"}
                      </span>
                    )}
                  </span>
                </div>
              );
            })}
          </div>
        </div>
      )}
    </div>
  );
}

function ActivePrompt({
  prompt,
  myPick,
  onPick,
}: {
  prompt: PromptView;
  myPick?: string;
  onPick: (promptId: string, optionKey: string) => void;
}) {
  const locked = prompt.status === "locked";
  const totalVotes = Object.values(prompt.tally).reduce((a, b) => a + b, 0) || 1;
  return (
    <div className="px-4 py-3">
      <div className="flex items-center justify-between">
        <p className="text-base font-bold">{prompt.question}</p>
        <span className="chip shrink-0 text-[var(--color-gold)]">+{prompt.basePoints}</span>
      </div>
      <div className="mt-0.5 text-[11px] text-[var(--color-mut)]">
        {locked ? "🔒 Locked — awaiting result" : `Locks at ${prompt.locksAtMinute}'`}
      </div>

      <div className="mt-3 grid gap-2" style={{ gridTemplateColumns: `repeat(${Math.min(prompt.options.length, 3)}, minmax(0,1fr))` }}>
        {prompt.options.map((o) => {
          const picked = myPick === o.key;
          const share = Math.round(((prompt.tally[o.key] ?? 0) / totalVotes) * 100);
          return (
            <button
              key={o.key}
              disabled={locked || !!myPick}
              onClick={() => onPick(prompt.id, o.key)}
              className={`relative overflow-hidden rounded-xl border px-2 py-2.5 text-center text-sm font-semibold transition ${
                picked
                  ? "border-[var(--color-lime)] bg-[var(--color-lime)]/15"
                  : "border-[var(--color-line)] bg-black/20 hover:border-white/30"
              } ${locked || (myPick && !picked) ? "opacity-60" : ""}`}
            >
              <span
                className="absolute inset-y-0 left-0 bg-white/5"
                style={{ width: `${share}%` }}
                aria-hidden
              />
              <span className="relative block">{o.label}</span>
              {o.hint && <span className="relative block text-[10px] text-[var(--color-mut)]">{o.hint}</span>}
              <span className="relative block text-[10px] text-[var(--color-mut)]">{share}% of room</span>
            </button>
          );
        })}
      </div>

      {myPick && !locked && (
        <p className="mt-2 text-center text-[11px] text-[var(--color-lime)]">
          Locked in. Streak rewards stack — keep calling them right. 🔥
        </p>
      )}
    </div>
  );
}
