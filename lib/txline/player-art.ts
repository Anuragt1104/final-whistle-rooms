/**
 * Exact-ID portrait manifest. This deliberately has no name/surname fallback:
 * a face is returned only when its normative TxLINE player ID is curated.
 * Deployments may inject licensed entries as JSON via TXLINE_PLAYER_PORTRAITS.
 */
const bundled: Readonly<Record<string, string>> = Object.freeze({});

let injected: Record<string, string> | null = null;
function manifest(): Record<string, string> {
  if (injected) return injected;
  try {
    const parsed = JSON.parse(process.env.TXLINE_PLAYER_PORTRAITS ?? "{}") as Record<string, unknown>;
    injected = Object.fromEntries(Object.entries(parsed).filter((entry): entry is [string, string] => typeof entry[1] === "string" && /^https:\/\//.test(entry[1])));
  } catch {
    injected = {};
  }
  return { ...bundled, ...injected };
}

export function portraitForPlayerId(playerId: string): string | undefined {
  return manifest()[playerId];
}

export function __resetPortraitManifestForTests(): void {
  injected = null;
}
