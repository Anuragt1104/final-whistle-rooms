import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  generatePrompt,
  tryResolve,
  forceResolve,
  biasFromIntensity,
} from '../lib/game/nextswing.ts';

const score = {
  minute: 40,
  goals: { home: 0, away: 0 },
  corners: { home: 2, away: 1 },
  yellow: { home: 1, away: 0 },
  red: { home: 0, away: 0 },
  phase: 2,
};
const win = { home: 55, draw: 25, away: 20 };

test('win-swing forceResolve: HIGHER when the favourite rises, LOWER when it falls', () => {
  const p = { resolver: { kind: 'win-swing', side: 'home', baseline: 55, minute: 45 } };
  assert.equal(forceResolve(p, score, { home: 61, draw: 20, away: 19 }), 'up');
  assert.equal(forceResolve(p, score, { home: 49, draw: 26, away: 25 }), 'down');
});

test('win-swing tryResolve stays locked until the deadline minute', () => {
  const p = { resolver: { kind: 'win-swing', side: 'home', baseline: 55, minute: 45 } };
  assert.equal(tryResolve(p, [], { ...score, minute: 43 }, { home: 70 }), null);
  assert.equal(tryResolve(p, [], { ...score, minute: 45 }, { home: 70, draw: 15, away: 15 }), 'up');
});

test('skill prompts dominate — win-swing + odds-move + literacy beat coin-flip next-event', () => {
  let skill = 0, coinFlip = 0, total = 0;
  const skillKinds = new Set(['win-swing', 'odds-move', 'next-card-side', 'lead-by-two', 'total-goals', 'next-corner-side']);
  for (let i = 0; i < 400; i++) {
    let s = (i * 2654435761) & 0x7fffffff;
    const rand = () => { s = (s * 1103515245 + 12345) & 0x7fffffff; return s / 0x7fffffff; };
    const p = generatePrompt(score, null, win, rand);
    if (!p) continue;
    total++;
    if (skillKinds.has(p.resolver.kind)) skill++;
    if (p.resolver.kind === 'next-event') coinFlip++;
  }
  const skillShare = skill / total;
  const coinShare = coinFlip / total;
  assert.ok(skillShare > 0.7, `skill share was ${skillShare.toFixed(2)}`);
  assert.ok(coinShare < 0.12, `coin-flip share was ${coinShare.toFixed(2)}`);
});

test('odds-move appears in generation', () => {
  let hit = 0;
  for (let i = 0; i < 500; i++) {
    let s = (i * 1103515245) & 0x7fffffff;
    const rand = () => { s = (s * 1103515245 + 12345) & 0x7fffffff; return s / 0x7fffffff; };
    const p = generatePrompt(score, null, win, rand);
    if (p?.resolver.kind === 'odds-move') hit++;
  }
  assert.ok(hit > 20, `odds-move only appeared ${hit} times`);
});

test('next-card-side forceResolve uses yellow/red deltas', () => {
  const p = {
    resolver: { kind: 'next-card-side' },
    lockState: { goals: { home: 0, away: 0 }, corners: { home: 0, away: 0 }, cards: { home: 1, away: 0 } },
  };
  const after = {
    ...score,
    yellow: { home: 1, away: 2 },
    red: { home: 0, away: 0 },
  };
  assert.equal(forceResolve(p, after, win), 'away');
});

test('lead-by-two and total-goals settle from the scoreboard', () => {
  assert.equal(
    forceResolve({ resolver: { kind: 'lead-by-two', minute: 90 } }, { ...score, goals: { home: 2, away: 0 } }, win),
    'yes',
  );
  assert.equal(
    forceResolve({ resolver: { kind: 'total-goals', target: 2, minute: 90 } }, { ...score, goals: { home: 1, away: 1 } }, win),
    'yes',
  );
});

test('odds-move forceResolve mirrors the home win-chance vs baseline', () => {
  const p = { resolver: { kind: 'odds-move', baseline: 50, minute: 46 } };
  assert.equal(forceResolve(p, score, { home: 55 }), 'yes');
  assert.equal(forceResolve(p, score, { home: 45 }), 'no');
});

test('next-goal-before resolves to the scoring side, else none at the deadline', () => {
  const p = { resolver: { kind: 'next-goal-before', minute: 55 } };
  assert.equal(tryResolve(p, [{ kind: 'goal', side: 'home', minute: 50 }], score, win), 'home');
  assert.equal(forceResolve({ ...p }, { ...score, minute: 55 }, win), 'none');
});

test('biasFromIntensity: pulse corner storm → corners; flurry → flurry', () => {
  assert.equal(
    biasFromIntensity({
      goalsLast10Min: 0,
      cardsLast5Min: 0,
      scoreJustChanged: false,
      isComeback: false,
      redCardActive: false,
      momentumAbs: 10,
      challenge: 'corners',
    }),
    'corners',
  );
  assert.equal(
    biasFromIntensity({
      goalsLast10Min: 3,
      cardsLast5Min: 0,
      scoreJustChanged: true,
      isComeback: false,
      redCardActive: false,
      momentumAbs: 40,
      flurrySummary: '3 goals in 8 minutes',
    }),
    'flurry',
  );
  assert.equal(
    biasFromIntensity({
      goalsLast10Min: 1,
      cardsLast5Min: 0,
      scoreJustChanged: true,
      isComeback: true,
      redCardActive: false,
      momentumAbs: 30,
    }),
    'comeback',
  );
});

test('flurry bias heavily prefers next-goal / total-goals over coin-flips', () => {
  const hot = {
    ...score,
    goals: { home: 2, away: 1 },
    minute: 67,
  };
  const story = {
    goalsLast10Min: 3,
    scoreJustChanged: true,
    flurrySummary: '3 goals in 11 minutes',
    lastScorer: 'Messi',
    lastGoalMinute: 64,
  };
  let drama = 0;
  let total = 0;
  for (let i = 0; i < 300; i++) {
    let s = (i * 2654435761) & 0x7fffffff;
    const rand = () => {
      s = (s * 1103515245 + 12345) & 0x7fffffff;
      return s / 0x7fffffff;
    };
    const p = generatePrompt(hot, null, win, rand, 'flurry', story);
    if (!p) continue;
    total++;
    if (p.resolver.kind === 'next-goal-before' || p.resolver.kind === 'total-goals') drama++;
  }
  const share = drama / total;
  assert.ok(share > 0.55, `flurry drama share was ${share.toFixed(2)}`);
});

test('corners bias prefers next-corner-side', () => {
  let corners = 0;
  let total = 0;
  for (let i = 0; i < 200; i++) {
    let s = (i * 1103515245) & 0x7fffffff;
    const rand = () => {
      s = (s * 1103515245 + 12345) & 0x7fffffff;
      return s / 0x7fffffff;
    };
    const p = generatePrompt(score, null, win, rand, 'corners');
    if (!p) continue;
    total++;
    if (p.resolver.kind === 'next-corner-side') corners++;
  }
  const share = corners / total;
  assert.ok(share > 0.5, `corners bias share was ${share.toFixed(2)}`);
});

test('templates include score line so LLM failure still feels match-specific', () => {
  const p = generatePrompt(
    { ...score, goals: { home: 0, away: 2 }, minute: 55 },
    null,
    win,
    () => 0.01,
    'flurry',
    { flurrySummary: '3 goals in 11 minutes', lastScorer: 'Álvarez', lastGoalMinute: 52 },
  );
  assert.ok(p);
  assert.match(p.question, /0–2|3 goals|Álvarez|grip|reach|goal/i);
});

test('production templates use plain match language without odds or sportsbook thresholds', () => {
  const banned = /%|odds|clear by|higher or lower|bet|wager/i;
  for (let i = 0; i < 400; i++) {
    let s = (i * 2654435761) & 0x7fffffff;
    const rand = () => { s = (s * 1103515245 + 12345) & 0x7fffffff; return s / 0x7fffffff; };
    const p = generatePrompt(score, null, win, rand);
    assert.ok(p);
    assert.doesNotMatch(p.question, banned);
    for (const option of p.options) assert.doesNotMatch(`${option.label} ${option.hint ?? ''}`, banned);
  }
});
