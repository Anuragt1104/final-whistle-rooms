/**
 * Next Swing — bite-sized, skill-based live prediction prompts tied strictly to
 * documented TxLINE primitives (goals, cards, corners, phase, odds movement).
 * No cash staking: players build points and streaks. Prompts open with a short
 * betting window, lock, then settle automatically as the match unfolds — so the
 * same logic works on simulated and live data.
 */
import type { MatchEvent, OddsSnapshot, ScoreSnapshot, StatPair } from "@/lib/txline/types";
import type { WinChance } from "@/lib/engine/pulse";

export interface SwingOption {
  key: string;
  label: string;
  /** Friendly implied chance shown as a hint (from the market when relevant). */
  hint?: string;
}

export type SwingResolver =
  /** First of these event kinds to occur after lock wins its mapped option. */
  | { kind: "next-event"; map: Partial<Record<"goal" | "corner" | "card", string>> }
  /** Side of the next corner. */
  | { kind: "next-corner-side" }
  /** Which side scores next (or none) before `minute`. */
  | { kind: "next-goal-before"; minute: number }
  /** Is the given half level when it ends? */
  | { kind: "half-level"; endMinute: number }
  /** Does the home win-chance move up/down by `delta` before `minute`? */
  | { kind: "odds-move"; baseline: number; minute: number };

export type SwingStatus = "open" | "locked" | "settled";

export interface SwingPrompt {
  id: string;
  question: string;
  options: SwingOption[];
  resolver: SwingResolver;
  /** Points awarded for a correct call (higher for longer odds). */
  basePoints: number;
  /** Match minute the window closes (predictions lock). */
  locksAtMinute: number;
  status: SwingStatus;
  winningKey?: string;
  createdAt: number;
  /** Stat totals captured the moment the prompt locked — lets us resolve from
   *  deltas at a deadline even if no per-tick event fired. */
  lockState?: { goals: StatPair; corners: StatPair; cards: StatPair };
}

let counter = 0;
function pid(): string {
  return `sw_${Date.now().toString(36)}_${counter++}`;
}

/**
 * Generate a fresh prompt appropriate to the current match state. Returns null
 * when it's not a good moment (e.g. half-time, or match over).
 */
export function generatePrompt(
  score: ScoreSnapshot,
  odds: OddsSnapshot | null,
  win: WinChance,
  rand: () => number,
): SwingPrompt | null {
  const minute = score.minute;
  if (minute >= 88) return null;
  const home = labelOf(odds, "home");
  const away = labelOf(odds, "away");
  const lock = Math.min(minute + 5, 90);

  // weight the menu by what's live and dramatic
  const menu: Array<() => SwingPrompt> = [];

  menu.push(() => ({
    id: pid(),
    question: "What happens first?",
    options: [
      { key: "goal", label: "A goal ⚽" },
      { key: "card", label: "A card 🟨" },
    ],
    resolver: { kind: "next-event", map: { goal: "goal", card: "card" } },
    basePoints: 120,
    locksAtMinute: lock,
    status: "open",
    createdAt: Date.now(),
  }));

  menu.push(() => ({
    id: pid(),
    question: "Who wins the next corner?",
    options: [
      { key: "home", label: home },
      { key: "away", label: away },
    ],
    resolver: { kind: "next-corner-side" },
    basePoints: 100,
    locksAtMinute: lock,
    status: "open",
    createdAt: Date.now(),
  }));

  menu.push(() => ({
    id: pid(),
    question: `Next goal before ${Math.min(minute + 15, 90)}'?`,
    options: [
      { key: "home", label: home, hint: pctHint(win.home) },
      { key: "none", label: "No goal" },
      { key: "away", label: away, hint: pctHint(win.away) },
    ],
    resolver: { kind: "next-goal-before", minute: Math.min(minute + 15, 90) },
    basePoints: 140,
    locksAtMinute: lock,
    status: "open",
    createdAt: Date.now(),
  }));

  // odds-movement prompt (the "market translator" as a game)
  menu.push(() => ({
    id: pid(),
    question: `Does ${home}'s win chance rise in the next 6'?`,
    options: [
      { key: "yes", label: "Rises 📈" },
      { key: "no", label: "Holds / drops 📉" },
    ],
    resolver: { kind: "odds-move", baseline: win.home, minute: Math.min(minute + 6, 90) },
    basePoints: 110,
    locksAtMinute: Math.min(minute + 2, 90),
    status: "open",
    createdAt: Date.now(),
  }));

  // first-half level prompt, only when relevant
  if (minute < 40) {
    menu.push(() => ({
      id: pid(),
      question: "Is it level at half-time?",
      options: [
        { key: "yes", label: "Level 🤝" },
        { key: "no", label: "Someone leads" },
      ],
      resolver: { kind: "half-level", endMinute: 45 },
      basePoints: 100,
      locksAtMinute: 44,
      status: "open",
      createdAt: Date.now(),
    }));
  }

  const pick = menu[Math.floor(rand() * menu.length)];
  return pick();
}

/**
 * Try to settle a locked prompt against a new tick. Returns the winning option
 * key, or null if still unresolved.
 */
export function tryResolve(
  prompt: SwingPrompt,
  events: MatchEvent[],
  score: ScoreSnapshot,
  win: WinChance,
): string | null {
  const r = prompt.resolver;
  switch (r.kind) {
    case "next-event": {
      for (const e of events) {
        if (e.kind === "goal" && r.map.goal) return r.map.goal;
        if (e.kind === "corner" && r.map.corner) return r.map.corner;
        if ((e.kind === "yellow" || e.kind === "red") && r.map.card) return r.map.card;
      }
      return null;
    }
    case "next-corner-side": {
      const corner = events.find((e) => e.kind === "corner");
      return corner?.side ?? null;
    }
    case "next-goal-before": {
      const goal = events.find((e) => e.kind === "goal");
      if (goal?.side) return goal.side;
      if (score.minute >= r.minute) return "none";
      return null;
    }
    case "half-level": {
      if (score.minute >= r.endMinute || score.phase >= 2) {
        return score.goals.home === score.goals.away ? "yes" : "no";
      }
      return null;
    }
    case "odds-move": {
      if (score.minute >= r.minute) {
        return win.home > r.baseline ? "yes" : "no";
      }
      return null;
    }
  }
}

/** Snapshot the stat totals at lock time (cards = yellow + red per side). */
export function lockSnapshot(score: ScoreSnapshot): NonNullable<SwingPrompt["lockState"]> {
  return {
    goals: { ...score.goals },
    corners: { ...score.corners },
    cards: { home: score.yellow.home + score.red.home, away: score.yellow.away + score.red.away },
  };
}

/**
 * Deterministically settle a prompt at its deadline (no per-tick event needed)
 * using the delta since it locked. Returns a winning key, or "__void__" when
 * nothing relevant happened so the prompt still closes out (no points, no
 * streak penalty — handled in settlePrompt).
 */
export function forceResolve(prompt: SwingPrompt, score: ScoreSnapshot, win: WinChance): string {
  const r = prompt.resolver;
  const ls = prompt.lockState;
  const dGoalsH = ls ? score.goals.home - ls.goals.home : score.goals.home;
  const dGoalsA = ls ? score.goals.away - ls.goals.away : score.goals.away;
  const dCornH = ls ? score.corners.home - ls.corners.home : 0;
  const dCornA = ls ? score.corners.away - ls.corners.away : 0;
  const dCards = ls ? score.yellow.home + score.red.home + score.yellow.away + score.red.away - ls.cards.home - ls.cards.away : 0;
  switch (r.kind) {
    case "next-event":
      if (dGoalsH + dGoalsA > 0) return r.map.goal ?? "__void__";
      if (dCards > 0) return r.map.card ?? "__void__";
      return "__void__";
    case "next-corner-side":
      if (dCornH > dCornA) return "home";
      if (dCornA > dCornH) return "away";
      return "__void__";
    case "next-goal-before":
      if (dGoalsH > dGoalsA) return "home";
      if (dGoalsA > dGoalsH) return "away";
      if (dGoalsH + dGoalsA === 0) return "none";
      return "__void__";
    case "half-level":
      return score.goals.home === score.goals.away ? "yes" : "no";
    case "odds-move":
      return win.home > r.baseline ? "yes" : "no";
  }
}

function labelOf(odds: OddsSnapshot | null, key: "home" | "away"): string {
  const m = odds?.markets.find((x) => x.type === "match_result");
  return m?.selections.find((s) => s.key === key)?.label ?? (key === "home" ? "Home" : "Away");
}
function pctHint(p: number): string {
  return `${p}%`;
}
