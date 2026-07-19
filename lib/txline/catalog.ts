import type { Fixture } from "@/lib/txline/types";

export interface CanonicalTournamentCatalog {
  ok: boolean;
  fixtures: Fixture[];
  groupFixtures: Fixture[];
  knockoutFixtures: Fixture[];
  excluded: Fixture[];
  reason?: string;
}

const pairKey = (fixture: Fixture) =>
  [fixture.home.id, fixture.away.id].sort().join(":");

const fixtureTime = (fixture: Fixture) =>
  Number.isFinite(Date.parse(fixture.kickoff)) ? Date.parse(fixture.kickoff) : 0;

function preferReplacement(current: Fixture, candidate: Fixture): Fixture {
  const currentTime = fixtureTime(current);
  const candidateTime = fixtureTime(candidate);
  if (candidateTime !== currentTime) return candidateTime > currentTime ? candidate : current;
  if (candidate.score && !current.score) return candidate;
  return current;
}

function combinations<T>(items: T[], count: number): T[][] {
  if (count === 0) return [[]];
  if (items.length < count) return [];
  const result: T[][] = [];
  for (let i = 0; i <= items.length - count; i += 1) {
    for (const rest of combinations(items.slice(i + 1), count - 1)) {
      result.push([items[i], ...rest]);
    }
  }
  return result;
}

function completeGroups(rows: Fixture[]): string[][] {
  const edges = new Set(rows.map(pairKey));
  const teams = [...new Set(rows.flatMap((row) => [row.home.id, row.away.id]))].sort();
  const neighbours = new Map<string, Set<string>>();
  for (const row of rows) {
    const home = neighbours.get(row.home.id) ?? new Set<string>();
    const away = neighbours.get(row.away.id) ?? new Set<string>();
    home.add(row.away.id);
    away.add(row.home.id);
    neighbours.set(row.home.id, home);
    neighbours.set(row.away.id, away);
  }

  const cliques = new Map<string, string[]>();
  for (const team of teams) {
    const candidates = [...(neighbours.get(team) ?? [])].filter((id) => id > team).sort();
    for (const trio of combinations(candidates, 3)) {
      const group = [team, ...trio].sort();
      const complete = combinations(group, 2).every(([a, b]) =>
        edges.has([a, b].sort().join(":")),
      );
      if (complete) cliques.set(group.join("|"), group);
    }
  }

  const ordered = [...cliques.values()].sort((a, b) => a.join("|").localeCompare(b.join("|")));
  const cover = (remaining: string[][], chosen: string[][], used: Set<string>): string[][] | null => {
    if (chosen.length === 12) return used.size === 48 ? chosen : null;
    const nextTeam = teams.find((team) => !used.has(team));
    if (!nextTeam) return null;
    for (const group of remaining) {
      if (!group.includes(nextTeam) || group.some((team) => used.has(team))) continue;
      const nextUsed = new Set(used);
      group.forEach((team) => nextUsed.add(team));
      const found = cover(remaining, [...chosen, group], nextUsed);
      if (found) return found;
    }
    return null;
  };

  return cover(ordered, [], new Set()) ?? [];
}

/**
 * Proves the 2026 tournament shape instead of trusting every provider row.
 * Group play must form twelve disjoint K4 graphs (six fixtures each); the
 * knockout phase must contain exactly 32 fixtures. Provider replacement rows
 * and cross-group accidents are returned in `excluded` for observability.
 */
export function canonicalizeTournamentFixtures(
  input: readonly Fixture[],
): CanonicalTournamentCatalog {
  const byGroup = new Map<string, Fixture[]>();
  for (const fixture of input) {
    const key = fixture.groupId ?? "ungrouped";
    const rows = byGroup.get(key) ?? [];
    rows.push(fixture);
    byGroup.set(key, rows);
  }

  const groupBucket = [...byGroup.values()].sort((a, b) => b.length - a.length)[0] ?? [];
  const uniquePairs = new Map<string, Fixture>();
  for (const fixture of groupBucket) {
    const key = pairKey(fixture);
    const current = uniquePairs.get(key);
    uniquePairs.set(key, current ? preferReplacement(current, fixture) : fixture);
  }

  const candidateRows = [...uniquePairs.values()];
  const groups = completeGroups(candidateRows);
  const validPairs = new Set(groups.flatMap((group) => combinations(group, 2).map(([a, b]) => [a, b].sort().join(":"))));
  const groupFixtures = candidateRows.filter((fixture) => validPairs.has(pairKey(fixture)));
  const groupIds = new Set(groupBucket.map((fixture) => fixture.id));
  const knockoutFixtures = input.filter((fixture) => !groupIds.has(fixture.id));
  const selectedIds = new Set([...groupFixtures, ...knockoutFixtures].map((fixture) => fixture.id));
  const excluded = input.filter((fixture) => !selectedIds.has(fixture.id));

  if (groupFixtures.length !== 72 || groups.length !== 12) {
    return {
      ok: false,
      fixtures: [],
      groupFixtures: [],
      knockoutFixtures: [],
      excluded,
      reason: `Could not prove 72 group fixtures (found ${groupFixtures.length})`,
    };
  }
  if (knockoutFixtures.length !== 32) {
    return {
      ok: false,
      fixtures: [],
      groupFixtures: [],
      knockoutFixtures: [],
      excluded,
      reason: `Could not prove 32 knockout fixtures (found ${knockoutFixtures.length})`,
    };
  }

  const fixtures = [...groupFixtures, ...knockoutFixtures].sort(
    (a, b) => fixtureTime(a) - fixtureTime(b),
  );
  return { ok: true, fixtures, groupFixtures, knockoutFixtures, excluded };
}
