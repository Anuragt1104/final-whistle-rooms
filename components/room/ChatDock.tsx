"use client";

import { useEffect, useRef, useState } from "react";
import type { ChatView } from "@/lib/store/types";

const REACTIONS = ["⚽", "🔥", "😱", "👏", "🎉", "😤"];

export function ChatDock({
  chat,
  onSend,
  onReact,
  disabled,
}: {
  chat: ChatView[];
  onSend: (text: string) => void;
  onReact: (emoji: string) => void;
  disabled?: boolean;
}) {
  const [text, setText] = useState("");
  const endRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    endRef.current?.scrollIntoView({ behavior: "smooth" });
  }, [chat.length]);

  function send() {
    const t = text.trim();
    if (!t) return;
    onSend(t);
    setText("");
  }

  return (
    <div className="card flex h-[60vh] flex-col overflow-hidden">
      <div className="flex-1 space-y-1.5 overflow-y-auto p-3 no-scrollbar">
        {chat.length === 0 && (
          <p className="py-6 text-center text-sm text-[var(--color-mut)]">
            Say hi 👋 — react together as the match unfolds.
          </p>
        )}
        {chat.map((m) =>
          m.kind === "system" ? (
            <div key={m.id} className="py-0.5 text-center text-[11px] text-[var(--color-mut)]">
              — {m.text} —
            </div>
          ) : (
            <div key={m.id} className="flex items-start gap-2">
              <span className="text-base leading-none">{m.avatar}</span>
              <div className="min-w-0">
                <span className="mr-1 text-xs font-semibold text-[var(--color-mut)]">{m.name}</span>
                <span className={m.kind === "reaction" ? "text-xl" : "text-sm"}>{m.text}</span>
              </div>
            </div>
          ),
        )}
        <div ref={endRef} />
      </div>

      <div className="border-t border-[var(--color-line)] p-2">
        <div className="mb-2 flex gap-1">
          {REACTIONS.map((r) => (
            <button
              key={r}
              disabled={disabled}
              onClick={() => onReact(r)}
              className="grid h-8 w-8 place-items-center rounded-lg bg-black/30 text-lg transition hover:bg-white/10 disabled:opacity-40"
            >
              {r}
            </button>
          ))}
        </div>
        <div className="flex gap-2">
          <input
            className="input"
            placeholder={disabled ? "Join the room to chat" : "Message the room…"}
            value={text}
            disabled={disabled}
            onChange={(e) => setText(e.target.value)}
            onKeyDown={(e) => e.key === "Enter" && send()}
          />
          <button className="btn btn-primary px-4" onClick={send} disabled={disabled || !text.trim()}>
            Send
          </button>
        </div>
      </div>
    </div>
  );
}
