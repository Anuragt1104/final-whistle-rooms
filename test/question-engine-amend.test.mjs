import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  createActionLedger,
  reconcileActions,
  confirmedEntry,
} from '../lib/game/question-engine/action-ledger.ts';

test('amend updates ledger data before engine consumers see the action', () => {
  const ledger = createActionLedger('fix-amend');
  reconcileActions(ledger, [
    {
      Seq: 1,
      Ts: 1,
      Action: 'goal',
      Confirmed: true,
      Id: 'g1',
      Participant1IsHome: true,
      Clock: { Seconds: 1200 },
      Data: { Participant: 1, PlayerId: 'p1' },
    },
  ]);
  assert.equal(confirmedEntry(ledger, 'g1')?.playerId, 'p1');

  reconcileActions(ledger, [
    {
      Seq: 2,
      Ts: 2,
      Action: 'action_amend',
      Confirmed: true,
      Id: 'a1',
      Participant1IsHome: true,
      Clock: { Seconds: 1201 },
      Data: { ActionId: 'g1', New: { PlayerId: 'p2' } },
    },
  ]);
  assert.equal(confirmedEntry(ledger, 'g1')?.playerId, 'p2');
});

test('discard removes action from confirmed set', () => {
  const ledger = createActionLedger('fix-discard');
  const first = reconcileActions(ledger, [
    {
      Seq: 1,
      Ts: 1,
      Action: 'yellow_card',
      Confirmed: true,
      Id: 'y1',
      Participant1IsHome: true,
      Clock: { Seconds: 900 },
      Data: { Participant: 2 },
    },
  ]);
  assert.ok(first.some((s) => s.kind === 'card'));

  const second = reconcileActions(ledger, [
    {
      Seq: 2,
      Ts: 2,
      Action: 'action_discarded',
      Confirmed: true,
      Id: 'd1',
      Data: { ActionId: 'y1' },
    },
  ]);
  assert.ok(second.some((s) => s.kind === 'discard' && s.targetActionId === 'y1'));
  assert.equal(confirmedEntry(ledger, 'y1'), undefined);
});
