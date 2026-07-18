/**
 * Per-fixture action ledger — confirm / amend / discard before the engine
 * consumes match events (extends match-intelligence patterns).
 */
import type { RawRecord } from "@/lib/explorer/types";
import type { FootballSignal } from "./signals";
import { isWaterBreakComment, signalsFromRawActions } from "./signals";

type AnyMap = Record<string, unknown>;
const asMap = (v: unknown): AnyMap =>
  v && typeof v === "object" && !Array.isArray(v) ? (v as AnyMap) : {};
const str = (v: unknown): string | undefined => {
  if (v == null) return undefined;
  const s = String(v).trim();
  return s || undefined;
};
const num = (v: unknown, fb = 0): number => {
  const n = Number(v);
  return Number.isFinite(n) ? n : fb;
};

export type LedgerActionKind =
  | "goal"
  | "yellow"
  | "red"
  | "corner"
  | "substitution"
  | "shot"
  | "danger"
  | "penalty"
  | "var"
  | "injury"
  | "water-break"
  | "comment";

export interface LedgerEntry {
  actionId: string;
  kind: LedgerActionKind;
  side?: "home" | "away";
  playerId?: string;
  playerName?: string;
  playerInId?: string;
  playerOutId?: string;
  onTarget?: boolean;
  clockSec: number;
  seq: number;
  ts: number;
  confirmed: boolean;
  discarded: boolean;
  data: AnyMap;
}

export interface ActionLedgerState {
  fixtureId: string;
  entries: Map<string, LedgerEntry>;
  discarded: Set<string>;
  coverageSecondary: boolean;
  unreliableSecondary: boolean;
  waterBreakActive: boolean;
  lastSeq: number;
}

const KIND_MAP: Record<string, LedgerActionKind> = {
  goal: "goal",
  yellow_card: "yellow",
  red_card: "red",
  corner: "corner",
  substitution: "substitution",
  shot: "shot",
  shot_on_target: "shot",
  danger: "danger",
  dangerous_attack: "danger",
  penalty: "penalty",
  var: "var",
  var_decision: "var",
  injury: "injury",
  comment: "comment",
  match_comment: "comment",
};

function participantSide(record: RawRecord, participant: unknown): "home" | "away" {
  const p = num(participant, 1);
  const p1Home = record.Participant1IsHome !== false;
  return (p === 1) === p1Home ? "home" : "away";
}

export function createActionLedger(fixtureId: string): ActionLedgerState {
  return {
    fixtureId,
    entries: new Map(),
    discarded: new Set(),
    coverageSecondary: true,
    unreliableSecondary: false,
    waterBreakActive: false,
    lastSeq: -1,
  };
}

/**
 * Ingest ordered raw records. Returns confirmed FootballSignals ready for the engine.
 * Amend/discard mutate the ledger; discarded actions never emit.
 */
export function reconcileActions(
  ledger: ActionLedgerState,
  records: RawRecord[],
): FootballSignal[] {
  const out: FootballSignal[] = [];
  const ordered = [...records].sort((a, b) => num(a.Seq) - num(b.Seq));

  for (const record of ordered) {
    const seq = num(record.Seq);
    if (seq <= ledger.lastSeq && record.Action !== "action_amend" && record.Action !== "action_discarded") {
      // Allow late amend/discard; skip pure regressive duplicates.
      continue;
    }
    ledger.lastSeq = Math.max(ledger.lastSeq, seq);
    const ts = num(record.Ts, Date.now());
    const data = asMap(record.Data);
    const action = record.Action ?? "";
    const clockSec = Math.max(0, Math.floor(num(record.Clock?.Seconds)));

    if (record.CoverageSecondaryData === false) {
      ledger.coverageSecondary = false;
    } else if (record.CoverageSecondaryData === true) {
      ledger.coverageSecondary = true;
    }

    if (action === "action_discarded") {
      const target = str(data.ActionId ?? data.TargetId ?? data.Id);
      if (!target) continue;
      ledger.discarded.add(target);
      const entry = ledger.entries.get(target);
      if (entry) entry.discarded = true;
      out.push({ kind: "discard", fixtureId: ledger.fixtureId, seq, targetActionId: target, ts });
      continue;
    }

    if (action === "action_amend") {
      const target = str(data.ActionId ?? data.TargetId ?? data.Id);
      if (!target) continue;
      const prior = ledger.entries.get(target);
      if (prior && !prior.discarded) {
        prior.data = { ...prior.data, ...asMap(data.New) };
        const sidePart = prior.data.Participant ?? data.Participant;
        if (sidePart != null) prior.side = participantSide(record, sidePart);
        prior.playerId = str(prior.data.PlayerId) ?? prior.playerId;
      }
      out.push({ kind: "amend", fixtureId: ledger.fixtureId, seq, targetActionId: target, ts });
      continue;
    }

    if (action === "unreliable_secondary" || action === "coverage_secondary_off") {
      ledger.unreliableSecondary = true;
      ledger.coverageSecondary = false;
      out.push({
        kind: "reliability",
        fixtureId: ledger.fixtureId,
        seq,
        level: "unreliable_secondary",
        reason: action,
        ts,
      });
      continue;
    }

    if (record.Confirmed === false) continue;

    const kind = KIND_MAP[action];
    if (!kind) continue;

    const actionId = str(record.Id) ?? `${action}:${seq}`;
    if (ledger.discarded.has(actionId)) continue;

    if (kind === "comment") {
      const text = data.Text ?? data.text;
      if (isWaterBreakComment(text)) {
        ledger.waterBreakActive = true;
        const entry: LedgerEntry = {
          actionId,
          kind: "water-break",
          clockSec,
          seq,
          ts,
          confirmed: true,
          discarded: false,
          data,
        };
        ledger.entries.set(actionId, entry);
        out.push({
          kind: "water-break",
          fixtureId: ledger.fixtureId,
          seq,
          active: true,
          clockSec,
          actionId,
          ts,
        });
      }
      continue;
    }

    const side = participantSide(record, data.Participant ?? record.Participant);
    const entry: LedgerEntry = {
      actionId,
      kind,
      side,
      playerId: str(kind === "substitution" ? data.PlayerOutId : data.PlayerId),
      playerInId: str(data.PlayerInId),
      playerOutId: str(data.PlayerOutId),
      onTarget: action === "shot_on_target" || data.OnTarget === true,
      clockSec,
      seq,
      ts,
      confirmed: true,
      discarded: false,
      data,
    };
    ledger.entries.set(actionId, entry);

    const base = {
      fixtureId: ledger.fixtureId,
      seq,
      clockSec,
      actionId,
      ts,
      side: side as "home" | "away",
    };

    switch (kind) {
      case "goal":
        out.push({ kind: "goal", ...base, playerId: entry.playerId });
        break;
      case "yellow":
        out.push({ kind: "card", ...base, color: "yellow", playerId: entry.playerId });
        break;
      case "red":
        out.push({ kind: "card", ...base, color: "red", playerId: entry.playerId });
        break;
      case "corner":
        out.push({ kind: "corner", ...base });
        break;
      case "shot":
        if (ledger.coverageSecondary && !ledger.unreliableSecondary) {
          out.push({ kind: "shot", ...base, onTarget: entry.onTarget });
        }
        break;
      case "danger":
        if (ledger.coverageSecondary && !ledger.unreliableSecondary) {
          out.push({ kind: "danger", ...base });
        }
        break;
      case "penalty":
        out.push({ kind: "penalty", ...base });
        break;
      case "var":
        out.push({ kind: "var", fixtureId: ledger.fixtureId, seq, clockSec, actionId, ts });
        break;
      case "substitution":
        out.push({
          kind: "substitution",
          ...base,
          playerOutId: entry.playerOutId,
          playerInId: entry.playerInId,
        });
        break;
      case "injury":
        out.push({ kind: "injury", ...base, playerId: entry.playerId });
        break;
      default:
        break;
    }
  }

  // Also surface pure meta signals (discard/amend already included).
  for (const sig of signalsFromRawActions(ledger.fixtureId, records)) {
    if (sig.kind === "reliability" && !out.some((s) => s.kind === "reliability" && s.seq === sig.seq)) {
      out.push(sig);
    }
  }

  return out;
}

/** Whether shot/danger/player-secondary rules may fire. */
export function secondaryCoverageOk(ledger: ActionLedgerState, feedFreshness: string): boolean {
  if (ledger.unreliableSecondary) return false;
  if (!ledger.coverageSecondary) return false;
  if (feedFreshness === "stale" || feedFreshness === "paused") return false;
  return true;
}

export function confirmedEntry(ledger: ActionLedgerState, actionId: string): LedgerEntry | undefined {
  const e = ledger.entries.get(actionId);
  if (!e || e.discarded || !e.confirmed) return undefined;
  return e;
}
