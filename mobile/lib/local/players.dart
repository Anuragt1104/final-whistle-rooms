import 'dart:math';

/// Plausible player surnames so goals and Man-of-the-Match have real names.
/// Seeded per fixture+side so the same match always fields the same XI.
const _pool = [
  'Saka', 'Ødegaard', 'Núñez', 'Rice', 'Bellingham', 'Mbappé', 'Vinícius', 'Musiala',
  'Pedri', 'Foden', 'Haaland', 'Rodri', 'Griezmann', 'Kane', 'Son', 'Modrić',
  'Bruno', 'Leão', 'Yamal', 'Gakpo', 'Wirtz', 'Olmo', 'Lautaro', 'Álvarez',
  'Osimhen', 'Salah', 'Doku', 'Gnabry', 'Kvara', 'Valverde', 'Dembélé', 'Gündoğan',
];

List<String> roster(String fixtureId, String side) {
  final rng = Random((fixtureId + side).hashCode);
  final pool = [..._pool]..shuffle(rng);
  return pool.take(6).toList();
}

/// Name for the Nth goal a side scores.
String scorerName(String fixtureId, String side, int goalIndexForSide) {
  final r = roster(fixtureId, side);
  return r[goalIndexForSide % r.length];
}
