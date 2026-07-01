import { test } from 'node:test';
import assert from 'node:assert/strict';
import { generatePrompt, tryResolve, forceResolve } from '../lib/game/nextswing.ts';

const score = { minute: 40, goals: { home: 0, away: 0 }, corners: { home: 2, away: 1 }, phase: 2 };
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

test('win-swing is the featured prompt (40-70% of generated prompts)', () => {
  let swing = 0, total = 0;
  for (let i = 0; i < 400; i++) {
    let s = (i * 2654435761) & 0x7fffffff;
    const rand = () => { s = (s * 1103515245 + 12345) & 0x7fffffff; return s / 0x7fffffff; };
    const p = generatePrompt(score, null, win, rand);
    if (!p) continue;
    total++;
    if (p.resolver.kind === 'win-swing') swing++;
  }
  const share = swing / total;
  assert.ok(share > 0.4 && share < 0.7, `win-swing share was ${share.toFixed(2)}`);
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
