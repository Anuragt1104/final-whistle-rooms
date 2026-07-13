/**
 * Next Swing — skill/knowledge Micro-Plays tied to TxLINE score, discipline,
 * corners, and odds. Bias toward reading the match over coin-flip prompts.
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
  | { kind: "odds-move"; baseline: number; minute: number }
  /** HIGHER or LOWER: is the side's win-chance above `baseline` by `minute`? */
  | { kind: "win-swing"; side: "home" | "away"; baseline: number; minute: number }
  /** Which side picks up the next yellow/red (discipline read). */
  | { kind: "next-card-side" }
  /** Will either side lead by 2+ when the clock hits `minute` (or FT). */
  | { kind: "lead-by-two"; minute: number }
  /** Will total goals reach `target` by `minute`. */
  | { kind: "total-goals"; target: number; minute: number };

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
  const totalGoals = score.goals.home + score.goals.away;
  const yellowH = score.yellow.home;
  const yellowA = score.yellow.away;

  // Skill / knowledge menu — weighted, not equal coin-flips
  type Weighted = { w: number; make: () => SwingPrompt };
  const menu: Weighted[] = [];

  // Market literacy — featured Higher/Lower with explicit favourite %
  const leader = win.home >= win.away ? home : away;
  const leaderPct = Math.max(win.home, win.away);
  const leaderSide: "home" | "away" = win.home >= win.away ? "home" : "away";
  menu.push({
    w: 3.2,
    make: () => ({
      id: pid(),
      question: `Favourite ${leader} at ${leaderPct}% — call the swing in 5'`,
      options: [
        { key: "up", label: "Higher", hint: "📈 market firm" },
        { key: "down", label: "Lower", hint: "📉 market soft" },
      ],
      resolver: { kind: "win-swing", side: leaderSide, baseline: leaderPct, minute: Math.min(minute + 5, 90) },
      basePoints: 110 + Math.round(Math.abs(50 - leaderPct)),
      locksAtMinute: Math.min(minute + 2, 90),
      status: "open",
      createdAt: Date.now(),
    }),
  });

  // Odds-move: will home win% clear the baseline?
  menu.push({
    w: 2.4,
    make: () => ({
      id: pid(),
      question: `${home} win% is ${win.home} — clear ${win.home} by ${Math.min(minute + 6, 90)}'?`,
      options: [
        { key: "yes", label: "Yes — rises", hint: pctHint(win.home) },
        { key: "no", label: "No — stalls/falls" },
      ],
      resolver: { kind: "odds-move", baseline: win.home, minute: Math.min(minute + 6, 90) },
      basePoints: 130,
      locksAtMinute: Math.min(minute + 2, 90),
      status: "open",
      createdAt: Date.now(),
    }),
  });

  // Pressure / discipline read
  menu.push({
    w: 2.6,
    make: () => ({
      id: pid(),
      question: `Who gets the next yellow? (${home} ${yellowH} · ${away} ${yellowA})`,
      options: [
        { key: "home", label: home, hint: yellowH >= yellowA ? "hot" : "cooler" },
        { key: "away", label: away, hint: yellowA >= yellowH ? "hot" : "cooler" },
      ],
      resolver: { kind: "next-card-side" },
      basePoints: 125,
      locksAtMinute: lock,
      status: "open",
      createdAt: Date.now(),
    }),
  });

  // Set-piece IQ — corner side with form hint
  const cornerHint =
    score.corners.home === score.corners.away
      ? "even so far"
      : score.corners.home > score.corners.away
        ? `${home} lead corners ${score.corners.home}–${score.corners.away}`
        : `${away} lead corners ${score.corners.away}–${score.corners.home}`;
  menu.push({
    w: 2.2,
    make: () => ({
      id: pid(),
      question: `Next corner — who wins it? (${cornerHint})`,
      options: [
        { key: "home", label: home },
        { key: "away", label: away },
      ],
      resolver: { kind: "next-corner-side" },
      basePoints: 105,
      locksAtMinute: lock,
      status: "open",
      createdAt: Date.now(),
    }),
  });

  // Scoreboard literacy — lead by 2+
  const leadTarget = Math.min(Math.max(minute + 20, 70), 90);
  menu.push({
    w: 2.0,
    make: () => ({
      id: pid(),
      question: `Will either side lead by 2+ at ${leadTarget}'? (now ${score.goals.home}–${score.goals.away})`,
      options: [
        { key: "yes", label: "Yes — 2-goal cushion" },
        { key: "no", label: "No — stays tight" },
      ],
      resolver: { kind: "lead-by-two", minute: leadTarget },
      basePoints: 140,
      locksAtMinute: Math.min(minute + 3, 90),
      status: "open",
      createdAt: Date.now(),
    }),
  });

  // Total goals literacy
  const goalTarget = totalGoals + 1 + (rand() < 0.45 ? 1 : 0);
  const goalsDeadline = Math.min(Math.max(minute + 25, 75), 90);
  menu.push({
    w: 2.0,
    make: () => ({
      id: pid(),
      question: `Will total goals hit ${goalTarget} by ${goalsDeadline}'? (now ${totalGoals})`,
      options: [
        { key: "yes", label: `Yes — reach ${goalTarget}` },
        { key: "no", label: `No — stay under` },
      ],
      resolver: { kind: "total-goals", target: goalTarget, minute: goalsDeadline },
      basePoints: 135,
      locksAtMinute: Math.min(minute + 3, 90),
      status: "open",
      createdAt: Date.now(),
    }),
  });

  // Next goal before — still skill (who scores) but lower weight
  menu.push({
    w: 1.4,
    make: () => ({
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
    }),
  });

  if (minute < 40) {
    menu.push({
      w: 1.2,
      make: () => ({
        id: pid(),
        question: "Is it level at half-time?",
        options: [
          { key: "yes", label: "Level" },
          { key: "no", label: "Someone leads" },
        ],
        resolver: { kind: "half-level", endMinute: 45 },
        basePoints: 100,
        locksAtMinute: 44,
        status: "open",
        createdAt: Date.now(),
      }),
    });
  }

  // Rare variety: goal vs card — heavily down-weighted vs skill prompts
  menu.push({
    w: 0.55,
    make: () => ({
      id: pid(),
      question: "What happens first — goal or card?",
      options: [
        { key: "goal", label: "A goal" },
        { key: "card", label: "A card" },
      ],
      resolver: { kind: "next-event", map: { goal: "goal", card: "card" } },
      basePoints: 100,
      locksAtMinute: lock,
      status: "open",
      createdAt: Date.now(),
    }),
  });

  const totalW = menu.reduce((s, m) => s + m.w, 0);
  let roll = rand() * totalW;
  for (const item of menu) {
    roll -= item.w;
    if (roll <= 0) return item.make();
  }
  return menu[menu.length - 1].make();
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
    case "next-card-side": {
      const card = events.find((e) => e.kind === "yellow" || e.kind === "red");
      return card?.side ?? null;
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
    case "win-swing": {
      if (score.minute >= r.minute) {
        const cur = r.side === "home" ? win.home : win.away;
        return cur > r.baseline ? "up" : "down";
      }
      return null;
    }
    case "lead-by-two": {
      if (score.minute >= r.minute || score.phase >= 4) {
        return Math.abs(score.goals.home - score.goals.away) >= 2 ? "yes" : "no";
      }
      return null;
    }
    case "total-goals": {
      const tot = score.goals.home + score.goals.away;
      if (tot >= r.target) return "yes";
      if (score.minute >= r.minute || score.phase >= 4) return "no";
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
  const cardsNow = score.yellow.home + score.red.home + score.yellow.away + score.red.away;
  const cardsLock = ls ? ls.cards.home + ls.cards.away : 0;
  const dCardsH = ls
    ? score.yellow.home + score.red.home - ls.cards.home
    : score.yellow.home + score.red.home;
  const dCardsA = ls
    ? score.yellow.away + score.red.away - ls.cards.away
    : score.yellow.away + score.red.away;
  switch (r.kind) {
    case "next-event":
      if (dGoalsH + dGoalsA > 0) return r.map.goal ?? "__void__";
      if (cardsNow - cardsLock > 0) return r.map.card ?? "__void__";
      return "__void__";
    case "next-corner-side":
      if (dCornH > dCornA) return "home";
      if (dCornA > dCornH) return "away";
      return "__void__";
    case "next-card-side":
      if (dCardsH > dCardsA) return "home";
      if (dCardsA > dCardsH) return "away";
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
    case "win-swing": {
      const cur = r.side === "home" ? win.home : win.away;
      return cur > r.baseline ? "up" : "down";
    }
    case "lead-by-two":
      return Math.abs(score.goals.home - score.goals.away) >= 2 ? "yes" : "no";
    case "total-goals":
      return score.goals.home + score.goals.away >= r.target ? "yes" : "no";
  }
}

function labelOf(odds: OddsSnapshot | null, key: "home" | "away"): string {
  const m = odds?.markets.find((x) => x.type === "match_result");
  return m?.selections.find((s) => s.key === key)?.label ?? (key === "home" ? "Home" : "Away");
}
function pctHint(p: number): string {
  return `${p}%`;
}
