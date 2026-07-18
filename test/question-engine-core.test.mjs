import { test } from 'node:test';
import assert from 'node:assert/strict';
import { FixtureQuestionCoordinator, resetAllCoordinators } from '../lib/game/question-engine/coordinator.ts';
import { questionId } from '../lib/game/question-engine/ids.ts';
import { rankCandidates } from '../lib/game/question-engine/score.ts';
import { detectCandidates } from '../lib/game/question-engine/rules/catalog.ts';
import { buildHistorySnapshot, summarizeTape } from '../lib/game/question-engine/history.ts';
import { MAX_ACTIVE, canGenerate } from '../lib/game/question-engine/cadence.ts';
import { compressTape, decompressTape } from '../lib/game/question-engine/tape.ts';
import { GamePhase } from '../lib/txline/types.ts';

function score(minute, overrides = {}) {
  return {
    fixtureId: 'f1',
    seq: minute,
    ts: new Date().toISOString(),
    phase: minute < 45 ? GamePhase.FirstHalf : minute < 90 ? GamePhase.SecondHalf : GamePhase.FullTime,
    minute,
    clockSeconds: minute * 60,
    running: true,
    updatedAt: Date.now(),
    goals: { home: 0, away: 0 },
    yellow: { home: 0, away: 0 },
    red: { home: 0, away: 0 },
    corners: { home: 1, away: 0 },
    periods: {
      firstHalf: { goals: { home: 0, away: 0 }, yellow: { home: 0, away: 0 }, red: { home: 0, away: 0 }, corners: { home: 0, away: 0 } },
      secondHalf: { goals: { home: 0, away: 0 }, yellow: { home: 0, away: 0 }, red: { home: 0, away: 0 }, corners: { home: 0, away: 0 } },
    },
    ...overrides,
  };
}

const win = { home: 55, draw: 25, away: 20 };

test('deterministic question ids', () => {
  assert.equal(questionId('f1', 'win-swing', 3, 0), 'q:f1:1:win-swing:3:0');
});

test('rankCandidates is stable (no Math.random)', () => {
  const ctx = {
    fixtureId: 'f1',
    homeCode: 'HOM',
    awayCode: 'AWY',
    homeName: 'Home',
    awayName: 'Away',
    score: score(40),
    win,
    feedFreshness: 'fresh',
    coverageSecondary: true,
    lineupConfirmed: true,
    onPitchPlayerIds: new Set(),
    clockSec: 2400,
    phase: GamePhase.FirstHalf,
  };
  const cands = detectCandidates(ctx, 'main');
  const a = rankCandidates(cands, ctx, new Set(), 'salt').map((c) => c.ruleId);
  const b = rankCandidates(cands, ctx, new Set(), 'salt').map((c) => c.ruleId);
  assert.deepEqual(a, b);
  assert.ok(a.length >= 3);
});

test('cadence: max 2 active; continues past 86′', () => {
  resetAllCoordinators();
  const coord = new FixtureQuestionCoordinator({
    fixtureId: 'f-late',
    homeCode: 'HOM',
    awayCode: 'AWY',
    homeName: 'Home',
    awayName: 'Away',
  });
  const s87 = score(87, { phase: GamePhase.SecondHalf, seq: 87 });
  const cmds = coord.advance(
    { kind: 'tick', fixtureId: 'f-late', seq: 87, score: s87, events: [], feedFreshness: 'fresh', ts: Date.now() },
    s87,
    win,
    [],
    { feedFreshness: 'fresh', majorEvent: true },
  );
  const opens = cmds.filter((c) => c.type === 'open');
  assert.ok(opens.length >= 1, 'should open Live Calls after 86′');
  assert.ok(opens.length <= MAX_ACTIVE);

  const snap = coord.snapshot();
  const active = snap.questions.filter((q) => q.status === 'open' || q.status === 'locked');
  assert.ok(active.length <= MAX_ACTIVE);
});

test('halftime deck opens break-lane questions', () => {
  resetAllCoordinators();
  const coord = new FixtureQuestionCoordinator({
    fixtureId: 'f-ht',
    homeCode: 'HOM',
    awayCode: 'AWY',
    homeName: 'Home',
    awayName: 'Away',
  });
  const s = score(45, { phase: GamePhase.HalfTime, running: false, seq: 45 });
  const cmds = coord.advance(
    { kind: 'tick', fixtureId: 'f-ht', seq: 45, score: s, events: [], feedFreshness: 'fresh', ts: Date.now() },
    s,
    win,
    [],
    { feedFreshness: 'fresh', atHalftime: true },
  );
  const opens = cmds.filter((c) => c.type === 'open');
  assert.ok(opens.length >= 1);
  assert.ok(opens.every((c) => c.question.lane === 'break'));
});

test('coverage paused voids open questions and blocks generation', () => {
  resetAllCoordinators();
  const coord = new FixtureQuestionCoordinator({
    fixtureId: 'f-pause',
    homeCode: 'HOM',
    awayCode: 'AWY',
    homeName: 'Home',
    awayName: 'Away',
  });
  const live = score(30, { seq: 30 });
  coord.advance(
    { kind: 'tick', fixtureId: 'f-pause', seq: 30, score: live, events: [], feedFreshness: 'fresh', ts: Date.now() },
    live,
    win,
    [],
    { feedFreshness: 'fresh', majorEvent: true },
  );
  const paused = score(31, { phase: GamePhase.CoveragePaused, running: false, seq: 31, statusNote: 'Coverage suspended' });
  const cmds = coord.advance(
    { kind: 'tick', fixtureId: 'f-pause', seq: 31, score: paused, events: [], feedFreshness: 'paused', ts: Date.now() },
    paused,
    win,
    [],
    { feedFreshness: 'paused' },
  );
  assert.ok(cmds.some((c) => c.type === 'void'));
  assert.equal(cmds.filter((c) => c.type === 'open').length, 0);
});

test('live vs replay identical open ids for same tape', () => {
  resetAllCoordinators();
  const mk = (id) =>
    new FixtureQuestionCoordinator({
      fixtureId: id,
      homeCode: 'HOM',
      awayCode: 'AWY',
      homeName: 'Home',
      awayName: 'Away',
    });
  const a = mk('parity');
  const b = mk('parity');
  // Separate instances with same fixtureId share registry — reset between.
  resetAllCoordinators();
  const live = new FixtureQuestionCoordinator({
    fixtureId: 'parity-live',
    homeCode: 'HOM',
    awayCode: 'AWY',
    homeName: 'Home',
    awayName: 'Away',
  });
  resetAllCoordinators();
  const replay = new FixtureQuestionCoordinator({
    fixtureId: 'parity-live',
    homeCode: 'HOM',
    awayCode: 'AWY',
    homeName: 'Home',
    awayName: 'Away',
  });

  const run = (coord) => {
    const ids = [];
    for (const minute of [20, 25, 40]) {
      const s = score(minute, { seq: minute, clockSeconds: minute * 60 });
      // Force gap by setting major + enough clock delta
      const cmds = coord.advance(
        { kind: 'tick', fixtureId: 'parity-live', seq: minute, score: s, events: [], feedFreshness: 'fresh', ts: Date.now() },
        s,
        win,
        [],
        { feedFreshness: 'fresh', majorEvent: true },
      );
      for (const c of cmds) if (c.type === 'open') ids.push(c.question.id);
    }
    return ids;
  };
  // Fresh coordinators each — but getFixtureCoordinator caches; use advance on isolated instances.
  // The constructor path above already creates isolated instances not via registry after reset.
  const idsA = run(live);
  // Rebuild identical coordinator state by replaying same inputs on fresh instance
  resetAllCoordinators();
  const replay2 = new FixtureQuestionCoordinator({
    fixtureId: 'parity-live',
    homeCode: 'HOM',
    awayCode: 'AWY',
    homeName: 'Home',
    awayName: 'Away',
  });
  const idsB = run(replay2);
  assert.deepEqual(idsA, idsB);
  assert.ok(idsA.length >= 1);
});

test('history cutoff excludes future fixtures', () => {
  const tapes = [
    summarizeTape('old', '2026-06-01T00:00:00Z', [
      { minute: 10, kind: 'goal' },
      { minute: 80, kind: 'goal' },
    ]),
    summarizeTape('future', '2026-07-01T00:00:00Z', [{ minute: 5, kind: 'goal' }]),
  ];
  const snap = buildHistorySnapshot('now', '2026-06-15T00:00:00Z', tapes);
  assert.equal(snap.sampleSize, 1);
  assert.deepEqual(snap.sourceFixtureIds, ['old']);
  assert.ok(snap.lateGoalRate > 0);
});

test('tape compress round-trip', () => {
  const payload = {
    fixtureId: 'f1',
    kickoff: '2026-06-01T00:00:00Z',
    scores: [score(1)],
    events: [],
    archivedAt: Date.now(),
  };
  const buf = compressTape(payload);
  const back = decompressTape(buf);
  assert.equal(back.fixtureId, 'f1');
  assert.equal(back.scores.length, 1);
});

test('canGenerate false when stale', () => {
  const ctx = {
    fixtureId: 'f1',
    homeCode: 'H',
    awayCode: 'A',
    homeName: 'H',
    awayName: 'A',
    score: score(40),
    win,
    feedFreshness: 'stale',
    coverageSecondary: true,
    lineupConfirmed: true,
    onPitchPlayerIds: new Set(),
    clockSec: 2400,
    phase: GamePhase.FirstHalf,
  };
  assert.equal(canGenerate(ctx, [], 0), false);
});

test('engine eval budget — advance under 50ms for typical tick', () => {
  resetAllCoordinators();
  const coord = new FixtureQuestionCoordinator({
    fixtureId: 'perf',
    homeCode: 'HOM',
    awayCode: 'AWY',
    homeName: 'Home',
    awayName: 'Away',
  });
  const s = score(55, { seq: 55 });
  const t0 = performance.now();
  const cmds = coord.advance(
    { kind: 'tick', fixtureId: 'perf', seq: 55, score: s, events: [], feedFreshness: 'fresh', ts: Date.now() },
    s,
    win,
    [],
    { feedFreshness: 'fresh', majorEvent: true },
  );
  const ms = performance.now() - t0;
  assert.ok(ms < 50, `eval took ${ms}ms`);
  const metric = cmds.find((c) => c.type === 'metric' && c.name === 'eval_ms');
  assert.ok(metric);
});
