import 'dart:math';

import '../api/models.dart';
import 'squads.dart';

/// Real squad-backed player names for goals and Man-of-the-Match, so the sim
/// says "GOAL — Mbappé!" for France instead of a random surname. Seeded per
/// fixture+side so the same match always leans on the same players.
List<String> roster(Fixture f, String side) {
  final team = side == 'home' ? f.home : f.away;
  final xi = squadFor(team).startingXI.where((p) => p.pos != 'GK').toList();
  final rng = Random((f.id + side).hashCode);
  // attackers first (they get the goals), with a seeded shuffle inside lines
  final fw = xi.where((p) => p.pos == 'FW').toList()..shuffle(rng);
  final mf = xi.where((p) => p.pos == 'MF').toList()..shuffle(rng);
  final df = xi.where((p) => p.pos == 'DF').toList()..shuffle(rng);
  return [...fw, ...mf, ...df].map((p) => p.name).take(6).toList();
}

/// Name for the Nth goal a side scores.
String scorerName(Fixture f, String side, int goalIndexForSide) {
  final r = roster(f, side);
  return r[goalIndexForSide % r.length];
}

List<SquadPlayer> _xi(Fixture f, String side) =>
    squadFor(side == 'home' ? f.home : f.away).startingXI;

/// Who takes the Nth corner — set-piece midfielders first, then wide forwards.
/// Seeded per fixture+side so every surface names the same taker.
String cornerTaker(Fixture f, String side, int idx) {
  final xi = _xi(f, side);
  final rng = Random((f.id + side + 'ck').hashCode);
  final mf = xi.where((p) => p.pos == 'MF').toList()..shuffle(rng);
  final fw = xi.where((p) => p.pos == 'FW').toList()..shuffle(rng);
  final pool = [...mf.take(2), ...fw.take(1)];
  if (pool.isEmpty) return scorerName(f, side, idx);
  return pool[idx % pool.length].name;
}

/// Who picks up the Nth booking — defenders 3×, midfielders 2×, forwards 1×.
String bookedPlayer(Fixture f, String side, int idx) {
  final xi = _xi(f, side);
  final rng = Random((f.id + side + 'yc').hashCode);
  final pool = <SquadPlayer>[
    for (final p in xi.where((p) => p.pos == 'DF')) ...[p, p, p],
    for (final p in xi.where((p) => p.pos == 'MF')) ...[p, p],
    ...xi.where((p) => p.pos == 'FW'),
  ]..shuffle(rng);
  if (pool.isEmpty) return scorerName(f, side, idx);
  return pool[idx % pool.length].name;
}

/// The side's goalkeeper.
String keeperName(Fixture f, String side) {
  final team = side == 'home' ? f.home : f.away;
  final squad = squadFor(team);
  for (final p in squad.startingXI) {
    if (p.pos == 'GK') return p.name;
  }
  for (final p in squad.players) {
    if (p.pos == 'GK') return p.name;
  }
  return scorerName(f, side, 0);
}

/// Penalty-shootout taker order: forwards, then midfielders, then defenders —
/// seeded shuffle within each line, cycling for sudden death.
String penaltyTaker(Fixture f, String side, int kickIdx) {
  final xi = _xi(f, side);
  final rng = Random((f.id + side + 'pen').hashCode);
  final fw = xi.where((p) => p.pos == 'FW').toList()..shuffle(rng);
  final mf = xi.where((p) => p.pos == 'MF').toList()..shuffle(rng);
  final df = xi.where((p) => p.pos == 'DF').toList()..shuffle(rng);
  final order = [...fw, ...mf, ...df];
  if (order.isEmpty) return scorerName(f, side, kickIdx);
  return order[kickIdx % order.length].name;
}
