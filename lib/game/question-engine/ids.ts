import { RULE_VERSION } from "./types";

/** Stable question id: q:{fixtureId}:{ruleVersion}:{ruleId}:{openSeq}:{ordinal} */
export function questionId(
  fixtureId: string,
  ruleId: string,
  openSeq: number,
  ordinal: number,
  ruleVersion = RULE_VERSION,
): string {
  return `q:${fixtureId}:${ruleVersion}:${ruleId}:${openSeq}:${ordinal}`;
}

/** FNV-1a 32-bit — deterministic tie-break / hash, no Math.random. */
export function stableHash(input: string): number {
  let h = 0x811c9dc5;
  for (let i = 0; i < input.length; i++) {
    h ^= input.charCodeAt(i);
    h = Math.imul(h, 0x01000193);
  }
  return h >>> 0;
}
