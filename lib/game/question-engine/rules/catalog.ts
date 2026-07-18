/**
 * Typed rule catalog — situation → candidates (no Math.random).
 */
import type { MatchContext, QuestionCandidate, QuestionLane } from "../types";

function label(ctx: MatchContext, side: "home" | "away"): string {
  return side === "home" ? ctx.homeCode || ctx.homeName : ctx.awayCode || ctx.awayName;
}

function scoreLine(ctx: MatchContext): string {
  return `${label(ctx, "home")} ${ctx.score.goals.home}–${ctx.score.goals.away} ${label(ctx, "away")}`;
}

/** Produce rule candidates for the current match context + preferred lane. */
export function detectCandidates(ctx: MatchContext, lane: QuestionLane): QuestionCandidate[] {
  const minute = ctx.score.minute;
  const home = label(ctx, "home");
  const away = label(ctx, "away");
  const line = scoreLine(ctx);
  const lock = Math.min(minute + 5, minute + 15);
  const totalGoals = ctx.score.goals.home + ctx.score.goals.away;
  const out: QuestionCandidate[] = [];

  if (lane === "hydration" || lane === "break") {
    out.push({
      ruleId: "ht-next-goal-side",
      lane,
      category: "scoreboard",
      question: lane === "hydration"
        ? `Water break — who scores first when play resumes? (${line})`
        : `Half-time — who scores first in the second half? (${line})`,
      options: [
        { key: "home", label: home },
        { key: "away", label: away },
        { key: "none", label: "Neither soon" },
      ],
      resolver: { kind: "next-goal-before", minute: Math.min(minute + 20, 90) },
      basePoints: 120,
      reason: lane === "hydration" ? "hydration deck" : "half-time deck",
      urgency: 0.7,
      locksAtMinute: minute + 3,
      resolutionDeadlineMinute: Math.min(minute + 20, 105),
      priority: 8,
      cooldownKey: `${lane}:next-goal`,
      noveltyKey: `${lane}:next-goal:${minute}`,
    });
    out.push({
      ruleId: "ht-total-goals",
      lane,
      category: "scoreboard",
      question: `Will we reach ${totalGoals + 1} total goals by full time? (${line})`,
      options: [
        { key: "yes", label: `Yes — ${totalGoals + 1}+` },
        { key: "no", label: "No — stays here" },
      ],
      resolver: { kind: "total-goals", target: totalGoals + 1, minute: 90 },
      basePoints: 110,
      reason: "break total goals",
      urgency: 0.55,
      locksAtMinute: minute + 2,
      resolutionDeadlineMinute: 95,
      priority: 6,
      cooldownKey: `${lane}:total`,
      noveltyKey: `${lane}:total:${totalGoals}`,
    });
    return out;
  }

  const leaderSide: "home" | "away" = ctx.win.home >= ctx.win.away ? "home" : "away";
  const leader = label(ctx, leaderSide);
  const leaderPct = Math.max(ctx.win.home, ctx.win.away);
  const lastHit =
    ctx.lastScorer && ctx.lastGoalMinute != null
      ? `${ctx.lastScorer}'s ${ctx.lastGoalMinute}'`
      : null;

  out.push({
    ruleId: "win-swing",
    lane,
    category: "market",
    question: lastHit
      ? `${lastHit} shifted the match (${line}) — will ${leader}'s grip strengthen in five minutes?`
      : ctx.flurrySummary
        ? `${ctx.flurrySummary} — will ${leader}'s grip strengthen in five minutes?`
        : `${line} at ${minute}' — will ${leader}'s grip strengthen in five minutes?`,
    options: [
      { key: "up", label: "Yes — stronger" },
      { key: "down", label: "No — weakens" },
    ],
    resolver: {
      kind: "win-swing",
      side: leaderSide,
      baseline: leaderPct,
      minute: Math.min(minute + 5, 130),
    },
    basePoints: 110 + Math.round(Math.abs(50 - leaderPct)),
    reason: "market grip read",
    urgency: ctx.majorEvent ? 0.85 : 0.55,
    locksAtMinute: Math.min(minute + 2, 130),
    resolutionDeadlineMinute: Math.min(minute + 5, 130),
    priority: 7,
    cooldownKey: "win-swing",
    noveltyKey: `win-swing:${leaderSide}:${Math.floor(leaderPct)}`,
  });

  out.push({
    ruleId: "odds-move",
    lane,
    category: "market",
    question: `${line} — will ${home} take more control by ${Math.min(minute + 6, 130)}'?`,
    options: [
      { key: "yes", label: "Yes — more control" },
      { key: "no", label: "No — not yet" },
    ],
    resolver: { kind: "odds-move", baseline: ctx.win.home, minute: Math.min(minute + 6, 130) },
    basePoints: 130,
    reason: "home control window",
    urgency: 0.5,
    locksAtMinute: Math.min(minute + 2, 130),
    resolutionDeadlineMinute: Math.min(minute + 6, 130),
    priority: 5,
    cooldownKey: "odds-move",
    noveltyKey: `odds-move:${Math.floor(ctx.win.home)}`,
  });

  const yellowH = ctx.score.yellow.home;
  const yellowA = ctx.score.yellow.away;
  out.push({
    ruleId: "next-card-side",
    lane,
    category: "discipline",
    question:
      (ctx.cardsLast5Min ?? 0) >= 2
        ? `Chaos brewing (${ctx.cardsLast5Min} cards in 5') — who gets booked next?`
        : yellowH + yellowA > 0
          ? `Ref's losing patience (${yellowH}–${yellowA} yellows) — which side is booked next?`
          : `First booking incoming at ${minute}' — which side cracks?`,
    options: [
      { key: "home", label: home, hint: yellowH >= yellowA ? "hot" : "cooler" },
      { key: "away", label: away, hint: yellowA >= yellowH ? "hot" : "cooler" },
    ],
    resolver: { kind: "next-card-side" },
    basePoints: 125,
    reason: "discipline read",
    urgency: (ctx.cardsLast5Min ?? 0) >= 2 ? 0.9 : 0.45,
    locksAtMinute: lock,
    resolutionDeadlineMinute: Math.min(minute + 12, 130),
    priority: (ctx.cardsLast5Min ?? 0) >= 2 ? 12 : 4,
    cooldownKey: "next-card",
    noveltyKey: `next-card:${yellowH}-${yellowA}`,
  });

  const cornerHint =
    ctx.score.corners.home === ctx.score.corners.away
      ? "even so far"
      : ctx.score.corners.home > ctx.score.corners.away
        ? `${home} lead corners ${ctx.score.corners.home}–${ctx.score.corners.away}`
        : `${away} lead corners ${ctx.score.corners.away}–${ctx.score.corners.home}`;
  out.push({
    ruleId: "next-corner-side",
    lane,
    category: "set-piece",
    question: `Who wins the next corner? (${cornerHint})`,
    options: [
      { key: "home", label: home, hint: cornerHint },
      { key: "away", label: away, hint: cornerHint },
    ],
    resolver: { kind: "next-corner-side" },
    basePoints: 105,
    reason: "set-piece pressure",
    urgency: 0.4,
    locksAtMinute: lock,
    resolutionDeadlineMinute: Math.min(minute + 12, 130),
    priority: 3,
    cooldownKey: "next-corner",
    noveltyKey: `next-corner:${ctx.score.corners.home}-${ctx.score.corners.away}`,
  });

  const leadTarget = Math.min(Math.max(minute + 20, 70), 130);
  out.push({
    ruleId: "lead-by-two",
    lane,
    category: "scoreboard",
    question: ctx.isComeback
      ? `Comeback on — will either side hold a 2-goal cushion by ${leadTarget}'? (now ${line})`
      : `Will either team lead by two at ${leadTarget}'? (now ${line})`,
    options: [
      { key: "yes", label: "Yes — 2-goal cushion" },
      { key: "no", label: "No — stays tight" },
    ],
    resolver: { kind: "lead-by-two", minute: leadTarget },
    basePoints: 140,
    reason: "scoreboard literacy",
    urgency: ctx.isComeback ? 0.8 : 0.4,
    locksAtMinute: Math.min(minute + 3, 130),
    resolutionDeadlineMinute: leadTarget,
    priority: ctx.isComeback ? 10 : 3,
    cooldownKey: "lead-two",
    noveltyKey: `lead-two:${leadTarget}`,
  });

  // Deterministic target: +1, or +2 when already scoring freely.
  const goalTarget = totalGoals + 1 + ((ctx.goalsLast10Min ?? 0) >= 2 ? 1 : 0);
  const goalsDeadline = Math.min(Math.max(minute + 25, 75), 130);
  out.push({
    ruleId: "total-goals",
    lane,
    category: "scoreboard",
    question: ctx.flurrySummary
      ? `${ctx.flurrySummary} — reach ${goalTarget} total by ${goalsDeadline}'?`
      : totalGoals > 0
        ? `${totalGoals} already — reach ${goalTarget} by ${goalsDeadline}'? (${line})`
        : `Still 0–0 — a goal by ${goalsDeadline}'?`,
    options: [
      { key: "yes", label: `Yes — reach ${goalTarget}` },
      { key: "no", label: "No — stay under" },
    ],
    resolver: { kind: "total-goals", target: goalTarget, minute: goalsDeadline },
    basePoints: 135,
    reason: "total goals window",
    urgency: (ctx.goalsLast10Min ?? 0) >= 2 ? 0.85 : 0.45,
    locksAtMinute: Math.min(minute + 3, 130),
    resolutionDeadlineMinute: goalsDeadline,
    priority: (ctx.goalsLast10Min ?? 0) >= 2 ? 11 : 4,
    cooldownKey: "total-goals",
    noveltyKey: `total-goals:${goalTarget}`,
  });

  const nextGoalDeadline = Math.min(minute + 15, 130);
  out.push({
    ruleId: "next-goal-before",
    lane,
    category: "next-event",
    question: ctx.redCardActive
      ? `10 men — who scores next before ${nextGoalDeadline}'? (${line})`
      : lastHit
        ? `${lastHit} just went in (${line}) — reply before ${nextGoalDeadline}'?`
        : `Next goal before ${nextGoalDeadline}'? (${line})`,
    options: [
      { key: "home", label: home },
      { key: "none", label: "No goal" },
      { key: "away", label: away },
    ],
    resolver: { kind: "next-goal-before", minute: nextGoalDeadline },
    basePoints: 140,
    reason: "next goal window",
    urgency: ctx.majorEvent || ctx.redCardActive ? 0.95 : 0.5,
    locksAtMinute: lock,
    resolutionDeadlineMinute: nextGoalDeadline,
    priority: ctx.majorEvent || ctx.redCardActive ? 14 : 5,
    cooldownKey: "next-goal",
    noveltyKey: `next-goal:${totalGoals}:${nextGoalDeadline}`,
  });

  if (minute < 40 && lane === "main") {
    out.push({
      ruleId: "half-level",
      lane,
      category: "scoreboard",
      question: `Is it level at half-time? (now ${line})`,
      options: [
        { key: "yes", label: "Level" },
        { key: "no", label: "Someone leads" },
      ],
      resolver: { kind: "half-level", endMinute: 45 },
      basePoints: 100,
      reason: "half-time level",
      urgency: 0.35,
      locksAtMinute: 44,
      resolutionDeadlineMinute: 46,
      priority: 2,
      cooldownKey: "half-level",
      noveltyKey: "half-level",
    });
  }

  // Low-priority variety (still deterministic — ranked last).
  out.push({
    ruleId: "next-event-goal-card",
    lane,
    category: "next-event",
    question: `What happens first — goal or card? (${line})`,
    options: [
      { key: "goal", label: "A goal" },
      { key: "card", label: "A card" },
    ],
    resolver: { kind: "next-event", map: { goal: "goal", card: "card" } },
    basePoints: 100,
    reason: "variety",
    urgency: 0.25,
    locksAtMinute: lock,
    resolutionDeadlineMinute: Math.min(minute + 12, 130),
    priority: 1,
    cooldownKey: "next-event",
    noveltyKey: `next-event:${minute}`,
  });

  return out;
}
