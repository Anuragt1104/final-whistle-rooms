import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mapScores } from '../lib/txline/live.ts';
import { GamePhase } from '../lib/txline/types.ts';
import {
  isWaterBreakComment,
  phaseFromStatusId,
} from '../lib/game/question-engine/signals.ts';
import {
  createActionLedger,
  reconcileActions,
  secondaryCoverageOk,
} from '../lib/game/question-engine/action-ledger.ts';

test('C / TXCC / TXCS are cancel/coverage — not cooling break', () => {
  const base = {
    FixtureId: 1,
    Clock: { Running: false, Seconds: 2700 },
    Stats: {},
    Score: {},
  };
  const cancelled = mapScores({ ...base, GameState: 'C' }, 1, new Date().toISOString());
  assert.equal(cancelled.phase, GamePhase.Cancelled);
  assert.equal(cancelled.statusNote, 'Cancelled');
  assert.ok(!/cooling/i.test(cancelled.statusNote ?? ''));

  const txcc = mapScores({ ...base, GameState: 'TXCC' }, 2, new Date().toISOString());
  assert.equal(txcc.phase, GamePhase.CoveragePaused);
  assert.equal(txcc.statusNote, 'Coverage cancelled');

  const txcs = mapScores({ ...base, GameState: 'TXCS' }, 3, new Date().toISOString());
  assert.equal(txcs.phase, GamePhase.CoveragePaused);
  assert.equal(txcs.statusNote, 'Coverage suspended');
});

test('StatusId preferred over GameState string', () => {
  const s = mapScores(
    {
      FixtureId: 9,
      StatusId: 18, // TXCS
      GameState: 'H2', // misleading
      Clock: { Running: true, Seconds: 4000 },
      Stats: {},
      Score: {},
    },
    1,
    new Date().toISOString(),
  );
  assert.equal(s.phase, GamePhase.CoveragePaused);
  assert.equal(phaseFromStatusId(16), GamePhase.Cancelled);
  assert.equal(phaseFromStatusId(17), GamePhase.CoveragePaused);
});

test('water-break only from exact comment text', () => {
  assert.equal(isWaterBreakComment('Water-drinking break'), true);
  assert.equal(isWaterBreakComment('Cooling break'), false);
  assert.equal(isWaterBreakComment('water break'), false);

  const ledger = createActionLedger('fix1');
  const signals = reconcileActions(ledger, [
    {
      Seq: 1,
      Ts: Date.now(),
      Action: 'comment',
      Confirmed: true,
      Id: 'c1',
      Clock: { Seconds: 1800 },
      Data: { Text: 'Water-drinking break' },
    },
  ]);
  assert.ok(signals.some((s) => s.kind === 'water-break' && s.active));
  assert.equal(ledger.waterBreakActive, true);
});

test('secondary coverage gates shot/danger', () => {
  const ledger = createActionLedger('fix2');
  assert.equal(secondaryCoverageOk(ledger, 'fresh'), true);
  reconcileActions(ledger, [
    {
      Seq: 1,
      Ts: Date.now(),
      Action: 'unreliable_secondary',
      Confirmed: true,
      Id: 'u1',
      Data: {},
    },
  ]);
  assert.equal(secondaryCoverageOk(ledger, 'fresh'), false);
  assert.equal(secondaryCoverageOk(ledger, 'stale'), false);
});
