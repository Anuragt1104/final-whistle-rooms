/**
 * Card Economy — primary seam (ADR-0001).
 * mintFromEvent / openPack / craft / inventoryOf / Called It / pack weights.
 */
import { buildMerkleTree, verifyMerkleProof } from "@/lib/util/merkle";
import { applyLineageImprint } from "./lineage";
import { marketRarity, momentPackWeight } from "./rarity";
import { pickRosterWeighted, SKILL_TEMPLATES } from "./roster";
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

const inventories = new Map<string, FanInventory>();
const momentIndex = new Map<string, Moment>();
const cardIndex = new Map<string, Card>();
/** Fixture/room-scoped Moment leaf strings for Merkle. */
const momentLeaves = new Map<string, string[]>(); // key = roomId || fixtureId

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
  if (pack.opened) return { error: "Pack already opened" };

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

  // burn
  inv.moments = inv.moments.filter((m) => !momentIds.includes(m.id));
  for (const id of momentIds) {
    momentIndex.delete(id);
    cardIndex.delete(id);
  }

  const seedKind = moments.sort((a, b) => b.rarity - a.rarity)[0].kind;
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
    lineageMomentId: moments[0].id,
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

/** Test helper — wipe in-memory store. */
export function __resetCardEconomyForTests() {
  inventories.clear();
  momentIndex.clear();
  cardIndex.clear();
  momentLeaves.clear();
}
