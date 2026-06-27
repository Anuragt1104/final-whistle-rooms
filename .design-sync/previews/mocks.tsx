// Shared realistic fixtures for Final Whistle Rooms preview cards.
// Imported by the authored .design-sync/previews/<Name>.tsx files; never a
// component itself. Types come from the app source via the @/ alias (resolved
// by tsconfig.dsbuild.json); type-only imports are erased at bundle time.
import * as React from "react";
import { GamePhase } from "@/lib/txline/types";
import type { Fixture, Team, OddsMarket } from "@/lib/txline/types";
import type {
  RoomView,
  MemberView,
  ChatView,
  PromptView,
  ScoreView,
  RecapView,
} from "@/lib/store/types";
import type { PulseCard, WinChance } from "@/lib/engine/pulse";

// Final Whistle Rooms is a dark-themed, phone-shaped product: every component
// is designed to sit on the app's dark pitch gradient with light text. Cards
// in claude.ai/design render on a neutral surface, so each preview wraps its
// stories in this backdrop — the same background `body` paints in the app.
export function Frame({
  children,
  width = 460,
}: {
  children: React.ReactNode;
  width?: number;
}) {
  return (
    <div
      style={{
        background:
          "radial-gradient(900px 500px at 50% -10%, #14233d 0%, rgba(20,35,61,0) 60%), linear-gradient(180deg, #0a1019 0%, #070b14 100%)",
        color: "#eaf1fb",
        padding: 20,
        minHeight: 80,
        fontFamily:
          'ui-sans-serif, system-ui, -apple-system, "Segoe UI", Roboto, Helvetica, Arial',
      }}
    >
      <div style={{ maxWidth: width, margin: "0 auto" }}>{children}</div>
    </div>
  );
}

export const portugal: Team = {
  id: "t_por",
  name: "Portugal",
  code: "POR",
  flag: "🇵🇹",
  rating: 86,
  groupId: "A",
};
export const spain: Team = {
  id: "t_esp",
  name: "Spain",
  code: "ESP",
  flag: "🇪🇸",
  rating: 88,
  groupId: "A",
};

export const fixture: Fixture = {
  id: "fx_por_esp",
  competition: "World Cup",
  stage: "Round of 16",
  groupId: "A",
  home: portugal,
  away: spain,
  kickoff: "2026-06-28T19:00:00.000Z",
  venue: "MetLife Stadium",
  status: "live",
};

export const score: ScoreView = {
  minute: 67,
  phase: GamePhase.SecondHalf,
  goals: { home: 2, away: 1 },
  yellow: { home: 1, away: 3 },
  red: { home: 0, away: 1 },
  corners: { home: 5, away: 4 },
};

export const win: WinChance = { home: 58, draw: 24, away: 18 };

export const markets: OddsMarket[] = [
  {
    type: "match_result",
    label: "Match result",
    selections: [
      { key: "home", label: "POR", price: 1.7, prevPrice: 1.9, impliedProb: 0.58 },
      { key: "draw", label: "Draw", price: 4.1, prevPrice: 3.8, impliedProb: 0.24 },
      { key: "away", label: "ESP", price: 5.2, prevPrice: 4.5, impliedProb: 0.18 },
    ],
  },
];

export const members: MemberView[] = [
  { id: "m1", name: "Mariana", avatar: "🦊", walletShort: "7Ftd…9kQ2", side: "home", points: 148, streak: 4, bestStreak: 4, correct: 9, isHost: true },
  { id: "m2", name: "Diego", avatar: "🐯", walletShort: "3pLm…x8Tn", side: "away", points: 132, streak: 0, bestStreak: 3, correct: 8, isHost: false },
  { id: "m3", name: "Aisha", avatar: "🦁", side: "home", points: 119, streak: 2, bestStreak: 5, correct: 7, isHost: false },
  { id: "m4", name: "Tom", avatar: "🐼", walletShort: "9aZc…2vLp", side: "away", points: 94, streak: 1, bestStreak: 2, correct: 5, isHost: false },
  { id: "m5", name: "Yuki", avatar: "🐸", side: "home", points: 61, streak: 0, bestStreak: 1, correct: 3, isHost: false },
];

export const pulse: PulseCard[] = [
  {
    id: "pc_ko",
    kind: "kickoff",
    minute: 0,
    emoji: "🟢",
    headline: "We're live",
    detail: "Portugal vs Spain is under way. The room is watching together.",
    accent: "neutral",
    createdAt: 0,
  },
  {
    id: "pc_goal1",
    kind: "goal",
    minute: 23,
    emoji: "⚽",
    headline: "GOAL — Portugal!",
    detail: "POR 1–0 ESP · room win chance swung 11 points",
    accent: "home",
    createdAt: 1,
  },
  {
    id: "pc_red",
    kind: "red",
    minute: 41,
    emoji: "🟥",
    headline: "Red card — Spain",
    detail: "Down to 10 men. Momentum is turning Portugal's way.",
    accent: "home",
    createdAt: 2,
  },
  {
    id: "pc_swing",
    kind: "market-swing",
    minute: 58,
    emoji: "📈",
    headline: "Market swing",
    detail: "The market is shifting toward Portugal — win chance up 9 pts without a goal.",
    accent: "home",
    createdAt: 3,
  },
  {
    id: "pc_corner",
    kind: "corner-storm",
    minute: 64,
    emoji: "🚩",
    headline: "Corner storm — Portugal",
    detail: "3 corners in a few minutes. Pressure building — corner challenge live.",
    accent: "home",
    challenge: "corners",
    createdAt: 4,
  },
];

export const prompts: PromptView[] = [
  {
    id: "sw_open",
    question: "Who takes the next corner?",
    options: [
      { key: "home", label: "Portugal", hint: "62%" },
      { key: "away", label: "Spain", hint: "38%" },
    ],
    basePoints: 12,
    locksAtMinute: 70,
    status: "open",
    tally: { home: 6, away: 3 },
    createdAt: 10,
  },
  {
    id: "sw_settled1",
    question: "Goal before the 60th minute?",
    options: [
      { key: "yes", label: "Yes" },
      { key: "no", label: "No" },
    ],
    basePoints: 10,
    locksAtMinute: 60,
    status: "settled",
    winningKey: "no",
    tally: { yes: 4, no: 5 },
    createdAt: 5,
  },
  {
    id: "sw_settled2",
    question: "First half level?",
    options: [
      { key: "yes", label: "Level" },
      { key: "no", label: "Not level" },
    ],
    basePoints: 8,
    locksAtMinute: 45,
    status: "settled",
    winningKey: "no",
    tally: { yes: 2, no: 7 },
    createdAt: 2,
  },
];

export const myPicks: Record<string, string> = { sw_settled1: "no", sw_settled2: "yes" };

export const chat: ChatView[] = [
  { id: "c1", memberId: "system", name: "Room", avatar: "📣", text: "Kick-off! The room is live.", kind: "system", ts: 1 },
  { id: "c2", memberId: "m2", name: "Diego", avatar: "🐯", text: "Spain start strong 🔥", kind: "chat", ts: 2 },
  { id: "c3", memberId: "m1", name: "Mariana", avatar: "🦊", text: "⚽", kind: "reaction", ts: 3 },
  { id: "c4", memberId: "m1", name: "Mariana", avatar: "🦊", text: "GOOOAL! Told you 🇵🇹", kind: "chat", ts: 4 },
  { id: "c5", memberId: "system", name: "Room", avatar: "📣", text: "Next Swing settled — No. 5 called it right.", kind: "system", ts: 5 },
  { id: "c6", memberId: "m4", name: "Tom", avatar: "🐼", text: "that red changes everything", kind: "chat", ts: 6 },
  { id: "c7", memberId: "m3", name: "Aisha", avatar: "🦁", text: "😱", kind: "reaction", ts: 7 },
];

export const recap: RecapView = {
  id: "rc1",
  scope: "half-time",
  minute: 45,
  text: "End-to-end first half. Portugal lead 1–0 after a sharp finish on 23', but Spain's red card on 41' flips the run of play. The room is buzzing — corners are piling up and the win-chance bar keeps sliding toward Portugal.",
  topMember: "Mariana",
  createdAt: 5,
};

export const room: RoomView = {
  id: "room_demo",
  code: "PORESP",
  name: "Iberian Derby 🇵🇹🇪🇸",
  fixture,
  modes: { draft: true, nextSwing: true },
  hostId: "m1",
  status: "live",
  momentum: 42,
  win,
  score,
  markets,
  members,
  chat,
  pulse,
  prompts,
  recaps: [recap],
  proof: { leafCount: 37, root: "0xa1b2c3", anchored: true, anchorSignature: "5xPq…", cluster: "devnet" },
  createdAt: 0,
};
