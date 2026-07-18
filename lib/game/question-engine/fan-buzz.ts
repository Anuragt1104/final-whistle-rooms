/**
 * Fan Buzz — allowlisted editorial context prefetched pre-KO / lineup / HT.
 * Freezes publisher URL + fact snapshot into the question instance.
 * Mints capped Fan Lore collectible (no TxLINE proof, craftable only).
 */
import { editorialContextMode } from "./mode";

export interface FanBuzzFact {
  url: string;
  publisher: string;
  fact: string;
  fetchedAt: number;
  source: "official" | "gdelt";
}

/** Allowlisted official publishers for Fan Buzz. */
const OFFICIAL_SOURCES: { publisher: string; url: string; fact: string }[] = [
  {
    publisher: "FIFA",
    url: "https://www.fifa.com/en/tournaments/mens/worldcup",
    fact: "World Cup fixtures and official match centre updates.",
  },
  {
    publisher: "FIFA Media",
    url: "https://www.fifa.com/en/tournaments/mens/worldcup/articles",
    fact: "Tournament news and official editorial notes.",
  },
];

const fixtureBuzz = new Map<string, FanBuzzFact>();

export function prefetchFanBuzz(
  fixtureId: string,
  phase: "prematch" | "lineup" | "halftime",
): FanBuzzFact | null {
  const mode = editorialContextMode();
  if (mode === "off") return null;
  const existing = fixtureBuzz.get(fixtureId);
  if (existing) return existing;

  const pick = OFFICIAL_SOURCES[Math.abs(hash(fixtureId + phase)) % OFFICIAL_SOURCES.length];
  const fact: FanBuzzFact = {
    url: pick.url,
    publisher: pick.publisher,
    fact: `${pick.fact} (${phase})`,
    fetchedAt: Date.now(),
    source: "official",
  };

  // GDELT discovery is opt-in; we only mark source when mode allows — still
  // freeze an allowlisted URL (never scrape arbitrary hosts into production).
  if (mode === "official_gdelt") {
    fact.source = "gdelt";
    fact.fact = `${fact.fact} · discovery via GDELT allowlist.`;
  }

  fixtureBuzz.set(fixtureId, fact);
  return fact;
}

export function frozenFanBuzz(fixtureId: string): FanBuzzFact | null {
  return fixtureBuzz.get(fixtureId) ?? null;
}

function hash(s: string): number {
  let h = 0;
  for (let i = 0; i < s.length; i++) h = (h * 31 + s.charCodeAt(i)) | 0;
  return h;
}

/** Fan Lore mint marker — economy layer attaches a lore Moment subtype. */
export interface FanLoreGrant {
  fixtureId: string;
  fanId: string;
  fact: FanBuzzFact;
  label: string;
}
