// Groupes de places de la vraie carte (SCRUM-60) : lecture du JSON et repères qui ne se chevauchent pas.
import 'package:client7360/carte_reelle_page.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

GroupeCarte groupe(String nom, String genre, double lat, double long, int places) =>
    GroupeCarte(nom: nom, genre: genre, position: LatLng(lat, long), places: places, libres: places);

void main() {
  test('lit un parking et une rue renvoyés par /data/parkings', () {
    final p = GroupeCarte.depuisJson({
      'nom': 'Parking Boulevard Newton', 'genre': 'parking', 'adresse': 'Boulevard Newton, Champs-sur-Marne',
      'lat': 48.843, 'long': 2.587, 'places': 126, 'libres': 120, 'pmr': 2, 'elec': 0,
      'tarif_min': 2.0, 'tarif_max': 2.0,
      'contour': [[48.8431, 2.5869], [48.8432, 2.5872], [48.8429, 2.5873]],
    })!;
    expect(p.estParking, isTrue);
    expect(p.contour, hasLength(3));
    expect(p.libres, 120);
    expect(p.tarifMin, 2.0);

    final r = GroupeCarte.depuisJson({'nom': 'Rue Albert Einstein', 'genre': 'rue', 'lat': 48.84, 'long': 2.58,
      'contour': null, 'places': 40, 'libres': 0})!;
    expect(r.estParking, isFalse);
    expect(r.contour, isEmpty);
    expect(GroupeCarte.depuisJson({'nom': 'sans position'}), isNull);
  });

  test('de loin, deux repères qui se chevauchent : le parking passe avant la rue', () {
    final groupes = [
      groupe('Rue A', 'rue', 48.8390, 2.5853, 200),
      groupe('Parking B', 'parking', 48.8391, 2.5854, 30), // à une dizaine de mètres
    ];
    expect(reperesVisibles(groupes, 15).map((g) => g.nom), ['Parking B']);
    // Assez près, les deux tiennent
    expect(reperesVisibles(groupes, 19.5).map((g) => g.nom), ['Parking B', 'Rue A']);
  });

  test('entre deux parkings qui se chevauchent, le plus gros gagne ; un groupe vide est ignoré', () {
    final groupes = [
      groupe('Petit', 'parking', 48.8390, 2.5853, 4),
      groupe('Gros', 'parking', 48.8390, 2.5854, 146),
      groupe('Loin', 'parking', 48.8450, 2.5950, 10),
      groupe('Vide', 'parking', 48.8300, 2.5700, 0),
    ];
    expect(reperesVisibles(groupes, 15).map((g) => g.nom), ['Gros', 'Loin']);
  });
}
