import assert from "node:assert/strict";
import test from "node:test";

import { canonicalizeTournamentFixtures } from "../lib/txline/catalog.ts";

const team = (id) => ({
  id,
  name: id,
  code: id,
  flag: "",
  rating: 75,
});

const fixture = (id, home, away, groupId, kickoff, score = undefined) => ({
  id,
  competition: "World Cup",
  stage: "World Cup",
  groupId,
  home: team(home),
  away: team(away),
  kickoff: new Date(kickoff).toISOString(),
  venue: "—",
  status: "finished",
  score,
});

function validTournamentWithProviderNoise() {
  const rows = [];
  let id = 0;
  const start = Date.UTC(2026, 5, 11);
  for (let group = 0; group < 12; group += 1) {
    const members = [0, 1, 2, 3].map((n) => `G${group}${n}`);
    for (let a = 0; a < members.length; a += 1) {
      for (let b = a + 1; b < members.length; b += 1) {
        rows.push(
          fixture(
            `group-${id++}`,
            members[a],
            members[b],
            "group-stage",
            start + id * 60_000,
            { home: 1, away: 0, minute: 90, clockSeconds: 5400, running: false },
          ),
        );
      }
    }
  }

  // TxLINE currently exposes both of these noise shapes: a replaced duplicate
  // pairing and a cross-group fixture accidentally attached to group stage.
  rows.push(fixture("obsolete-repeat", "G00", "G01", "group-stage", start - 60_000));
  rows.push(fixture("cross-group", "G10", "G20", "group-stage", start + 99_000));

  for (let n = 0; n < 32; n += 1) {
    rows.push(
      fixture(
        `knockout-${n}`,
        `K${n * 2}`,
        `K${n * 2 + 1}`,
        `knockout-${Math.floor(n / 16)}`,
        Date.UTC(2026, 6, 1) + n * 60_000,
      ),
    );
  }
  return rows;
}

test("canonical catalog proves 72 group fixtures and 32 knockout fixtures", () => {
  const result = canonicalizeTournamentFixtures(validTournamentWithProviderNoise());

  assert.equal(result.ok, true);
  assert.equal(result.fixtures.length, 104);
  assert.equal(result.groupFixtures.length, 72);
  assert.equal(result.knockoutFixtures.length, 32);
  assert.deepEqual(
    result.excluded.map((row) => row.id).sort(),
    ["cross-group", "obsolete-repeat"],
  );
});

test("catalog fails closed when a complete 12-group graph cannot be proven", () => {
  const rows = validTournamentWithProviderNoise().filter(
    (row) => row.id !== "group-0" && row.id !== "obsolete-repeat",
  );
  const result = canonicalizeTournamentFixtures(rows);

  assert.equal(result.ok, false);
  assert.equal(result.fixtures.length, 0);
  assert.match(result.reason, /72 group fixtures/i);
});
