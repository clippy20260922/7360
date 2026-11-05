import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'parking_map_view.dart';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

// ───────────────────────── Accès backend ─────────────────────────

class ParkingService {
  /// URL du serveur (server7360). Pour la changer sans toucher au code :
  ///   flutter run --dart-define=API_URL=http://192.168.1.20:8000
  static final String baseUrl = _resolveBaseUrl();

  static String _resolveBaseUrl() {
    const fromEnv = String.fromEnvironment('API_URL');
    if (fromEnv.isNotEmpty) return fromEnv;
    // Sur l'émulateur Android, 127.0.0.1 désigne l'émulateur lui-même,
    // pas le PC : 10.0.2.2 est l'adresse du PC vu depuis l'émulateur.
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:8000';
    }
    return 'http://127.0.0.1:8000';
  }

  /// GET /parking → { "spots": [...], "roads": [...], "buildings": [...] }
  static Future<ParkingData> fetch() async {
    final res = await http
        .get(Uri.parse('$baseUrl/parking'))
        .timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) {
      throw Exception('Erreur serveur (${res.statusCode})');
    }
    return ParkingData.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  /// POST /parking/spots/{id}/reserve
  static Future<void> reserve(String spotId) async {
    final res = await http
        .post(Uri.parse('$baseUrl/parking/spots/${Uri.encodeComponent(spotId)}/reserve'))
        .timeout(const Duration(seconds: 10));
    if (res.statusCode != 200 && res.statusCode != 204) {
      throw Exception('Réservation impossible (${res.statusCode})');
    }
  }
}

// ───────────────────────── Page ─────────────────────────

/// Page qui affiche le plan du parking dans un rectangle centré.
class ParkingMapPage extends StatefulWidget {
  const ParkingMapPage({super.key});

  @override
  State<ParkingMapPage> createState() => _ParkingMapPageState();
}

class _ParkingMapPageState extends State<ParkingMapPage> {
  static const _refreshEvery = Duration(seconds: 5);

  // Données de démonstration utilisées tant que le backend n'est pas prêt.
  // Le modèle ParkingData reste identique à celui attendu par l'API.
  static final ParkingData _demoData = _createDemoData();

  static ParkingData _createDemoData() {
    final random = math.Random(94440); // rendu stable à chaque rechargement

    // Plan fictif (mètres locaux, pas de GPS) : un quadrillage irrégulier
    // légèrement tourné, deux axes principaux dans chaque sens, un boulevard
    // en diagonale, deux parcs avec plan d'eau et des îlots de bâtiments.
    // Le plan dépasse largement la fenêtre : on peut le parcourir en glissant.
    const theta = -0.14;
    final cosT = math.cos(theta), sinT = math.sin(theta);
    Offset rot(Offset p) =>
        Offset(p.dx * cosT - p.dy * sinT, p.dx * sinT + p.dy * cosT);

    const xs = <double>[-390, -300, -205, -110, -10, 85, 190, 290, 390];
    const ys = <double>[-330, -240, -150, -60, 35, 130, 225, 320];
    const mainX = <int>{3, 5}; // indices des axes principaux verticaux
    const mainY = <int>{2, 5}; // indices des axes principaux horizontaux
    const parkCells = <(int, int)>[(1, 2), (6, 5)]; // (colonne, ligne)

    // ── Routes ──
    final roads = <Road>[];
    for (var i = 0; i < xs.length; i++) {
      roads.add(Road(
        rot(Offset(xs[i], ys.first - 30)),
        rot(Offset(xs[i], ys.last + 30)),
        mainX.contains(i) ? 8.0 : 5.5,
      ));
    }
    for (var j = 0; j < ys.length; j++) {
      roads.add(Road(
        rot(Offset(xs.first - 30, ys[j])),
        rot(Offset(xs.last + 30, ys[j])),
        mainY.contains(j) ? 8.0 : 5.5,
      ));
    }
    // Boulevard en diagonale
    roads.add(Road(rot(const Offset(-260, -370)), rot(const Offset(330, 65)), 8));

    // ── Parcs et plans d'eau ──
    final zones = <Zone>[];
    for (final (i, j) in parkCells) {
      zones.add(Zone(ZoneKind.park, [
        rot(Offset(xs[i], ys[j])),
        rot(Offset(xs[i + 1], ys[j])),
        rot(Offset(xs[i + 1], ys[j + 1])),
        rot(Offset(xs[i], ys[j + 1])),
      ]));
    }
    for (final (i, j) in parkCells) {
      final cx = (xs[i] + xs[i + 1]) / 2, cy = (ys[j] + ys[j + 1]) / 2;
      final rx = i == 1 ? 26.0 : 18.0, ry = i == 1 ? 16.0 : 12.0;
      zones.add(Zone(ZoneKind.water, [
        for (var k = 0; k < 28; k++)
          () {
            final a = 2 * math.pi * k / 28;
            final wobble = 1 + 0.08 * math.sin(3 * a);
            return rot(Offset(
                cx + rx * wobble * math.cos(a), cy + ry * wobble * math.sin(a)));
          }(),
      ]));
    }

    // ── Bâtiments ──
    double distanceToSegment(Offset point, Road road) {
      final delta = road.b - road.a;
      final lengthSquared = delta.dx * delta.dx + delta.dy * delta.dy;
      if (lengthSquared == 0) return (point - road.a).distance;
      final relative = point - road.a;
      final t = ((relative.dx * delta.dx + relative.dy * delta.dy) /
              lengthSquared)
          .clamp(0.0, 1.0);
      return (point - (road.a + delta * t)).distance;
    }

    bool onRoad(Offset p) => roads
        .any((r) => distanceToSegment(p, r) < r.width / 2 + 2.5);

    final spots = <ParkingSpot>[];
    var lotNumber = 1;

    SpotStatus randomStatus() {
      final roll = random.nextInt(100);
      return roll < 62
          ? SpotStatus.free
          : roll < 90
              ? SpotStatus.occupied
              : SpotStatus.reserved;
    }

    const inset = 12.0; // retrait par rapport aux axes des rues
    const gap = 3.0; // espace entre deux bâtiments
    const wall = Color(0xFFD9D5CC);
    final buildings = <Building>[];
    for (var i = 0; i < xs.length - 1; i++) {
      for (var j = 0; j < ys.length - 1; j++) {
        if (parkCells.contains((i, j))) continue;
        final x0 = xs[i] + inset, x1 = xs[i + 1] - inset;
        final y0 = ys[j] + inset, y1 = ys[j + 1] - inset;
        final cols = 2 + random.nextInt(2), rows = 2 + random.nextInt(2);
        final lotW = (x1 - x0 - gap * (cols - 1)) / cols;
        final lotH = (y1 - y0 - gap * (rows - 1)) / rows;
        for (var c = 0; c < cols; c++) {
          for (var r = 0; r < rows; r++) {
            if (random.nextInt(100) < 8) continue; // cour ou dent creuse
            final x = x0 + c * (lotW + gap) + random.nextDouble() * 2.5;
            final y = y0 + r * (lotH + gap) + random.nextDouble() * 2.5;
            final w = lotW - 2.5 - random.nextDouble() * 2.5;
            final h = lotH - 2.5 - random.nextDouble() * 2.5;
            // Quelques emplacements deviennent des parkings (plus grands que
            // les places, affichés en bleu) à la place d'un bâtiment.
            if (random.nextInt(100) < 5) {
              final lotCenter = rot(Offset(x + w / 2, y + h / 2));
              final lot = ParkingSpot(
                'P-${(lotNumber).toString().padLeft(2, '0')}',
                lotCenter,
                width: w,
                length: h,
                angle: theta,
                status: randomStatus(),
                isLot: true,
              );
              if (!onRoad(lotCenter) && !lot.corners.any(onRoad)) {
                spots.add(lot);
                lotNumber++;
              }
              continue;
            }
            final raw = random.nextInt(100) < 12
                ? <Offset>[
                    // bâtiment en L
                    Offset(x, y), Offset(x + w * 0.55, y),
                    Offset(x + w * 0.55, y + h * 0.45),
                    Offset(x + w, y + h * 0.45),
                    Offset(x + w, y + h), Offset(x, y + h),
                  ]
                : <Offset>[
                    Offset(x, y), Offset(x + w, y),
                    Offset(x + w, y + h), Offset(x, y + h),
                  ];
            final footprint = raw.map(rot).toList();
            final center = rot(Offset(x + w / 2, y + h / 2));
            if (onRoad(center) || footprint.any(onRoad)) continue;
            // Plus haut vers le centre-ville
            final fromCenter = Offset(x + w / 2, y + h / 2).distance;
            final height =
                6 + random.nextInt(9) + math.max(0.0, 1 - fromCenter / 320) * 16;
            buildings.add(Building(footprint, height, wall));
          }
        }
      }
    }

    // ── Places de la base (slot_table, ids 1 à 7), le long de la rue x = xs[4] ──
    // (slot_id, slot_type, slot_occupied). PMR / électrique / protégé ne sont
    // pas gérés par ParkingSpot et sont donc ignorés ici.
    const slots = <(int, String, bool)>[
      (1, 'voit', false),
      (2, 'voit', false),
      (3, 'voit', false),
      (4, 'voit', false),
      (5, 'voit', false),
      (6, 'moto', false),
      (7, 'voit', false),
    ];
    var along = ys[4] + 15;
    for (final (id, type, occupied) in slots) {
      final w = type == 'moto' ? 1.0 : 2.5;
      final l = type == 'moto' ? 2.2 : 5.0;
      // Perpendiculaires à la rue (5,5 m de large), côté est
      final center = Offset(xs[4] + 5.5 / 2 + l / 2 + 0.4, along + w / 2);
      spots.add(ParkingSpot(
        id.toString(),
        rot(center),
        width: w,
        length: l,
        angle: math.pi / 2 + theta,
        status: occupied ? SpotStatus.occupied : SpotStatus.free,
      ));
      along += w + 0.5;
    }

    // ── Places le long des rues secondaires ──
    // Petites rangées perpendiculaires à la rue, à l'écart des carrefours,
    // sur un côté ou l'autre ; celles qui toucheraient une autre route
    // (boulevard en diagonale, par exemple) sont écartées.
    var nextId = slots.length + 1;

    bool spotIsClear(ParkingSpot s) => s.corners.every((c) =>
        roads.every((r) => distanceToSegment(c, r) >= r.width / 2 + 0.2));

    void addGroup(bool vertical, double fixed, double from, double to,
        double side, double roadWidth) {
      const margin = 14.0, pitch = 2.9;
      final room = to - from - 2 * margin;
      final maxCount = (room / pitch).floor();
      if (maxCount < 3) return;
      final count = math.min(maxCount, 3 + random.nextInt(6));
      final start = from + margin + random.nextDouble() * (room - count * pitch);
      final offset = side * (roadWidth / 2 + 2.5 + 0.4);
      for (var k = 0; k < count; k++) {
        final t = start + k * pitch + 1.25;
        final c = vertical ? Offset(fixed + offset, t) : Offset(t, fixed + offset);
        final spot = ParkingSpot(
          nextId.toString(),
          rot(c),
          width: 2.5,
          length: 5,
          angle: (vertical ? math.pi / 2 : 0.0) + theta,
          status: randomStatus(),
        );
        if (!spotIsClear(spot)) continue;
        spots.add(spot);
        nextId++;
      }
    }

    for (var i = 0; i < xs.length; i++) {
      if (mainX.contains(i)) continue;
      for (var j = 0; j < ys.length - 1; j++) {
        for (final side in const [-1.0, 1.0]) {
          // Côté déjà occupé par les places de la base
          if (i == 4 && j == 4 && side > 0) continue;
          if (random.nextInt(100) < 35) {
            addGroup(true, xs[i], ys[j], ys[j + 1], side, 5.5);
          }
        }
      }
    }
    for (var j = 0; j < ys.length; j++) {
      if (mainY.contains(j)) continue;
      for (var i = 0; i < xs.length - 1; i++) {
        for (final side in const [-1.0, 1.0]) {
          if (random.nextInt(100) < 35) {
            addGroup(false, ys[j], xs[i], xs[i + 1], side, 5.5);
          }
        }
      }
    }

    return ParkingData(
      spots: spots,
      roads: roads,
      buildings: buildings,
      zones: zones,
    );
  }

  final ParkingMapController _controller = ParkingMapController();

  ParkingData _data = const ParkingData();
  bool _loading = true; // vrai uniquement pour le tout premier chargement
  bool _fetching = false; // évite deux requêtes en même temps
  String? _error;
  Timer? _timer;

  /// Id de la place sélectionnée (null si aucune).
  String? _selectedId;

  ParkingSpot? get _selectedSpot {
    for (final s in _data.spots) {
      if (s.id == _selectedId) return s;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(_refreshEvery, (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (_fetching) return;
    _fetching = true;
    try {
      final data = await ParkingService.fetch();
      if (!mounted) return;

      // Un backend qui répond avec des listes vides est traité comme non prêt.
      final isEmpty = data.spots.isEmpty &&
          data.roads.isEmpty &&
          data.buildings.isEmpty;
      setState(() {
        _data = isEmpty ? _demoData : data;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        // On garde les données déjà affichées si un refresh échoue.
        // Au premier lancement, on utilise les données de démonstration.
        if (_data.spots.isEmpty &&
            _data.roads.isEmpty &&
            _data.buildings.isEmpty) {
          _data = _demoData;
        }
        _error = e.toString();
        _loading = false;
      });
    } finally {
      _fetching = false;
    }
  }

  Future<void> _reserveSelected() async {
    final id = _selectedId;
    if (id == null) return;
    try {
      await ParkingService.reserve(id);
      _controller.clearSelection();
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('Plan du parking'),
        actions: [
          IconButton(
            icon: const Icon(Icons.restart_alt),
            tooltip: 'Réinitialiser la vue',
            onPressed: _controller.resetView,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    // Erreur et rien à afficher
    if (_error != null && _data.spots.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Erreur : $_error'),
            TextButton(onPressed: _load, child: const Text('Réessayer')),
          ],
        ),
      );
    }

    final sel = _selectedSpot;
    return Column(
      children: [
        Expanded(
          child: Center(
            child: FractionallySizedBox(
              widthFactor: 0.9, // 90 % de la largeur
              heightFactor: 0.9,
              child: Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.black26, width: 2),
                ),
                child: ParkingMapView(
                  controller: _controller,
                  initialTilt: 0,
                  spots: _data.spots,
                  roads: _data.roads,
                  buildings: _data.buildings,
                  zones: _data.zones,
                  // Récupère l'id de la place sélectionnée
                  onSpotSelected: (id) => setState(() => _selectedId = id),
                ),
              ),
            ),
          ),
        ),
        // Exemple d'utilisation de l'id sélectionné, à remplacer par ton UI
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _selectedId == null
                      ? 'Aucune place sélectionnée'
                      : '${sel != null && sel.isLot ? 'Parking' : 'Place'} sélectionné(e) : $_selectedId',
                ),
              ),
              FilledButton(
                onPressed: sel != null && sel.status == SpotStatus.free
                    ? _reserveSelected
                    : null,
                child: const Text('Réserver'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}