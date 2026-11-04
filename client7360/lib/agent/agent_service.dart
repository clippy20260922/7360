import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ChangeNotifier;
import 'package:flutter/material.dart' show IconData, Icons;
import 'package:http/http.dart' as http;

import '../parking_map_page.dart' show ParkingService, buildDemoParkingData;
import '../parking_map_view.dart';
import 'agent_models.dart';

// ───────────────────────── Connexion ─────────────────────────

class AgentAuthException implements Exception {
  AgentAuthException(this.message);
  final String message;
  @override
  String toString() => message;
}

// ───────────────────────── Statistiques ─────────────────────────

class CategoryStat {
  const CategoryStat(this.label, this.icon, this.occupied, this.total);
  final String label;
  final IconData icon;
  final int occupied, total;
  double get rate => total == 0 ? 0 : occupied / total;
}

class AgentStats {
  const AgentStats({
    required this.total,
    required this.occupied,
    required this.free,
    required this.reserved,
    required this.compliant,
    required this.expiring,
    required this.overtime,
    required this.unpaid,
    required this.avgOvertime,
    required this.buckets,
    required this.categories,
    required this.lotsTotal,
    required this.lotsFull,
  });

  factory AgentStats.compute(
    List<SlotInfo> slots,
    List<ParkingSpot> mapSpots,
    DateTime now,
  ) {
    var occupied = 0, reserved = 0, ok = 0, expiring = 0;
    var overtime = 0, unpaid = 0;
    var overtimeTotal = Duration.zero;
    // < 15 min, 15 min – 1 h, 1 h – 3 h, > 3 h, non payé
    final buckets = [0, 0, 0, 0, 0];

    for (final s in slots) {
      if (s.reserved) reserved++;
      if (!s.occupied) continue;
      occupied++;
      switch (s.complianceAt(now)) {
        case Compliance.ok:
          ok++;
        case Compliance.expiringSoon:
          expiring++;
        case Compliance.overtime:
          overtime++;
          final overdue = s.overtimeAt(now);
          overtimeTotal += overdue;
          final m = overdue.inMinutes;
          buckets[m < 15
              ? 0
              : m < 60
                  ? 1
                  : m < 180
                      ? 2
                      : 3]++;
        case Compliance.unpaid:
          unpaid++;
          buckets[4]++;
        case Compliance.none:
          break;
      }
    }

    CategoryStat cat(String label, IconData icon, bool Function(SlotInfo) f) {
      final list = slots.where(f).toList();
      return CategoryStat(
          label, icon, list.where((s) => s.occupied).length, list.length);
    }

    final lots = mapSpots.where((s) => s.isLot).toList();
    return AgentStats(
      total: slots.length,
      occupied: occupied,
      free: slots.length - occupied - reserved,
      reserved: reserved,
      compliant: ok + expiring,
      expiring: expiring,
      overtime: overtime,
      unpaid: unpaid,
      avgOvertime: overtime == 0
          ? Duration.zero
          : Duration(seconds: overtimeTotal.inSeconds ~/ overtime),
      buckets: buckets,
      categories: [
        cat('Voitures', Icons.directions_car_rounded, (s) => s.type != 'moto'),
        cat('Motos', Icons.two_wheeler_rounded, (s) => s.type == 'moto'),
        cat('PMR', Icons.accessible_rounded, (s) => s.pmr),
        cat('Électriques', Icons.bolt_rounded, (s) => s.elec),
      ].where((c) => c.total > 0).toList(),
      lotsTotal: lots.length,
      lotsFull: lots.where((s) => s.status == SpotStatus.occupied).length,
    );
  }

  final int total, occupied, free, reserved;
  final int compliant, expiring, overtime, unpaid;
  final Duration avgOvertime;
  final List<int> buckets;
  final List<CategoryStat> categories;
  final int lotsTotal, lotsFull;

  int get violations => overtime + unpaid;
  double get occupancyRate => total == 0 ? 0 : occupied / total;

  /// Part des véhicules garés qui sont en règle (1 quand il n'y en a aucun).
  double get complianceRate => occupied == 0 ? 1 : compliant / occupied;
}

// ───────────────────────── Instantané ─────────────────────────

/// Tout ce que les trois onglets affichent, à un instant donné.
class AgentSnapshot {
  AgentSnapshot({
    required this.map,
    required this.slots,
    required this.mapIsDemo,
    required this.fetchedAt,
    this.error,
  }) : _byId = {for (final s in slots) s.id: s};

  final ParkingData map;
  final List<SlotInfo> slots;
  final bool mapIsDemo;
  final DateTime fetchedAt; // UTC
  final String? error;
  final Map<String, SlotInfo> _byId;

  SlotInfo? slotById(String id) => _byId[id];

  /// Stationnements non réglementaires, les plus graves d'abord.
  late final List<SlotInfo> violations = () {
    double gravity(SlotInfo s) => s.complianceAt(fetchedAt) == Compliance.unpaid
        ? 1e9
        : s.overtimeAt(fetchedAt).inSeconds.toDouble();
    return slots.where((s) => s.complianceAt(fetchedAt).isViolation).toList()
      ..sort((a, b) => gravity(b).compareTo(gravity(a)));
  }();

  late final AgentStats stats =
      AgentStats.compute(slots, map.spots, fetchedAt);
}

// ───────────────────────── Service ─────────────────────────

class AgentService {
  static const _timeout = Duration(seconds: 10);

  /// Identifiant de l'agent connecté (null = pas connecté).
  static String? agentId;

  /// POST /token (formulaire OAuth2). Lève [AgentAuthException] si refusé ;
  /// toute autre exception = serveur injoignable.
  static Future<void> login(String username, String password) async {
    final res = await http
        .post(
          Uri.parse('${ParkingService.baseUrl}/token'),
          body: {'username': username, 'password': password},
        )
        .timeout(_timeout);

    if (res.statusCode == 200) {
      agentId = username;
      return;
    }
    var message = 'Identifiant ou mot de passe incorrect.';
    try {
      final detail = (jsonDecode(res.body) as Map<String, dynamic>)['detail'];
      if (detail is String && detail.isNotEmpty) message = detail;
    } catch (_) {}
    throw AgentAuthException(message);
  }

  static void logout() => agentId = null;

  /// Charge le plan (GET /parking) et les fiches de places (GET /data).
  /// Chaque morceau manquant est remplacé par des données de démonstration,
  /// sans jamais lever d'exception.
  static Future<AgentSnapshot> load() async {
    ParkingData map;
    var mapIsDemo = false;
    String? error;
    try {
      map = await ParkingService.fetch();
      if (map.spots.isEmpty && map.roads.isEmpty && map.buildings.isEmpty) {
        throw Exception('plan vide');
      }
    } catch (e) {
      map = buildDemoParkingData();
      mapIsDemo = true;
      error = e.toString().replaceFirst('Exception: ', '');
    }

    var rows = <SlotInfo>[];
    try {
      rows = await _fetchSlots();
    } catch (_) {
      // Les fiches manquantes sont simulées plus bas.
    }

    final mapIds = {for (final s in map.spots) s.id: s};
    // Avec un vrai plan, toute ligne de la base compte (même hors plan).
    // Avec le plan de démo, on ne garde que les lignes qui y figurent.
    final slots = <SlotInfo>[
      for (final r in rows)
        if (!mapIsDemo || mapIds.containsKey(r.id)) r,
    ];
    final known = {for (final s in slots) s.id};

    // La carte et les fiches doivent raconter la même chose.
    for (final s in slots) {
      final spot = mapIds[s.id];
      if (spot != null && !spot.isLot && spot.status != SpotStatus.reserved) {
        spot.status = s.occupied ? SpotStatus.occupied : SpotStatus.free;
      }
    }

    final epoch = _epoch;
    for (final spot in map.spots) {
      if (spot.isLot || known.contains(spot.id)) continue;
      slots.add(_simulate(spot, epoch));
    }

    return AgentSnapshot(
      map: map,
      slots: slots,
      mapIsDemo: mapIsDemo,
      fetchedAt: DateTime.now().toUtc(),
      error: error,
    );
  }

  static Future<List<SlotInfo>> _fetchSlots() async {
    final res = await http
        .get(Uri.parse('${ParkingService.baseUrl}/data'))
        .timeout(_timeout);
    if (res.statusCode != 200) {
      throw Exception('Erreur serveur (${res.statusCode})');
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final rows = body['data'] as List<dynamic>? ?? const [];
    return [
      for (final r in rows)
        if (r is List && r.length >= 12) SlotInfo.fromRow(r),
    ];
  }

  // ───────── Données simulées (mode démo) ─────────

  static final DateTime _epoch = DateTime.now().toUtc();

  static SlotInfo _simulate(ParkingSpot spot, DateTime epoch) {
    var h = 17;
    for (final c in spot.id.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    final r = math.Random(h);
    final isMoto = spot.width < 1.5;
    final occupied = spot.status == SpotStatus.occupied;

    DateTime? end;
    if (occupied) {
      final roll = r.nextInt(100);
      if (roll < 60) {
        end = epoch.add(Duration(minutes: 45 + r.nextInt(430))); // en règle
      } else if (roll < 68) {
        end = epoch.add(Duration(minutes: 3 + r.nextInt(6))); // expire bientôt
      } else if (roll < 90) {
        end = epoch.subtract(Duration(minutes: 5 + r.nextInt(200))); // retard
      } // sinon : aucun paiement
    }

    const letters = 'ABCDEFGHJKLMNPQRSTVWXYZ';
    String l() => letters[r.nextInt(letters.length)];
    return SlotInfo(
      id: spot.id,
      type: isMoto ? 'moto' : 'voit',
      pmr: r.nextInt(100) < 6,
      elec: r.nextInt(100) < 8,
      occupied: occupied,
      reserved: spot.status == SpotStatus.reserved,
      address: 'Plan de démonstration',
      tariff: isMoto ? 0.8 : 1.2 + (h % 5) * 0.4,
      plate: occupied ? '${l()}${l()}-${100 + r.nextInt(900)}-${l()}${l()}' : null,
      owner: occupied ? 'usager${1000 + r.nextInt(9000)}' : null,
      endsAt: end,
      simulated: true,
    );
  }
}

// ───────────────────────── Contrôleur partagé par les onglets ─────────────────────────

class AgentController extends ChangeNotifier {
  AgentSnapshot? snapshot;
  bool loading = true;
  final List<double> occupancyHistory = [];

  Timer? _timer;
  bool _busy = false;
  bool _disposed = false;

  void start() {
    refresh();
    _timer = Timer.periodic(const Duration(seconds: 8), (_) => refresh());
  }

  Future<void> refresh() async {
    if (_busy) return;
    _busy = true;
    try {
      final s = await AgentService.load();
      if (_disposed) return;
      snapshot = s;
      loading = false;
      occupancyHistory.add(s.stats.occupancyRate);
      if (occupancyHistory.length > 30) occupancyHistory.removeAt(0);
      notifyListeners();
    } finally {
      _busy = false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}
