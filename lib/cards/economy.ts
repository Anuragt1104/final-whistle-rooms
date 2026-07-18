/**
 * Card Economy — primary seam (ADR-0001).
 * mintFromEvent / openPack / craft / inventoryOf / Called It / pack weights.
 */
import { buildMerkleTree, verifyMerkleProof } from "@/lib/util/merkle";
import { pickRosterWeighted, SKILL_TEMPLATES, ROSTER } from "./roster";
import { applyLineageImprint } from "./lineage";
import { marketRarity, momentPackWeight } from "./rarity";
import type {
  Card,
  FanInventory,
  MintContext,
  Moment,
  MomentKind,
  OddsSandwich,
  PackGrant,
  PlayerCard,
  SkillCard,
} from "./types";

function uid(prefix: string): string {
  return `${prefix}_${Math.random().toString(36).slice(2, 10)}${Date.now().toString(36).slice(-4)}`;
}

function lineageSnapshot(moment: Moment | undefined) {
  if (!moment) return undefined;
  return {
    parentMomentId: moment.id,
    fixtureId: moment.fixtureId,
    kind: moment.kind,
    teamCode: moment.teamCode,
    rarity: moment.rarity,
    calledIt: moment.calledIt,
    sourceEventId: moment.sourceEventId,
    oddsSandwich: structuredClone(moment.oddsSandwich),
    proofRef: moment.leafData,
  } as const;
}

type EconomyStore = {
  inventories: Map<string, FanInventory>;
  momentIndex: Map<string, Moment>;
  cardIndex: Map<string, Card>;
  /** Fixture/room-scoped Moment leaf strings for Merkle. */
  momentLeaves: Map<string, string[]>;
};

// Next compiles route handlers into separate module graphs. Keep the hackathon
// economy process-scoped, but make every route graph share that one instance.
const economyGlobal = globalThis as unknown as { __fwr_economy?: EconomyStore };
const economy =
  economyGlobal.__fwr_economy ??
  (economyGlobal.__fwr_economy = {
    inventories: new Map(),
    momentIndex: new Map(),
    cardIndex: new Map(),
    momentLeaves: new Map(),
  });
const { inventories, momentIndex, cardIndex, momentLeaves } = economy;

function emptyInv(fanId: string): FanInventory {
  return { fanId, moments: [], players: [], skills: [], packs: [], packWeightBonus: 0 };
}

export function inventoryOf(fanId: string): FanInventory {
  let inv = inventories.get(fanId);
  if (!inv) {
    inv = emptyInv(fanId);
    inventories.set(fanId, inv);
  }
  return inv;
}

function indexInventory(inv: FanInventory) {
  for (const moment of inv.moments) {
    momentIndex.set(moment.id, moment);
    cardIndex.set(moment.id, moment);
  }
  for (const player of inv.players) cardIndex.set(player.id, player);
  for (const skill of inv.skills) cardIndex.set(skill.id, skill);
}

/** Apply a durable inventory row into the in-memory maps after Postgres hydrate. */
export function applyDurableInventory(fanId: string, inventory: unknown) {
  const inv = inventory as FanInventory;
  inventories.set(fanId, inv);
  indexInventory(inv);
}

export function applyDurableLeaves(leafKey: string, leaves: string[]) {
  momentLeaves.set(leafKey, leaves);
}

export function getMoment(id: string): Moment | undefined {
  return momentIndex.get(id);
}

export function getCard(id: string): Card | undefined {
  return cardIndex.get(id);
}

/** Register a card into the global index (bot ephemeral cards, etc.). */
export function registerCard(card: Card) {
  cardIndex.set(card.id, card);
}

/**
 * Move a card between fan inventories (marketplace settlement). Returns the
 * card with its new owner, or null when the seller doesn't hold it.
 */
export function transferCard(cardId: string, fromFanId: string, toFanId: string): Card | null {
  const from = inventoryOf(fromFanId);
  const to = inventoryOf(toFanId);
  const pull = <T extends Card>(arr: T[]): T | null => {
    const i = arr.findIndex((c) => c.id === cardId);
    return i >= 0 ? arr.splice(i, 1)[0] : null;
  };
  const card: Card | null = pull(from.moments) ?? pull(from.players) ?? pull(from.skills);
  if (!card) return null;
  const moved = { ...card, ownerId: toFanId } as Card;
  if (moved.type === "moment") to.moments.push(moved);
  else if (moved.type === "player") to.players.push(moved);
  else to.skills.push(moved);
  cardIndex.set(moved.id, moved);
  return moved;
}

/** Grant pack-weight (World Cup Pass "bonus pack" rewards). */
export function grantPackWeight(fanId: string, amount: number) {
  inventoryOf(fanId).packWeightBonus += amount;
}

function significantKind(kind: string): MomentKind | null {
  if (kind === "goal" || kind === "red" || kind === "yellow" || kind === "corner") return kind;
  if (kind === "market-swing" || kind === "chaos") return kind;
  return null;
}

/** Mint a Moment for one Fan from a significant Match Event. */
export function mintFromEvent(ctx: MintContext): Moment | null {
  const kind = significantKind(ctx.event.kind);
  if (!kind) return null;

  const prior =
    ctx.event.side === "away"
      ? ctx.oddsSandwich.before.away
      : ctx.event.side === "home"
        ? ctx.oddsSandwich.before.home
        : ctx.priorHomeProb;

  const rarity = marketRarity(kind, prior, ctx.oddsSandwich);
  const leafData = [
    "moment",
    ctx.fixtureId,
    ctx.event.seq,
    ctx.event.minute,
    kind,
    ctx.event.side ?? "-",
    rarity,
    ctx.fanId,
  ].join(":");

  const moment: Moment = {
    id: uid("mom"),
    type: "moment",
    ownerId: ctx.fanId,
    fixtureId: ctx.fixtureId,
    matchLabel: ctx.matchLabel,
    kind,
    side: ctx.event.side,
    minute: ctx.event.minute,
    label: ctx.event.label,
    sourceEventId: ctx.event.sourceEventId,
    playerId: ctx.event.playerId,
    playerName: ctx.event.playerName,
    teamCode: ctx.event.teamCode,
    imageUrl: ctx.event.imageUrl,
    artKey: ctx.event.artKey,
    rarity,
    oddsSandwich: ctx.oddsSandwich,
    calledIt: false,
    leafData,
    roomId: ctx.roomId,
    createdAt: Date.now(),
  };

  const inv = inventoryOf(ctx.fanId);
  inv.moments.push(moment);
  momentIndex.set(moment.id, moment);
  cardIndex.set(moment.id, moment);

  const leafKey = ctx.roomId ?? ctx.fixtureId;
  const leaves = momentLeaves.get(leafKey) ?? [];
  leaves.push(leafData);
  momentLeaves.set(leafKey, leaves);

  // Auto-grant an unopened pack charge weighted by rarity + party multiplier
  const mult = ctx.partyMultiplier && ctx.partyMultiplier > 1 ? ctx.partyMultiplier : 1;
  const weight = momentPackWeight(rarity, false) * mult;
  inv.packs.push({
    id: uid("pack"),
    ownerId: ctx.fanId,
    weight,
    momentIds: [moment.id],
    opened: false,
    cards: [],
    createdAt: Date.now(),
    roomId: ctx.roomId,
  });

  return moment;
}

const fanLoreCap = new Map<string, number>(); // `${fanId}:${fixtureId}` -> count

/**
 * Mint a capped Fan Lore collectible from editorial Fan Buzz.
 * No TxLINE proof badge, no auto-pack — craftable in the normal 3-card craft only.
 */
export function mintFanLore(opts: {
  fanId: string;
  fixtureId: string;
  matchLabel: string;
  fact: string;
  publisherUrl: string;
  roomId?: string;
}): Moment | null {
  const key = `${opts.fanId}:${opts.fixtureId}`;
  const n = fanLoreCap.get(key) ?? 0;
  if (n >= 1) return null; // one Fan Lore per fan per fixture
  fanLoreCap.set(key, n + 1);

  const leafData = ["fan-lore", opts.fixtureId, opts.fanId, opts.publisherUrl].join(":");
  const moment: Moment = {
    id: uid("lore"),
    type: "moment",
    ownerId: opts.fanId,
    fixtureId: opts.fixtureId,
    matchLabel: opts.matchLabel,
    kind: "fan-lore",
    minute: 0,
    label: opts.fact.slice(0, 80),
    sourceEventId: `fan-lore:${opts.publisherUrl}`,
    rarity: 1,
    oddsSandwich: {
      before: { home: 0.33, draw: 0.34, away: 0.33 },
      after: { home: 0.33, draw: 0.34, away: 0.33 },
    },
    calledIt: false,
    leafData,
    roomId: opts.roomId,
    createdAt: Date.now(),
  };
  const inv = inventoryOf(opts.fanId);
  inv.moments.push(moment);
  momentIndex.set(moment.id, moment);
  cardIndex.set(moment.id, moment);
  // Intentionally no pack grant — Fan Lore is craft-only fuel.
  return moment;
}

/**
 * Mint Moments for every Fan in a room on a significant event.
 * Returns minted Moments (one per fan).
 */
export function mintForRoomFans(
  fanIds: string[],
  base: Omit<MintContext, "fanId">,
): Moment[] {
  const out: Moment[] = [];
  for (const fanId of fanIds) {
    const m = mintFromEvent({ ...base, fanId });
    if (m) out.push(m);
  }
  return out;
}

/** Stamp Called It on Moments related to a correct Micro-Play and boost pack weight. */
export function stampCalledIt(
  fanId: string,
  opts: { fixtureId: string; kinds?: MomentKind[]; sinceMinute?: number },
): Moment[] {
  const inv = inventoryOf(fanId);
  const stamped: Moment[] = [];
  for (const m of inv.moments) {
    if (m.fixtureId !== opts.fixtureId) continue;
    if (m.calledIt) continue;
    if (opts.kinds && !opts.kinds.includes(m.kind)) continue;
    if (opts.sinceMinute !== undefined && m.minute < opts.sinceMinute) continue;
    m.calledIt = true;
    stamped.push(m);
    inv.packWeightBonus += 0.25;
    // boost any unopened pack tied to this moment
    for (const p of inv.packs) {
      if (!p.opened && p.momentIds.includes(m.id)) {
        p.weight *= 1.35;
      }
    }
  }
  return stamped;
}

export function openPack(fanId: string, packId: string, rand: () => number = Math.random): PackGrant | { error: string } {
  const inv = inventoryOf(fanId);
  const pack = inv.packs.find((p) => p.id === packId);
  if (!pack) return { error: "Pack not found" };
  // Opening is keyed by the Pack itself. A timed-out client may safely retry
  // and must see the exact same reveal instead of losing the cards behind a
  // misleading "already opened" error.
  if (pack.opened) return pack;

  // Fold Fan pack-weight bonus (Called It / Pass rewards) into this open, then consume it.
  if (inv.packWeightBonus > 0) {
    pack.weight += inv.packWeightBonus;
    inv.packWeightBonus = 0;
  }

  const parentMoment = pack.momentIds[0] ? momentIndex.get(pack.momentIds[0]) : undefined;
  const roster = pickRosterWeighted(rand);
  const axes = parentMoment
    ? applyLineageImprint({ ...roster.axes }, parentMoment.kind)
    : { ...roster.axes };

  const lineageLeaf = [
    "lineage",
    roster.id,
    parentMoment?.id ?? "none",
    fanId,
    Date.now(),
  ].join(":");

  const player: PlayerCard = {
    id: uid("plr"),
    type: "player",
    ownerId: fanId,
    playerId: roster.id,
    name: roster.name,
    teamCode: roster.teamCode,
    teamName: roster.teamName,
    position: roster.position,
    imageUrl: roster.imageUrl,
    axes,
    lineageMomentId: parentMoment?.id,
    lineage: lineageSnapshot(parentMoment),
    leafData: lineageLeaf,
    createdAt: Date.now(),
  };

  const cards: Card[] = [player];

  // ~30% chance of a Skill card at weight >= 2
  if (pack.weight >= 2 && rand() < 0.35) {
    const tmpl = SKILL_TEMPLATES[Math.floor(rand() * SKILL_TEMPLATES.length)];
    const skill: SkillCard = {
      id: uid("skl"),
      type: "skill",
      ownerId: fanId,
      name: tmpl.name,
      description: tmpl.description,
      effect: tmpl.effect,
      leafData: `skill:${tmpl.id}:${fanId}:${Date.now()}`,
      createdAt: Date.now(),
    };
    cards.push(skill);
    inv.skills.push(skill);
    cardIndex.set(skill.id, skill);
  }

  pack.opened = true;
  pack.cards = cards;
  inv.players.push(player);
  cardIndex.set(player.id, player);

  if (parentMoment) {
    const leafKey = parentMoment.roomId ?? parentMoment.fixtureId;
    const leaves = momentLeaves.get(leafKey) ?? [];
    leaves.push(lineageLeaf);
    momentLeaves.set(leafKey, leaves);
  }

  return pack;
}

/** Craft a Player Card by burning Moments (need 3 of same rarity, or 2×5★). */
export function craft(
  fanId: string,
  momentIds: string[],
  rand: () => number = Math.random,
): PlayerCard | { error: string } {
  const inv = inventoryOf(fanId);
  if (momentIds.length < 2) return { error: "Need at least 2 Moments" };

  const moments: Moment[] = [];
  for (const id of momentIds) {
    const m = inv.moments.find((x) => x.id === id);
    if (!m) return { error: `Moment ${id} not in inventory` };
    moments.push(m);
  }

  const rarities = moments.map((m) => m.rarity);
  const minR = Math.min(...rarities);
  if (moments.length === 2 && !(rarities.every((r) => r >= 5))) {
    return { error: "Two-Moment craft requires two 5★ Moments" };
  }
  if (moments.length >= 3 && rarities.some((r) => r < minR)) {
    /* ok — burn mixed; use min rarity for imprint seed */
  }

  // Capture immutable provenance before the source records are burned.
  const parent = [...moments].sort((a, b) => b.rarity - a.rarity)[0];
  const lineage = lineageSnapshot(parent);

  // burn
  inv.moments = inv.moments.filter((m) => !momentIds.includes(m.id));
  for (const id of momentIds) {
    momentIndex.delete(id);
    cardIndex.delete(id);
  }

  const seedKind = parent.kind;
  const roster = pickRosterWeighted(rand);
  const axes = applyLineageImprint({ ...roster.axes }, seedKind);
  const leafData = `craft:${roster.id}:${momentIds.join("+")}:${fanId}`;

  const player: PlayerCard = {
    id: uid("plr"),
    type: "player",
    ownerId: fanId,
    playerId: roster.id,
    name: roster.name,
    teamCode: roster.teamCode,
    teamName: roster.teamName,
    position: roster.position,
    imageUrl: roster.imageUrl,
    axes,
    lineageMomentId: lineage?.parentMomentId,
    lineage,
    leafData,
    createdAt: Date.now(),
  };

  inv.players.push(player);
  cardIndex.set(player.id, player);
  return player;
}

export function momentProof(momentId: string): {
  moment: Moment;
  root: string;
  proof: ReturnType<ReturnType<typeof buildMerkleTree>["proof"]>;
  leafIndex: number;
  verified: boolean;
} | null {
  const moment = momentIndex.get(momentId);
  if (!moment) return null;
  const leafKey = moment.roomId ?? moment.fixtureId;
  const leaves = momentLeaves.get(leafKey) ?? [moment.leafData];
  const tree = buildMerkleTree(leaves);
  const leafIndex = leaves.indexOf(moment.leafData);
  if (leafIndex < 0) return null;
  const proof = tree.proof(leafIndex);
  const verified = verifyMerkleProof(moment.leafData, proof, tree.root);
  return { moment, root: tree.root, proof, leafIndex, verified };
}

export function partyDropMultiplier(memberCount: number): number {
  if (memberCount >= 4) return 1.5;
  if (memberCount >= 2) return 1.25;
  return 1;
}

/** Build OddsSandwich helper from win chances (0..1). */
export function sandwichFromWin(
  before: { home: number; draw: number; away: number },
  after: { home: number; draw: number; away: number },
): OddsSandwich {
  return { before, after };
}

/**
 * Demo / test seed — fills inventory so Album, Craft, and Duels are playable
 * without a live mint. Idempotent once the fan has ≥3 Player Cards and ≥1 Moment.
 */
export function seedDemoInventory(fanId: string): { inventory: FanInventory; seeded: boolean } {
  const inv = inventoryOf(fanId);
  if (inv.players.length >= 3 && inv.moments.length > 0) {
    return { inventory: inv, seeded: false };
  }
  // Wipe partial junk so a clean demo set is always available for Arena testing.
  if (inv.moments.length > 0 || inv.players.length > 0 || inv.packs.length > 0) {
    for (const m of inv.moments) {
      momentIndex.delete(m.id);
      cardIndex.delete(m.id);
    }
    for (const p of inv.players) cardIndex.delete(p.id);
    for (const s of inv.skills) cardIndex.delete(s.id);
    inv.moments = [];
    inv.players = [];
    inv.skills = [];
    inv.packs = [];
  }

  const fixtureId = "demo-fixture";
  const matchLabel = "FRA vs ARG (demo)";
  const roomId = "demo-room";
  const leafKey = roomId;
  const leaves: string[] = [];

  const specs: Array<{
    kind: MomentKind;
    side: "home" | "away";
    minute: number;
    label: string;
    prior: number;
    sandwich: OddsSandwich;
    calledIt?: boolean;
  }> = [
    {
      kind: "goal",
      side: "home",
      minute: 12,
      label: "Goal — France",
      prior: 0.48,
      sandwich: sandwichFromWin(
        { home: 0.48, draw: 0.28, away: 0.24 },
        { home: 0.62, draw: 0.22, away: 0.16 },
      ),
    },
    {
      kind: "goal",
      side: "away",
      minute: 34,
      label: "Goal — Argentina",
      prior: 0.22,
      sandwich: sandwichFromWin(
        { home: 0.55, draw: 0.25, away: 0.2 },
        { home: 0.4, draw: 0.28, away: 0.32 },
      ),
      calledIt: true,
    },
    {
      kind: "red",
      side: "away",
      minute: 51,
      label: "Red card — Argentina",
      prior: 0.12,
      sandwich: sandwichFromWin(
        { home: 0.5, draw: 0.27, away: 0.23 },
        { home: 0.68, draw: 0.2, away: 0.12 },
      ),
    },
    {
      kind: "corner",
      side: "home",
      minute: 67,
      label: "Corner storm — France",
      prior: 0.55,
      sandwich: sandwichFromWin(
        { home: 0.55, draw: 0.25, away: 0.2 },
        { home: 0.57, draw: 0.24, away: 0.19 },
      ),
    },
    {
      kind: "market-swing",
      side: "home",
      minute: 78,
      label: "Market swing",
      prior: 0.35,
      sandwich: sandwichFromWin(
        { home: 0.35, draw: 0.3, away: 0.35 },
        { home: 0.58, draw: 0.24, away: 0.18 },
      ),
      calledIt: true,
    },
  ];

  const momentIds: string[] = [];
  specs.forEach((s, i) => {
    const rarity = marketRarity(s.kind, s.prior, s.sandwich);
    const leafData = ["moment", fixtureId, i + 1, s.minute, s.kind, s.side, rarity, fanId].join(":");
    const moment: Moment = {
      id: uid("mom"),
      type: "moment",
      ownerId: fanId,
      fixtureId,
      matchLabel,
      kind: s.kind,
      side: s.side,
      minute: s.minute,
      label: s.label,
      rarity,
      oddsSandwich: s.sandwich,
      calledIt: !!s.calledIt,
      leafData,
      roomId,
      createdAt: Date.now() - (specs.length - i) * 60_000,
    };
    inv.moments.push(moment);
    momentIndex.set(moment.id, moment);
    cardIndex.set(moment.id, moment);
    leaves.push(leafData);
    momentIds.push(moment.id);
  });
  momentLeaves.set(leafKey, leaves);

  // Exactly 2 unopened packs (tied to first two moments)
  for (let i = 0; i < 2; i++) {
    const m = inv.moments[i];
    inv.packs.push({
      id: uid("pack"),
      ownerId: fanId,
      weight: momentPackWeight(m.rarity, m.calledIt) + (i === 1 ? 1 : 0),
      momentIds: [m.id],
      opened: false,
      cards: [],
      createdAt: Date.now(),
      roomId,
    });
  }

  // 3 ready Player Cards for Trump Duel
  const starters = [ROSTER[0], ROSTER[1], ROSTER[2]]; // Mbappé, Messi, Bellingham
  starters.forEach((roster, i) => {
    const parent = inv.moments[i];
    const axes = applyLineageImprint({ ...roster.axes }, parent.kind);
    const leafData = ["lineage", roster.id, parent.id, fanId, Date.now()].join(":");
    const player: PlayerCard = {
      id: uid("plr"),
      type: "player",
      ownerId: fanId,
      playerId: roster.id,
      name: roster.name,
      teamCode: roster.teamCode,
      teamName: roster.teamName,
      position: roster.position,
      imageUrl: roster.imageUrl,
      axes,
      lineageMomentId: parent.id,
      lineage: lineageSnapshot(parent),
      leafData,
      createdAt: Date.now(),
    };
    inv.players.push(player);
    cardIndex.set(player.id, player);
    leaves.push(leafData);
  });

  const tmpl = SKILL_TEMPLATES[0];
  const skill: SkillCard = {
    id: uid("skl"),
    type: "skill",
    ownerId: fanId,
    name: tmpl.name,
    description: tmpl.description,
    effect: tmpl.effect,
    leafData: `skill:${tmpl.id}:${fanId}:demo`,
    createdAt: Date.now(),
  };
  inv.skills.push(skill);
  cardIndex.set(skill.id, skill);
  inv.packWeightBonus = 0.5;

  return { inventory: inv, seeded: true };
}

/** Test helper — wipe in-memory store. */
export function __resetCardEconomyForTests() {
  inventories.clear();
  momentIndex.clear();
  cardIndex.clear();
  momentLeaves.clear();
}
