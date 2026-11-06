import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' show PointMode;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart' hide Path;

import 'paiement_page.dart';
import 'parking_map_page.dart' show ParkingService;

/// Une place du serveur, telle que renvoyée par GET /data/carte.
class PlaceCarte {
  const PlaceCarte({
    required this.id,
    required this.position,
    required this.type,
    this.pmr = false,
    this.elec = false,
    this.adresse,
    this.ville,
    this.parking,
    this.tarif,
    this.occupee = false,
  });

  final int id;
  final LatLng position;
  final String type; // voit, moto, cami
  final bool pmr, elec, occupee;
  final String? adresse, ville, parking;
  final double? tarif;

  /// null si la place n'a pas de coordonnées GPS valides.
  static PlaceCarte? depuisJson(Map<String, dynamic> j) {
    final lat = (j['lat'] as num?)?.toDouble();
    final long = (j['long'] as num?)?.toDouble();
    if (lat == null || long == null || lat.abs() > 90 || long.abs() > 180) {
      return null;
    }
    return PlaceCarte(
      id: (j['id'] as num).toInt(),
      position: LatLng(lat, long),
      type: (j['type'] as String?) ?? 'voit',
      pmr: j['pmr'] == true,
      elec: j['elec'] == true,
      adresse: j['adresse'] as String?,
      ville: j['ville'] as String?,
      parking: j['parking'] as String?,
      tarif: (j['tarif'] as num?)?.toDouble(),
      occupee: j['occupee'] == true,
    );
  }

  String get typeLisible => switch (type) {
        'moto' => 'Moto',
        'cami' => 'Camion',
        _ => 'Voiture',
      };
}

/// Un groupe de places (SCRUM-60) : un parking, ou une rue. Renvoyé par GET /data/parkings.
class GroupeCarte {
  const GroupeCarte({
    required this.nom,
    required this.genre,
    required this.position,
    this.adresse,
    this.contour = const [],
    this.places = 0,
    this.libres = 0,
    this.pmr = 0,
    this.elec = 0,
    this.tarifMin,
    this.tarifMax,
  });

  final String nom;
  final String genre; // parking, rue
  final String? adresse;
  final LatLng position;
  final List<LatLng> contour; // vide pour une rue
  final int places, libres, pmr, elec;
  final double? tarifMin, tarifMax;

  bool get estParking => genre == 'parking';

  static GroupeCarte? depuisJson(Map<String, dynamic> j) {
    final lat = (j['lat'] as num?)?.toDouble();
    final long = (j['long'] as num?)?.toDouble();
    final nom = j['nom'] as String?;
    if (nom == null || lat == null || long == null) return null;
    return GroupeCarte(
      nom: nom,
      genre: (j['genre'] as String?) ?? 'parking',
      adresse: j['adresse'] as String?,
      position: LatLng(lat, long),
      contour: [
        for (final c in (j['contour'] as List<dynamic>? ?? []))
          if (c is List && c.length == 2) LatLng((c[0] as num).toDouble(), (c[1] as num).toDouble()),
      ],
      places: (j['places'] as num?)?.toInt() ?? 0,
      libres: (j['libres'] as num?)?.toInt() ?? 0,
      pmr: (j['pmr'] as num?)?.toInt() ?? 0,
      elec: (j['elec'] as num?)?.toInt() ?? 0,
      tarifMin: (j['tarif_min'] as num?)?.toDouble(),
      tarifMax: (j['tarif_max'] as num?)?.toDouble(),
    );
  }
}

/// Taille d'un repère de groupe à l'écran (pixels).
const tailleRepere = Size(86, 28);

/// Repères qui tiennent à l'écran au zoom donné sans se chevaucher :
/// les parkings d'abord, puis les rues, et dans chaque genre les plus gros groupes.
List<GroupeCarte> reperesVisibles(List<GroupeCarte> groupes, double zoom) {
  final echelle = math.pow(2, zoom).toDouble();
  final tries = [...groupes]..sort((a, b) {
      if (a.estParking != b.estParking) return a.estParking ? -1 : 1;
      return b.places.compareTo(a.places);
    });
  final pris = <Rect>[];
  final gardes = <GroupeCarte>[];
  for (final g in tries) {
    if (g.places == 0) continue;
    final r = Rect.fromCenter(
        center: projeter(g.position) * echelle,
        width: tailleRepere.width + 4,
        height: tailleRepere.height + 4);
    if (pris.any(r.overlaps)) continue;
    pris.add(r);
    gardes.add(g);
  }
  return gardes;
}

String euros(double v) => '${v.toStringAsFixed(2).replaceAll('.', ',')} €';

/// Vraie carte OpenStreetMap (SCRUM-52) avec les places du serveur.
/// Vert = libre, rouge = occupée. Toucher une place affiche sa fiche,
/// d'où l'on peut la payer.
class CarteReellePage extends StatefulWidget {
  const CarteReellePage({super.key});

  /// ESIEE Paris (Noisy-le-Grand / Champs-sur-Marne) : centre de départ
  static const LatLng esiee = LatLng(48.8390, 2.5853);

  @override
  State<CarteReellePage> createState() => _CarteReellePageState();
}

class _CarteReellePageState extends State<CarteReellePage> {
  final MapController _carte = MapController();

  List<PlaceCarte> _places = [];
  List<GroupeCarte> _groupes = [];
  Map<String, GroupeCarte> _groupeParNom = {};
  bool _chargement = true;
  String? _erreur;

  // Palier de zoom : 0 = de loin (simples points), 1 à 3 = pastilles de plus en plus grandes.
  // On ne reconstruit la page qu'au changement de palier, pas à chaque image du zoom.
  int _palier = 0;
  static int palierPour(double zoom) => zoom >= 18.5 ? 3 : zoom >= 17.5 ? 2 : zoom >= 16.5 ? 1 : 0;
  static const _taillesPastille = [0.0, 12.0, 20.0, 30.0];
  // De loin, les repères de groupe sont recalculés tous les demi-crans de zoom
  int _cran = 30;
  static int cranPour(double zoom) => (zoom * 2).floor();

  // Calculés une seule fois par chargement (et par palier pour les pastilles)
  List<Offset> _libresProjetees = [], _occupeesProjetees = [];
  List<Marker> _pastilles = [];
  List<List<Offset>> _contoursProjetes = [];
  Map<String, _DessinRepere> _dessins = {}; // textes des repères, mis en page une seule fois
  List<GroupeCarte> _reperes = [];

  void _preparerDessin() {
    _libresProjetees = [for (final p in _places) if (!p.occupee) projeter(p.position)];
    _occupeesProjetees = [for (final p in _places) if (p.occupee) projeter(p.position)];
    _pastilles = _palier == 0 ? [] : [for (final p in _places) _marqueur(p)];
    _contoursProjetes = [
      for (final g in _groupes)
        if (g.contour.length >= 3) [for (final c in g.contour) projeter(c)],
    ];
    _preparerReperes();
  }

  void _preparerReperes() {
    _reperes = _palier == 0 ? reperesVisibles(_groupes, _cran / 2) : [];
  }

  @override
  void dispose() {
    for (final d in _dessins.values) {
      d.dispose();
    }
    super.dispose();
  }

  /// De loin, un toucher ouvre le repère de groupe touché, sinon la place la plus proche (à moins de 14 pixels).
  void _toucherCarte(TapPosition _, LatLng point) {
    if (_palier != 0 || _places.isEmpty) return;
    final zoom = _carte.camera.zoom;
    final echelle = math.pow(2, zoom).toDouble();
    final ici = projeter(point) * echelle;
    for (final g in _reperes) {
      final r = Rect.fromCenter(
          center: projeter(g.position) * echelle, width: tailleRepere.width, height: tailleRepere.height);
      if (r.contains(ici)) {
        _ouvrirFicheGroupe(g);
        return;
      }
    }
    const distance = Distance();
    final metresParPixel = 156543.03 * math.cos(point.latitude * math.pi / 180) / math.pow(2, zoom);
    PlaceCarte? meilleure;
    var dMin = 14 * metresParPixel;
    for (final p in _places) {
      final d = distance.as(LengthUnit.Meter, p.position, point);
      if (d < dMin) {
        dMin = d;
        meilleure = p;
      }
    }
    if (meilleure != null) _ouvrirFiche(meilleure);
  }

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    setState(() {
      _chargement = true;
      _erreur = null;
    });
    try {
      final base = ParkingService.baseUrl;
      final reponses = await Future.wait([
        http.get(Uri.parse('$base/data/carte')),
        // Les groupes sont un plus : sans eux (ancien serveur), la carte marche quand même
        http.get(Uri.parse('$base/data/parkings')).catchError((_) => http.Response('', 503)),
      ]).timeout(const Duration(seconds: 10));
      final reponse = reponses[0];
      if (!mounted) return;
      if (reponse.statusCode != 200) {
        setState(() => _erreur = 'Erreur serveur (${reponse.statusCode})');
        return;
      }
      List<dynamic> lignes(http.Response r) =>
          (jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>)['data'] as List<dynamic>? ?? [];
      final places = [
        for (final p in lignes(reponse))
          if (p is Map<String, dynamic>) PlaceCarte.depuisJson(p),
      ].whereType<PlaceCarte>().toList();
      final groupes = reponses[1].statusCode == 200
          ? [
              for (final g in lignes(reponses[1]))
                if (g is Map<String, dynamic>) GroupeCarte.depuisJson(g),
            ].whereType<GroupeCarte>().toList()
          : <GroupeCarte>[];
      setState(() {
        _places = places;
        _groupes = groupes;
        _groupeParNom = {for (final g in groupes) g.nom: g};
        for (final d in _dessins.values) {
          d.dispose();
        }
        _dessins = {for (final g in groupes) g.nom: _DessinRepere(g)};
        _preparerDessin();
      });
    } catch (_) {
      if (mounted) setState(() => _erreur = 'Serveur injoignable');
    } finally {
      if (mounted) setState(() => _chargement = false);
    }
  }

  void _voirToutesLesPlaces() {
    // On cadre les places autour du campus (à moins de 30 km de l'ESIEE) :
    // les places de démo ont des coordonnées fictives, loin de tout.
    const distance = Distance();
    final proches = _places
        .where((p) => distance.as(LengthUnit.Kilometer, p.position, CarteReellePage.esiee) < 30)
        .toList();
    final cadre = proches.isEmpty ? _places : proches;
    if (cadre.isEmpty) return;
    if (cadre.length == 1) {
      _carte.move(cadre.first.position, 17);
      return;
    }
    _carte.fitCamera(CameraFit.coordinates(
      coordinates: [for (final p in cadre) p.position],
      padding: const EdgeInsets.all(48),
      maxZoom: 18,
    ));
  }

  void _ouvrirFiche(PlaceCarte place) {
    showModalBottomSheet<void>(
      context: context,
      builder: (contexteFiche) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Place n°${place.id}', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              if (place.adresse != null || place.ville != null)
                Text([place.adresse, place.ville].whereType<String>().join(', ')),
              if (_groupeParNom[place.parking] case final g?)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: Icon(g.estParking ? Icons.local_parking : Icons.add_road, color: Colors.blue.shade700),
                  title: Text(g.estParking ? g.nom : 'Dans la rue : ${g.nom}'),
                  subtitle: Text('${g.libres} libre(s) sur ${g.places}'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.pop(contexteFiche);
                    _ouvrirFicheGroupe(g);
                  },
                )
              else if (place.parking != null)
                Text('Parking : ${place.parking}'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Chip(
                    avatar: Icon(place.occupee ? Icons.block : Icons.check_circle,
                        color: place.occupee ? Colors.red : Colors.green),
                    label: Text(place.occupee ? 'Occupée' : 'Libre'),
                  ),
                  Chip(label: Text(place.typeLisible)),
                  if (place.pmr) const Chip(avatar: Icon(Icons.accessible), label: Text('PMR')),
                  if (place.elec) const Chip(avatar: Icon(Icons.bolt), label: Text('Électrique')),
                  if (place.tarif != null)
                    Chip(label: Text('${place.tarif!.toStringAsFixed(2).replaceAll('.', ',')} € / h')),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  icon: const Icon(Icons.euro),
                  label: const Text('Payer cette place'),
                  onPressed: () {
                    Navigator.pop(contexteFiche);
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => PaiementPage(idPlace: place.id)),
                    ).then((_) => _charger()); // la place a pu passer occupée
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Cadre la carte sur un parking (son contour) ou une rue (ses places), d'assez près pour toucher les places.
  void _voirGroupe(GroupeCarte g) {
    final points = g.contour.length >= 3
        ? g.contour
        : [for (final p in _places) if (p.parking == g.nom) p.position];
    if (points.length < 2) {
      _carte.move(points.isEmpty ? g.position : points.first, 18.6);
      return;
    }
    _carte.fitCamera(CameraFit.coordinates(
      coordinates: points,
      padding: const EdgeInsets.fromLTRB(32, 72, 32, 32),
      minZoom: 17.6, // assez près pour voir les pastilles
      maxZoom: 19,
    ));
  }

  void _ouvrirFicheGroupe(GroupeCarte g) {
    final tarif = switch ((g.tarifMin, g.tarifMax)) {
      (final a?, final b?) when a != b => '${euros(a)} à ${euros(b)} / h',
      (final a?, _) => '${euros(a)} / h',
      _ => null,
    };
    showModalBottomSheet<void>(
      context: context,
      builder: (contexteFiche) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(g.estParking ? Icons.local_parking : Icons.add_road, color: Colors.blue.shade700),
                const SizedBox(width: 8),
                Expanded(child: Text(g.nom, style: Theme.of(context).textTheme.titleLarge)),
              ]),
              const SizedBox(height: 4),
              Text(g.estParking ? 'Parking' : 'Stationnement dans la rue'),
              if (g.adresse != null) Text(g.adresse!),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Chip(
                    avatar: Icon(g.libres > 0 ? Icons.check_circle : Icons.block,
                        color: g.libres > 0 ? Colors.green : Colors.red),
                    label: Text('${g.libres} libre(s) sur ${g.places}'),
                  ),
                  if (g.pmr > 0) Chip(avatar: const Icon(Icons.accessible), label: Text('${g.pmr} PMR')),
                  if (g.elec > 0) Chip(avatar: const Icon(Icons.bolt), label: Text('${g.elec} électrique(s)')),
                  if (tarif != null) Chip(label: Text(tarif)),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  icon: const Icon(Icons.zoom_in),
                  label: const Text('Voir les places'),
                  onPressed: () {
                    Navigator.pop(contexteFiche);
                    _voirGroupe(g);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Marker _marqueur(PlaceCarte place) {
    final couleur = place.occupee ? Colors.red.shade600 : Colors.green.shade600;
    final taille = _taillesPastille[_palier];
    final pastille = Container(
      decoration: BoxDecoration(
        color: couleur,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: taille >= 20 ? 2 : 1),
        boxShadow: taille >= 20 ? const [BoxShadow(blurRadius: 3, color: Colors.black38)] : null,
      ),
      child: taille >= 20
          ? Icon(place.type == 'moto' ? Icons.two_wheeler : Icons.local_parking,
              color: Colors.white, size: taille * 0.6)
          : null,
    );
    return Marker(
      point: place.position,
      width: taille,
      height: taille,
      child: GestureDetector(
        onTap: () => _ouvrirFiche(place),
        child: taille >= 20 ? Tooltip(message: 'Place n°${place.id}', child: pastille) : pastille,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final libres = _places.where((p) => !p.occupee).length;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('Carte des places'),
        actions: [
          IconButton(
            icon: const Icon(Icons.school),
            tooltip: "Recentrer sur l'ESIEE",
            onPressed: () => _carte.move(CarteReellePage.esiee, 15),
          ),
          IconButton(
            icon: const Icon(Icons.zoom_out_map),
            tooltip: 'Voir toutes les places',
            onPressed: _places.isEmpty ? null : _voirToutesLesPlaces,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualiser',
            onPressed: _chargement ? null : _charger,
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _carte,
            options: MapOptions(
              initialCenter: CarteReellePage.esiee,
              initialZoom: 15,
              minZoom: 3,
              maxZoom: 20,
              onTap: _toucherCarte,
              onPositionChanged: (camera, _) {
                final palier = palierPour(camera.zoom);
                final cran = cranPour(camera.zoom);
                if (palier != _palier) {
                  setState(() {
                    _palier = palier;
                    _cran = cran;
                    _preparerDessin();
                  });
                } else if (palier == 0 && cran != _cran) {
                  setState(() {
                    _cran = cran;
                    _preparerReperes();
                  });
                }
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.client7360',
              ),
              // Contours des parkings, et de loin : toutes les places et un repère par parking ou par rue,
              // peints d'un coup (rapide) ; de près : des pastilles touchables, seules celles à l'écran sont construites
              _CoucheDessin(
                contours: _contoursProjetes,
                libres: _palier == 0 ? _libresProjetees : const [],
                occupees: _palier == 0 ? _occupeesProjetees : const [],
                reperes: [for (final g in _reperes) ?_dessins[g.nom]],
              ),
              if (_palier != 0) MarkerLayer(markers: _pastilles),
              const RichAttributionWidget(
                attributions: [TextSourceAttribution('OpenStreetMap contributors')],
              ),
            ],
          ),
          // Bandeau d'état en haut de la carte
          Positioned(
            top: 12,
            left: 12,
            right: 12,
            child: Center(
              child: Material(
                elevation: 2,
                borderRadius: BorderRadius.circular(20),
                color: _erreur != null ? Colors.red.shade50 : Colors.white,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  child: _chargement
                      ? const SizedBox.square(
                          dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(_erreur ??
                          '${_places.length} place(s), dont $libres libre(s)'
                              '${_groupes.isEmpty ? '' : ' · ${_groupes.where((g) => g.estParking).length} parkings'}'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Position d'un point en pixels de la carte au zoom 0 (projection Web Mercator, tuiles de 256 px).
/// Au zoom z, il suffit de multiplier par 2^z : rien à recalculer pendant qu'on fait glisser la carte.
Offset projeter(LatLng p) {
  final lat = p.latitude * math.pi / 180;
  return Offset(
    (p.longitude + 180) / 360 * 256,
    (1 - math.log(math.tan(lat) + 1 / math.cos(lat)) / math.pi) / 2 * 256,
  );
}

/// Repère d'un groupe vu de loin : « P » pour un parking, une route pour une rue, et ses places libres.
/// Les textes sont mis en page une seule fois par chargement ; la carte les peint ensuite à chaque image.
/// Pas de détecteur de toucher : c'est la carte qui sait quel repère a été touché (_toucherCarte).
class _DessinRepere {
  _DessinRepere(GroupeCarte g)
      : position = projeter(g.position),
        _bord = Paint()
          ..color = g.estParking ? Colors.blue.shade700 : Colors.blueGrey.shade500
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
        _rond = Paint()..color = g.estParking ? Colors.blue.shade700 : Colors.blueGrey.shade500,
        _symbole = TextPainter(
          textDirection: TextDirection.ltr,
          text: g.estParking
              ? const TextSpan(
                  text: 'P', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold))
              : TextSpan(
                  text: String.fromCharCode(Icons.add_road.codePoint),
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontFamily: Icons.add_road.fontFamily,
                      package: Icons.add_road.fontPackage)),
        )..layout(),
        _texte = TextPainter(
          textDirection: TextDirection.ltr,
          text: TextSpan(
            text: '${g.libres}/${g.places}',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: g.libres > 0 ? Colors.green.shade800 : Colors.red.shade700,
            ),
          ),
        )..layout();

  final Offset position; // au zoom 0, voir projeter()
  final Paint _bord, _rond;
  final TextPainter _symbole, _texte;

  static final _fond = Paint()..color = Colors.white;
  static final _ombre = Paint()..color = Colors.black.withValues(alpha: 0.18);

  void dispose() {
    _symbole.dispose();
    _texte.dispose();
  }

  void peindre(Canvas canvas, Offset centre) {
    final cadre = RRect.fromRectAndRadius(
        Rect.fromCenter(center: centre, width: 2 + 18 + 4 + _texte.width + 7, height: 24),
        const Radius.circular(12));
    canvas.drawRRect(cadre.inflate(1.5).shift(const Offset(0, 1)), _ombre);
    canvas.drawRRect(cadre, _fond);
    canvas.drawRRect(cadre, _bord);
    final rond = Offset(cadre.left + 2 + 9, centre.dy);
    canvas.drawCircle(rond, 9, _rond);
    _symbole.paint(canvas, rond - Offset(_symbole.width / 2, _symbole.height / 2));
    _texte.paint(canvas, Offset(cadre.left + 2 + 18 + 4, centre.dy - _texte.height / 2));
  }
}

/// Contours des parkings, puis (de loin) toutes les places et les repères de groupe, peints d'un coup.
/// Bien plus léger que des centaines de widgets (mesuré : la carte restait fluide).
class _CoucheDessin extends StatelessWidget {
  const _CoucheDessin({
    required this.contours,
    required this.libres,
    required this.occupees,
    required this.reperes,
  });

  final List<List<Offset>> contours; // positions au zoom 0, voir projeter()
  final List<Offset> libres, occupees;
  final List<_DessinRepere> reperes;

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    return MobileLayerTransformer(
      child: CustomPaint(
        size: Size.infinite,
        painter: _PeintreCarte(camera, contours, libres, occupees, reperes),
      ),
    );
  }
}

class _PeintreCarte extends CustomPainter {
  _PeintreCarte(this.camera, this.contours, this.libres, this.occupees, this.reperes);

  final MapCamera camera;
  final List<List<Offset>> contours;
  final List<Offset> libres, occupees;
  final List<_DessinRepere> reperes;

  static Paint _crayon(Color c, double epaisseur) => Paint()
    ..color = c
    ..strokeWidth = epaisseur
    ..strokeCap = StrokeCap.round;
  static final _contour = _crayon(Colors.white, 9);
  static final _vert = _crayon(Colors.green.shade600, 7);
  static final _rouge = _crayon(Colors.red.shade600, 7);
  static final _fondParking = Paint()..color = Colors.blue.withValues(alpha: 0.10);
  static final _bordParking = Paint()
    ..color = Colors.blue.shade700
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.5;

  @override
  void paint(Canvas canvas, Size size) {
    final echelle = math.pow(2, camera.zoom).toDouble();
    final origine = camera.pixelOrigin;
    final ecran = (Offset.zero & size).inflate(10);
    Offset aLEcran(Offset b) => b * echelle - origine;

    for (final c in contours) {
      final chemin = Path()..addPolygon([for (final b in c) aLEcran(b)], true);
      if (!chemin.getBounds().overlaps(ecran)) continue;
      canvas.drawPath(chemin, _fondParking);
      canvas.drawPath(chemin, _bordParking);
    }

    final l = [for (final b in libres) if (ecran.contains(aLEcran(b))) aLEcran(b)];
    final o = [for (final b in occupees) if (ecran.contains(aLEcran(b))) aLEcran(b)];
    canvas.drawPoints(PointMode.points, l, _contour);
    canvas.drawPoints(PointMode.points, o, _contour);
    canvas.drawPoints(PointMode.points, l, _vert);
    canvas.drawPoints(PointMode.points, o, _rouge);

    final zoneReperes = ecran.inflate(50);
    for (final r in reperes) {
      final c = aLEcran(r.position);
      if (zoneReperes.contains(c)) r.peindre(canvas, c);
    }
  }

  @override
  bool shouldRepaint(_PeintreCarte ancien) => true;
}
