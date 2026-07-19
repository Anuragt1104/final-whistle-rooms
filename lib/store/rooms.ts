/**
 * Room store + live match engine (server-side, in-memory, per-process).
 *
 * Each room runs its own match. The engine has one processing core (`applyTick`)
 * fed by either:
 *   - the deterministic MatchSimulation in explicitly selected demo mode, or
 *   - the live TxLINE SSE feed in production, with confirmed source events and
 *     score-delta fallback reconciliation.
 * State changes are pushed to subscribers over SSE. State is intentionally
 * in-memory: perfect for a single-instance demo; production would back this
 * with Redis/Postgres (noted in the README).
 */
import {
  GamePhase,
  isLivePhase,
  type Fixture,
  type MatchEvent,
  type OddsSnapshot,
  type ScoreSnapshot,
} from "@/lib/txline/types";
import { MatchSimulation } from "@/lib/txline/simulation";
import { PulseInterpreter, type PulseCard, winChance, type WinChance } from "@/lib/engine/pulse";
import {
  generatePrompt,
  tryResolve,
  forceResolve,
  lockSnapshot,
  biasFromIntensity,
  isDefinitiveTerminalPhase,
  type MatchIntensity,
  type MatchStory,
  type SwingPrompt,
} from "@/lib/game/nextswing";
import { swingPoints, teamBonusForEvent, TEAM_BONUS } from "@/lib/game/scoring";
import { notifyGoal } from "@/lib/push/goals";
import { generateRecap } from "@/lib/recap/generate";
import { getSource, sourceMode } from "@/lib/txline/source";
import { buildMerkleTree } from "@/lib/util/merkle";
import { shareCode, uid } from "@/lib/util/id";
import {
  mintFromEvent,
  mintFanLore,
  partyDropMultiplier,
  sandwichFromWin,
  stampCalledIt,
} from "@/lib/cards/economy";
import type { MintContext, OddsSandwich } from "@/lib/cards/types";
import { llmConfigured } from "@/lib/llm/client";
import { rewritePromptText, type PromptContext } from "@/lib/game/prompt-writer";
import { EARN, earn as earnCredits } from "@/lib/platform/ledger";
import { addXp as addPassXp, XP as PASS_XP } from "@/lib/platform/pass";
import {
  getFixtureCoordinator,
  questionEngineMode,
  questionLlmMode,
  tickSignal,
  archiveFixtureTape,
  prefetchFanBuzz,
  frozenFanBuzz,
  persistQuestionInstance,
  persistQuestionAnswer,
  type EngineCommand,
  type QuestionSpec,
} from "@/lib/game/question-engine";
import type {
  ChatView,
  MemberView,
  MomentDropView,
  PromptView,
  RecapView,
  ReplayStateView,
  RoomModes,
  RoomKind,
  RoomStatus,
  RoomView,
  ScoreView,
} from "@/lib/store/types";
import type { HistoricalFeedHandle } from "@/lib/txline/historical";
import {
  SHOWCASE_REPLAY_BEATS,
  advanceShowcaseBeat,
  createShowcasePrompt,
  initialShowcaseReplayState,
  reachShowcaseBeat,
} from "@/lib/showcase/replay";

const TICK_MS = 1000;
const HALFTIME_PAUSE_MS = 5000;
const SHOWCASE_TOTAL_MINUTES = SHOWCASE_REPLAY_BEATS.at(-1)?.minute ?? 120;
const AVATARS = ["🦊", "🐯", "🦁", "🐼", "🐸", "🐵", "🦉", "🐙", "🦄", "🐲", "🐺", "🐨", "🦅", "🐝", "🦈", "🐳"];

function secondsPerMatchMinute(): number {
  const n = Number(process.env.SIM_SECONDS_PER_MATCH_MINUTE);
  return Number.isFinite(n) && n > 0 ? n : 2;
}

interface Member {
  id: string;
  name: string;
  avatar: string;
  walletPubkey?: string;
  side?: "home" | "away";
  points: number;
  streak: number;
  bestStreak: number;
  correct: number;
  isHost: boolean;
  joinedAt: number;
}

interface ChatMsg {
  id: string;
  memberId: string;
  text: string;
  kind: "chat" | "reaction" | "system";
  ts: number;
}

interface RoomRuntime {
  id: string;
  code: string;
  name: string;
  kind: RoomKind;
  autoManaged: boolean;
  fixture: Fixture;
  modes: RoomModes;
  visibility: "public" | "invite";
  reactionPack: string;
  voice: boolean;
  spoilerSafe: boolean;
  replay: boolean;
  hostId: string;
  status: RoomStatus;
  createdAt: number;
  revision: number;

  members: Map<string, Member>;
  chat: ChatMsg[];
  pulse: PulseCard[];
  momentDrops: MomentDropView[];
  prompts: Map<string, SwingPrompt>;
  picks: Map<string, Map<string, string>>; // memberId -> promptId -> optionKey
  // Significant match moments buffered as mint SOURCES. Nothing mints on the
  // event itself — a fan earns the Moment by answering a Micro-Play correctly.
  recentMintables: Array<{ event: MintContext["event"]; oddsSandwich: OddsSandwich; priorHomeProb: number }>;
  rewardedCalls: Set<string>;
  rewardedSourceEvents: Set<string>;

  // live match state
  score: ScoreSnapshot | null;
  odds: OddsSnapshot | null;
  win: WinChance;
  winHistory: number[];
  winSampleMinute: number;
  momentum: number;
  recaps: RecapView[];
  keyEvents: MatchEvent[];
  /** Buffered score snapshots for fixture_event_tapes archive. */
  tapeScores: ScoreSnapshot[];
  answerActions: Map<string, string>; // `${memberId}:${promptId}` -> actionId

  // engine internals
  interpreter: PulseInterpreter;
  sim: MatchSimulation | null;
  simMinute: number;
  prevProcessedInt: number;
  atHalftime: boolean;
  halftimeResumeAt: number;
  lastPromptMinute: number;
  htRecapDone: boolean;
  interval: ReturnType<typeof setInterval> | null;
  closeLiveFeed: (() => void) | null;
  replayHandle: HistoricalFeedHandle | null;
  replayState: ReplayStateView | null;
  showcase: {
    checkpoints: readonly number[];
    beat: number;
    awaitingAction: boolean;
  } | null;
  pendingFinish: ReturnType<typeof setTimeout> | null;
  liveScore: ScoreSnapshot | null;
  liveOdds: OddsSnapshot | null;
  eventHighWater: EventHighWater;
  processedEventIds: Set<string>;
  starting: boolean;
  lastFeedAt: number;
  lineupStatus: "unknown" | "announced";
  feedStaleTimer: ReturnType<typeof setTimeout> | null;

  // proof
  merkleLeaves: string[];
  anchored: boolean;
  anchorSignature?: string;

  subscribers: Set<(payload: string) => void>;
}

type Store = {
  rooms: Map<string, RoomRuntime>;
  officialByFixture: Map<string, string>;
  pendingOfficial: Map<string, Promise<void>>;
};
const g = globalThis as unknown as { __fwr_store?: Store };
const store: Store = g.__fwr_store ?? (g.__fwr_store = {
  rooms: new Map(),
  officialByFixture: new Map(),
  pendingOfficial: new Map(),
});
// Hot reload can retain an older store shape while this module is replaced.
store.officialByFixture ??= new Map();
store.pendingOfficial ??= new Map();

function emojiAvatar(name: string): string {
  let h = 0;
  for (let i = 0; i < name.length; i++) h = (h * 31 + name.charCodeAt(i)) >>> 0;
  return AVATARS[h % AVATARS.length];
}
function walletShort(pk?: string): string | undefined {
  if (!pk) return undefined;
  return `${pk.slice(0, 4)}…${pk.slice(-4)}`;
}

// ── creation / membership ────────────────────────────────────────────────────
/**
 * Join the one Official Match Hub for a Fixture — the single global room every
 * fan shares. Creation is guarded by a per-Fixture promise so concurrent first
 * joins cannot fork the crowd into duplicate rooms. Finished Fixtures run as a
 * shared replay (the historical driver paces the verified match log).
 */
export async function joinOfficialHubForFixture(
  fixture: Fixture,
  input: { name: string; walletPubkey?: string },
  options: {
    autoStart?: boolean;
    scopeKey?: string;
    roomKind?: RoomKind;
    visibility?: "public" | "invite";
    name?: string;
    replayState?: ReplayStateView;
    reuseFinished?: boolean;
    showcase?: RoomRuntime["showcase"];
  } = {},
): Promise<{ roomId: string; memberId: string }> {
  const scopeKey = options.scopeKey ?? fixture.id;
  const existingId = store.officialByFixture.get(scopeKey);
  const existing = existingId ? store.rooms.get(existingId) : undefined;
  if (existing && (existing.status !== "finished" || options.reuseFinished)) {
    const joined = joinRoom(existing.id, input);
    if ("error" in joined) throw new Error(joined.error);
    if (options.autoStart !== false) void startMatch(existing.id, "");
    return { roomId: existing.id, memberId: joined.memberId };
  }

  const pending = store.pendingOfficial.get(scopeKey);
  if (pending) {
    await pending;
    return joinOfficialHubForFixture(fixture, input, options);
  }

  let releaseCreation!: () => void;
  const creation = new Promise<void>((resolve) => {
    releaseCreation = resolve;
  });
  store.pendingOfficial.set(scopeKey, creation);
  try {
    const id = uid("hub");
    const rt: RoomRuntime = {
      id,
      code: shareCode(),
      name: options.name ?? `${fixture.home.name} vs ${fixture.away.name} · Official Match Hub`,
      kind: options.roomKind ?? "official",
      autoManaged: true,
      fixture,
      modes: { draft: true, nextSwing: true },
      visibility: options.visibility ?? "public",
      reactionPack: "classic",
      voice: false,
      spoilerSafe: false,
      replay: options.replayState != null,
      hostId: "",
      status: "lobby",
      createdAt: Date.now(),
      revision: 0,
      members: new Map(),
      chat: [],
      pulse: [],
      momentDrops: [],
      prompts: new Map(),
      picks: new Map(),
      recentMintables: [],
      rewardedCalls: new Set(),
      rewardedSourceEvents: new Set(),
      score: null,
      odds: null,
      win: { home: 33, draw: 34, away: 33 },
      winHistory: [],
      winSampleMinute: -1,
      momentum: 0,
      recaps: [],
      keyEvents: [],
      tapeScores: [],
      answerActions: new Map(),
      interpreter: new PulseInterpreter(fixture),
      sim: null,
      simMinute: 0,
      prevProcessedInt: 0,
      atHalftime: false,
      halftimeResumeAt: 0,
      lastPromptMinute: -99,
      htRecapDone: false,
      interval: null,
      closeLiveFeed: null,
      replayHandle: null,
      replayState: options.replayState ?? null,
      showcase: options.showcase ?? null,
      pendingFinish: null,
      liveScore: null,
      liveOdds: null,
      eventHighWater: {
        goals: { home: 0, away: 0 },
        yellow: { home: 0, away: 0 },
        red: { home: 0, away: 0 },
        corners: { home: 0, away: 0 },
      },
      processedEventIds: new Set(),
      starting: false,
      lastFeedAt: 0,
      lineupStatus: "unknown",
      feedStaleTimer: null,
      merkleLeaves: [],
      anchored: false,
      subscribers: new Set(),
    };
    store.rooms.set(id, rt);
    store.officialByFixture.set(scopeKey, id);
    try {
      const { getFixtureMatchData } = await import("@/lib/txline/intelligence-service");
      const match = await getFixtureMatchData(fixture.id);
      rt.lineupStatus = match?.lineupStatus === "confirmed" ? "announced" : "unknown";
    } catch {
      // The hub still opens; the app shows an honest unavailable lineup state.
    }
    const joined = joinRoom(id, input);
    if ("error" in joined) throw new Error(joined.error);
    const result = { roomId: id, memberId: joined.memberId };
    if (options.autoStart !== false) void startMatch(id, "");
    return result;
  } finally {
    releaseCreation();
    store.pendingOfficial.delete(scopeKey);
  }
}

/**
 * Create the presenter's private, guided replay. Unlike a public Official Hub,
 * the identity is part of the concurrency key: retries from the same fan reuse
 * one session, while unrelated judges cannot enter it without the invite code.
 */
export async function joinShowcaseReplayForFixture(
  fixture: Fixture,
  input: { name: string; walletPubkey?: string },
  options: { autoStart?: boolean; actionId?: string } = {},
): Promise<{ roomId: string; memberId: string }> {
  const fanKey = input.walletPubkey?.trim() || options.actionId?.trim() || input.name.trim().toLowerCase();
  const replayState = initialShowcaseReplayState();
  const joined = await joinOfficialHubForFixture(fixture, input, {
    // Showcase creation must not return a tappable Next Beat control while the
    // historical tape is still loading. Start it synchronously below.
    autoStart: false,
    scopeKey: `${fixture.id}:showcase:${fanKey}`,
    roomKind: "party",
    visibility: "invite",
    name: `${fixture.home.name} vs ${fixture.away.name} · Verified Replay`,
    replayState,
    reuseFinished: true,
    showcase: {
      checkpoints: SHOWCASE_REPLAY_BEATS.map((beat) => beat.minute),
      beat: 0,
      awaitingAction: true,
    },
  });
  if (options.autoStart !== false) await startMatch(joined.roomId, "");
  return joined;
}

export async function joinOfficialHub(
  fixtureId: string,
  input: { name: string; walletPubkey?: string },
): Promise<{ roomId: string; memberId: string } | { error: string }> {
  const fixture = await getSource().getFixture(fixtureId);
  if (!fixture) return { error: "Fixture not found" };
  try {
    return await joinOfficialHubForFixture(fixture, input);
  } catch (error) {
    return { error: error instanceof Error ? error.message : String(error) };
  }
}

export async function joinShowcaseReplay(
  fixtureId: string,
  input: { name: string; walletPubkey?: string; actionId?: string },
): Promise<{ roomId: string; memberId: string } | { error: string }> {
  const fixture = await getSource().getFixture(fixtureId);
  if (!fixture) return { error: "Fixture not found" };
  if (fixture.status !== "finished") return { error: "Showcase replay requires a finished fixture" };
  try {
    return await joinShowcaseReplayForFixture(
      fixture,
      { name: input.name, walletPubkey: input.walletPubkey },
      { actionId: input.actionId },
    );
  } catch (error) {
    return { error: error instanceof Error ? error.message : String(error) };
  }
}

export function getRoomRuntime(id: string): RoomRuntime | undefined {
  return store.rooms.get(id);
}

export function joinRoom(
  id: string,
  input: { name: string; walletPubkey?: string },
): { memberId: string } | { error: string } {
  const rt = store.rooms.get(id);
  if (!rt) return { error: "Room not found" };
  // Identity is the wallet key, not the device. Rejoining with the same key
  // returns the SAME member (keeps points/side) instead of minting a duplicate
  // — and two different keys can never collide on one slot.
  if (input.walletPubkey) {
    for (const m of rt.members.values()) {
      if (m.walletPubkey && m.walletPubkey === input.walletPubkey) {
        if (input.name && input.name !== m.name) {
          m.name = input.name;
          m.avatar = emojiAvatar(input.name);
        }
        broadcast(rt);
        return { memberId: m.id };
      }
    }
  }
  const memberId = uid("m");
  rt.members.set(memberId, {
    id: memberId,
    name: input.name || "Fan",
    avatar: emojiAvatar(input.name || memberId),
    walletPubkey: input.walletPubkey,
    points: 0,
    streak: 0,
    bestStreak: 0,
    correct: 0,
    isHost: false,
    joinedAt: Date.now(),
  });
  system(rt, `${input.name || "A fan"} joined the room`);
  broadcast(rt);
  return { memberId };
}

export function pickSide(id: string, memberId: string, side: "home" | "away"): boolean {
  const rt = store.rooms.get(id);
  const m = rt?.members.get(memberId);
  if (!rt || !m) return false;
  m.side = side;
  const team = side === "home" ? rt.fixture.home : rt.fixture.away;
  system(rt, `${m.name} drafted ${team.flag} ${team.name}`);
  broadcast(rt);
  return true;
}

export function postChat(
  id: string,
  memberId: string,
  text: string,
  kind: "chat" | "reaction" = "chat",
): boolean {
  const rt = store.rooms.get(id);
  const m = rt?.members.get(memberId);
  if (!rt || !m) return false;
  rt.chat.push({ id: uid("c"), memberId, text: text.slice(0, 240), kind, ts: Date.now() });
  if (rt.chat.length > 200) rt.chat = rt.chat.slice(-200);
  broadcast(rt);
  return true;
}

export function submitPrediction(
  id: string,
  memberId: string,
  promptId: string,
  optionKey: string,
  actionId?: string,
): { error?: string; ok?: boolean } {
  const rt = store.rooms.get(id);
  if (!rt) return { error: "Room not found" };
  const m = rt.members.get(memberId);
  if (!m) return { error: "Not a member" };
  const prompt = rt.prompts.get(promptId);
  if (!prompt) return { error: "Prompt not found" };
  if (prompt.status !== "open") return { error: "Prediction window closed" };
  if (!prompt.options.some((o) => o.key === optionKey)) return { error: "Invalid option" };
  const actionKey = `${memberId}:${promptId}`;
  if (actionId) {
    const prior = rt.answerActions.get(actionKey);
    if (prior && prior === actionId) return { ok: true }; // idempotent retry
    if (prior && prior !== actionId && rt.picks.get(memberId)?.has(promptId)) {
      return { error: "Already answered" };
    }
    rt.answerActions.set(actionKey, actionId);
  }
  let mp = rt.picks.get(memberId);
  if (!mp) {
    mp = new Map();
    rt.picks.set(memberId, mp);
  }
  mp.set(promptId, optionKey);
  const fanId = m.walletPubkey ?? m.id;
  void persistQuestionAnswer({
    questionId: promptId,
    fanId,
    optionKey,
    actionId,
    roomId: rt.id,
  });
  broadcast(rt);
  return { ok: true };
}

function system(rt: RoomRuntime, text: string) {
  rt.chat.push({ id: uid("c"), memberId: "system", text, kind: "system", ts: Date.now() });
  if (rt.chat.length > 200) rt.chat = rt.chat.slice(-200);
}

// ── engine: start / stop ─────────────────────────────────────────────────────
export async function startMatch(id: string, memberId: string): Promise<{ error?: string; ok?: boolean }> {
  const rt = store.rooms.get(id);
  if (!rt) return { error: "Room not found" };
  if (rt.kind === "party" && memberId !== rt.hostId) return { error: "Only the host can start the match" };
  if (rt.status === "live") return { ok: true };
  if (rt.closeLiveFeed) return { ok: true };
  if (rt.starting) return { ok: true };

  rt.starting = true;
  // start at -1 so the minute-0 kick-off event is included on the first tick
  rt.prevProcessedInt = -1;
  rt.simMinute = 0;
  try {
    if (sourceMode() === "live") {
      const { shouldReplayFixture } = await import("@/lib/txline/historical");
      if (shouldReplayFixture(rt.fixture)) {
        rt.status = "live";
        rt.replay = true;
        system(rt, "▶ REPLAY — pacing verified TxLINE match history.");
        await startHistoricalDriver(rt);
      } else {
        rt.status = "lobby";
        system(rt, "Official Match Hub open — waiting for verified kick-off.");
        await startLiveDriver(rt);
      }
    } else {
      rt.status = "live";
      system(rt, "Kick-off! The room is live.");
      rt.sim = new MatchSimulation(rt.fixture);
      rt.interval = setInterval(() => simTick(rt), TICK_MS);
    }
  } finally {
    rt.starting = false;
  }
  broadcast(rt);
  return { ok: true };
}

/** Simulation driver — advances the deterministic match clock. */
function simTick(rt: RoomRuntime) {
  if (rt.status !== "live" || !rt.sim) return;

  if (rt.atHalftime) {
    if (Date.now() >= rt.halftimeResumeAt) {
      rt.atHalftime = false;
      rt.simMinute = 45.001;
    } else {
      broadcast(rt); // keep the HT countdown feel alive
      return;
    }
  }

  rt.simMinute += (TICK_MS / 1000) / secondsPerMatchMinute();
  let currentInt = Math.floor(rt.simMinute);

  // stop the clock exactly on the half-time whistle
  if (rt.prevProcessedInt < 45 && currentInt >= 45) {
    currentInt = 45;
    rt.simMinute = 45;
  }
  if (currentInt >= 90) {
    currentInt = 90;
    rt.simMinute = 90;
  }

  const ts = new Date().toISOString();
  const newEvents = rt.sim.eventsBetween(rt.prevProcessedInt, currentInt, ts);
  const score = rt.sim.scoreSnapshot(currentInt, currentInt, ts);
  const odds = rt.sim.oddsSnapshot(currentInt, score, currentInt, ts);
  rt.prevProcessedInt = currentInt;

  applyTick(rt, score, odds, newEvents);

  if (newEvents.some((e) => e.kind === "half-time")) {
    rt.atHalftime = true;
    rt.halftimeResumeAt = Date.now() + HALFTIME_PAUSE_MS;
    void doRecap(rt, "half-time");
  }
  if (currentInt >= 90) {
    finishMatch(rt);
  }
}

/** Live driver — feeds TxLINE SSE snapshots through the same core. */
async function startLiveDriver(rt: RoomRuntime) {
  const { openLiveMatchFeed } = await import("@/lib/txline/live");
  rt.closeLiveFeed = await openLiveMatchFeed(rt.fixture, {
    onScore: (s, verifiedEvents = []) => {
      rt.lastFeedAt = Date.now();
      if (rt.feedStaleTimer) clearTimeout(rt.feedStaleTimer);
      rt.feedStaleTimer = null;
      const prev = rt.liveScore;
      // SSE reconnects can replay frames already processed. Sequence is the
      // authoritative ordering key; never let one regress room state/events.
      if (prev && s.seq <= prev.seq) return;
      if (s.running || isLivePhase(s.phase) || s.phase === GamePhase.Penalties) {
        if (rt.status === "lobby") {
          rt.status = "live";
          system(rt, "Kick-off verified — Live Calls are open.");
        }
        if (rt.pendingFinish) clearTimeout(rt.pendingFinish);
        rt.pendingFinish = null;
      }
      rt.liveScore = s;
      const fallback = prev ? diffScoreToEvents(rt.eventHighWater, s) : seedEventHighWater(rt, s);
      if (verifiedEvents.length) seedEventHighWater(rt, s);
      const events = verifiedEvents.length ? verifiedEvents : fallback;
      const odds = rt.liveOdds ?? rt.odds;
      applyTick(rt, s, odds, events);
      if (s.phase === GamePhase.HalfTime && !rt.htRecapDone) void doRecap(rt, "half-time");
      if (s.phase === GamePhase.Finished || s.phase === GamePhase.Abandoned) {
        finishMatch(rt);
      } else if (s.phase === GamePhase.FullTime && !rt.pendingFinish) {
        // TxLINE can emit a regulation-time whistle before extra time. Keep the
        // room open long enough for ET/penalty frames to cancel this terminal.
        rt.pendingFinish = setTimeout(() => finishMatch(rt), 120_000);
      }
    },
    onOdds: (o) => {
      rt.liveOdds = o;
      if (rt.liveScore) applyTick(rt, rt.liveScore, o, []);
    },
    onError: (e) => {
      system(rt, `Live feed notice: ${String(e).slice(0, 80)}`);
      if (rt.feedStaleTimer) clearTimeout(rt.feedStaleTimer);
      rt.feedStaleTimer = setTimeout(() => {
        if (Date.now() - rt.lastFeedAt < 20_000) return;
        for (const prompt of rt.prompts.values()) {
          if (prompt.status !== "settled") settlePrompt(rt, prompt, "__void__");
        }
        system(rt, "Live Calls paused — waiting for a fresh verified feed.");
        broadcast(rt);
      }, 20_000);
    },
  });
}

/** Historical driver — paces TxLINE historical/updates log through applyTick. */
async function startHistoricalDriver(rt: RoomRuntime) {
  const { openHistoricalMatchFeed } = await import("@/lib/txline/historical");
  const handle = await openHistoricalMatchFeed(rt.fixture, {
    onScore: (s, verifiedEvents = []) => {
      rt.lastFeedAt = Date.now();
      const prev = rt.liveScore;
      rt.liveScore = s;
      const fallback = prev ? diffScoreToEvents(rt.eventHighWater, s) : seedEventHighWater(rt, s);
      if (verifiedEvents.length) seedEventHighWater(rt, s);
      const events = verifiedEvents.length ? verifiedEvents : fallback;
      const odds = rt.liveOdds ?? rt.odds;
      applyTick(rt, s, odds, events);
      if (s.phase === GamePhase.HalfTime && !rt.htRecapDone) void doRecap(rt, "half-time");
      // Only terminal-finish when the tape naturally ends (not mid-seek frames).
      if (
        !rt.replayState?.paused &&
        (s.phase === GamePhase.FullTime || s.phase === GamePhase.Finished)
      ) {
        /* finish deferred to onDone so seek to FT doesn't close the hub */
      }
    },
    onError: (e) => system(rt, `Replay notice: ${String(e).slice(0, 100)}`),
    onDone: () => {
      if (rt.status === "live") finishMatch(rt);
    },
    onStateChange: (state) => {
      let nextState: ReplayStateView = {
        active: state.active || rt.replay,
        paused: state.paused,
        currentMinute: state.currentMinute,
        totalMinutes: state.totalMinutes,
        speed: state.speed,
      };
      if (rt.showcase) {
        const prior = rt.replayState?.mode === "showcase"
          ? rt.replayState
          : initialShowcaseReplayState();
        nextState = {
          ...prior,
          active: state.active || rt.replay,
          paused: state.paused,
          currentMinute: state.currentMinute,
          totalMinutes: SHOWCASE_TOTAL_MINUTES,
          speed: state.speed,
          mode: "showcase",
          awaitingAction: rt.showcase.awaitingAction,
        };
        if (state.paused && !rt.showcase.awaitingAction) {
          const reached = reachShowcaseBeat(nextState, state.currentMinute);
          if ((reached.beat ?? 0) > rt.showcase.beat) {
            const reachedMinute = rt.showcase.checkpoints[rt.showcase.beat];
            rt.showcase.beat = reached.beat ?? rt.showcase.beat;
            rt.showcase.awaitingAction = reached.awaitingAction ?? false;
            nextState = reached;
            const prompt = createShowcasePrompt(rt.fixture, reachedMinute, rt.score?.seq ?? 0);
            if (prompt && !rt.prompts.has(prompt.id)) rt.prompts.set(prompt.id, prompt);
            if (reached.nextBeatMinute == null) rt.status = "finished";
          }
        }
      }
      rt.replayState = nextState;
      broadcast(rt);
    },
  });
  rt.replayHandle = handle;
  if (rt.showcase) {
    handle.pause();
    handle.seek(0);
    rt.replayState = {
      ...initialShowcaseReplayState(),
      totalMinutes: SHOWCASE_TOTAL_MINUTES,
    };
  } else {
    rt.replayState = {
      active: true,
      paused: false,
      currentMinute: handle.getState().currentMinute,
      totalMinutes: handle.getState().totalMinutes,
      speed: handle.getState().speed,
      mode: "standard",
    };
  }
  rt.closeLiveFeed = () => {
    handle.close();
    rt.replayHandle = null;
  };
}

export function controlReplay(
  id: string,
  body: { action: string; minute?: number; speed?: number },
): { error?: string; ok?: boolean; replayState?: ReplayStateView } {
  const rt = store.rooms.get(id);
  if (!rt) return { error: "Room not found" };
  if (!rt.replay || !rt.replayHandle) return { error: "Replay not active" };
  const h = rt.replayHandle;
  switch (body.action) {
    case "pause":
      h.pause();
      break;
    case "play":
      if (rt.showcase) return { error: "Use nextBeat for the guided replay" };
      h.play();
      break;
    case "speed":
      if (rt.showcase) return { error: "Showcase pacing is guided" };
      if (body.speed == null) return { error: "speed required" };
      h.setSpeed(Number(body.speed));
      break;
    case "seek":
      if (rt.showcase) return { error: "Seeking is disabled in the verified showcase" };
      if (body.minute == null) return { error: "minute required" };
      // Allow re-emitting verified events after seek.
      rt.processedEventIds.clear();
      rt.eventHighWater = {
        goals: { home: 0, away: 0 },
        yellow: { home: 0, away: 0 },
        red: { home: 0, away: 0 },
        corners: { home: 0, away: 0 },
      };
      h.seek(Number(body.minute));
      break;
    case "nextBeat": {
      if (!rt.showcase || rt.replayState?.mode !== "showcase") {
        return { error: "Guided replay not active" };
      }
      if (!rt.showcase.awaitingAction) return { error: "Replay is already advancing" };
      const advance = advanceShowcaseBeat(rt.replayState);
      rt.replayState = advance.state;
      rt.showcase.awaitingAction = false;
      h.advanceTo(advance.targetMinute);
      break;
    }
    case "reset":
      if (rt.showcase) {
        rt.processedEventIds.clear();
        rt.eventHighWater = {
          goals: { home: 0, away: 0 },
          yellow: { home: 0, away: 0 },
          red: { home: 0, away: 0 },
          corners: { home: 0, away: 0 },
        };
        rt.score = null;
        rt.liveScore = null;
        rt.keyEvents = [];
        rt.pulse = [];
        for (const [promptId, prompt] of rt.prompts) {
          if (prompt.category === "showcase") rt.prompts.delete(promptId);
        }
        rt.showcase.beat = 0;
        rt.showcase.awaitingAction = true;
        h.seek(0);
        rt.replayState = {
          ...initialShowcaseReplayState(),
          totalMinutes: SHOWCASE_TOTAL_MINUTES,
        };
      } else {
        h.seek(0);
      }
      break;
    default:
      return { error: "Unknown action" };
  }
  const st = h.getState();
  rt.replayState = rt.showcase
    ? {
        ...(rt.replayState ?? initialShowcaseReplayState()),
        active: true,
        paused: st.paused,
        currentMinute: st.currentMinute,
        totalMinutes: SHOWCASE_TOTAL_MINUTES,
        speed: st.speed,
        mode: "showcase",
        beat: rt.showcase.beat,
        nextBeatMinute: rt.showcase.checkpoints[rt.showcase.beat],
        awaitingAction: rt.showcase.awaitingAction,
      }
    : {
        active: true,
        paused: st.paused,
        currentMinute: st.currentMinute,
        totalMinutes: st.totalMinutes,
        speed: st.speed,
        mode: "standard",
      };
  broadcast(rt);
  return { ok: true, replayState: rt.replayState };
}

/** Synthesize discrete events by diffing two live score snapshots. */
export type EventHighWater = Pick<ScoreSnapshot, "goals" | "yellow" | "red" | "corners">;

function seedEventHighWater(rt: RoomRuntime, score: ScoreSnapshot): MatchEvent[] {
  for (const stat of ["goals", "corners", "yellow", "red"] as const) {
    rt.eventHighWater[stat].home = Math.max(rt.eventHighWater[stat].home, score[stat].home);
    rt.eventHighWater[stat].away = Math.max(rt.eventHighWater[stat].away, score[stat].away);
  }
  return [];
}

/**
 * Convert cumulative score counters into events without reminting after an
 * upstream correction (for example yellow 2 → 1 → 2).
 */
export function diffScoreToEvents(highWater: EventHighWater, next: ScoreSnapshot): MatchEvent[] {
  const out: MatchEvent[] = [];
  let seq = next.seq * 100;
  const push = (kind: MatchEvent["kind"], side: "home" | "away", label: string) =>
    out.push({ fixtureId: next.fixtureId, seq: seq++, ts: next.ts, minute: next.minute, phase: next.phase, kind, side, label });
  for (const side of ["home", "away"] as const) {
    const dg = next.goals[side] - highWater.goals[side];
    for (let i = 0; i < dg; i++) push("goal", side, "Goal");
    const dc = next.corners[side] - highWater.corners[side];
    for (let i = 0; i < dc; i++) push("corner", side, "Corner");
    const dy = next.yellow[side] - highWater.yellow[side];
    for (let i = 0; i < dy; i++) push("yellow", side, "Yellow card");
    const dr = next.red[side] - highWater.red[side];
    for (let i = 0; i < dr; i++) push("red", side, "Red card");
  }
  for (const stat of ["goals", "corners", "yellow", "red"] as const) {
    highWater[stat].home = Math.max(highWater[stat].home, next[stat].home);
    highWater[stat].away = Math.max(highWater[stat].away, next[stat].away);
  }
  return out;
}

/** The one processing core both drivers share. */
function applyTick(rt: RoomRuntime, score: ScoreSnapshot, odds: OddsSnapshot | null, newEvents: MatchEvent[]) {
  rt.tapeScores ??= [];
  rt.answerActions ??= new Map();
  newEvents = newEvents.filter((event) => {
    const key = event.sourceEventId ?? `${event.seq}:${event.kind}:${event.side ?? "-"}`;
    if (rt.processedEventIds.has(key)) return false;
    rt.processedEventIds.add(key);
    return true;
  });
  const previousWin = rt.win;
  rt.score = score;
  rt.odds = odds;

  // 1) interpretation -> pulse cards + win + momentum
  const { cards, win } = rt.interpreter.ingest(newEvents, score, odds);
  rt.win = win;
  // sample the win-chance once per match-minute for the live timeline
  if (score.minute > rt.winSampleMinute) {
    rt.winHistory.push(win.home);
    rt.winSampleMinute = score.minute;
    if (rt.winHistory.length > 130) rt.winHistory.shift();
  }
  rt.momentum = rt.interpreter.momentum;
  if (cards.length) {
    rt.pulse.push(...cards);
    if (rt.pulse.length > 60) rt.pulse = rt.pulse.slice(-60);
  }

  // 2) merkle leaves + team bonuses + Moment mint
  const beforeWin = {
    home: previousWin.home / 100,
    draw: previousWin.draw / 100,
    away: previousWin.away / 100,
  };
  const afterWin = {
    home: win.home / 100,
    draw: win.draw / 100,
    away: win.away / 100,
  };
  for (const e of newEvents) {
    if (e.kind === "kickoff" || e.kind === "half-time" || e.kind === "full-time") {
      rt.merkleLeaves.push(`${e.seq}:${e.minute}:${e.kind}`);
      continue;
    }
    rt.merkleLeaves.push(
      `${e.seq}:${e.minute}:${e.kind}:${e.side ?? "-"}:${score.goals.home}-${score.goals.away}`,
    );
    if (e.kind === "goal" || e.kind === "red") rt.keyEvents.push(e);
    for (const m of rt.members.values()) {
      if (m.side) m.points += teamBonusForEvent(e, m.side);
    }

    // Card Economy (ADR-0001, skill-gated): significant events become mint
    // SOURCES. The Moment itself is earned in settlePrompt by a correct call.
    if (e.kind === "goal" || e.kind === "red" || e.kind === "yellow" || e.kind === "corner") {
      rt.recentMintables.push({
        event: {
          kind: e.kind,
          side: e.side,
          minute: e.minute,
          seq: e.seq,
          label: e.label || `${e.kind} — ${e.side ?? "?"}`,
          sourceEventId: e.sourceEventId,
          playerId: e.playerId,
          playerName: e.playerName,
          teamCode: e.teamCode,
          artKey: e.artKey,
        },
        oddsSandwich: sandwichFromWin(beforeWin, afterWin),
        priorHomeProb: beforeWin.home,
      });
      if (rt.recentMintables.length > 12) rt.recentMintables.shift();
    }
  }

  // 3) Live Calls — Question Engine V2 (on/shadow) or legacy NextSwing (off)
  if (rt.modes.nextSwing) {
    const major = newEvents.some((e) => e.kind === "goal" || e.kind === "red");
    const intensity = computeIntensity(rt, score, newEvents, cards);
    rt.tapeScores.push(score);
    if (rt.tapeScores.length > 4000) rt.tapeScores = rt.tapeScores.slice(-4000);

    const mode = questionEngineMode();
    if (rt.showcase) {
      // The presenter controls question placement. The curated prompts are
      // inserted only after each known-state checkpoint is reached, then use
      // the ordinary resolver/reward path against subsequent TxLINE frames.
      resolvePrompts(rt, newEvents, score, win);
    } else if (mode === "on" || mode === "shadow") {
      const cmds = runQuestionEngine(rt, score, win, newEvents, intensity, major);
      if (mode === "on") {
        applyEngineCommands(rt, cmds, intensity);
      } else {
        // Shadow: log metrics only; keep publishing via legacy path.
        for (const c of cmds) {
          if (c.type === "metric") {
            // eslint-disable-next-line no-console
            console.info(`[qe-shadow] ${rt.fixture.id} ${c.name}=${c.value}${c.detail ? ` ${c.detail}` : ""}`);
          }
        }
        maybeGeneratePrompt(rt, score, odds, win, intensity, major);
        resolvePrompts(rt, newEvents, score, win);
      }
    } else {
      maybeGeneratePrompt(rt, score, odds, win, intensity, major);
      resolvePrompts(rt, newEvents, score, win);
    }
  }

  // 4) Push goal alerts to every installed app (FCM topic). Skips cleanly when
  // FCM env is unset. Clients suppress the tray while actively viewing this room.
  for (const e of rt.replay ? [] : newEvents) {
    if (e.kind !== "goal" || !e.side) continue;
    const team = e.side === "away" ? rt.fixture.away : rt.fixture.home;
    void notifyGoal({
      roomId: rt.id,
      fixtureId: rt.fixture.id,
      roomName: rt.name,
      stage: rt.fixture.stage,
      homeName: rt.fixture.home.name,
      awayName: rt.fixture.away.name,
      homeGoals: score.goals.home,
      awayGoals: score.goals.away,
      minute: e.minute,
      teamName: team.name,
      scorer: e.playerName || team.name,
      side: e.side,
      sourceEventId: e.sourceEventId,
    });
  }

  broadcast(rt);
}

function computeIntensity(
  rt: RoomRuntime,
  score: ScoreSnapshot,
  newEvents: MatchEvent[],
  pulseCards: PulseCard[],
): MatchIntensity {
  const minute = score.minute;
  const goalTimes = rt.keyEvents
    .filter((e) => e.kind === "goal" && minute - e.minute <= 10)
    .map((e) => e.minute);
  const goalsLast10 = goalTimes.length;
  // Cards aren't always in keyEvents — count yellows/reds from this tick + pulse chaos
  const cardsThisTick = newEvents.filter((e) => e.kind === "yellow" || e.kind === "red").length;
  const chaosPulse = pulseCards.find((c) => c.challenge === "next-goal" || c.challenge === "corners");
  const scoreJustChanged = newEvents.some((e) => e.kind === "goal");
  const redActive = score.red.home + score.red.away > 0;
  const lastGoal = [...rt.keyEvents].reverse().find((e) => e.kind === "goal");
  // Comeback: equalizer or trailing side just scored
  let isComeback = false;
  if (scoreJustChanged && lastGoal?.side) {
    const scorerGoals = lastGoal.side === "home" ? score.goals.home : score.goals.away;
    const otherGoals = lastGoal.side === "home" ? score.goals.away : score.goals.home;
    if (scorerGoals === otherGoals && otherGoals > 0) isComeback = true;
    else if (scorerGoals === otherGoals + 1 && otherGoals >= 1) isComeback = true;
  }
  const flurrySummary =
    goalsLast10 >= 2
      ? `${goalsLast10} goals in ${Math.max(1, minute - Math.min(...goalTimes))} minutes`
      : undefined;
  return {
    goalsLast10Min: goalsLast10,
    cardsLast5Min: cardsThisTick + (chaosPulse?.challenge === "next-goal" ? 2 : 0),
    scoreJustChanged,
    isComeback,
    redCardActive: redActive || newEvents.some((e) => e.kind === "red"),
    momentumAbs: Math.abs(rt.momentum),
    flurrySummary,
    challenge: chaosPulse?.challenge,
  };
}

function recordMomentDrops(
  rt: RoomRuntime,
  recipients: { memberId: string; fanId: string }[],
  minted: { id: string; ownerId: string; kind: string; label: string; rarity: number; minute: number; matchLabel: string; createdAt: number; sourceEventId?: string; playerId?: string; playerName?: string; teamCode?: string; imageUrl?: string; artKey?: string; calledIt?: boolean }[],
  call?: { promptId: string; promptQuestion: string; answerLabel: string },
) {
  const proofRoot = rt.merkleLeaves.length ? buildMerkleTree(rt.merkleLeaves).root : undefined;
  for (const moment of minted) {
    const recipient = recipients.find((r) => r.fanId === moment.ownerId);
    if (!recipient) continue;
    rt.momentDrops.push({
      id: moment.id,
      memberId: recipient.memberId,
      kind: moment.kind,
      label: moment.label,
      rarity: moment.rarity,
      minute: moment.minute,
      matchLabel: moment.matchLabel,
      createdAt: moment.createdAt,
      sourceEventId: moment.sourceEventId,
      playerId: moment.playerId,
      playerName: moment.playerName,
      teamCode: moment.teamCode,
      imageUrl: moment.imageUrl,
      artKey: moment.artKey,
      calledIt: moment.calledIt,
      promptId: call?.promptId,
      promptQuestion: call?.promptQuestion,
      answerLabel: call?.answerLabel,
      proof: {
        root: proofRoot,
        sourceEventId: moment.sourceEventId,
        anchored: rt.anchored,
      },
    });
  }
  if (rt.momentDrops.length > 80) rt.momentDrops = rt.momentDrops.slice(-80);
}

function runQuestionEngine(
  rt: RoomRuntime,
  score: ScoreSnapshot,
  win: WinChance,
  newEvents: MatchEvent[],
  intensity: MatchIntensity,
  major: boolean,
): EngineCommand[] {
  const feedFreshness =
    rt.lastFeedAt === 0
      ? "waiting" as const
      : score.phase === GamePhase.CoveragePaused || score.phase === GamePhase.Cancelled
        ? "paused" as const
        : Date.now() - rt.lastFeedAt > 20_000
          ? "stale" as const
          : "fresh" as const;

  if (rt.atHalftime && !rt.htRecapDone) {
    prefetchFanBuzz(rt.fixture.id, "halftime");
  }
  if (rt.lineupStatus === "announced") {
    prefetchFanBuzz(rt.fixture.id, "lineup");
  }

  const lastGoal = [...rt.keyEvents].reverse().find((e) => e.kind === "goal");
  const coord = getFixtureCoordinator({
    fixtureId: rt.fixture.id,
    homeCode: rt.fixture.home.code,
    awayCode: rt.fixture.away.code,
    homeName: rt.fixture.home.name,
    awayName: rt.fixture.away.name,
  });
  return coord.advance(tickSignal(score, newEvents, feedFreshness), score, win, newEvents, {
    feedFreshness,
    majorEvent: major,
    goalsLast10Min: intensity.goalsLast10Min,
    cardsLast5Min: intensity.cardsLast5Min,
    redCardActive: intensity.redCardActive,
    isComeback: intensity.isComeback,
    flurrySummary: intensity.flurrySummary,
    lastScorer: lastGoal?.playerName ?? lastGoal?.label,
    lastGoalMinute: lastGoal?.minute,
    atHalftime: rt.atHalftime || score.phase === GamePhase.HalfTime,
    lineupConfirmed: rt.lineupStatus === "announced",
  });
}

function specToSwing(q: QuestionSpec): SwingPrompt {
  return {
    id: q.id,
    question: q.question,
    options: q.options,
    resolver: q.resolver,
    basePoints: q.basePoints,
    locksAtMinute: q.locksAtMinute,
    status: q.status === "void" || q.status === "corrected" ? "settled" : q.status === "scheduled" ? "open" : q.status,
    winningKey: q.winningKey,
    createdAt: q.createdAt,
    openedAtMinute: q.openedAtMinute,
    openedAtSeq: q.openedAtSeq,
    lockState: q.lockState,
    lane: q.lane,
    category: q.category,
    ruleId: q.ruleId,
    reason: q.reason,
    urgency: q.urgency,
    openedClockSec: q.openedClockSec,
    answerClosesAt: q.answerClosesAt,
    resolutionDeadlineClockSec: q.resolutionDeadlineClockSec,
    feedFreshness: q.feedFreshness,
    sourceAttribution: q.sourceAttribution,
    rewardPreview: q.rewardPreview,
    fanBuzzUrl: q.fanBuzzUrl,
    fanBuzzFact: q.fanBuzzFact,
  };
}

function applyEngineCommands(rt: RoomRuntime, cmds: EngineCommand[], intensity?: MatchIntensity) {
  for (const cmd of cmds) {
    switch (cmd.type) {
      case "open": {
        const buzz = frozenFanBuzz(rt.fixture.id);
        if (buzz && cmd.question.lane === "break") {
          cmd.question.fanBuzzUrl = buzz.url;
          cmd.question.fanBuzzFact = `${buzz.publisher}: ${buzz.fact}`;
          cmd.question.category = "fan-buzz";
          // Cap Fan Lore mint for room members answering break-deck calls later
          // is handled on first correct settle; pre-mint lore for hostless hubs
          // when editorial context is on.
          for (const m of rt.members.values()) {
            const lore = mintFanLore({
              fanId: m.walletPubkey ?? m.id,
              fixtureId: rt.fixture.id,
              matchLabel: `${rt.fixture.home.code} vs ${rt.fixture.away.code}`,
              fact: buzz.fact,
              publisherUrl: buzz.url,
              roomId: rt.id,
            });
            if (lore) {
              recordMomentDrops(rt, [{ memberId: m.id, fanId: lore.ownerId }], [lore]);
            }
          }
        }
        const prompt = specToSwing(cmd.question);
        rt.prompts.set(prompt.id, prompt);
        rt.lastPromptMinute = rt.score?.minute ?? rt.lastPromptMinute;
        void persistQuestionInstance(cmd.question);
        if (questionLlmMode() !== "off" && llmConfigured()) {
          void upgradePromptText(rt, prompt, intensity);
        }
        break;
      }
      case "lock": {
        const p = rt.prompts.get(cmd.questionId);
        if (p && p.status === "open") {
          p.status = "locked";
          p.lockState = cmd.lockState;
        }
        break;
      }
      case "settle": {
        const p = rt.prompts.get(cmd.questionId);
        if (p && p.status !== "settled") {
          settlePrompt(rt, p, cmd.winningKey);
          void persistQuestionInstance(swingToSpec(p, rt.fixture.id));
        }
        break;
      }
      case "void": {
        const p = rt.prompts.get(cmd.questionId);
        if (p && p.status !== "settled") {
          settlePrompt(rt, p, "__void__");
          void persistQuestionInstance(swingToSpec(p, rt.fixture.id));
        }
        break;
      }
      case "correct": {
        const p = rt.prompts.get(cmd.questionId);
        if (!p) break;
        p.winningKey = cmd.winningKey;
        p.status = "corrected";
        // Compensate newly-correct fans only — never claw back prior grants.
        for (const m of rt.members.values()) {
          const pick = rt.picks.get(m.id)?.get(p.id);
          if (pick !== cmd.winningKey) continue;
          const rewardKey = `${m.id}:${p.id}`;
          if (rt.rewardedCalls.has(rewardKey)) continue;
          rt.rewardedCalls.add(rewardKey);
          m.points += swingPoints(p.basePoints, m.streak);
          m.streak += 1;
          m.bestStreak = Math.max(m.bestStreak, m.streak);
          m.correct += 1;
          const fanId = m.walletPubkey ?? m.id;
          earnCredits(fanId, EARN.correctCall, "corrected call");
          addPassXp(fanId, PASS_XP.correctCall, "corrected call");
        }
        void persistQuestionInstance(swingToSpec(p, rt.fixture.id));
        break;
      }
      default:
        break;
    }
  }
}

function swingToSpec(p: SwingPrompt, fixtureId: string): QuestionSpec {
  return {
    id: p.id,
    fixtureId,
    ruleId: p.ruleId ?? "legacy",
    ruleVersion: 1,
    lane: p.lane ?? "main",
    category: (p.category as QuestionSpec["category"]) ?? "next-event",
    question: p.question,
    options: p.options,
    resolver: p.resolver,
    basePoints: p.basePoints,
    reason: p.reason ?? "",
    urgency: p.urgency ?? 0.5,
    openedClockSec: p.openedClockSec ?? 0,
    locksAtMinute: p.locksAtMinute,
    answerClosesAt: p.answerClosesAt,
    resolutionDeadlineClockSec: p.resolutionDeadlineClockSec ?? (p.locksAtMinute + 12) * 60,
    status: p.status === "settled" ? "settled" : p.status === "locked" ? "locked" : "open",
    winningKey: p.winningKey,
    createdAt: p.createdAt,
    openedAtMinute: p.openedAtMinute,
    openedAtSeq: p.openedAtSeq,
    lockState: p.lockState,
    feedFreshness: p.feedFreshness as QuestionSpec["feedFreshness"],
    sourceAttribution: p.sourceAttribution,
    rewardPreview: p.rewardPreview,
    fanBuzzUrl: p.fanBuzzUrl,
    fanBuzzFact: p.fanBuzzFact,
  };
}

function maybeGeneratePrompt(
  rt: RoomRuntime,
  score: ScoreSnapshot,
  odds: OddsSnapshot | null,
  win: WinChance,
  intensity?: MatchIntensity,
  majorEvent = false,
) {
  if (!isLivePhase(score.phase)) return;
  if (sourceMode() === "live" && Date.now() - rt.lastFeedAt > 20_000) return;
  if (score.minute >= 86 || rt.atHalftime) return;
  const live = [...rt.prompts.values()].filter((p) => p.status !== "settled");
  if (live.length >= 2) return;
  const bias = biasFromIntensity(intensity);
  // Major events (goal/red) or pulse challenges: 2' debounce; otherwise 4'
  const gap = majorEvent || bias ? 2 : 4;
  if (score.minute - rt.lastPromptMinute < gap) return;

  const lastGoal = [...rt.keyEvents].reverse().find((e) => e.kind === "goal");
  const story: MatchStory = {
    lastScorer: lastGoal?.playerName ?? lastGoal?.label,
    lastGoalMinute: lastGoal?.minute,
    goalsLast10Min: intensity?.goalsLast10Min,
    cardsLast5Min: intensity?.cardsLast5Min,
    scoreJustChanged: intensity?.scoreJustChanged,
    isComeback: intensity?.isComeback,
    redCardActive: intensity?.redCardActive,
    flurrySummary: intensity?.flurrySummary,
  };

  const prompt = generatePrompt(score, odds, win, Math.random, bias, story);
  if (prompt) {
    prompt.openedAtMinute = score.minute;
    prompt.openedAtSeq = score.seq;
    rt.prompts.set(prompt.id, prompt);
    rt.lastPromptMinute = score.minute;
    // Publish the template text instantly, then let the LLM rewrite it into a
    // moment-specific question. Fire-and-forget: a slow/failed call is a no-op.
    if (questionLlmMode() !== "off" && llmConfigured()) {
      void upgradePromptText(rt, prompt, intensity);
    }
  }
}

/** Rewrite an open prompt's question/labels via the LLM, in place. */
async function upgradePromptText(
  rt: RoomRuntime,
  prompt: SwingPrompt,
  intensity?: MatchIntensity,
) {
  try {
    const s = rt.score;
    const ctx: PromptContext = {
      minute: s?.minute ?? 0,
      phaseLabel: s?.statusNote ?? "Live",
      home: { name: rt.fixture.home.name, code: rt.fixture.home.code },
      away: { name: rt.fixture.away.name, code: rt.fixture.away.code },
      score: { home: s?.goals.home ?? 0, away: s?.goals.away ?? 0 },
      cards: {
        yellow: { home: s?.yellow.home ?? 0, away: s?.yellow.away ?? 0 },
        red: { home: s?.red.home ?? 0, away: s?.red.away ?? 0 },
      },
      corners: { home: s?.corners.home ?? 0, away: s?.corners.away ?? 0 },
      win: { home: rt.win.home, draw: rt.win.draw, away: rt.win.away },
      momentum: rt.momentum,
      recentEvents: rt.keyEvents
        .slice(-6)
        .map((e) => `${e.minute}' ${e.label}${e.playerName ? ` (${e.playerName})` : ""} — ${e.side === "away" ? rt.fixture.away.name : rt.fixture.home.name}`),
      narrative: rt.pulse.slice(-4).map((c) => c.headline).filter((h): h is string => !!h),
      intensity: intensity
        ? {
            goalsLast10Min: intensity.goalsLast10Min,
            cardsLast5Min: intensity.cardsLast5Min,
            scoreJustChanged: intensity.scoreJustChanged,
            isComeback: intensity.isComeback,
            redCardActive: intensity.redCardActive,
            momentumAbs: intensity.momentumAbs,
            flurrySummary: intensity.flurrySummary,
          }
        : undefined,
    };
    const res = await rewritePromptText(prompt, ctx);
    if (!res) return;
    // Never rewrite once locked/settled or after someone already answered.
    if (rt.prompts.get(prompt.id) !== prompt || prompt.status !== "open") return;
    for (const mp of rt.picks.values()) if (mp.has(prompt.id)) return;
    prompt.question = res.question;
    for (const o of prompt.options) o.label = res.labels.get(o.key) ?? o.label;
    broadcast(rt);
  } catch {
    /* keep the template text */
  }
}

function resolvePrompts(rt: RoomRuntime, newEvents: MatchEvent[], score: ScoreSnapshot, win: WinChance) {
  for (const prompt of rt.prompts.values()) {
    if (prompt.status === "settled") continue;
    if (prompt.status === "open" && score.minute >= prompt.locksAtMinute) {
      prompt.status = "locked";
      prompt.lockState = lockSnapshot(score); // freeze stats so we can resolve from deltas
    }
    if (prompt.status === "locked") {
      const key = tryResolve(prompt, newEvents, score, win);
      if (key) {
        settlePrompt(rt, prompt, key);
      } else if (
        score.minute >= prompt.locksAtMinute + 12 ||
        isDefinitiveTerminalPhase(score.phase)
      ) {
        // deadline reached with no live event — settle deterministically so a
        // correct call still scores instead of dangling forever
        settlePrompt(rt, prompt, forceResolve(prompt, score, win));
      }
    }
  }
}

function settlePrompt(rt: RoomRuntime, prompt: SwingPrompt, winningKey: string) {
  if (prompt.status === "settled") return;
  prompt.status = "settled";
  prompt.winningKey = winningKey;
  // nothing relevant happened in the window — close it out without scoring or
  // resetting anyone's streak (a fair "no result").
  if (winningKey === "__void__") {
    system(rt, "Live Call — no result that window, no points lost.");
    return;
  }
  const opt = prompt.options.find((o) => o.key === winningKey);
  let winners = 0;
  for (const m of rt.members.values()) {
    const pick = rt.picks.get(m.id)?.get(prompt.id);
    if (pick === undefined) continue;
    if (pick === winningKey) {
      const rewardKey = `${m.id}:${prompt.id}`;
      if (rt.rewardedCalls.has(rewardKey)) continue;
      rt.rewardedCalls.add(rewardKey);
      m.points += swingPoints(prompt.basePoints, m.streak);
      m.streak += 1;
      m.bestStreak = Math.max(m.bestStreak, m.streak);
      m.correct += 1;
      winners++;
      const fanId = m.walletPubkey ?? m.id;
      // platform loops: FC + World Cup Pass XP for skill (streaks pay extra)
      earnCredits(fanId, EARN.correctCall + (m.streak >= 3 ? EARN.streakBonus : 0), "correct call");
      addPassXp(fanId, PASS_XP.correctCall, "correct call");
      // Skill-gated Card Economy: a correct call EARNS the Moment + pack for
      // the moment the prompt covered (latest significant event, or a
      // market-swing fallback so a correct call always pays a card).
      const openedMinute = prompt.openedAtMinute ?? Math.max(0, prompt.locksAtMinute - 5);
      const openedSeq = prompt.openedAtSeq ?? 0;
      const src = [...rt.recentMintables].reverse().find(
        (candidate) => {
          if (candidate.event.minute < openedMinute || candidate.event.seq < openedSeq) return false;
          const eventKey = candidate.event.sourceEventId ?? `${rt.fixture.id}:${candidate.event.seq}`;
          return !rt.rewardedSourceEvents.has(`${m.id}:${eventKey}`);
        },
      ) ?? null;
      const flatWin = { home: rt.win.home / 100, draw: rt.win.draw / 100, away: rt.win.away / 100 };
      const minted = mintFromEvent({
        fixtureId: rt.fixture.id,
        matchLabel: `${rt.fixture.home.code} vs ${rt.fixture.away.code}`,
        roomId: rt.id,
        partyMultiplier: partyDropMultiplier(rt.members.size),
        fanId,
        event: src?.event ?? {
          kind: "market-swing",
          minute: rt.score?.minute ?? prompt.locksAtMinute,
          seq: rt.score?.seq ?? 0,
          label: `Called It — ${opt?.label ?? winningKey}`,
          sourceEventId: `call:${prompt.id}`,
        },
        oddsSandwich: src?.oddsSandwich ?? sandwichFromWin(flatWin, flatWin),
        priorHomeProb: src?.priorHomeProb ?? rt.win.home / 100,
      });
      // Called It → stamp related Moments + pack weight (ADR-0004)
      const stamped = stampCalledIt(fanId, {
        fixtureId: rt.fixture.id,
        sinceMinute: openedMinute,
      });
      if (minted) {
        if (src) {
          const eventKey = src.event.sourceEventId ?? `${rt.fixture.id}:${src.event.seq}`;
          rt.rewardedSourceEvents.add(`${m.id}:${eventKey}`);
        }
        recordMomentDrops(rt, [{ memberId: m.id, fanId }], [minted], {
          promptId: prompt.id,
          promptQuestion: prompt.question,
          answerLabel: opt?.label ?? winningKey,
        });
        earnCredits(fanId, EARN.momentMinted, "correct call moment");
        addPassXp(fanId, PASS_XP.momentMinted, "correct call moment");
        system(rt, `✦ ${m.name} earned a ${minted.rarity}★ Moment + pack — ${minted.label}`);
      } else if (stamped.length) {
        system(rt, `✓ ${m.name} Called It — ${stamped.length} Moment${stamped.length > 1 ? "s" : ""} sealed`);
      }
    } else {
      m.streak = 0;
    }
  }
  system(rt, `Live Call settled — ${opt?.label ?? winningKey}. ${winners} called it right.`);
}

function finishMatch(rt: RoomRuntime) {
  if (rt.status === "finished") return;
  rt.status = "finished";
  if (rt.interval) clearInterval(rt.interval);
  rt.interval = null;
  if (rt.pendingFinish) clearTimeout(rt.pendingFinish);
  rt.pendingFinish = null;
  if (rt.feedStaleTimer) clearTimeout(rt.feedStaleTimer);
  rt.feedStaleTimer = null;
  if (rt.closeLiveFeed) rt.closeLiveFeed();
  rt.closeLiveFeed = null;

  // settle any still-open prompts from the final score so correct calls score
  for (const p of rt.prompts.values()) {
    if (p.status === "settled") continue;
    settlePrompt(rt, p, rt.score ? forceResolve(p, rt.score, rt.win) : "__void__");
  }

  // lead-at-full-time team bonus
  const s = rt.score;
  if (s) {
    const lead = s.goals.home - s.goals.away;
    const winningSide = lead > 0 ? "home" : lead < 0 ? "away" : null;
    if (winningSide) {
      for (const m of rt.members.values()) {
        if (m.side === winningSide) m.points += TEAM_BONUS.leadAtFullTime;
      }
    }
  }
  void doRecap(rt, "full-time");
  void archiveFixtureTape({
    fixtureId: rt.fixture.id,
    kickoff: rt.fixture.kickoff,
    scores: rt.tapeScores ?? [],
    events: rt.keyEvents,
    archivedAt: Date.now(),
  });
  broadcast(rt);
}

async function doRecap(rt: RoomRuntime, scope: "half-time" | "full-time") {
  if (scope === "half-time") rt.htRecapDone = true;
  const s = rt.score;
  if (!s) return;
  const sorted = [...rt.members.values()].sort((a, b) => b.points - a.points);
  const leader = sorted[0];
  const runnerUp = sorted[1];
  const keyEvents = rt.keyEvents;
  const text = await generateRecap({
    scope,
    homeName: rt.fixture.home.name,
    homeCode: rt.fixture.home.code,
    awayName: rt.fixture.away.name,
    awayCode: rt.fixture.away.code,
    homeGoals: s.goals.home,
    awayGoals: s.goals.away,
    leader: leader && leader.points > 0 ? { name: leader.name, points: leader.points, streak: leader.streak, bestStreak: leader.bestStreak } : undefined,
    runnerUp: runnerUp && runnerUp.points > 0 ? { name: runnerUp.name, points: runnerUp.points } : undefined,
    keyEvents,
    momentum: rt.momentum,
  });
  rt.recaps.push({
    id: uid("recap"),
    scope,
    minute: s.minute,
    text,
    topMember: leader && leader.points > 0 ? leader.name : undefined,
    createdAt: Date.now(),
  });
  broadcast(rt);
}

// ── serialization ────────────────────────────────────────────────────────────
export function buildView(rt: RoomRuntime): RoomView {
  const members: MemberView[] = [...rt.members.values()]
    .map((m) => ({
      id: m.id,
      name: m.name,
      avatar: m.avatar,
      walletShort: walletShort(m.walletPubkey),
      side: m.side,
      points: m.points,
      streak: m.streak,
      bestStreak: m.bestStreak,
      correct: m.correct,
      isHost: m.isHost,
    }))
    .sort((a, b) => b.points - a.points || b.bestStreak - a.bestStreak || a.name.localeCompare(b.name));

  const chat: ChatView[] = rt.chat.slice(-60).map((c) => {
    const m = rt.members.get(c.memberId);
    return {
      id: c.id,
      memberId: c.memberId,
      name: c.kind === "system" ? "Room" : m?.name ?? "Fan",
      avatar: c.kind === "system" ? "📣" : m?.avatar ?? "👤",
      text: c.text,
      kind: c.kind,
      ts: c.ts,
    };
  });

  const prompts: PromptView[] = [...rt.prompts.values()]
    .sort((a, b) => b.createdAt - a.createdAt)
    .slice(0, 8)
    .map((p) => {
      const tally: Record<string, number> = {};
      for (const o of p.options) tally[o.key] = 0;
      for (const mp of rt.picks.values()) {
        const pick = mp.get(p.id);
        if (pick && tally[pick] !== undefined) tally[pick] += 1;
      }
      const settled =
        p.status === "settled" || p.status === "void" || p.status === "corrected";
      return {
        id: p.id,
        question: p.question,
        options: p.options,
        basePoints: p.basePoints,
        locksAtMinute: p.locksAtMinute,
        status: p.status === "scheduled" ? "open" : p.status,
        // Never expose winningKey before settle.
        winningKey: settled ? p.winningKey : undefined,
        tally,
        createdAt: p.createdAt,
        lane: p.lane,
        category: p.category,
        ruleId: p.ruleId,
        reason: p.reason,
        urgency: p.urgency,
        openedClockSec: p.openedClockSec,
        answerClosesAt: p.answerClosesAt,
        resolutionDeadlineClockSec: p.resolutionDeadlineClockSec,
        feedFreshness: p.feedFreshness,
        sourceAttribution: p.sourceAttribution,
        rewardPreview: p.rewardPreview,
        fanBuzzUrl: p.fanBuzzUrl,
        fanBuzzFact: p.fanBuzzFact,
      };
    });

  const score: ScoreView | null = rt.score
    ? {
        minute: rt.score.minute,
        clockSeconds: rt.score.clockSeconds,
        running: rt.score.running,
        phase: rt.score.phase,
        statusNote: rt.score.statusNote,
        goals: rt.score.goals,
        yellow: rt.score.yellow,
        red: rt.score.red,
        corners: rt.score.corners,
        periods: rt.score.periods,
      }
    : null;

  const root = rt.merkleLeaves.length > 0 ? buildMerkleTree(rt.merkleLeaves).root : null;

  const reactionTally: Record<string, number> = {};
  for (const c of rt.chat) {
    if (c.kind !== "reaction") continue;
    const key = c.text.trim() || "👏";
    reactionTally[key] = (reactionTally[key] ?? 0) + 1;
  }

  rt.revision = (rt.revision ?? 0) + 1;

  return {
    id: rt.id,
    code: rt.code,
    name: rt.name,
    kind: rt.kind,
    autoManaged: rt.autoManaged,
    fixture: rt.fixture,
    modes: rt.modes,
    hostId: rt.hostId,
    status: rt.status,
    lifecycle: rt.status === "finished" ? "finished" : rt.status === "live" ? "live" : "pregame",
    feedFreshness: rt.lastFeedAt === 0 ? "waiting" : Date.now() - rt.lastFeedAt <= 20_000 ? "fresh" : "stale",
    lineupStatus: rt.lineupStatus,
    sourceUpdatedAt: rt.score?.updatedAt,
    revision: rt.revision,
    reactionTally,
    momentum: rt.momentum,
    win: rt.win,
    winHistory: [...rt.winHistory],
    score,
    markets: rt.odds?.markets ?? [],
    members,
    chat,
    pulse: rt.pulse.slice(-40),
    momentDrops: rt.momentDrops.slice(-40),
    prompts,
    recaps: rt.recaps,
    proof: {
      leafCount: rt.merkleLeaves.length,
      root,
      anchored: rt.anchored,
      anchorSignature: rt.anchorSignature,
      cluster: process.env.NEXT_PUBLIC_SOLANA_CLUSTER ?? "devnet",
    },
    spoilerSafe: rt.spoilerSafe,
    voice: rt.voice,
    reactionPack: rt.reactionPack,
    replay: rt.replay,
    replayState: rt.replay
      ? rt.replayState ?? {
          active: true,
          paused: false,
          currentMinute: rt.score?.minute ?? 0,
          totalMinutes: 90,
          speed: 1,
        }
      : undefined,
    createdAt: rt.createdAt,
  };
}

export interface RoomSummary {
  id: string;
  code: string;
  name: string;
  kind: RoomKind;
  fixture: Fixture;
  status: RoomStatus;
  memberCount: number;
  modes: RoomModes;
  createdAt: number;
  score: ScoreView | null;
}

export function listRooms(): RoomSummary[] {
  return [...store.rooms.values()]
    .filter((rt) => rt.visibility === "public")
    .map((rt) => ({
      id: rt.id,
      code: rt.code,
      name: rt.name,
      kind: rt.kind,
      fixture: rt.fixture,
      status: rt.status,
      memberCount: rt.members.size,
      modes: rt.modes,
      createdAt: rt.createdAt,
      score: rt.score
        ? {
            minute: rt.score.minute,
            clockSeconds: rt.score.clockSeconds,
            running: rt.score.running,
            phase: rt.score.phase,
            goals: rt.score.goals,
            yellow: rt.score.yellow,
            red: rt.score.red,
            corners: rt.score.corners,
          }
        : null,
    }))
    .sort((a, b) => b.createdAt - a.createdAt);
}

// ── SSE plumbing ─────────────────────────────────────────────────────────────
export function subscribe(id: string, send: (payload: string) => void): (() => void) | null {
  const rt = store.rooms.get(id);
  if (!rt) return null;
  rt.subscribers.add(send);
  const room = buildView(rt);
  send(JSON.stringify({ type: "state", revision: room.revision, room }));
  return () => rt.subscribers.delete(send);
}

function broadcast(rt: RoomRuntime) {
  if (rt.subscribers.size === 0) return;
  const room = buildView(rt);
  const payload = JSON.stringify({ type: "state", revision: room.revision, room });
  for (const send of rt.subscribers) {
    try {
      send(payload);
    } catch {
      /* dropped client */
    }
  }
}

export function setAnchor(id: string, signature: string) {
  const rt = store.rooms.get(id);
  if (!rt) return;
  rt.anchored = true;
  rt.anchorSignature = signature;
  system(rt, "Room proof anchored on Solana");
  broadcast(rt);
}

export function getProofData(id: string): { leaves: string[]; root: string } | null {
  const rt = store.rooms.get(id);
  if (!rt) return null;
  const tree = buildMerkleTree(rt.merkleLeaves);
  return { leaves: rt.merkleLeaves, root: tree.root };
}

export function __settlePromptForTests(rt: RoomRuntime, prompt: SwingPrompt, winningKey: string) {
  settlePrompt(rt, prompt, winningKey);
}

export function __resetRoomsForTests() {
  for (const room of store.rooms.values()) {
    if (room.interval) clearInterval(room.interval);
    if (room.pendingFinish) clearTimeout(room.pendingFinish);
    room.closeLiveFeed?.();
  }
  store.rooms.clear();
  store.officialByFixture.clear();
  store.pendingOfficial.clear();
}
