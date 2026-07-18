/**
 * Micro-Play prompt writer — the LLM rewrites a template question into vivid,
 * moment-specific copy. The ENGINE stays authoritative: resolver, option keys,
 * deadlines and points never change; only the question text and option labels
 * do. Any invalid/late/failed rewrite → null → the template text stands.
 */
import { chatJSON } from "@/lib/llm/client";
import type { SwingPrompt } from "@/lib/game/nextswing";

export interface PromptContext {
  minute: number;
  phaseLabel: string;
  home: { name: string; code: string };
  away: { name: string; code: string };
  score: { home: number; away: number };
  cards: { yellow: { home: number; away: number }; red: { home: number; away: number } };
  corners: { home: number; away: number };
  win: { home: number; draw: number; away: number };
  momentum: number;
  /** Last few key events, e.g. "67' Goal (Mbappé) — France". */
  recentEvents: string[];
  /** Recent pulse-feed headlines — the room's running narrative. */
  narrative: string[];
  /** High-drama flags so rewrites lean into flurries, comebacks, and cards. */
  intensity?: {
    goalsLast10Min: number;
    cardsLast5Min: number;
    scoreJustChanged: boolean;
    isComeback: boolean;
    redCardActive: boolean;
    momentumAbs: number;
    flurrySummary?: string;
  };
}

const SYSTEM_PROMPT =
  "You write in-match prediction questions for a World Cup watch-party app. " +
  "You are given the match situation and a mechanically-generated question with fixed option keys. " +
  "Rewrite ONLY the question text and option labels to be vivid, specific to this exact moment — " +
  "reference the score, minute, named players, momentum, and stakes when the context provides them. " +
  "When intensity is high (goal flurries, comebacks, red cards, chaos), lean hard into the drama — " +
  "name the flurry, the chase, the 10-men stakes — without inventing events that are not in context. " +
  "Rules: the rewritten question MUST ask for exactly the same thing the original resolves " +
  "(same outcome, same deadline minute, same teams/sides per option key); never change what an option key means; " +
  "no betting/money language; question under 120 characters; each label under 32 characters; " +
  'output only JSON: {"question": string, "options": [{"key": string, "label": string}]} ' +
  "with exactly the same keys in the same order as given.";

function deadlineMinute(prompt: SwingPrompt): number {
  const r = prompt.resolver;
  if ("minute" in r) return r.minute;
  if ("endMinute" in r) return r.endMinute;
  return prompt.locksAtMinute;
}

/** Validate an LLM rewrite against the engine's prompt. Exported for tests. */
export function validateRewrite(
  prompt: SwingPrompt,
  raw: unknown,
): { question: string; labels: Map<string, string> } | null {
  if (!raw || typeof raw !== "object") return null;
  const obj = raw as { question?: unknown; options?: unknown };
  if (typeof obj.question !== "string") return null;
  const question = obj.question.trim();
  if (question.length < 10 || question.length > 140) return null;
  if (!Array.isArray(obj.options) || obj.options.length !== prompt.options.length) return null;
  const labels = new Map<string, string>();
  for (const o of obj.options) {
    if (!o || typeof o !== "object") return null;
    const { key, label } = o as { key?: unknown; label?: unknown };
    if (typeof key !== "string" || typeof label !== "string") return null;
    const trimmed = label.trim();
    if (trimmed.length < 1 || trimmed.length > 40) return null;
    labels.set(key, trimmed);
  }
  // exact key set — every engine key present, nothing invented
  for (const o of prompt.options) if (!labels.has(o.key)) return null;
  if (labels.size !== prompt.options.length) return null;
  return { question, labels };
}

export async function rewritePromptText(
  prompt: SwingPrompt,
  ctx: PromptContext,
): Promise<{ question: string; labels: Map<string, string> } | null> {
  try {
    const raw = await chatJSON({
      system: SYSTEM_PROMPT,
      user: JSON.stringify({
        context: ctx,
        original: {
          question: prompt.question,
          deadlineMinute: deadlineMinute(prompt),
          resolverKind: prompt.resolver.kind,
          options: prompt.options.map((o) => ({ key: o.key, label: o.label })),
        },
      }),
    });
    return validateRewrite(prompt, raw);
  } catch {
    return null;
  }
}
