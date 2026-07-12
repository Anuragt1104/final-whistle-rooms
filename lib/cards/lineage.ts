/** Lineage Imprint — permanent Axis boost from Moment kind (ADR-0009). */
import type { Axis, AxisStats, MomentKind } from "./types";

export function imprintAxis(kind: MomentKind): Axis {
  switch (kind) {
    case "goal":
      return "finishing";
    case "red":
    case "yellow":
    case "chaos":
      return "chaos";
    case "corner":
      return "clutch";
    case "market-swing":
      return "marketShock";
    default:
      return "aura";
  }
}

const IMPRINT_BOOST = 8;

export function applyLineageImprint(base: AxisStats, kind: MomentKind): AxisStats {
  const axis = imprintAxis(kind);
  const next = { ...base };
  next[axis] = Math.min(99, next[axis] + IMPRINT_BOOST);
  return next;
}
