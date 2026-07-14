/**
 * The interpretation layer — where the product becomes original.
 *
 * It sits between raw TxLINE updates and the UI, turning low-level score/odds
 * movement into "room-native" events: plain-English pulse cards, a momentum
 * meter, and a friendly win-chance read of the market. This is the "market
 * translator" the concept is built around.
 */
import {
  GamePhase,
  type Fixture,
  type MatchEvent,
  type OddsSnapshot,
  type ScoreSnapshot,
} from "@/lib/txline/types";

export type PulseAccent = "home" | "away" | "neutral" | "hot" | "good" | "bad";

export interface PulseCard {
  id: string;
  kind:
    | "kickoff"
    | "goal"
    | "red"
    | "chaos"
    | "corner-storm"
    | "market-swing"
    | "half-time"
    | "full-time"
    | "momentum";
  minute: number;
  emoji: string;
  headline: string;
  detail: string;
  accent: PulseAccent;
  createdAt: number;
  /** Verified TxLINE player identity when the action record provides one. */
  scorer?: string;
  /** Optional: opens a matching Next Swing challenge. */
  challenge?: "corners" | "next-goal";
}

export interface WinChance {
  home: number;
  draw: number;
  away: number;
}

/** Friendly win-chance read from the de-margined match-result market. */
export function winChance(odds: OddsSnapshot | null): WinChance {
  const m = odds?.markets.find((x) => x.type === "match_result");
  if (!m) return { home: 33, draw: 34, away: 33 };
  const get = (k: string) => m.selections.find((s) => s.key === k)?.impliedProb ?? 0;
  let h = get("home");
  let d = get("draw");
  let a = get("away");
  const sum = h + d + a || 1;
  h /= sum;
  d /= sum;
  a /= sum;
  return { home: Math.round(h * 100), draw: Math.round(d * 100), away: Math.round(a * 100) };
}

interface CardStamp {
  minute: number;
  side: "home" | "away";
}

/**
 * Stateful interpreter held by each room. Feed it ticks; it returns the pulse
 * cards to broadcast and maintains a decaying momentum meter (-100 away .. +100
 * home).
 */
export class PulseInterpreter {
  private fixture: Fixture;
  private momentumValue = 0;
  private lastMomentumMinute = 0;
  private recentCards: CardStamp[] = [];
  private recentCorners: CardStamp[] = [];
  private lastWin: WinChance | null = null;
  private idCounter = 0;

  constructor(fixture: Fixture) {
    this.fixture = fixture;
  }

  get momentum(): number {
    return Math.round(this.momentumValue);
  }

  private id(kind: string): string {
    return `pc_${kind}_${this.idCounter++}`;
  }

  private decayTo(minute: number) {
    const dt = Math.max(0, minute - this.lastMomentumMinute);
    if (dt > 0) {
      this.momentumValue *= Math.pow(0.9, dt);
      this.lastMomentumMinute = minute;
    }
  }

  private bump(delta: number) {
    this.momentumValue = clamp(this.momentumValue + delta, -100, 100);
  }

  private teamName(side: "home" | "away"): string {
    return side === "home" ? this.fixture.home.name : this.fixture.away.name;
  }

  ingest(
    events: MatchEvent[],
    score: ScoreSnapshot,
    odds: OddsSnapshot | null,
  ): { cards: PulseCard[]; win: WinChance } {
    const now = Date.now();
    const win = winChance(odds);
    const cards: PulseCard[] = [];
    this.decayTo(score.minute);

    for (const e of events) {
      const side = e.side;
      switch (e.kind) {
        case "kickoff": {
          cards.push({
            id: this.id("ko"),
            kind: "kickoff",
            minute: 0,
            emoji: "🟢",
            headline: "We're live",
            detail: `${this.fixture.home.name} vs ${this.fixture.away.name} is under way. The room is watching together.`,
            accent: "neutral",
            createdAt: now,
          });
          break;
        }
        case "goal": {
          if (!side) break;
          this.bump(side === "home" ? 38 : -38);
          const swing = this.lastWin
            ? Math.abs((side === "home" ? win.home : win.away) - (side === "home" ? this.lastWin.home : this.lastWin.away))
            : 0;
          cards.push({
            id: this.id("goal"),
            kind: "goal",
            minute: e.minute,
            emoji: "⚽",
            headline: `GOAL — ${this.teamName(side)}!`,
            detail:
              `${e.playerName ? `${e.playerName} · ` : ""}${this.fixture.home.code} ${score.goals.home}–${score.goals.away} ${this.fixture.away.code}` +
              (swing >= 4 ? ` · room win chance swung ${swing} points` : ""),
            scorer: e.playerName,
            accent: side,
            createdAt: now,
          });
          break;
        }
        case "red": {
          if (!side) break;
          this.bump(side === "home" ? -26 : 26);
          cards.push({
            id: this.id("red"),
            kind: "red",
            minute: e.minute,
            emoji: "🟥",
            headline: `Red card — ${this.teamName(side)}`,
            detail: `${e.playerName ? `${e.playerName} sent off. ` : ""}Down to 10 men. Momentum is turning ${side === "home" ? this.fixture.away.name : this.fixture.home.name}'s way.`,
            accent: side === "home" ? "away" : "home",
            createdAt: now,
          });
          break;
        }
        case "yellow": {
          if (!side) break;
          this.bump(side === "home" ? -4 : 4);
          this.recentCards.push({ minute: e.minute, side });
          this.recentCards = this.recentCards.filter((c) => e.minute - c.minute <= 5);
          if (this.recentCards.length >= 2) {
            cards.push({
              id: this.id("chaos"),
              kind: "chaos",
              minute: e.minute,
              emoji: "⚡",
              headline: "Chaos watch",
              detail: `${this.recentCards.length} cards in ${e.minute - this.recentCards[0].minute || 1} minutes. It's getting spicy.`,
              accent: "hot",
              challenge: "next-goal",
              createdAt: now,
            });
            this.recentCards = [];
          }
          break;
        }
        case "corner": {
          if (!side) break;
          this.bump(side === "home" ? 5 : -5);
          this.recentCorners.push({ minute: e.minute, side });
          this.recentCorners = this.recentCorners.filter((c) => e.minute - c.minute <= 4);
          const sameSide = this.recentCorners.filter((c) => c.side === side);
          if (sameSide.length >= 3) {
            cards.push({
              id: this.id("corner"),
              kind: "corner-storm",
              minute: e.minute,
              emoji: "🚩",
              headline: `Corner storm — ${this.teamName(side)}`,
              detail: `${sameSide.length} corners in a few minutes. Pressure building — corner challenge live.`,
              accent: side,
              challenge: "corners",
              createdAt: now,
            });
            this.recentCorners = [];
          }
          break;
        }
        case "half-time": {
          cards.push({
            id: this.id("ht"),
            kind: "half-time",
            minute: 45,
            emoji: "⏸️",
            headline: "Half-time",
            detail: `${this.fixture.home.code} ${score.goals.home}–${score.goals.away} ${this.fixture.away.code}. Recap dropping in the room.`,
            accent: "neutral",
            createdAt: now,
          });
          break;
        }
        case "full-time": {
          cards.push({
            id: this.id("ft"),
            kind: "full-time",
            minute: 90,
            emoji: "🏁",
            headline: "Full-time",
            detail: `${this.fixture.home.code} ${score.goals.home}–${score.goals.away} ${this.fixture.away.code}. Final whistle — see who topped the room.`,
            accent: "neutral",
            createdAt: now,
          });
          break;
        }
      }
    }

    // Market swing with no goal this tick — surface a translated odds move.
    const goalThisTick = events.some((e) => e.kind === "goal");
    if (!goalThisTick && this.lastWin && score.phase !== GamePhase.PreMatch) {
      const dh = win.home - this.lastWin.home;
      if (Math.abs(dh) >= 7) {
        const towardHome = dh > 0;
        cards.push({
          id: this.id("swing"),
          kind: "market-swing",
          minute: score.minute,
          emoji: "📈",
          headline: "Market swing",
          detail: `The market is shifting toward ${towardHome ? this.fixture.home.name : this.fixture.away.name} — win chance ${towardHome ? "up" : "down"} ${Math.abs(dh)} pts without a goal.`,
          accent: towardHome ? "home" : "away",
          createdAt: now,
        });
      }
    }

    this.lastWin = win;
    return { cards, win };
  }
}

function clamp(x: number, lo: number, hi: number): number {
  return Math.max(lo, Math.min(hi, x));
}
