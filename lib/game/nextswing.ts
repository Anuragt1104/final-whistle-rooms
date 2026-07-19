/**
 * Next Swing — skill/knowledge Micro-Plays tied to TxLINE score, discipline,
 * corners, and odds. Bias toward reading the match over coin-flip prompts.
 * Intense spells (goal flurries, reds, corner storms) force drama-weighted picks.
 */
import { GamePhase, type MatchEvent, type OddsSnapshot, type ScoreSnapshot, type StatPair } from "@/lib/txline/types";
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
  status: SwingStatus | "scheduled" | "void" | "corrected";
  winningKey?: string;
  createdAt: number;
  openedAtMinute?: number;
  openedAtSeq?: number;
  /** Stat totals captured the moment the prompt locked — lets us resolve from
   *  deltas at a deadline even if no per-tick event fired. */
  lockState?: { goals: StatPair; corners: StatPair; cards: StatPair };
  /** Question Engine V2 metadata (optional; absent on legacy NextSwing). */
  lane?: "main" | "quick" | "break" | "hydration";
  category?: string;
  ruleId?: string;
  reason?: string;
  urgency?: number;
  openedClockSec?: number;
  answerClosesAt?: number;
  resolutionDeadlineClockSec?: number;
  feedFreshness?: string;
  sourceAttribution?: string;
  rewardPreview?: string;
  fanBuzzUrl?: string;
  fanBuzzFact?: string;
}

/** Bias from pulse challenges or major match events. */
export type PromptBias = "corners" | "next-goal" | "next-card" | "flurry" | "comeback" | "red";

/** Story extras so templates stay vivid even when the LLM rewrite fails. */
export interface MatchStory {
  lastScorer?: string;
  lastGoalMinute?: number;
  goalsLast10Min?: number;
  cardsLast5Min?: number;
  scoreJustChanged?: boolean;
  isComeback?: boolean;
  redCardActive?: boolean;
  flurrySummary?: string;
}

export interface MatchIntensity {
  goalsLast10Min: number;
  cardsLast5Min: number;
  scoreJustChanged: boolean;
  isComeback: boolean;
  redCardActive: boolean;
  momentumAbs: number;
  flurrySummary?: string;
  challenge?: "corners" | "next-goal";
}

export function isDefinitiveTerminalPhase(phase: GamePhase | number): boolean {
  return (
    phase === GamePhase.Finished ||
    phase === GamePhase.Abandoned ||
    phase === GamePhase.Cancelled
  );
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
  bias?: PromptBias | null,
  story?: MatchStory | null,
): SwingPrompt | null {
  const minute = score.minute;
  if (minute >= 88) return null;
  const home = labelOf(odds, "home");
  const away = labelOf(odds, "away");
  const lock = Math.min(minute + 5, 90);
  const totalGoals = score.goals.home + score.goals.away;
  const yellowH = score.yellow.home;
  const yellowA = score.yellow.away;
  const scoreLine = `${home} ${score.goals.home}–${score.goals.away} ${away}`;
  const flurry = story?.flurrySummary;
  const lastHit =
    story?.lastScorer && story.lastGoalMinute != null
      ? `${story.lastScorer}'s ${story.lastGoalMinute}'`
      : null;

  // Skill / knowledge menu — weighted, not equal coin-flips
  type Weighted = { w: number; make: () => SwingPrompt; kind: string };
  const menu: Weighted[] = [];

  // A plain-language live read. The probability powers scoring internally;
  // fans should not have to parse sportsbook-style thresholds.
  const leader = win.home >= win.away ? home : away;
  const leaderPct = Math.max(win.home, win.away);
  const leaderSide: "home" | "away" = win.home >= win.away ? "home" : "away";
  const swingQ = lastHit
    ? `${lastHit} shifted the match (${scoreLine}) — will ${leader}'s grip strengthen in five minutes?`
    : flurry
      ? `${flurry} — will ${leader}'s grip strengthen in five minutes?`
      : `${scoreLine} at ${minute}' — will ${leader}'s grip strengthen in five minutes?`;
  menu.push({
    kind: "win-swing",
    w: 3.2,
    make: () => ({
      id: pid(),
      question: swingQ,
      options: [
        { key: "up", label: "Yes — stronger" },
        { key: "down", label: "No — weakens" },
      ],
      resolver: { kind: "win-swing", side: leaderSide, baseline: leaderPct, minute: Math.min(minute + 5, 90) },
      basePoints: 110 + Math.round(Math.abs(50 - leaderPct)),
      locksAtMinute: Math.min(minute + 2, 90),
      status: "open",
      createdAt: Date.now(),
    }),
  });

  // A second short-window chance question with a clear deadline.
  menu.push({
    kind: "odds-move",
    w: 2.4,
    make: () => ({
      id: pid(),
      question: `${scoreLine} — will ${home} take more control by ${Math.min(minute + 6, 90)}'?`,
      options: [
        { key: "yes", label: "Yes — more control" },
        { key: "no", label: "No — not yet" },
      ],
      resolver: { kind: "odds-move", baseline: win.home, minute: Math.min(minute + 6, 90) },
      basePoints: 130,
      locksAtMinute: Math.min(minute + 2, 90),
      status: "open",
      createdAt: Date.now(),
    }),
  });

  // Pressure / discipline read
  const cardQ =
    (story?.cardsLast5Min ?? 0) >= 2
      ? `Chaos brewing (${story!.cardsLast5Min} cards in 5') — who gets booked next?`
      : yellowH + yellowA > 0
        ? `Ref's losing patience (${yellowH}–${yellowA} yellows) — which side is booked next?`
        : `First booking incoming at ${minute}' — which side cracks?`;
  menu.push({
    kind: "next-card-side",
    w: bias === "next-card" || bias === "red" ? 12 : 2.6,
    make: () => ({
      id: pid(),
      question: cardQ,
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
  const cornerQ =
    bias === "corners"
      ? `Corner storm — who wins the next one? (${score.corners.home}–${score.corners.away})`
      : `Who wins the next corner? (${cornerHint})`;
  menu.push({
    kind: "next-corner-side",
    w: bias === "corners" ? 14 : 2.2,
    make: () => ({
      id: pid(),
      question: cornerQ,
      options: [
        { key: "home", label: home, hint: cornerHint },
        { key: "away", label: away, hint: cornerHint },
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
  const leadQ = story?.isComeback
    ? `Comeback on — will either side hold a 2-goal cushion by ${leadTarget}'? (now ${scoreLine})`
    : `Will either team lead by two at ${leadTarget}'? (now ${scoreLine})`;
  menu.push({
    kind: "lead-by-two",
    w: bias === "comeback" ? 10 : 2.0,
    make: () => ({
      id: pid(),
      question: leadQ,
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
  const goalsQ = flurry
    ? `${flurry} — reach ${goalTarget} total by ${goalsDeadline}'?`
    : totalGoals > 0
      ? `${totalGoals} already — reach ${goalTarget} by ${goalsDeadline}'? (${scoreLine})`
      : `Still 0–0 — a goal by ${goalsDeadline}'?`;
  menu.push({
    kind: "total-goals",
    w: bias === "flurry" ? 12 : 2.0,
    make: () => ({
      id: pid(),
      question: goalsQ,
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

  // Next goal before — boosted hard during flurries / reds / pulse next-goal
  const nextGoalDeadline = Math.min(minute + 15, 90);
  const nextGoalQ =
    bias === "red" || story?.redCardActive
      ? `10 men — who scores next before ${nextGoalDeadline}'? (${scoreLine})`
      : lastHit
        ? `${lastHit} just went in (${scoreLine}) — reply before ${nextGoalDeadline}'?`
        : flurry
          ? `${flurry} — next goal before ${nextGoalDeadline}'?`
          : `Next goal before ${nextGoalDeadline}'? (${scoreLine})`;
  menu.push({
    kind: "next-goal-before",
    w:
      bias === "next-goal" || bias === "flurry" || bias === "red" || bias === "comeback"
        ? 14
        : 1.4,
    make: () => ({
      id: pid(),
      question: nextGoalQ,
      options: [
        { key: "home", label: home },
        { key: "none", label: "No goal" },
        { key: "away", label: away },
      ],
      resolver: { kind: "next-goal-before", minute: nextGoalDeadline },
      basePoints: 140,
      locksAtMinute: lock,
      status: "open",
      createdAt: Date.now(),
    }),
  });

  if (minute < 40) {
    menu.push({
      kind: "half-level",
      w: 1.2,
      make: () => ({
        id: pid(),
        question: `Is it level at half-time? (now ${scoreLine})`,
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
    kind: "next-event",
    w: 0.55,
    make: () => ({
      id: pid(),
      question: `What happens first — goal or card? (${scoreLine})`,
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

/** Derive a prompt bias from match intensity / pulse challenges. */
export function biasFromIntensity(intensity: MatchIntensity | null | undefined): PromptBias | null {
  if (!intensity) return null;
  if (intensity.challenge === "corners") return "corners";
  if (intensity.challenge === "next-goal") return "next-goal";
  if (intensity.redCardActive && intensity.scoreJustChanged) return "red";
  if (intensity.redCardActive) return "red";
  if (intensity.isComeback && intensity.scoreJustChanged) return "comeback";
  if (intensity.goalsLast10Min >= 2) return "flurry";
  if (intensity.scoreJustChanged) return "next-goal";
  if (intensity.cardsLast5Min >= 2) return "next-card";
  return null;
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
      if (score.minute >= r.minute || isDefinitiveTerminalPhase(score.phase)) {
        return Math.abs(score.goals.home - score.goals.away) >= 2 ? "yes" : "no";
      }
      return null;
    }
    case "total-goals": {
      const tot = score.goals.home + score.goals.away;
      if (tot >= r.target) return "yes";
      if (score.minute >= r.minute || isDefinitiveTerminalPhase(score.phase)) return "no";
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
