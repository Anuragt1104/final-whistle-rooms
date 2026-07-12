/**
 * Room store + live match engine (server-side, in-memory, per-process).
 *
 * Each room runs its own match. The engine has one processing core (`applyTick`)
 * fed by either:
 *   - the deterministic MatchSimulation (default / demo), or
 *   - the live TxLINE SSE feed (TXLINE_MODE=live), with events synthesized by
 *     diffing successive score snapshots.
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
import { generatePrompt, tryResolve, forceResolve, lockSnapshot, type SwingPrompt } from "@/lib/game/nextswing";
import { swingPoints, teamBonusForEvent, TEAM_BONUS } from "@/lib/game/scoring";
import { generateRecap } from "@/lib/recap/generate";
import { getSource, sourceMode } from "@/lib/txline/source";
import { buildMerkleTree } from "@/lib/util/merkle";
import { shareCode, uid } from "@/lib/util/id";
import {
  mintForRoomFans,
  partyDropMultiplier,
  sandwichFromWin,
  stampCalledIt,
} from "@/lib/cards/economy";
import type {
  ChatView,
  MemberView,
  PromptView,
  RecapView,
  RoomModes,
  RoomStatus,
  RoomView,
  ScoreView,
} from "@/lib/store/types";

const TICK_MS = 1000;
const HALFTIME_PAUSE_MS = 5000;
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
  fixture: Fixture;
  modes: RoomModes;
  visibility: "public" | "invite";
  reactionPack: string;
  voice: boolean;
  spoilerSafe: boolean;
  hostId: string;
  status: RoomStatus;
  createdAt: number;

  members: Map<string, Member>;
  chat: ChatMsg[];
  pulse: PulseCard[];
  prompts: Map<string, SwingPrompt>;
  picks: Map<string, Map<string, string>>; // memberId -> promptId -> optionKey

  // live match state
  score: ScoreSnapshot | null;
  odds: OddsSnapshot | null;
  win: WinChance;
  winHistory: number[];
  winSampleMinute: number;
  momentum: number;
  recaps: RecapView[];
  keyEvents: MatchEvent[];

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
  liveScore: ScoreSnapshot | null;
  liveOdds: OddsSnapshot | null;

  // proof
  merkleLeaves: string[];
  anchored: boolean;
  anchorSignature?: string;

  subscribers: Set<(payload: string) => void>;
}

type Store = { rooms: Map<string, RoomRuntime> };
const g = globalThis as unknown as { __fwr_store?: Store };
const store: Store = g.__fwr_store ?? (g.__fwr_store = { rooms: new Map() });

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
export async function createRoom(input: {
  name: string;
  fixtureId: string;
  modes: RoomModes;
  hostName: string;
  hostWallet?: string;
  visibility?: "public" | "invite";
  reactionPack?: string;
  voice?: boolean;
  spoilerSafe?: boolean;
}): Promise<{ roomId: string; hostId: string } | { error: string }> {
  const fixture = await getSource().getFixture(input.fixtureId);
  if (!fixture) return { error: "Fixture not found" };

  const id = uid("room");
  const hostId = uid("m");
  const host: Member = {
    id: hostId,
    name: input.hostName || "Host",
    avatar: emojiAvatar(input.hostName || "Host"),
    walletPubkey: input.hostWallet,
    points: 0,
    streak: 0,
    bestStreak: 0,
    correct: 0,
    isHost: true,
    joinedAt: Date.now(),
  };

  const rt: RoomRuntime = {
    id,
    code: shareCode(),
    name: input.name || `${fixture.home.name} watch party`,
    fixture,
    modes: input.modes,
    visibility: input.visibility ?? "public",
    reactionPack: input.reactionPack ?? "classic",
    voice: input.voice ?? false,
    spoilerSafe: input.spoilerSafe ?? false,
    hostId,
    status: "lobby",
    createdAt: Date.now(),
    members: new Map([[hostId, host]]),
    chat: [],
    pulse: [],
    prompts: new Map(),
    picks: new Map(),
    score: null,
    odds: null,
    win: { home: 33, draw: 34, away: 33 },
    winHistory: [],
    winSampleMinute: -1,
    momentum: 0,
    recaps: [],
    keyEvents: [],
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
    liveScore: null,
    liveOdds: null,
    merkleLeaves: [],
    anchored: false,
    subscribers: new Set(),
  };
  store.rooms.set(id, rt);
  return { roomId: id, hostId };
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
): { error?: string; ok?: boolean } {
  const rt = store.rooms.get(id);
  if (!rt) return { error: "Room not found" };
  const m = rt.members.get(memberId);
  if (!m) return { error: "Not a member" };
  const prompt = rt.prompts.get(promptId);
  if (!prompt) return { error: "Prompt not found" };
  if (prompt.status !== "open") return { error: "Prediction window closed" };
  if (!prompt.options.some((o) => o.key === optionKey)) return { error: "Invalid option" };
  let mp = rt.picks.get(memberId);
  if (!mp) {
    mp = new Map();
    rt.picks.set(memberId, mp);
  }
  mp.set(promptId, optionKey);
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
  if (memberId !== rt.hostId) return { error: "Only the host can start the match" };
  if (rt.status === "live") return { ok: true };

  rt.status = "live";
  // start at -1 so the minute-0 kick-off event is included on the first tick
  rt.prevProcessedInt = -1;
  rt.simMinute = 0;
  system(rt, "Kick-off! The room is live.");

  if (sourceMode() === "live") {
    const { shouldReplayFixture } = await import("@/lib/txline/historical");
    if (shouldReplayFixture(rt.fixture)) {
      system(rt, "▶ REPLAY — pacing verified TxLINE match history.");
      await startHistoricalDriver(rt);
    } else {
      await startLiveDriver(rt);
    }
  } else {
    rt.sim = new MatchSimulation(rt.fixture);
    rt.interval = setInterval(() => simTick(rt), TICK_MS);
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
    onScore: (s) => {
      const prev = rt.liveScore;
      rt.liveScore = s;
      const events = prev ? diffToEvents(prev, s) : [];
      const odds = rt.liveOdds ?? rt.odds;
      applyTick(rt, s, odds, events);
      if (s.phase === GamePhase.HalfTime && !rt.htRecapDone) void doRecap(rt, "half-time");
      if (s.phase === GamePhase.FullTime || s.phase === GamePhase.Finished) finishMatch(rt);
    },
    onOdds: (o) => {
      rt.liveOdds = o;
      if (rt.liveScore) applyTick(rt, rt.liveScore, o, []);
    },
    onError: (e) => system(rt, `Live feed notice: ${String(e).slice(0, 80)}`),
  });
}

/** Historical driver — paces TxLINE historical/updates log through applyTick. */
async function startHistoricalDriver(rt: RoomRuntime) {
  const { openHistoricalMatchFeed } = await import("@/lib/txline/historical");
  rt.closeLiveFeed = await openHistoricalMatchFeed(rt.fixture, {
    onScore: (s) => {
      const prev = rt.liveScore;
      rt.liveScore = s;
      const events = prev ? diffToEvents(prev, s) : [];
      const odds = rt.liveOdds ?? rt.odds;
      applyTick(rt, s, odds, events);
      if (s.phase === GamePhase.HalfTime && !rt.htRecapDone) void doRecap(rt, "half-time");
      if (s.phase === GamePhase.FullTime || s.phase === GamePhase.Finished) finishMatch(rt);
    },
    onError: (e) => system(rt, `Replay notice: ${String(e).slice(0, 100)}`),
    onDone: () => {
      if (rt.status === "live") finishMatch(rt);
    },
  });
}

/** Synthesize discrete events by diffing two live score snapshots. */
function diffToEvents(prev: ScoreSnapshot, next: ScoreSnapshot): MatchEvent[] {
  const out: MatchEvent[] = [];
  let seq = next.seq * 100;
  const push = (kind: MatchEvent["kind"], side: "home" | "away", label: string) =>
    out.push({ fixtureId: next.fixtureId, seq: seq++, ts: next.ts, minute: next.minute, phase: next.phase, kind, side, label });
  for (const side of ["home", "away"] as const) {
    const dg = next.goals[side] - prev.goals[side];
    for (let i = 0; i < dg; i++) push("goal", side, "Goal");
    const dc = next.corners[side] - prev.corners[side];
    for (let i = 0; i < dc; i++) push("corner", side, "Corner");
    const dy = next.yellow[side] - prev.yellow[side];
    for (let i = 0; i < dy; i++) push("yellow", side, "Yellow card");
    const dr = next.red[side] - prev.red[side];
    for (let i = 0; i < dr; i++) push("red", side, "Red card");
  }
  return out;
}

/** The one processing core both drivers share. */
function applyTick(rt: RoomRuntime, score: ScoreSnapshot, odds: OddsSnapshot | null, newEvents: MatchEvent[]) {
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
    home: rt.win.home / 100,
    draw: rt.win.draw / 100,
    away: rt.win.away / 100,
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

    // Card Economy: mint Moments for significant events (ADR-0001)
    if (e.kind === "goal" || e.kind === "red" || e.kind === "yellow" || e.kind === "corner") {
      let fanIds = [...rt.members.values()].map((m) => m.walletPubkey ?? m.id);
      if (fanIds.length === 0) fanIds = [...rt.members.keys()];
      const sandwich = sandwichFromWin(beforeWin, afterWin);
      const minted = mintForRoomFans(fanIds, {
        fixtureId: rt.fixture.id,
        matchLabel: `${rt.fixture.home.code} vs ${rt.fixture.away.code}`,
        roomId: rt.id,
        partyMultiplier: partyDropMultiplier(rt.members.size),
        event: {
          kind: e.kind,
          side: e.side,
          minute: e.minute,
          seq: e.seq,
          label: e.label || `${e.kind} — ${e.side ?? "?"}`,
        },
        oddsSandwich: sandwich,
        priorHomeProb: beforeWin.home,
      });
      if (minted.length) {
        system(rt, `✦ ${minted[0].rarity}★ Moment minted — ${minted[0].label} (${minted.length} fans)`);
      }
    }
  }

  // market-swing Moments from pulse cards
  for (const c of cards) {
    if (c.kind !== "market-swing") continue;
    const fanIds = [...rt.members.values()].map((m) => m.walletPubkey ?? m.id);
    mintForRoomFans(fanIds, {
      fixtureId: rt.fixture.id,
      matchLabel: `${rt.fixture.home.code} vs ${rt.fixture.away.code}`,
      roomId: rt.id,
      partyMultiplier: partyDropMultiplier(rt.members.size),
      event: {
        kind: "market-swing",
        minute: score.minute,
        seq: score.seq,
        label: c.headline ?? "Market swing",
      },
      oddsSandwich: sandwichFromWin(beforeWin, afterWin),
      priorHomeProb: beforeWin.home,
    });
  }

  // 3) Next Swing — generate, lock, resolve
  if (rt.modes.nextSwing) {
    maybeGeneratePrompt(rt, score, odds, win);
    resolvePrompts(rt, newEvents, score, win);
  }

  broadcast(rt);
}

function maybeGeneratePrompt(rt: RoomRuntime, score: ScoreSnapshot, odds: OddsSnapshot | null, win: WinChance) {
  if (!isLivePhase(score.phase)) return;
  if (score.minute >= 86 || rt.atHalftime) return;
  const live = [...rt.prompts.values()].filter((p) => p.status !== "settled");
  if (live.length >= 3) return;
  if (score.minute - rt.lastPromptMinute < 4) return;
  const prompt = generatePrompt(score, odds, win, Math.random);
  if (prompt) {
    rt.prompts.set(prompt.id, prompt);
    rt.lastPromptMinute = score.minute;
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
      } else if (score.minute >= prompt.locksAtMinute + 12 || score.phase >= GamePhase.FullTime) {
        // deadline reached with no live event — settle deterministically so a
        // correct call still scores instead of dangling forever
        settlePrompt(rt, prompt, forceResolve(prompt, score, win));
      }
    }
  }
}

function settlePrompt(rt: RoomRuntime, prompt: SwingPrompt, winningKey: string) {
  prompt.status = "settled";
  prompt.winningKey = winningKey;
  // nothing relevant happened in the window — close it out without scoring or
  // resetting anyone's streak (a fair "no result").
  if (winningKey === "__void__") {
    system(rt, "Micro-Play — no result that window, no points lost.");
    return;
  }
  let winners = 0;
  for (const m of rt.members.values()) {
    const pick = rt.picks.get(m.id)?.get(prompt.id);
    if (pick === undefined) continue;
    if (pick === winningKey) {
      m.points += swingPoints(prompt.basePoints, m.streak);
      m.streak += 1;
      m.bestStreak = Math.max(m.bestStreak, m.streak);
      m.correct += 1;
      winners++;
      // Called It → stamp related Moments + pack weight (ADR-0004)
      const fanId = m.walletPubkey ?? m.id;
      const stamped = stampCalledIt(fanId, {
        fixtureId: rt.fixture.id,
        sinceMinute: Math.max(0, prompt.locksAtMinute - 8),
      });
      if (stamped.length) {
        system(rt, `✓ ${m.name} Called It — ${stamped.length} Moment${stamped.length > 1 ? "s" : ""} sealed`);
      }
    } else {
      m.streak = 0;
    }
  }
  const opt = prompt.options.find((o) => o.key === winningKey);
  system(rt, `Micro-Play settled — ${opt?.label ?? winningKey}. ${winners} called it right.`);
}

function finishMatch(rt: RoomRuntime) {
  if (rt.status === "finished") return;
  rt.status = "finished";
  if (rt.interval) clearInterval(rt.interval);
  rt.interval = null;
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
      return {
        id: p.id,
        question: p.question,
        options: p.options,
        basePoints: p.basePoints,
        locksAtMinute: p.locksAtMinute,
        status: p.status,
        winningKey: p.winningKey,
        tally,
        createdAt: p.createdAt,
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

  return {
    id: rt.id,
    code: rt.code,
    name: rt.name,
    fixture: rt.fixture,
    modes: rt.modes,
    hostId: rt.hostId,
    status: rt.status,
    momentum: rt.momentum,
    win: rt.win,
    winHistory: [...rt.winHistory],
    score,
    markets: rt.odds?.markets ?? [],
    members,
    chat,
    pulse: rt.pulse.slice(-40),
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
    createdAt: rt.createdAt,
  };
}

export interface RoomSummary {
  id: string;
  code: string;
  name: string;
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

export function findByCode(code: string): RoomRuntime | undefined {
  const up = code.toUpperCase();
  return [...store.rooms.values()].find((r) => r.code === up);
}

// ── SSE plumbing ─────────────────────────────────────────────────────────────
export function subscribe(id: string, send: (payload: string) => void): (() => void) | null {
  const rt = store.rooms.get(id);
  if (!rt) return null;
  rt.subscribers.add(send);
  // push an immediate snapshot
  send(JSON.stringify({ type: "state", room: buildView(rt) }));
  return () => rt.subscribers.delete(send);
}

function broadcast(rt: RoomRuntime) {
  if (rt.subscribers.size === 0) return;
  const payload = JSON.stringify({ type: "state", room: buildView(rt) });
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
