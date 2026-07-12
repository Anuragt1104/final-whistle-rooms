/**
 * Fixed World Cup demo roster — Base Stats (0–99) for Player Cards (ADR-0007/0009).
 * Image URLs reuse TheSportsDB-style CDN paths where known.
 */
import type { AxisStats } from "./types";

export interface RosterPlayer {
  id: string;
  name: string;
  teamCode: string;
  teamName: string;
  position: string;
  axes: AxisStats;
  imageUrl?: string;
}

function a(f: number, c: number, cl: number, m: number, au: number): AxisStats {
  return { finishing: f, chaos: c, clutch: cl, marketShock: m, aura: au };
}

export const ROSTER: RosterPlayer[] = [
  { id: "mbappe", name: "Kylian Mbappé", teamCode: "FRA", teamName: "France", position: "FW", axes: a(96, 72, 88, 70, 94) },
  { id: "messi", name: "Lionel Messi", teamCode: "ARG", teamName: "Argentina", position: "FW", axes: a(94, 68, 97, 75, 99) },
  { id: "bellingham", name: "Jude Bellingham", teamCode: "ENG", teamName: "England", position: "MF", axes: a(82, 74, 90, 68, 88) },
  { id: "vinicius", name: "Vinícius Jr", teamCode: "BRA", teamName: "Brazil", position: "FW", axes: a(90, 86, 78, 72, 91) },
  { id: "yamal", name: "Lamine Yamal", teamCode: "ESP", teamName: "Spain", position: "FW", axes: a(84, 80, 76, 78, 92) },
  { id: "saka", name: "Bukayo Saka", teamCode: "ENG", teamName: "England", position: "FW", axes: a(86, 70, 84, 66, 85) },
  { id: "musiala", name: "Jamal Musiala", teamCode: "GER", teamName: "Germany", position: "MF", axes: a(85, 78, 82, 64, 86) },
  { id: "wirtz", name: "Florian Wirtz", teamCode: "GER", teamName: "Germany", position: "MF", axes: a(83, 72, 80, 62, 84) },
  { id: "pedri", name: "Pedri", teamCode: "ESP", teamName: "Spain", position: "MF", axes: a(74, 60, 88, 58, 87) },
  { id: "rodri", name: "Rodri", teamCode: "ESP", teamName: "Spain", position: "MF", axes: a(70, 55, 92, 60, 89) },
  { id: "valverde", name: "Fede Valverde", teamCode: "URU", teamName: "Uruguay", position: "MF", axes: a(78, 82, 86, 65, 83) },
  { id: "alvarez", name: "Julián Álvarez", teamCode: "ARG", teamName: "Argentina", position: "FW", axes: a(88, 70, 85, 63, 82) },
  { id: "lautaro", name: "Lautaro Martínez", teamCode: "ARG", teamName: "Argentina", position: "FW", axes: a(90, 76, 84, 61, 84) },
  { id: "raphinha", name: "Raphinha", teamCode: "BRA", teamName: "Brazil", position: "FW", axes: a(85, 80, 75, 67, 80) },
  { id: "hakimi", name: "Achraf Hakimi", teamCode: "MAR", teamName: "Morocco", position: "DF", axes: a(72, 78, 80, 70, 81) },
  { id: "saliba", name: "William Saliba", teamCode: "FRA", teamName: "France", position: "DF", axes: a(55, 48, 88, 52, 86) },
  { id: "vandijk", name: "Virgil van Dijk", teamCode: "NED", teamName: "Netherlands", position: "DF", axes: a(60, 50, 93, 55, 90) },
  { id: "donnarumma", name: "Gianluigi Donnarumma", teamCode: "ITA", teamName: "Italy", position: "GK", axes: a(40, 45, 91, 50, 85) },
  { id: "courtois", name: "Thibaut Courtois", teamCode: "BEL", teamName: "Belgium", position: "GK", axes: a(38, 42, 94, 48, 88) },
  { id: "kane", name: "Harry Kane", teamCode: "ENG", teamName: "England", position: "FW", axes: a(93, 58, 90, 64, 87) },
  { id: "son", name: "Son Heung-min", teamCode: "KOR", teamName: "South Korea", position: "FW", axes: a(89, 68, 86, 62, 86) },
  { id: "osimen", name: "Victor Osimhen", teamCode: "NGA", teamName: "Nigeria", position: "FW", axes: a(91, 84, 79, 66, 83) },
  { id: "guler", name: "Arda Güler", teamCode: "TUR", teamName: "Turkey", position: "MF", axes: a(80, 74, 72, 71, 84) },
  { id: "frimpong", name: "Jeremiah Frimpong", teamCode: "NED", teamName: "Netherlands", position: "DF", axes: a(68, 82, 74, 60, 78) },
];

export const SKILL_TEMPLATES = [
  {
    id: "ice",
    name: "Ice in Veins",
    description: "+12 Clutch this round",
    effect: { kind: "axisBoost" as const, axis: "clutch" as const, amount: 12 },
  },
  {
    id: "chaos-ball",
    name: "Chaos Ball",
    description: "+15 Chaos this round",
    effect: { kind: "axisBoost" as const, axis: "chaos" as const, amount: 15 },
  },
  {
    id: "market-read",
    name: "Market Read",
    description: "+14 Market Shock this round",
    effect: { kind: "axisBoost" as const, axis: "marketShock" as const, amount: 14 },
  },
  {
    id: "spotlight",
    name: "Spotlight",
    description: "Double Aura this round",
    effect: { kind: "doubleAura" as const },
  },
  {
    id: "steal-attack",
    name: "Steal Attack",
    description: "Become Attacker next round",
    effect: { kind: "swapAttacker" as const },
  },
];

export function pickRosterWeighted(rand: () => number): RosterPlayer {
  // slight bias toward higher aura stars for pack feel
  const idx = Math.min(ROSTER.length - 1, Math.floor(rand() * rand() * ROSTER.length));
  return ROSTER[idx];
}

export function rosterById(id: string): RosterPlayer | undefined {
  return ROSTER.find((p) => p.id === id);
}

export function rosterForTeam(teamCode: string): RosterPlayer[] {
  return ROSTER.filter((p) => p.teamCode === teamCode);
}
