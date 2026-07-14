import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../api/models.dart';
import '../theme.dart';

/// Country name -> ISO 3166-1 alpha-2 code (lowercase), used to load real flag
/// images from flagcdn.com. Keyed by the full name TxLINE / local fixtures use,
/// with common variants. Falls back to the colored badge when a name is unknown.
const Map<String, String> _iso = {
  'argentina': 'ar',
  'brazil': 'br',
  'france': 'fr',
  'spain': 'es',
  'germany': 'de',
  'england': 'gb-eng',
  'scotland': 'gb-sct',
  'wales': 'gb-wls',
  'northern ireland': 'gb-nir',
  'portugal': 'pt',
  'netherlands': 'nl',
  'holland': 'nl',
  'belgium': 'be',
  'croatia': 'hr',
  'uruguay': 'uy',
  'mexico': 'mx',
  'usa': 'us',
  'united states': 'us',
  'japan': 'jp',
  'morocco': 'ma',
  'senegal': 'sn',
  'denmark': 'dk',
  'switzerland': 'ch',
  'serbia': 'rs',
  'poland': 'pl',
  'south korea': 'kr',
  'korea republic': 'kr',
  'korea': 'kr',
  'north korea': 'kp',
  'canada': 'ca',
  'colombia': 'co',
  'nigeria': 'ng',
  'ecuador': 'ec',
  'ghana': 'gh',
  'cameroon': 'cm',
  'australia': 'au',
  'iran': 'ir',
  'ir iran': 'ir',
  'egypt': 'eg',
  'cape verde': 'cv',
  'cabo verde': 'cv',
  'saudi arabia': 'sa',
  'saudi': 'sa',
  'new zealand': 'nz',
  'jordan': 'jo',
  'algeria': 'dz',
  'south africa': 'za',
  'paraguay': 'py',
  'uzbekistan': 'uz',
  'italy': 'it',
  'sweden': 'se',
  'norway': 'no',
  'austria': 'at',
  'ukraine': 'ua',
  'tunisia': 'tn',
  'ivory coast': 'ci',
  "cote d'ivoire": 'ci',
  'côte d’ivoire': 'ci',
  'mali': 'ml',
  'qatar': 'qa',
  'iraq': 'iq',
  'united arab emirates': 'ae',
  'uae': 'ae',
  'peru': 'pe',
  'chile': 'cl',
  'venezuela': 've',
  'bolivia': 'bo',
  'costa rica': 'cr',
  'panama': 'pa',
  'honduras': 'hn',
  'jamaica': 'jm',
  'turkey': 'tr',
  'türkiye': 'tr',
  'greece': 'gr',
  'czech republic': 'cz',
  'czechia': 'cz',
  'romania': 'ro',
  'hungary': 'hu',
  'russia': 'ru',
  'china': 'cn',
  'china pr': 'cn',
  'india': 'in',
  'indonesia': 'id',
  'thailand': 'th',
  'vietnam': 'vn',
  'oman': 'om',
  'kuwait': 'kw',
  'bahrain': 'bh',
  'congo': 'cg',
  'angola': 'ao',
  'zambia': 'zm',
  'kenya': 'ke',
  'uganda': 'ug',
  'tanzania': 'tz',
  'burkina faso': 'bf',
  'guinea': 'gn',
  'gabon': 'ga',
  'benin': 'bj',
  'togo': 'tg',
  'mauritania': 'mr',
  'sudan': 'sd',
  'libya': 'ly',
  'slovenia': 'si',
  'slovakia': 'sk',
  'albania': 'al',
  'north macedonia': 'mk',
  'bosnia and herzegovina': 'ba',
  'bosnia & herzegovina': 'ba',
  'bosnia': 'ba',
  'dr congo': 'cd',
  'congo dr': 'cd',
  'congo-brazzaville': 'cg',
  'montenegro': 'me',
  'finland': 'fi',
  'iceland': 'is',
  'ireland': 'ie',
  'israel': 'il',
  'lebanon': 'lb',
  'syria': 'sy',
  'palestine': 'ps',
  'kosovo': 'xk',
  'georgia': 'ge',
  'armenia': 'am',
  'azerbaijan': 'az',
  'kazakhstan': 'kz',
};

/// ISO code for a team, or null if unknown. Tries a few spelling variants so
/// "Bosnia & Herzegovina" / "Bosnia and Herzegovina" both resolve.
String? isoForTeam(Team t) {
  final base = t.name.trim().toLowerCase();
  for (final n in <String>{
    base,
    base.replaceAll('.', ''),
    base.replaceAll(' & ', ' and '),
    base.replaceAll(' and ', ' & '),
    base.replaceAll(RegExp(r'\s+'), ' '),
  }) {
    final hit = _iso[n];
    if (hit != null) return hit;
  }
  return null;
}

String flagUrl(String iso, {int w = 160}) => 'https://flagcdn.com/w$w/$iso.png';

/// A circular real-flag image with a fallback to the team's colored badge.
class CircleFlag extends StatelessWidget {
  final Team team;
  final double size;
  final bool ring;
  const CircleFlag({
    super.key,
    required this.team,
    this.size = 54,
    this.ring = true,
  });

  @override
  Widget build(BuildContext context) {
    final iso = isoForTeam(team);
    final border = ring
        ? Border.all(
            color: Colors.white.withValues(alpha: 0.85),
            width: size > 30 ? 2 : 1.4,
          )
        : null;
    Widget fallback = _ColorBadge(team: team, size: size, border: border);
    if (iso == null) return fallback;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: border,
        boxShadow: const [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 4,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: ClipOval(
        child: CachedNetworkImage(
          imageUrl: flagUrl(iso, w: size > 30 ? 160 : 80),
          width: size,
          height: size,
          // flags are 3:2 — cover crops to a clean circle
          fit: BoxFit.cover,
          fadeInDuration: const Duration(milliseconds: 120),
          errorWidget: (_, __, ___) => fallback,
          placeholder: (_, __) =>
              _ColorBadge(team: team, size: size, border: null),
        ),
      ),
    );
  }
}

class _ColorBadge extends StatelessWidget {
  final Team team;
  final double size;
  final BoxBorder? border;
  const _ColorBadge({required this.team, required this.size, this.border});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: teamColor(team.code),
        shape: BoxShape.circle,
        border: border,
      ),
      alignment: Alignment.center,
      child: Text(
        team.code,
        style: TextStyle(
          fontFamily: kDisplay,
          color: Colors.white,
          fontSize: size * 0.32,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

/// Small inline flag (for fixture rows) — real image, falls back to emoji.
class InlineFlag extends StatelessWidget {
  final Team team;
  final double size;
  const InlineFlag({super.key, required this.team, this.size = 26});
  @override
  Widget build(BuildContext context) {
    final iso = isoForTeam(team);
    if (iso == null)
      return Text(team.flag, style: TextStyle(fontSize: size * 0.85));
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: CachedNetworkImage(
        imageUrl: flagUrl(iso, w: 80),
        width: size,
        height: size * 0.7,
        fit: BoxFit.cover,
        fadeInDuration: const Duration(milliseconds: 120),
        errorWidget: (_, __, ___) =>
            Text(team.flag, style: TextStyle(fontSize: size * 0.85)),
      ),
    );
  }
}
