/**
 * FixtureQuestionCoordinator — one per fixture.
 * advance(signal) order (locked):
 *   reject dup/regressive → reconcile → lock closed windows → settle/void →
 *   detect opportunities → generate/validate/rank/open → emit atomic commands.
 */
import { GamePhase } from "@/lib/txline/types";
import type { MatchEvent, ScoreSnapshot } from "@/lib/txline/types";
import type { WinChance } from "@/lib/engine/pulse";
import { canGenerate, preferredLane, slotsToOpen } from "./cadence";
import { questionId } from "./ids";
import { detectCandidates } from "./rules/catalog";
import {
  forceResolveQuestion,
  lockSnapshot,
  pastResolutionDeadline,
  resolveQuestion,
} from "./resolvers";
import { rankCandidates } from "./score";
import type { FootballSignal } from "./signals";
import { freshnessFrom } from "./signals";
import {
  ENGINE_VERSION,
  RULE_VERSION,
  type CoordinatorSnapshot,
  type EngineCommand,
  type HistorySnapshot,
  type MatchContext,
  type QuestionSpec,
} from "./types";

export interface CoordinatorOptions {
  fixtureId: string;
  homeCode: string;
  awayCode: string;
  homeName: string;
  awayName: string;
  history?: HistorySnapshot | null;
}

export class FixtureQuestionCoordinator {
  readonly fixtureId: string;
  readonly homeCode: string;
  readonly awayCode: string;
  readonly homeName: string;
  readonly awayName: string;
  history: HistorySnapshot | null;

  private questions = new Map<string, QuestionSpec>();
  private openSeq = 0;
  private lastOpenClockSec = 0;
  private cooldownUntil: Record<string, number> = {};
  private lastSeq = -1;
  private recentNovelty = new Set<string>();
  private onPitch = new Set<string>();
  private lineupConfirmed = false;
  private waterBreakActive = false;
  private atHalftime = false;
  private unreliableSecondary = false;
  private emptyIntervals = 0;
  private voidCount = 0;
  private settleCount = 0;
  private lastEvalMs = 0;

  constructor(opts: CoordinatorOptions) {
    this.fixtureId = opts.fixtureId;
    this.homeCode = opts.homeCode;
    this.awayCode = opts.awayCode;
    this.homeName = opts.homeName;
    this.awayName = opts.awayName;
    this.history = opts.history ?? null;
  }

  snapshot(): CoordinatorSnapshot {
    const settled = this.settleCount + this.voidCount;
    return {
      fixtureId: this.fixtureId,
      openSeq: this.openSeq,
      questions: [...this.questions.values()],
      lastOpenClockSec: this.lastOpenClockSec,
      cooldownUntil: { ...this.cooldownUntil },
      metrics: {
        evalMs: this.lastEvalMs,
        emptyIntervals: this.emptyIntervals,
        voidRate: settled > 0 ? this.voidCount / settled : 0,
      },
    };
  }

  /** Submit is room-scoped — coordinator only validates option keys. */
  submit(questionId: string, optionKey: string): { ok: boolean; error?: string } {
    const q = this.questions.get(questionId);
    if (!q) return { ok: false, error: "unknown question" };
    if (q.status !== "open") return { ok: false, error: "question not open" };
    if (!q.options.some((o) => o.key === optionKey)) return { ok: false, error: "bad option" };
    return { ok: true };
  }

  advance(
    signal: FootballSignal,
    score: ScoreSnapshot,
    win: WinChance,
    events: MatchEvent[] = [],
    extras?: Partial<MatchContext>,
  ): EngineCommand[] {
    const t0 = performance.now?.() ?? Date.now();
    const commands: EngineCommand[] = [];

    // 1) reject dup / regressive score ticks
    if (signal.kind === "tick" || signal.kind === "score") {
      const seq = signal.seq;
      if (seq < this.lastSeq) {
        this.lastEvalMs = (performance.now?.() ?? Date.now()) - t0;
        return [{ type: "metric", name: "regressive_reject", value: 1 }];
      }
      this.lastSeq = seq;
    }

    // 2) reconcile signal side-effects
    this.reconcileSignal(signal);

    const feedFreshness =
      extras?.feedFreshness ??
      (signal.kind === "tick"
        ? signal.feedFreshness
        : freshnessFrom(score.updatedAt, Date.now(), score.phase));

    const ctx: MatchContext = {
      fixtureId: this.fixtureId,
      homeCode: this.homeCode,
      awayCode: this.awayCode,
      homeName: this.homeName,
      awayName: this.awayName,
      score,
      win,
      feedFreshness,
      coverageSecondary: !this.unreliableSecondary && (score.coverageSecondary !== false),
      lineupConfirmed: this.lineupConfirmed,
      onPitchPlayerIds: this.onPitch,
      history: this.history,
      majorEvent: extras?.majorEvent ?? events.some((e) => e.kind === "goal" || e.kind === "red"),
      goalsLast10Min: extras?.goalsLast10Min,
      cardsLast5Min: extras?.cardsLast5Min,
      redCardActive: extras?.redCardActive ?? score.red.home + score.red.away > 0,
      isComeback: extras?.isComeback,
      flurrySummary: extras?.flurrySummary,
      lastScorer: extras?.lastScorer,
      lastGoalMinute: extras?.lastGoalMinute,
      atHalftime: extras?.atHalftime ?? (this.atHalftime || score.phase === GamePhase.HalfTime),
      waterBreakActive: extras?.waterBreakActive ?? this.waterBreakActive,
      clockSec: score.clockSeconds,
      phase: score.phase,
    };

    // Pause generation on coverage issues
    if (
      score.phase === GamePhase.CoveragePaused ||
      score.phase === GamePhase.Cancelled ||
      feedFreshness === "paused"
    ) {
      for (const q of this.questions.values()) {
        if (q.status === "open" || q.status === "locked") {
          q.status = "void";
          q.winningKey = "__void__";
          this.voidCount++;
          commands.push({ type: "void", questionId: q.id, reason: "coverage_paused" });
        }
      }
      this.lastEvalMs = (performance.now?.() ?? Date.now()) - t0;
      commands.push({ type: "metric", name: "eval_ms", value: this.lastEvalMs });
      return commands;
    }

    // 3) lock closed windows
    for (const q of this.questions.values()) {
      if (q.status === "open" && score.minute >= q.locksAtMinute) {
        q.status = "locked";
        q.lockState = lockSnapshot(score);
        commands.push({ type: "lock", questionId: q.id, lockState: q.lockState });
      }
    }

    // 4) settle / void
    const terminal =
      score.phase === GamePhase.Finished || score.phase === GamePhase.Abandoned;

    for (const q of this.questions.values()) {
      if (q.status !== "locked") continue;
      const key = resolveQuestion(q, events, score, win);
      if (key) {
        q.status = "settled";
        q.winningKey = key;
        if (key === "__void__") this.voidCount++;
        else this.settleCount++;
        commands.push({ type: "settle", questionId: q.id, winningKey: key });
        continue;
      }
      if (pastResolutionDeadline(q, score.clockSeconds, terminal)) {
        const forced = forceResolveQuestion(q, score, win);
        q.status = forced === "__void__" ? "void" : "settled";
        q.winningKey = forced;
        if (forced === "__void__") this.voidCount++;
        else this.settleCount++;
        commands.push(
          forced === "__void__"
            ? { type: "void", questionId: q.id, reason: "deadline" }
            : { type: "settle", questionId: q.id, winningKey: forced },
        );
      }
    }

    // Handle discard of evidence after settle → mark corrected (no clawback here;
    // rooms compensate newly-correct fans).
    if (signal.kind === "discard" || signal.kind === "amend") {
      // Future: re-evaluate linked questions. For now emit metric only.
      commands.push({ type: "metric", name: "ledger_mutation", value: 1, detail: signal.kind });
    }

    // 5–6) detect → generate / validate / rank / open
    const active = [...this.questions.values()];
    if (canGenerate(ctx, active, this.lastOpenClockSec)) {
      const slots = slotsToOpen(ctx, active);
      if (slots <= 0) {
        this.emptyIntervals++;
      } else {
        let opened = 0;
        for (let i = 0; i < slots; i++) {
          const lane = preferredLane(ctx, [...this.questions.values()]);
          const candidates = detectCandidates(ctx, lane).filter((c) => {
            const until = this.cooldownUntil[c.cooldownKey] ?? 0;
            return score.clockSeconds >= until;
          });
          const ranked = rankCandidates(
            candidates,
            ctx,
            this.recentNovelty,
            `${this.fixtureId}:${this.openSeq}:${score.seq}`,
          );
          const pick = ranked[0];
          if (!pick) {
            this.emptyIntervals++;
            break;
          }
          this.openSeq += 1;
          const id = questionId(this.fixtureId, pick.ruleId, this.openSeq, opened);
          const spec: QuestionSpec = {
            id,
            fixtureId: this.fixtureId,
            ruleId: pick.ruleId,
            ruleVersion: RULE_VERSION,
            lane: pick.lane,
            category: pick.category,
            question: pick.question,
            options: pick.options,
            resolver: pick.resolver,
            basePoints: pick.basePoints,
            reason: pick.reason,
            urgency: pick.urgency,
            openedClockSec: score.clockSeconds,
            locksAtMinute: pick.locksAtMinute,
            answerClosesAt: Date.now() + Math.max(30, (pick.locksAtMinute - score.minute) * 60) * 1000,
            resolutionDeadlineClockSec: pick.resolutionDeadlineMinute * 60,
            status: "open",
            createdAt: Date.now(),
            openedAtMinute: score.minute,
            openedAtSeq: score.seq,
            feedFreshness,
            sourceAttribution: `txline:${ENGINE_VERSION}`,
            rewardPreview: `+${pick.basePoints} · Moment on settle`,
          };
          this.questions.set(id, spec);
          this.lastOpenClockSec = score.clockSeconds;
          this.cooldownUntil[pick.cooldownKey] = score.clockSeconds + 180;
          this.recentNovelty.add(pick.noveltyKey);
          if (this.recentNovelty.size > 40) {
            const first = this.recentNovelty.values().next().value;
            if (first) this.recentNovelty.delete(first);
          }
          commands.push({ type: "open", question: spec });
          opened++;
        }
      }
    }

    this.lastEvalMs = (performance.now?.() ?? Date.now()) - t0;
    commands.push({ type: "metric", name: "eval_ms", value: this.lastEvalMs });
    return commands;
  }

  private reconcileSignal(signal: FootballSignal) {
    switch (signal.kind) {
      case "water-break":
        this.waterBreakActive = signal.active;
        break;
      case "lineups":
        this.lineupConfirmed = signal.confirmed;
        this.onPitch = new Set(signal.onPitchIds);
        break;
      case "reliability":
        if (signal.level === "unreliable_secondary" || signal.level === "coverage_paused") {
          this.unreliableSecondary = true;
        }
        break;
      case "status":
        this.atHalftime = signal.phase === GamePhase.HalfTime;
        if (signal.phase === GamePhase.SecondHalf || signal.phase === GamePhase.FirstHalf) {
          this.waterBreakActive = false;
          this.atHalftime = false;
        }
        break;
      case "tick":
        this.atHalftime = signal.score.phase === GamePhase.HalfTime;
        break;
      case "substitution":
        if (signal.playerOutId) this.onPitch.delete(signal.playerOutId);
        if (signal.playerInId) this.onPitch.add(signal.playerInId);
        break;
      default:
        break;
    }
  }
}

/** Shared coordinators keyed by fixture (Official Hub + parties share Live Calls). */
const coordinators = new Map<string, FixtureQuestionCoordinator>();

export function getFixtureCoordinator(opts: CoordinatorOptions): FixtureQuestionCoordinator {
  let c = coordinators.get(opts.fixtureId);
  if (!c) {
    c = new FixtureQuestionCoordinator(opts);
    coordinators.set(opts.fixtureId, c);
  }
  return c;
}

export function resetFixtureCoordinator(fixtureId: string) {
  coordinators.delete(fixtureId);
}

/** Test helper — wipe all coordinators. */
export function resetAllCoordinators() {
  coordinators.clear();
}
