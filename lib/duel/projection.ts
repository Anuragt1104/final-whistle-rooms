import { AuthoritativeDuelEngine } from "./engine";
import type { DuelState, DuelView } from "./types";

const engine = new AuthoritativeDuelEngine();

/** Actor-specific DuelView with opponent secrets redacted until reveal. */
export function projectDuelView(state: DuelState, actorId: string): DuelView {
  return engine.view(state, actorId);
}
