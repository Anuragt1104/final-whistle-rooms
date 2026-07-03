import 'dart:math';

import '../api/models.dart';

/// On-device squad database for the 48-team World Cup — starting XI (in
/// formation order: GK, defenders, midfielders, forwards) plus bench, kit
/// numbers, positions, formation and coach for every team. This is what powers
/// the FotMob-style line-ups, player ratings, scorers and the Golden Boot race,
/// fully offline.
class SquadPlayer {
  final int number;
  final String name;
  final String pos; // GK | DF | MF | FW
  const SquadPlayer(this.number, this.name, this.pos);
}

class TeamSquad {
  final String formation; // e.g. '4-3-3'
  final String coach;
  final List<SquadPlayer> players; // first 11 = starting XI, rest = bench

  const TeamSquad(this.formation, this.coach, this.players);

  List<SquadPlayer> get startingXI => players.take(11).toList();
  List<SquadPlayer> get bench => players.skip(11).toList();
}

SquadPlayer _p(String s) {
  final parts = s.split('|'); // 'pos|num|name'
  return SquadPlayer(int.parse(parts[1]), parts[2], parts[0]);
}

TeamSquad _sq(String formation, String coach, List<String> raw) =>
    TeamSquad(formation, coach, raw.map(_p).toList());

final Map<String, TeamSquad> _squads = {
  // ---------------- Hosts ----------------
  'MEX': _sq('4-3-3', 'Javier Aguirre', [
    'GK|13|Malagón', 'DF|2|Sánchez', 'DF|3|Montes', 'DF|15|Vásquez', 'DF|23|Gallardo',
    'MF|4|E. Álvarez', 'MF|6|Romo', 'MF|14|Pineda', 'FW|11|Lozano', 'FW|9|R. Jiménez', 'FW|22|Vega',
    'GK|1|Ochoa', 'DF|5|Araujo', 'MF|18|Chávez', 'FW|10|Gímenez',
  ]),
  'USA': _sq('4-2-3-1', 'Mauricio Pochettino', [
    'GK|1|Turner', 'DF|2|Dest', 'DF|3|Ream', 'DF|13|Richards', 'DF|5|Robinson',
    'MF|4|Adams', 'MF|6|Musah', 'MF|10|Pulisic', 'MF|11|Weah', 'MF|7|Reyna', 'FW|9|Balogun',
    'GK|25|Schulte', 'DF|12|Scally', 'MF|8|McKennie', 'FW|16|Pepi',
  ]),
  'CAN': _sq('3-4-3', 'Jesse Marsch', [
    'GK|18|St. Clair', 'DF|4|Cornelius', 'DF|5|Bombito', 'DF|19|Waterman',
    'MF|2|Johnston', 'MF|7|Eustáquio', 'MF|13|Kone', 'MF|3|A. Davies',
    'FW|11|Buchanan', 'FW|20|J. David', 'FW|10|Shaffelburg',
    'GK|1|Crépeau', 'DF|15|Miller', 'MF|8|Ahmed', 'FW|9|Larin',
  ]),
  // ---------------- Europe ----------------
  'ESP': _sq('4-3-3', 'Luis de la Fuente', [
    'GK|23|Unai Simón', 'DF|2|Carvajal', 'DF|3|Le Normand', 'DF|14|Laporte', 'DF|24|Cucurella',
    'MF|8|Fabián Ruiz', 'MF|16|Rodri', 'MF|20|Pedri', 'FW|19|Lamine Yamal', 'FW|7|Morata', 'FW|17|Nico Williams',
    'GK|13|Raya', 'DF|5|Vivian', 'MF|6|Merino', 'FW|10|Dani Olmo',
  ]),
  'FRA': _sq('4-2-3-1', 'Didier Deschamps', [
    'GK|16|Maignan', 'DF|5|Koundé', 'DF|4|Saliba', 'DF|17|Upamecano', 'DF|22|T. Hernández',
    'MF|8|Tchouaméni', 'MF|14|Camavinga', 'MF|7|Griezmann', 'MF|11|Dembélé', 'MF|10|Mbappé', 'FW|12|Kolo Muani',
    'GK|1|Samba', 'DF|3|L. Hernández', 'MF|18|Zaïre-Emery', 'FW|9|Thuram',
  ]),
  'ENG': _sq('4-2-3-1', 'Thomas Tuchel', [
    'GK|1|Pickford', 'DF|2|Walker', 'DF|5|Stones', 'DF|6|Guéhi', 'DF|3|Lewis-Skelly',
    'MF|4|Rice', 'MF|8|Wharton', 'MF|7|Saka', 'MF|10|Bellingham', 'MF|11|Foden', 'FW|9|Kane',
    'GK|13|Henderson', 'DF|12|Konsa', 'MF|19|Palmer', 'FW|17|Watkins',
  ]),
  'GER': _sq('4-2-3-1', 'Julian Nagelsmann', [
    'GK|1|ter Stegen', 'DF|6|Kimmich', 'DF|2|Rüdiger', 'DF|4|Tah', 'DF|18|Mittelstädt',
    'MF|23|Andrich', 'MF|8|Goretzka', 'MF|10|Musiala', 'MF|21|Gündoğan', 'MF|17|Wirtz', 'FW|9|Füllkrug',
    'GK|12|Baumann', 'DF|3|Raum', 'MF|7|Havertz', 'FW|11|Sané',
  ]),
  'POR': _sq('4-3-3', 'Roberto Martínez', [
    'GK|22|D. Costa', 'DF|20|Cancelo', 'DF|3|Rúben Dias', 'DF|4|Inácio', 'DF|19|N. Mendes',
    'MF|18|Rúben Neves', 'MF|8|Bruno Fernandes', 'MF|23|Vitinha', 'FW|11|João Félix', 'FW|7|Ronaldo', 'FW|17|Leão',
    'GK|1|José Sá', 'DF|13|Danilo', 'MF|10|Bernardo Silva', 'FW|9|Gonçalo Ramos',
  ]),
  'NED': _sq('4-3-3', 'Ronald Koeman', [
    'GK|1|Verbruggen', 'DF|22|Dumfries', 'DF|2|de Vrij', 'DF|4|van Dijk', 'DF|5|Aké',
    'MF|24|Schouten', 'MF|8|Gravenberch', 'MF|21|F. de Jong', 'FW|18|Simons', 'FW|9|Depay', 'FW|11|Gakpo',
    'GK|13|Flekken', 'DF|3|de Ligt', 'MF|14|Reijnders', 'FW|10|Brobbey',
  ]),
  'BEL': _sq('4-2-3-1', 'Rudi García', [
    'GK|1|Courtois', 'DF|21|Castagne', 'DF|3|Faes', 'DF|4|Debast', 'DF|5|Theate',
    'MF|24|Onana', 'MF|8|Tielemans', 'MF|11|Trossard', 'MF|7|De Bruyne', 'MF|22|Doku', 'FW|9|Openda',
    'GK|13|Sels', 'DF|2|Meunier', 'MF|6|Vanaken', 'FW|10|Lukebakio',
  ]),
  'CRO': _sq('4-3-3', 'Zlatko Dalić', [
    'GK|1|Livaković', 'DF|22|Juranović', 'DF|5|Erlić', 'DF|20|Gvardiol', 'DF|19|Sosa',
    'MF|10|Modrić', 'MF|11|Brozović', 'MF|8|Kovačić', 'FW|15|Pašalić', 'FW|9|Kramarić', 'FW|17|Budimir',
    'GK|12|Ivušić', 'DF|6|Šutalo', 'MF|13|Vlašić', 'FW|18|Baturina',
  ]),
  'SUI': _sq('4-2-3-1', 'Murat Yakin', [
    'GK|1|Sommer', 'DF|3|Widmer', 'DF|5|Akanji', 'DF|4|Elvedi', 'DF|13|Rodríguez',
    'MF|10|Xhaka', 'MF|8|Freuler', 'MF|17|Vargas', 'MF|23|Rieder', 'MF|7|Ndoye', 'FW|9|Embolo',
    'GK|21|Kobel', 'DF|2|Schär', 'MF|16|Sow', 'FW|19|Amdouni',
  ]),
  'ITA': _sq('4-3-3', 'Gennaro Gattuso', [
    'GK|1|Donnarumma', 'DF|2|Di Lorenzo', 'DF|4|Buongiorno', 'DF|5|Bastoni', 'DF|3|Dimarco',
    'MF|8|Barella', 'MF|18|Tonali', 'MF|10|Pellegrini', 'FW|11|Politano', 'FW|9|Retegui', 'FW|22|Zaccagni',
    'GK|13|Vicario', 'DF|6|Calafiori', 'MF|16|Frattesi', 'FW|20|Kean',
  ]),
  'UKR': _sq('4-3-3', 'Serhiy Rebrov', [
    'GK|1|Lunin', 'DF|2|Konoplya', 'DF|13|Zabarnyi', 'DF|4|Matviyenko', 'DF|16|Mykolenko',
    'MF|6|Stepanenko', 'MF|8|Malinovskyi', 'MF|10|Shaparenko', 'FW|7|Yarmolenko', 'FW|9|Dovbyk', 'FW|11|Mudryk',
    'GK|23|Trubin', 'DF|22|Svatok', 'MF|14|Sudakov', 'FW|19|Vanat',
  ]),
  'SCO': _sq('3-4-2-1', 'Steve Clarke', [
    'GK|1|Gunn', 'DF|5|Hanley', 'DF|6|Hendry', 'DF|13|Tierney',
    'MF|2|Hickey', 'MF|8|McGregor', 'MF|4|Gilmour', 'MF|3|Robertson',
    'MF|7|McGinn', 'MF|10|McTominay', 'FW|9|Adams',
    'GK|12|Kelly', 'DF|15|McKenna', 'MF|11|Christie', 'FW|19|Dykes',
  ]),
  'TUR': _sq('4-2-3-1', 'Vincenzo Montella', [
    'GK|23|Çakır', 'DF|2|Çelik', 'DF|3|Demiral', 'DF|4|Bardakcı', 'DF|20|Kadıoğlu',
    'MF|6|Ayhan', 'MF|15|Yüksek', 'MF|18|Aktürkoğlu', 'MF|10|Çalhanoğlu', 'MF|8|Güler', 'FW|17|Yıldız',
    'GK|1|Bayındır', 'DF|14|Akaydin', 'MF|5|Özcan', 'FW|9|Tosun',
  ]),
  'AUT': _sq('4-2-3-1', 'Ralf Rangnick', [
    'GK|13|Schlager', 'DF|2|Posch', 'DF|4|Danso', 'DF|3|Lienhart', 'DF|8|Mwene',
    'MF|6|Seiwald', 'MF|9|Sabitzer', 'MF|19|Baumgartner', 'MF|10|Grillitsch', 'MF|18|Wimmer', 'FW|11|Arnautović',
    'GK|1|Pentz', 'DF|5|Wöber', 'MF|14|Laimer', 'FW|7|Gregoritsch',
  ]),
  'POL': _sq('3-5-2', 'Jan Urban', [
    'GK|1|Szczęsny', 'DF|5|Bednarek', 'DF|15|Kiwior', 'DF|3|Dawidowicz',
    'MF|2|Frankowski', 'MF|10|Zieliński', 'MF|6|Slisz', 'MF|8|Moder', 'MF|21|Zalewski',
    'FW|9|Lewandowski', 'FW|23|Świderski',
    'GK|22|Skorupski', 'DF|4|Wiśniewski', 'MF|16|Szymański', 'FW|7|Piątek',
  ]),
  'SWE': _sq('4-4-2', 'Graham Potter', [
    'GK|1|Olsen', 'DF|2|Lagerbielke', 'DF|3|Lindelöf', 'DF|4|Hien', 'DF|6|Gudmundsson',
    'MF|7|Saletros', 'MF|8|Ayari', 'MF|16|Bergvall', 'MF|10|Forsberg',
    'FW|9|Gyökeres', 'FW|11|Isak',
    'GK|12|Johansson', 'DF|5|Starfelt', 'MF|18|Karlström', 'FW|20|Elanga',
  ]),
  'NOR': _sq('4-3-3', 'Ståle Solbakken', [
    'GK|1|Nyland', 'DF|2|Ryerson', 'DF|3|Ajer', 'DF|6|Østigård', 'DF|5|Meling',
    'MF|23|Berg', 'MF|8|Berge', 'MF|10|Ødegaard', 'FW|7|Sørloth', 'FW|9|Haaland', 'FW|11|Nusa',
    'GK|12|Dyngeland', 'DF|4|Heggem', 'MF|18|Thorstvedt', 'FW|20|Bobb',
  ]),
  'DEN': _sq('3-4-3', 'Brian Riemer', [
    'GK|1|Schmeichel', 'DF|2|Andersen', 'DF|6|Christensen', 'DF|4|Vestergaard',
    'MF|5|Mæhle', 'MF|23|Højbjerg', 'MF|8|Hjulmand', 'MF|17|Kristiansen',
    'FW|10|Eriksen', 'FW|9|Højlund', 'FW|21|Isaksen',
    'GK|16|Hermansen', 'DF|3|Nelsson', 'MF|11|Skov Olsen', 'FW|19|Dolberg',
  ]),
  // ---------------- South America ----------------
  'ARG': _sq('4-3-3', 'Lionel Scaloni', [
    'GK|23|E. Martínez', 'DF|26|Molina', 'DF|13|Romero', 'DF|25|Otamendi', 'DF|3|Tagliafico',
    'MF|7|De Paul', 'MF|24|Enzo Fernández', 'MF|20|Mac Allister', 'FW|10|Messi', 'FW|9|J. Álvarez', 'FW|11|Nico González',
    'GK|1|Rulli', 'DF|6|Balerdi', 'MF|5|Paredes', 'FW|22|Lautaro Martínez',
  ]),
  'BRA': _sq('4-2-3-1', 'Carlo Ancelotti', [
    'GK|1|Alisson', 'DF|2|Vanderson', 'DF|3|Marquinhos', 'DF|4|Gabriel', 'DF|6|Wendell',
    'MF|5|Bruno Guimarães', 'MF|8|Gerson', 'MF|10|Raphinha', 'MF|7|Vini Jr.', 'MF|21|Estêvão', 'FW|9|Cunha',
    'GK|23|Ederson', 'DF|13|Militão', 'MF|18|Paquetá', 'FW|19|Endrick',
  ]),
  'URU': _sq('4-3-3', 'Marcelo Bielsa', [
    'GK|23|Rochet', 'DF|4|Nández', 'DF|2|Giménez', 'DF|3|Araújo', 'DF|17|Olivera',
    'MF|5|Ugarte', 'MF|15|Valverde', 'MF|10|Arrascaeta', 'FW|11|Pellistri', 'FW|9|Núñez', 'FW|7|Aguirre',
    'GK|1|Mele', 'DF|22|Cáceres', 'MF|6|Bentancur', 'FW|19|Viñas',
  ]),
  'COL': _sq('4-2-3-1', 'Néstor Lorenzo', [
    'GK|1|Vargas', 'DF|17|Muñoz', 'DF|2|Cuesta', 'DF|23|Sánchez', 'DF|21|Mojica',
    'MF|6|Ríos', 'MF|5|Lerma', 'MF|10|James', 'MF|7|L. Díaz', 'MF|8|Arias', 'FW|9|J. Durán',
    'GK|12|Montero', 'DF|4|Lucumí', 'MF|20|Quintero', 'FW|24|Córdoba',
  ]),
  'ECU': _sq('4-2-3-1', 'Sebastián Beccacece', [
    'GK|1|Galíndez', 'DF|4|Ordóñez', 'DF|3|Pacho', 'DF|2|Torres', 'DF|7|Estupiñán',
    'MF|21|Caicedo', 'MF|8|Franco', 'MF|10|Kendry Páez', 'MF|16|Sarmiento', 'MF|11|Valencia', 'FW|9|Rodríguez',
    'GK|22|Domínguez', 'DF|14|Hincapié', 'MF|5|Gruezo', 'FW|19|Plata',
  ]),
  'PAR': _sq('4-3-3', 'Gustavo Alfaro', [
    'GK|1|Fernández', 'DF|2|Velázquez', 'DF|5|Balbuena', 'DF|3|Gómez', 'DF|13|Alonso',
    'MF|8|Bobadilla', 'MF|6|Villasanti', 'MF|10|Almirón', 'FW|11|Sanabria', 'FW|9|Enciso', 'FW|7|Sosa',
    'GK|12|Coronel', 'DF|4|Alderete', 'MF|16|Cubas', 'FW|18|Ávalos',
  ]),
  // ---------------- Africa ----------------
  'MAR': _sq('4-3-3', 'Walid Regragui', [
    'GK|1|Bounou', 'DF|2|Hakimi', 'DF|5|Aguerd', 'DF|6|Saïss', 'DF|25|Mazraoui',
    'MF|4|Amrabat', 'MF|8|Ounahi', 'MF|7|Ziyech', 'FW|17|Diaz', 'FW|9|En-Nesyri', 'FW|16|Ezzalzouli',
    'GK|12|Munir', 'DF|3|El Yamiq', 'MF|15|Amallah', 'FW|19|Rahimi',
  ]),
  'SEN': _sq('4-3-3', 'Pape Thiaw', [
    'GK|16|E. Mendy', 'DF|21|Diatta', 'DF|3|Koulibaly', 'DF|22|Diallo', 'DF|12|Jakobs',
    'MF|26|P. Gueye', 'MF|5|I. Gueye', 'MF|17|Camara', 'FW|18|I. Sarr', 'FW|9|N. Jackson', 'FW|10|Mané',
    'GK|1|S. Diallo', 'DF|4|Niakhaté', 'MF|8|Sabaly', 'FW|19|Habib Diallo',
  ]),
  'EGY': _sq('4-2-3-1', 'Hossam Hassan', [
    'GK|1|El Shenawy', 'DF|7|Fatouh', 'DF|6|Hegazi', 'DF|24|Abdelmonem', 'DF|3|Hamdi',
    'MF|8|Elneny', 'MF|17|Fathi', 'MF|19|Zizo', 'MF|10|Salah', 'MF|22|Trézéguet', 'FW|9|Marmoush',
    'GK|16|Sobhi', 'DF|2|Ashraf', 'MF|21|Sherif', 'FW|11|Mostafa',
  ]),
  'ALG': _sq('4-3-3', 'Vladimir Petković', [
    'GK|16|Mandrea', 'DF|2|Aït-Nouri', 'DF|4|Tougai', 'DF|5|Bensebaini', 'DF|20|Atal',
    'MF|8|Bennacer', 'MF|17|Bentaleb', 'MF|10|Bendebka', 'FW|7|Mahrez', 'FW|9|Amoura', 'FW|11|Gouiri',
    'GK|1|Oukidja', 'DF|3|Mandi', 'MF|14|Chaïbi', 'FW|22|Bounedjah',
  ]),
  'TUN': _sq('4-3-3', 'Sami Trabelsi', [
    'GK|26|Dahmen', 'DF|2|Kechrida', 'DF|3|Talbi', 'DF|6|Bronn', 'DF|12|Abdi',
    'MF|14|Laïdouni', 'MF|17|Skhiri', 'MF|10|Msakni', 'FW|7|Achouri', 'FW|9|Jebali', 'FW|23|Sliti',
    'GK|1|Ben Saïd', 'DF|4|Meriah', 'MF|8|Sassi', 'FW|11|Khazri',
  ]),
  'CIV': _sq('4-2-3-1', 'Emerse Faé', [
    'GK|23|Fofana', 'DF|4|Aurier', 'DF|17|Ndicka', 'DF|5|Konan', 'DF|2|Singo',
    'MF|8|Kessié', 'MF|6|Seri', 'MF|10|Gradel', 'MF|7|Pépé', 'MF|19|Diallo', 'FW|9|Haller',
    'GK|1|Sangaré', 'DF|3|Boly', 'MF|18|Sangaré', 'FW|11|Krasso',
  ]),
  'GHA': _sq('4-3-3', 'Otto Addo', [
    'GK|1|Ati-Zigi', 'DF|2|Lamptey', 'DF|4|Salisu', 'DF|6|Djiku', 'DF|3|Mensah',
    'MF|21|Partey', 'MF|8|Abu', 'MF|10|Kudus', 'FW|7|F. Nuamah', 'FW|9|Semenyo', 'FW|22|J. Ayew',
    'GK|16|Nurudeen', 'DF|5|Amartey', 'MF|20|Sulemana', 'FW|19|Inaki Williams',
  ]),
  'RSA': _sq('4-3-3', 'Hugo Broos', [
    'GK|1|R. Williams', 'DF|2|Mudau', 'DF|4|Kekana', 'DF|5|Sibisi', 'DF|3|Modiba',
    'MF|8|Sithole', 'MF|6|Mokoena', 'MF|10|Zwane', 'FW|7|Tau', 'FW|9|Foster', 'FW|11|Adams',
    'GK|16|Chaine', 'DF|15|Xulu', 'MF|14|Aubaas', 'FW|19|Rayners',
  ]),
  'CPV': _sq('4-4-2', 'Bubista', [
    'GK|1|Vozinha', 'DF|2|Stopira', 'DF|4|Lopes', 'DF|5|Fortes', 'DF|3|Paulo',
    'MF|8|Andrade', 'MF|6|Semedo', 'MF|10|Bebé', 'MF|7|Cabral',
    'FW|9|Ryan Mendes', 'FW|11|Rodrigues',
    'GK|12|Dylan', 'DF|13|Tavares', 'MF|18|Monteiro', 'FW|19|Lenini',
  ]),
  // ---------------- Asia & Oceania ----------------
  'JPN': _sq('3-4-2-1', 'Hajime Moriyasu', [
    'GK|12|Suzuki', 'DF|4|Itakura', 'DF|22|Tomiyasu', 'DF|3|Taniguchi',
    'MF|2|Sugawara', 'MF|6|Endo', 'MF|17|Morita', 'MF|5|Mitoma',
    'MF|10|Kubo', 'MF|14|Kamada', 'FW|9|Ueda',
    'GK|1|Osako', 'DF|16|Machida', 'MF|8|Minamino', 'FW|11|Furuhashi',
  ]),
  'KOR': _sq('4-2-3-1', 'Hong Myung-bo', [
    'GK|21|Jo Hyeon-woo', 'DF|2|Seol Young-woo', 'DF|4|Kim Min-jae', 'DF|3|Kim Ju-sung', 'DF|14|Lee Myung-jae',
    'MF|6|Hwang In-beom', 'MF|8|Paik Seung-ho', 'MF|10|Lee Jae-sung', 'MF|7|Son Heung-min', 'MF|11|Hwang Hee-chan', 'FW|9|Cho Gue-sung',
    'GK|1|Kim Seung-gyu', 'DF|15|Jung Seung-hyun', 'MF|13|Lee Kang-in', 'FW|19|Oh Hyeon-gyu',
  ]),
  'IRN': _sq('4-3-3', 'Amir Ghalenoei', [
    'GK|1|Beiranvand', 'DF|2|Moharrami', 'DF|8|Pouraliganji', 'DF|4|Khalilzadeh', 'DF|3|Mohammadi',
    'MF|6|Ezatolahi', 'MF|21|Gholizadeh', 'MF|11|Amiri', 'FW|7|Jahanbakhsh', 'FW|20|Sardar Azmoun', 'FW|9|Taremi',
    'GK|24|Niazmand', 'DF|5|Kanaani', 'MF|17|Hajsafi', 'FW|10|Ansarifard',
  ]),
  'KSA': _sq('4-3-3', 'Hervé Renard', [
    'GK|21|Al-Owais', 'DF|2|Abdulhamid', 'DF|5|Al-Bulaihi', 'DF|4|Al-Amri', 'DF|13|Al-Shahrani',
    'MF|8|Al-Malki', 'MF|23|Kanno', 'MF|7|Al-Faraj', 'FW|10|Al-Dawsari', 'FW|9|Al-Buraikan', 'FW|11|Al-Shehri',
    'GK|1|Al-Aqidi', 'DF|3|Al-Tambakti', 'MF|29|Al-Juwayr', 'FW|20|Radif',
  ]),
  'QAT': _sq('5-3-2', 'Julen Lopetegui', [
    'GK|1|Barsham', 'DF|2|Pedro Miguel', 'DF|15|Khoukhi', 'DF|3|Salman', 'DF|13|Hassan', 'DF|14|Ahmed',
    'MF|23|Madibo', 'MF|6|Hatem', 'MF|10|Al-Haydos',
    'FW|11|Akram Afif', 'FW|19|Almoez Ali',
    'GK|22|Al-Sheeb', 'DF|5|Waad', 'MF|20|Boudiaf', 'FW|9|Muntari',
  ]),
  'UZB': _sq('4-2-3-1', 'Fabio Cannavaro', [
    'GK|1|Yusupov', 'DF|2|Ashurmatov', 'DF|5|Khusanov', 'DF|4|Eshmurodov', 'DF|3|Alijonov',
    'MF|6|Urunov', 'MF|8|Turgunboev', 'MF|10|Fayzullaev', 'MF|7|Masharipov', 'MF|11|Erkinov', 'FW|9|Shomurodov',
    'GK|12|Nematov', 'DF|13|Hamrobekov', 'MF|17|Jaloliddinov', 'FW|20|Norchaev',
  ]),
  'JOR': _sq('4-3-3', 'Jamal Sellami', [
    'GK|1|Abulaila', 'DF|2|Al-Ajalin', 'DF|4|Al-Arab', 'DF|5|Nasib', 'DF|3|Haddad',
    'MF|6|Al-Rashdan', 'MF|8|Abu Hasheesh', 'MF|10|Al-Rawabdeh', 'FW|7|Al-Taamari', 'FW|9|Al-Naimat', 'FW|11|Olwan',
    'GK|22|Abu Laila', 'DF|13|Al-Marimi', 'MF|14|Sadeq', 'FW|18|Haddad',
  ]),
  'IRQ': _sq('4-2-3-1', 'Graham Arnold', [
    'GK|1|Hachim', 'DF|2|Doski', 'DF|4|Nassif', 'DF|5|Al-Hamawi', 'DF|3|Tavares',
    'MF|6|Al-Ammari', 'MF|8|Bayesh', 'MF|10|Bashar Resan', 'MF|7|Zidane Iqbal', 'MF|11|Ali Jasim', 'FW|9|Ayman Hussein',
    'GK|12|Al-Basri', 'DF|13|Qasim', 'MF|14|Chand', 'FW|19|Al-Aliawi',
  ]),
  'AUS': _sq('4-2-3-1', 'Tony Popovic', [
    'GK|1|Ryan', 'DF|2|Degenek', 'DF|4|Souttar', 'DF|5|Burgess', 'DF|16|Behich',
    'MF|13|O\'Neill', 'MF|8|Irvine', 'MF|10|Metcalfe', 'MF|7|Boyle', 'MF|11|Goodwin', 'FW|9|Duke',
    'GK|18|Gauci', 'DF|3|Deng', 'MF|6|Teague', 'FW|15|Velupillay',
  ]),
  'NZL': _sq('4-4-2', 'Darren Bazeley', [
    'GK|1|Marinović', 'DF|2|Bell', 'DF|5|Boxall', 'DF|4|Surman', 'DF|3|Tuiloma',
    'MF|7|Bindon', 'MF|8|Stamenić', 'MF|6|Thomas', 'MF|10|Garbett',
    'FW|9|C. Wood', 'FW|11|Just',
    'GK|12|Crocombe', 'DF|13|Pijnaker', 'MF|16|Payne', 'FW|19|Waine',
  ]),
  // ---------------- CONCACAF ----------------
  'PAN': _sq('4-4-2', 'Thomas Christiansen', [
    'GK|1|Mosquera', 'DF|2|Murillo', 'DF|4|Andrade', 'DF|5|Escobar', 'DF|3|Davis',
    'MF|8|Carrasquilla', 'MF|6|Godoy', 'MF|10|Barcenas', 'MF|7|Yanis',
    'FW|9|Fajardo', 'FW|11|Waterman',
    'GK|12|Guerra', 'DF|13|Cummings', 'MF|20|Martínez', 'FW|18|Díaz',
  ]),
  'CRC': _sq('5-4-1', 'Miguel Herrera', [
    'GK|1|Navas', 'DF|4|K. Waston', 'DF|3|J. Vargas', 'DF|6|Calvo', 'DF|2|F. Calvo', 'DF|8|Mora',
    'MF|5|Galo', 'MF|20|Brenes', 'MF|10|Zamora', 'MF|7|Ugalde',
    'FW|9|Alcócer',
    'GK|18|Sequeira', 'DF|15|Quirós', 'MF|14|Aguilera', 'FW|11|Venegas',
  ]),
  'HAI': _sq('4-3-3', 'Sébastien Migné', [
    'GK|1|Placide', 'DF|2|Adé', 'DF|4|Arcus', 'DF|5|Milazar', 'DF|3|Casimir',
    'MF|8|Pierrot', 'MF|6|Ariel', 'MF|10|Bellegarde', 'FW|7|Saba', 'FW|9|Nazon', 'FW|11|Picault',
    'GK|16|Duverne', 'DF|13|Elien', 'MF|14|Damus', 'FW|19|Étienne',
  ]),
  'CUW': _sq('4-2-3-1', 'Dick Advocaat', [
    'GK|1|Room', 'DF|2|St. Jago', 'DF|4|Van der Kust', 'DF|5|Angela', 'DF|3|Margaret',
    'MF|6|L. Bacuna', 'MF|8|Antonia', 'MF|10|J. Bacuna', 'MF|7|Hooi', 'MF|11|Zschusschen', 'FW|9|Antonisse',
    'GK|12|Fabias', 'DF|13|Isenia', 'MF|14|Martina', 'FW|19|Maria',
  ]),
};

/// Generated fallback for teams outside the on-device dataset (e.g. a backend
/// fixture with an unknown code) — deterministic, so the same team always
/// fields the same names.
const _fallbackFirst = ['A.', 'B.', 'D.', 'E.', 'F.', 'J.', 'K.', 'L.', 'M.', 'N.', 'R.', 'S.', 'T.', 'Y.'];
const _fallbackLast = [
  'Silva', 'Santos', 'Kone', 'Traore', 'Ahmed', 'Hassan', 'Petrov', 'Ivanov', 'Kim',
  'Tanaka', 'Novak', 'Kovac', 'Diallo', 'Mensah', 'Okafor', 'Diaz', 'Lopez', 'Rojas',
];

TeamSquad _generatedSquad(Team t) {
  final rng = Random(t.code.hashCode);
  const positions = ['GK', 'DF', 'DF', 'DF', 'DF', 'MF', 'MF', 'MF', 'FW', 'FW', 'FW', 'GK', 'DF', 'MF', 'FW'];
  final used = <String>{};
  final players = <SquadPlayer>[];
  for (var i = 0; i < positions.length; i++) {
    String name;
    do {
      name = '${_fallbackFirst[rng.nextInt(_fallbackFirst.length)]} ${_fallbackLast[rng.nextInt(_fallbackLast.length)]}';
    } while (used.contains(name));
    used.add(name);
    players.add(SquadPlayer(i + 1, name, positions[i]));
  }
  return TeamSquad('4-3-3', 'Head Coach', players);
}

final Map<String, TeamSquad> _generatedCache = {};

/// The squad for a team (real data for the 48-team field, generated otherwise).
TeamSquad squadFor(Team t) {
  final real = _squads[t.code.toUpperCase()];
  if (real != null) return real;
  return _generatedCache[t.code] ??= _generatedSquad(t);
}

bool hasRealSquad(String code) => _squads.containsKey(code.toUpperCase());
