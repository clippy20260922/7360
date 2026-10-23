import 'dart:math' as math;
import 'package:flutter/gestures.dart' show PointerScrollEvent, PointerSignalEvent;
import 'package:flutter/material.dart';

// ───────────────────────── Modèles ─────────────────────────

enum SpotStatus { free, occupied, reserved }

List<Offset> rectCorners(Offset c, double w, double l, double angle) {
  final hw = w / 2, hl = l / 2;
  final ca = math.cos(angle), sa = math.sin(angle);
  return [Offset(-hw, -hl), Offset(hw, -hl), Offset(hw, hl), Offset(-hw, hl)]
      .map((p) => Offset(c.dx + p.dx * ca - p.dy * sa, c.dy + p.dx * sa + p.dy * ca))
      .toList();
}

class ParkingSpot {
  ParkingSpot(this.id, this.center,
      {this.width = 2.5,
      this.length = 5,
      this.angle = 0,
      this.status = SpotStatus.free,
      this.isLot = false});

  /// Format JSON attendu (à adapter à ton backend) :
  /// { "id": "A1", "x": -28.6, "y": -5.5, "width": 2.5, "length": 5,
  ///   "angle": 0, "status": "free" | "occupied" | "reserved",
  ///   "lot": true }   ← "lot" facultatif : true pour un parking (affiché en bleu)
  factory ParkingSpot.fromJson(Map<String, dynamic> j) => ParkingSpot(
        j['id'].toString(),
        Offset((j['x'] as num).toDouble(), (j['y'] as num).toDouble()),
        width: (j['width'] as num?)?.toDouble() ?? 2.5,
        length: (j['length'] as num?)?.toDouble() ?? 5,
        angle: (j['angle'] as num?)?.toDouble() ?? 0,
        status: SpotStatus.values.asNameMap()[j['status']] ?? SpotStatus.free,
        isLot: j['lot'] == true,
      );

  final String id;
  final Offset center;
  final double width, length, angle;
  SpotStatus status;

  /// true = parking (grande surface, affichée en bleu), false = place simple.
  final bool isLot;
  List<Offset> get corners => rectCorners(center, width, length, angle);
}

class Road {
  const Road(this.a, this.b, this.width, {this.name = ''});

  /// { "ax": -34, "ay": 0, "bx": 34, "by": 0, "width": 6 }
  factory Road.fromJson(Map<String, dynamic> j) => Road(
        Offset((j['ax'] as num).toDouble(), (j['ay'] as num).toDouble()),
        Offset((j['bx'] as num).toDouble(), (j['by'] as num).toDouble()),
        (j['width'] as num).toDouble(),
        name: j['name'] as String? ?? '',
      );

  final Offset a, b;
  final double width;
  final String name;
  List<Offset> get corners {
    final d = b - a;
    final n = Offset(-d.dy, d.dx) / d.distance * (width / 2);
    return [a + n, b + n, b - n, a - n];
  }
}

class Building {
  const Building(this.footprint, this.height, this.color);

  /// { "footprint": [ {"x": 0, "y": 0}, ... ], "height": 14, "color": 4289379013 }
  /// (color = entier ARGB, par ex. 0xFFB0BEC5 ; gris par défaut si absent)
  factory Building.fromJson(Map<String, dynamic> j) => Building(
        (j['footprint'] as List)
            .map((p) => Offset((p['x'] as num).toDouble(), (p['y'] as num).toDouble()))
            .toList(),
        (j['height'] as num).toDouble(),
        Color((j['color'] as num?)?.toInt() ?? 0xFFB0BEC5),
      );

  final List<Offset> footprint;
  final double height;
  final Color color;
}

enum ZoneKind { park, water }

/// Zone au sol (parc, plan d'eau) dessinée sous les routes.
class Zone {
  const Zone(this.kind, this.polygon);

  /// { "kind": "park" | "water", "polygon": [ {"x": 0, "y": 0}, ... ] }
  factory Zone.fromJson(Map<String, dynamic> j) => Zone(
        ZoneKind.values.asNameMap()[j['kind']] ?? ZoneKind.park,
        (j['polygon'] as List)
            .map((p) => Offset((p['x'] as num).toDouble(), (p['y'] as num).toDouble()))
            .toList(),
      );

  final ZoneKind kind;
  final List<Offset> polygon;
}

/// Ce que renvoie le backend : les listes ensemble (zones est facultatif).
class ParkingData {
  const ParkingData({
    this.spots = const [],
    this.roads = const [],
    this.buildings = const [],
    this.zones = const [],
  });

  /// { "spots": [...], "roads": [...], "buildings": [...], "zones": [...] }
  factory ParkingData.fromJson(Map<String, dynamic> j) => ParkingData(
        spots: (j['spots'] as List? ?? [])
            .map((e) => ParkingSpot.fromJson(e as Map<String, dynamic>))
            .toList(),
        roads: (j['roads'] as List? ?? [])
            .map((e) => Road.fromJson(e as Map<String, dynamic>))
            .toList(),
        buildings: (j['buildings'] as List? ?? [])
            .map((e) => Building.fromJson(e as Map<String, dynamic>))
            .toList(),
        zones: (j['zones'] as List? ?? [])
            .map((e) => Zone.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  final List<ParkingSpot> spots;
  final List<Road> roads;
  final List<Building> buildings;
  final List<Zone> zones;
}

// ───────────────────────── Caméra (projection 3D → 2D) ─────────────────────────

class MapCamera {
  Offset center = Offset.zero; // point du monde (en mètres) au centre de l'écran
  double rotation = 0; // rotation autour de l'axe vertical (radians)
  double tilt; // 0 = vue du dessus, ~1.2 = très inclinée
  double zoom = 1.4; // pixels par mètre : cadrage adapté au centre-ville
  Size viewport = Size.zero;
  static const double focal = 1400; // force de la perspective

  MapCamera({this.initialTilt = 0.9}) : tilt = initialTilt;
  final double initialTilt;

  ({double x, double y, double dist}) _transform(Offset p, double z) {
    final dx = (p.dx - center.dx) * zoom;
    final dy = (p.dy - center.dy) * zoom;
    final dz = z * zoom;
    final c = math.cos(rotation), s = math.sin(rotation);
    final x = dx * c - dy * s;
    final y = dx * s + dy * c;
    final yy = y * math.cos(tilt) - dz * math.sin(tilt);
    final dist = focal - y * math.sin(tilt) - dz * math.cos(tilt);
    return (x: x, y: yy, dist: dist);
  }

  /// Point du monde (x, y en mètres, z = hauteur) → position à l'écran.
  Offset project(Offset p, [double z = 0]) {
    final t = _transform(p, z);
    final k = focal / math.max(t.dist, 50);
    return Offset(viewport.width / 2 + t.x * k, viewport.height / 2 + t.y * k);
  }

  /// Vecteur monde (mètres, relatif au centre de la caméra) du point écran
  /// [s], au niveau du sol : l'inverse de [project] pour z = 0.
  Offset _groundOffset(Offset s) {
    final u = s.dx - viewport.width / 2;
    final v = s.dy - viewport.height / 2;
    final ct = math.cos(tilt), st = math.sin(tilt);
    final y = v * focal / (focal * ct + v * st);
    final x = u * (focal - y * st) / focal;
    final c = math.cos(rotation), sn = math.sin(rotation);
    return Offset(x * c + y * sn, -x * sn + y * c) / zoom;
  }

  /// Point du monde situé sous le point écran [s].
  Offset unproject(Offset s) => center + _groundOffset(s);

  /// Recentre la caméra pour que le point monde [world] soit sous le point
  /// écran [screen] (sert à zoomer / tourner autour des doigts).
  void anchor(Offset world, Offset screen) => center = world - _groundOffset(screen);

  /// Distance à la caméra (sert au tri : loin → près).
  double dist(Offset p, [double z = 0]) => _transform(p, z).dist;

  Path polygon(List<Offset> pts, [double z = 0]) =>
      Path()..addPolygon(pts.map((e) => project(e, z)).toList(), true);

  void reset() {
    center = Offset.zero;
    rotation = 0;
    tilt = initialTilt;
    zoom = 1.4;
  }
}

// ───────────────────────── Peinture ─────────────────────────

class _Box {
  _Box(this.footprint, this.height);
  final List<Offset> footprint;
  final double height;
  Offset get centroid =>
      footprint.fold(Offset.zero, (a, b) => a + b) / footprint.length.toDouble();
}

class ParkingPainter extends CustomPainter {
  ParkingPainter(this.cam, this.roads, this.buildings, this.spots, this.selected,
      {this.zones = const []});
  final MapCamera cam;
  final List<Road> roads;
  final List<Building> buildings;
  final List<ParkingSpot> spots;
  final List<Zone> zones;
  final ParkingSpot? selected;

  // Palette claire inspirée de Waze / Google Maps.
  static const _land = Color(0xFFF2F0EB);
  static const _parkFill = Color(0xFFCDE8C0);
  static const _parkEdge = Color(0xFFB5D8A6);
  static const _waterFill = Color(0xFFA9D3F2);
  static const _minorFill = Color(0xFFFFFFFF);
  static const _minorCasing = Color(0xFFCDD1D6);
  static const _mainFill = Color(0xFFFFF3C4);
  static const _mainCasing = Color(0xFFE6C56A);
  static const _roof = Color(0xFFE6E2DA);
  static const _wallLight = Color(0xFFCFCAC0);
  static const _wallDark = Color(0xFFC3BEB4);
  static const _buildingEdge = Color(0xFFBDB8AE);
  static const _accent = Color(0xFF33CCFF);

  /// Les axes larges sont dessinés en jaune, les petites rues en blanc.
  static bool _isMain(Road r) => r.width >= 6.5;

  @override
  void paint(Canvas canvas, Size size) {
    // Sol
    canvas.drawRect(Offset.zero & size, Paint()..color = _land);

    // Parcs et plans d'eau
    for (final z in zones) {
      final path = cam.polygon(z.polygon);
      final isPark = z.kind == ZoneKind.park;
      canvas.drawPath(path, Paint()..color = isPark ? _parkFill : _waterFill);
      if (isPark) {
        canvas.drawPath(
          path,
          Paint()
            ..color = _parkEdge
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2,
        );
      }
    }

    // Routes : d'abord tous les contours, puis tous les remplissages,
    // pour que les carrefours soient propres (comme sur Waze).
    final minor = [for (final r in roads) if (!_isMain(r)) r];
    final main = [for (final r in roads) if (_isMain(r)) r];
    _drawRoads(canvas, minor, 1.6, _minorCasing);
    _drawRoads(canvas, main, 2.0, _mainCasing);
    _drawRoads(canvas, minor, 0, _minorFill);
    _drawRoads(canvas, main, 0, _mainFill);

    // Noms des rues (si le backend en fournit).
    final paintedNames = <String>{};
    for (final r in roads) {
      if (r.name.isEmpty || !paintedNames.add(r.name)) continue;
      final label = TextPainter(
        text: TextSpan(
          text: r.name,
          style: const TextStyle(
            color: Color(0xFF5F6368),
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout(maxWidth: 150);
      final p = cam.project((r.a + r.b) / 2);
      label.paint(canvas, Offset(p.dx - label.width / 2, p.dy - label.height / 2));
    }

    // Places et parkings. Les petites places hors écran sont ignorées.
    final view = (Offset.zero & size).inflate(120);
    for (final s in spots) {
      if (!s.isLot && !view.contains(cam.project(s.center))) continue;
      final Color color;
      if (s.isLot) {
        // Parkings : bleu (plus pâle quand ils sont pleins)
        color = s.status == SpotStatus.occupied
            ? const Color(0xFF9DB4D6)
            : const Color(0xFF1E6FE8);
      } else {
        color = switch (s.status) {
          SpotStatus.free => const Color(0xFF34C759),
          SpotStatus.occupied => const Color(0xFFFF5A5F),
          SpotStatus.reserved => const Color(0xFFFFB020),
        };
      }
      final path = cam.polygon(s.corners);
      canvas.drawPath(
          path, Paint()..color = color.withValues(alpha: s.isLot ? 0.9 : 0.85));
      canvas.drawPath(
        path,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = s.isLot ? 2 : 1.2,
      );
      if (s.isLot) {
        final fontSize = (math.min(s.width, s.length) * cam.zoom * 0.5).clamp(10.0, 40.0);
        final text = TextPainter(
          text: TextSpan(
            text: 'P',
            style: TextStyle(
                color: Colors.white,
                fontSize: fontSize,
                fontWeight: FontWeight.w800),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        final c = cam.project(s.center);
        text.paint(canvas, c - Offset(text.width / 2, text.height / 2));
      }
    }

    // Bâtiments extrudés, triés du plus loin au plus proche.
    // Ceux qui sont hors de l'écran ne sont pas dessinés (beaucoup de bâtiments).
    final items = <_Box>[
      for (final b in buildings) _Box(b.footprint, b.height),
    ].where((b) => _isVisible(b, view)).toList()
      ..sort((a, b) => cam.dist(b.centroid).compareTo(cam.dist(a.centroid)));
    for (final b in items) {
      _drawBox(canvas, b);
    }

    // Sélection (au-dessus de tout)
    final sel = selected;
    if (sel != null) {
      final path = cam.polygon(sel.corners);
      canvas.drawPath(path, Paint()..color = _accent.withValues(alpha: 0.35));
      canvas.drawPath(
        path,
        Paint()
          ..color = _accent
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
      _drawPin(canvas, cam.project(sel.center));
    }
  }

  void _drawRoads(Canvas canvas, List<Road> list, double extra, Color color) {
    final paint = Paint()..color = color;
    for (final r in list) {
      final d = r.b - r.a;
      final len = d.distance;
      if (len == 0) continue;
      final half = r.width / 2 + extra;
      final n = Offset(-d.dy, d.dx) / len * half;
      canvas.drawPath(cam.polygon([r.a + n, r.b + n, r.b - n, r.a - n]), paint);
      // Extrémités arrondies
      for (final p in [r.a, r.b]) {
        final c = cam.project(p);
        final radius = (cam.project(p + Offset(half, 0)) - c).distance;
        canvas.drawCircle(c, radius, paint);
      }
    }
  }

  bool _isVisible(_Box b, Rect view) {
    var minX = double.infinity, minY = double.infinity;
    var maxX = -double.infinity, maxY = -double.infinity;
    for (final p in b.footprint) {
      for (final q in [cam.project(p), cam.project(p, b.height)]) {
        if (q.dx < minX) minX = q.dx;
        if (q.dx > maxX) maxX = q.dx;
        if (q.dy < minY) minY = q.dy;
        if (q.dy > maxY) maxY = q.dy;
      }
    }
    return Rect.fromLTRB(minX, minY, maxX, maxY).overlaps(view);
  }

  void _drawBox(Canvas canvas, _Box b) {
    final fp = b.footprint;
    final n = fp.length;
    // Faces latérales, de la plus loin à la plus proche
    final order = List<int>.generate(n, (i) => i)
      ..sort((i, j) {
        final mi = (fp[i] + fp[(i + 1) % n]) / 2;
        final mj = (fp[j] + fp[(j + 1) % n]) / 2;
        return cam.dist(mj).compareTo(cam.dist(mi));
      });
    for (final i in order) {
      final a = fp[i], c = fp[(i + 1) % n];
      final side = Path()
        ..addPolygon([
          cam.project(a), cam.project(c),
          cam.project(c, b.height), cam.project(a, b.height),
        ], true);
      canvas.drawPath(side, Paint()..color = i.isEven ? _wallLight : _wallDark);
    }
    // Toit
    final roof = cam.polygon(fp, b.height);
    canvas.drawPath(roof, Paint()..color = _roof);
    canvas.drawPath(
      roof,
      Paint()
        ..color = _buildingEdge
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8,
    );
  }

  /// Épingle façon Waze au-dessus de la place sélectionnée.
  void _drawPin(Canvas canvas, Offset base) {
    const r = 13.0;
    final head = base - const Offset(0, 30);
    canvas.drawOval(
      Rect.fromCenter(center: base, width: 14, height: 5),
      Paint()..color = Colors.black26,
    );
    final tail = Path()
      ..moveTo(head.dx - r * 0.8, head.dy + r * 0.6)
      ..lineTo(base.dx, base.dy)
      ..lineTo(head.dx + r * 0.8, head.dy + r * 0.6)
      ..close();
    canvas.drawPath(tail, Paint()..color = _accent);
    canvas.drawCircle(head, r, Paint()..color = _accent);
    canvas.drawCircle(
      head,
      r,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
    final text = TextPainter(
      text: const TextSpan(
        text: 'P',
        style: TextStyle(
            color: Colors.white, fontSize: 14, fontWeight: FontWeight.w800),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    text.paint(canvas, head - Offset(text.width / 2, text.height / 2));
  }

  // Les listes sont remplacées à chaque refresh : on repeint toujours.
  @override
  bool shouldRepaint(covariant ParkingPainter old) => true;
}

// ───────────────────────── Contrôleur (optionnel) ─────────────────────────

/// Permet au parent de piloter la vue (bouton « réinitialiser », désélection…).
class ParkingMapController {
  VoidCallback? _onReset;
  VoidCallback? _onClearSelection;

  void resetView() => _onReset?.call();
  void clearSelection() => _onClearSelection?.call();
}

// ───────────────────────── Composant ─────────────────────────

class ParkingMapView extends StatefulWidget {
  const ParkingMapView({
    super.key,
    required this.spots,
    this.roads = const [],
    this.buildings = const [],
    this.zones = const [],
    this.controller,
    this.initialTilt = 0.9,
    this.onSpotSelected,
  });

  /// Listes à afficher. Quand le parent les remplace (nouveau `setState`
  /// avec de nouvelles listes), la vue se met à jour automatiquement.
  final List<ParkingSpot> spots;
  final List<Road> roads;
  final List<Building> buildings;
  final List<Zone> zones;
  final ParkingMapController? controller;
  final double initialTilt;

  /// Appelé à chaque sélection avec l'id de la place
  /// (null quand on tape dans le vide ou que la place a disparu).
  final ValueChanged<String?>? onSpotSelected;

  @override
  State<ParkingMapView> createState() => _ParkingMapViewState();
}

class _ParkingMapViewState extends State<ParkingMapView> {
  late final MapCamera cam = MapCamera(initialTilt: widget.initialTilt);

  // On garde l'id (et non l'objet) : à chaque refresh les ParkingSpot sont
  // de nouveaux objets, mais l'id reste le même, donc la sélection survit.
  String? _selectedId;
  double _startZoom = 1, _startRot = 0;
  Offset _anchorWorld = Offset.zero; // point du monde sous les doigts
  int _lastPointers = 0;

  ParkingSpot? get _selectedSpot {
    final id = _selectedId;
    if (id == null) return null;
    for (final s in widget.spots) {
      if (s.id == id) return s;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _attach(widget.controller);
  }

  @override
  void didUpdateWidget(covariant ParkingMapView old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      _detach(old.controller);
      _attach(widget.controller);
    }
    // La place sélectionnée n'existe plus dans la nouvelle liste
    if (_selectedId != null && _selectedSpot == null) {
      _selectedId = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onSpotSelected?.call(null);
      });
    }
  }

  @override
  void dispose() {
    _detach(widget.controller);
    super.dispose();
  }

  void _attach(ParkingMapController? c) {
    c?._onReset = _resetView;
    c?._onClearSelection = _clearSelection;
  }

  void _detach(ParkingMapController? c) {
    c?._onReset = null;
    c?._onClearSelection = null;
  }

  void _resetView() => setState(cam.reset);

  void _clearSelection() {
    if (_selectedId == null) return;
    setState(() => _selectedId = null);
    widget.onSpotSelected?.call(null);
  }

  void _onScaleStart(ScaleStartDetails d) {
    _lastPointers = d.pointerCount;
    _rebase(d.localFocalPoint);
  }

  /// Point de départ du geste : zoom / rotation actuels et point du monde
  /// qui se trouve sous les doigts (il y restera pendant tout le geste).
  void _rebase(Offset focal) {
    _startZoom = cam.zoom;
    _startRot = cam.rotation;
    _anchorWorld = cam.unproject(focal);
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    // Quand on pose ou lève un doigt, Flutter repart de scale = 1 / rotation = 0 :
    // on repart donc aussi de l'état actuel pour éviter un saut.
    if (d.pointerCount != _lastPointers) {
      _lastPointers = d.pointerCount;
      _rebase(d.localFocalPoint);
    }
    setState(() {
      cam.zoom = (_startZoom * d.scale).clamp(0.3, 40.0);
      cam.rotation = _startRot + d.rotation;
      // Déplacement + zoom + rotation autour des doigts
      cam.anchor(_anchorWorld, d.localFocalPoint);
    });
  }

  /// Molette de la souris (web / bureau) : zoom autour du curseur.
  void _onPointerSignal(PointerSignalEvent e) {
    if (e is! PointerScrollEvent) return;
    setState(() {
      final world = cam.unproject(e.localPosition);
      cam.zoom = (cam.zoom * math.exp(-e.scrollDelta.dy / 300)).clamp(0.3, 40.0);
      cam.anchor(world, e.localPosition);
    });
  }

  void _onTapUp(TapUpDetails d) {
    ParkingSpot? best;
    var bestDist = double.infinity;
    for (final s in widget.spots) {
      if (cam.polygon(s.corners).contains(d.localPosition)) {
        final dist = cam.dist(s.center);
        if (dist < bestDist) {
          bestDist = dist;
          best = s;
        }
      }
    }
    setState(() => _selectedId = best?.id);
    widget.onSpotSelected?.call(best?.id);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      cam.viewport = c.biggest;
      return Listener(
        onPointerSignal: _onPointerSignal,
        child: GestureDetector(
        onScaleStart: _onScaleStart,
        onScaleUpdate: _onScaleUpdate,
        onTapUp: _onTapUp,
        child: ClipRect(
          child: CustomPaint(
            size: Size.infinite,
            painter: ParkingPainter(
              cam,
              widget.roads,
              widget.buildings,
              widget.spots,
              _selectedSpot,
              zones: widget.zones,
            ),
          ),
        ),
        ),
      );
    });
  }
}