import 'dart:math' as math;
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
      {this.width = 2.5, this.length = 5, this.angle = 0, this.status = SpotStatus.free});
  final String id;
  final Offset center;
  final double width, length, angle;
  SpotStatus status;
  List<Offset> get corners => rectCorners(center, width, length, angle);
}

class Road {
  const Road(this.a, this.b, this.width);
  final Offset a, b;
  final double width;
  List<Offset> get corners {
    final d = b - a;
    final n = Offset(-d.dy, d.dx) / d.distance * (width / 2);
    return [a + n, b + n, b - n, a - n];
  }
}

class Building {
  const Building(this.footprint, this.height, this.color);
  final List<Offset> footprint;
  final double height;
  final Color color;
}

// ───────────────────────── Données de démo ─────────────────────────

class ParkingDemoData {
  static const roads = [
    Road(Offset(-34, 0), Offset(34, 0), 6),
    Road(Offset(-34, 22), Offset(34, 22), 6),
  ];

  static final buildings = [
    Building(rectCorners(const Offset(-15, -17), 20, 12, 0), 14, const Color(0xFFB0BEC5)),
    Building(rectCorners(const Offset(14, -17), 16, 12, 0), 22, const Color(0xFF90A4AE)),
  ];

  static List<ParkingSpot> spots() {
    const rowsY = {'A': -5.5, 'B': 5.5, 'C': 16.5, 'D': 27.5};
    final list = <ParkingSpot>[];
    var r = 0;
    rowsY.forEach((name, y) {
      for (var i = 0; i < 23; i++) {
        final k = (i * 7 + r * 3) % 10;
        list.add(ParkingSpot(
          '$name${i + 1}',
          Offset(-28.6 + i * 2.6, y),
          status: k < 4
              ? SpotStatus.occupied
              : k == 4
                  ? SpotStatus.reserved
                  : SpotStatus.free,
        ));
      }
      r++;
    });
    return list;
  }
}

// ───────────────────────── Caméra (projection 3D → 2D) ─────────────────────────

class MapCamera {
  Offset center = Offset.zero; // point du monde (en mètres) au centre de l'écran
  double rotation = 0; // rotation autour de l'axe vertical (radians)
  double tilt; // 0 = vue du dessus, ~1.2 = très inclinée
  double zoom = 8; // pixels par mètre
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

  /// Distance à la caméra (sert au tri : loin → près).
  double dist(Offset p, [double z = 0]) => _transform(p, z).dist;

  Path polygon(List<Offset> pts, [double z = 0]) =>
      Path()..addPolygon(pts.map((e) => project(e, z)).toList(), true);

  void reset() {
    center = Offset.zero;
    rotation = 0;
    tilt = initialTilt;
    zoom = 8;
  }
}

// ───────────────────────── Peinture ─────────────────────────

class _Box {
  _Box(this.footprint, this.height, this.color);
  final List<Offset> footprint;
  final double height;
  final Color color;
  Offset get centroid =>
      footprint.fold(Offset.zero, (a, b) => a + b) / footprint.length.toDouble();
}

class ParkingPainter extends CustomPainter {
  ParkingPainter(this.cam, this.roads, this.buildings, this.spots, this.selected);
  final MapCamera cam;
  final List<Road> roads;
  final List<Building> buildings;
  final List<ParkingSpot> spots;
  final ParkingSpot? selected;

  static const _carColors = [
    Color(0xFF455A64), Color(0xFF1565C0), Color(0xFF6D4C41),
    Color(0xFF8E24AA), Color(0xFFBDBDBD), Color(0xFF2E7D32),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    // Sol
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFFDDE3E8));
    canvas.drawPath(
      cam.polygon(rectCorners(const Offset(0, 6), 90, 70, 0)),
      Paint()..color = const Color(0xFFC8E6C9),
    );

    // Routes + ligne centrale en pointillés
    final roadPaint = Paint()..color = const Color(0xFF546E7A);
    final lane = Paint()
      ..color = Colors.white
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    for (final r in roads) {
      canvas.drawPath(cam.polygon(r.corners), roadPaint);
      final len = (r.b - r.a).distance;
      final dir = (r.b - r.a) / len;
      for (double t = 0; t < len; t += 4) {
        canvas.drawLine(cam.project(r.a + dir * t),
            cam.project(r.a + dir * math.min(t + 2, len)), lane);
      }
    }

    // Places
    for (final s in spots) {
      final color = switch (s.status) {
        SpotStatus.free => const Color(0xFF66BB6A),
        SpotStatus.occupied => const Color(0xFFEF5350),
        SpotStatus.reserved => const Color(0xFFFFA726),
      };
      final path = cam.polygon(s.corners);
      canvas.drawPath(path, Paint()..color = color.withValues(alpha: 0.55));
      canvas.drawPath(
        path,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }

    // Objets extrudés (bâtiments + voitures), triés du plus loin au plus proche
    final items = <_Box>[
      for (final b in buildings) _Box(b.footprint, b.height, b.color),
      for (final s in spots)
        if (s.status == SpotStatus.occupied)
          _Box(rectCorners(s.center, s.width * 0.78, s.length * 0.8, s.angle), 1.5,
              _carColors[s.id.hashCode.abs() % _carColors.length]),
    ]..sort((a, b) => cam.dist(b.centroid).compareTo(cam.dist(a.centroid)));
    for (final b in items) {
      _drawBox(canvas, b);
    }

    // Sélection (au-dessus de tout)
    final sel = selected;
    if (sel != null) {
      final path = cam.polygon(sel.corners);
      canvas.drawPath(path, Paint()..color = Colors.blue.withValues(alpha: 0.35));
      canvas.drawPath(
        path,
        Paint()
          ..color = Colors.blueAccent
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
    }
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
      final shade = Color.lerp(b.color, Colors.black, 0.15 + 0.12 * (i % 2))!;
      canvas.drawPath(side, Paint()..color = shade);
    }
    // Toit
    canvas.drawPath(cam.polygon(fp, b.height),
        Paint()..color = Color.lerp(b.color, Colors.white, 0.2)!);
  }

  @override
  bool shouldRepaint(covariant ParkingPainter old) => true;
}

// ───────────────────────── Contrôleur (optionnel) ─────────────────────────

/// Permet au parent de piloter la vue (ex. bouton « réinitialiser » dans son AppBar).
class ParkingMapController {
  VoidCallback? _onReset;
  void resetView() => _onReset?.call();
}

// ───────────────────────── Composant ─────────────────────────

class ParkingMapView extends StatefulWidget {
  const ParkingMapView({
    super.key,
    required this.spots,
    this.roads = const [],
    this.buildings = const [],
    this.controller,
    this.initialTilt = 0.9,
    this.showSelectionCard = true,
    this.onSpotSelected,
    this.onReserve,
  });

  /// Places à afficher (mutables : `status` est modifié si [onReserve] est null).
  final List<ParkingSpot> spots;
  final List<Road> roads;
  final List<Building> buildings;
  final ParkingMapController? controller;
  final double initialTilt;
  final bool showSelectionCard;

  /// Appelé à chaque sélection (null quand on tape dans le vide).
  final ValueChanged<ParkingSpot?>? onSpotSelected;

  /// Appelé quand l'utilisateur appuie sur « Réserver ».
  /// Si null, la place passe simplement en `reserved` en local.
  final ValueChanged<ParkingSpot>? onReserve;

  @override
  State<ParkingMapView> createState() => _ParkingMapViewState();
}

class _ParkingMapViewState extends State<ParkingMapView> {
  late final MapCamera cam = MapCamera(initialTilt: widget.initialTilt);
  ParkingSpot? selected;
  double _startZoom = 1, _startRot = 0;
  Offset _lastFocal = Offset.zero;

  @override
  void initState() {
    super.initState();
    widget.controller?._onReset = _resetView;
  }

  @override
  void didUpdateWidget(covariant ParkingMapView old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller?._onReset = null;
      widget.controller?._onReset = _resetView;
    }
    if (selected != null && !widget.spots.contains(selected)) selected = null;
  }

  @override
  void dispose() {
    widget.controller?._onReset = null;
    super.dispose();
  }

  void _resetView() => setState(cam.reset);

  void _onScaleStart(ScaleStartDetails d) {
    _startZoom = cam.zoom;
    _startRot = cam.rotation;
    _lastFocal = d.localFocalPoint;
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    setState(() {
      cam.zoom = (_startZoom * d.scale).clamp(3.0, 40.0);
      cam.rotation = _startRot + d.rotation;

      // Déplacement : on convertit le glissement écran en déplacement monde
      final delta = d.localFocalPoint - _lastFocal;
      _lastFocal = d.localFocalPoint;
      final sx = delta.dx / cam.zoom;
      final sy = delta.dy / (cam.zoom * math.max(math.cos(cam.tilt), 0.3));
      final c = math.cos(cam.rotation), s = math.sin(cam.rotation);
      final wx = sx * c + sy * s;
      final wy = -sx * s + sy * c;
      cam.center -= Offset(wx, wy);
    });
  }

  void _onTapUp(TapUpDetails d) {
    ParkingSpot? best;
    var bestDist = double.infinity;
    for (final s in widget.spots) {
      final hit = cam.polygon(s.corners).contains(d.localPosition) ||
          (s.status == SpotStatus.occupied &&
              cam.polygon(s.corners, 1.5).contains(d.localPosition));
      if (hit) {
        final dist = cam.dist(s.center);
        if (dist < bestDist) {
          bestDist = dist;
          best = s;
        }
      }
    }
    setState(() => selected = best);
    widget.onSpotSelected?.call(best);
  }

  void _reserve(ParkingSpot spot) {
    if (widget.onReserve != null) {
      widget.onReserve!(spot);
    } else {
      spot.status = SpotStatus.reserved;
    }
    setState(() {});
  }

  String _label(SpotStatus s) => switch (s) {
        SpotStatus.free => 'Libre',
        SpotStatus.occupied => 'Occupée',
        SpotStatus.reserved => 'Réservée',
      };

  @override
  Widget build(BuildContext context) {
    final sel = selected;
    return Stack(children: [
      LayoutBuilder(builder: (context, c) {
        cam.viewport = c.biggest;
        return GestureDetector(
          onScaleStart: _onScaleStart,
          onScaleUpdate: _onScaleUpdate,
          onTapUp: _onTapUp,
          child: ClipRect(
            child: CustomPaint(
              size: Size.infinite,
              painter: ParkingPainter(
                  cam, widget.roads, widget.buildings, widget.spots, selected),
            ),
          ),
        );
      }),
      if (widget.showSelectionCard && sel != null)
        Positioned(
          left: 12,
          right: 12,
          bottom: 12,
          child: SafeArea(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (widget.showSelectionCard && sel != null)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.local_parking),
                    title: Text('Place ${sel.id}'),
                    subtitle: Text(_label(sel.status)),
                    trailing: sel.status == SpotStatus.free
                        ? FilledButton(
                            onPressed: () => _reserve(sel),
                            child: const Text('Réserver'),
                          )
                        : null,
                  ),
                ),
            ]),
          ),
        ),
    ]);
  }
}
