import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show ChangeNotifier;
import 'package:flutter/material.dart' show IconData, Icons;
import 'package:http/http.dart' as http;

import '../parking_map_page.dart' show ParkingService;
import '../parking_map_view.dart';
import 'agent_fines.dart';
import 'agent_models.dart';
import 'agent_reports.dart';

// ───────────────────────── Erreurs ─────────────────────────

/// Identifiants refusés (ou compte qui n'est pas un compte agent).
class AgentAuthException implements Exception {
  AgentAuthException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Réponse d'erreur du serveur (avec son message `detail`).
class AgentApiException implements Exception {
  AgentApiException(this.message);
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

/// Tout ce que les onglets affichent, à un instant donné.
class AgentSnapshot {
  AgentSnapshot({
    required this.map,
    required this.slots,
    required this.fetchedAt,
  }) : _byId = {for (final s in slots) s.id: s};

  final ParkingData map;
  final List<SlotInfo> slots;
  final DateTime fetchedAt; // heure du serveur, en UTC
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

// ───────────────────────── Service (appels au serveur) ─────────────────────────

class AgentService {
  static const _timeout = Duration(seconds: 10);
  static const _jsonHeaders = {'Content-Type': 'application/json'};

  static String get _base => ParkingService.baseUrl;

  /// Identifiant de l'agent connecté (null = pas connecté).
  static String? agentId;

  // Gardé en mémoire le temps de la session : le serveur retient « qui est
  // connecté » en un seul exemplaire, donc s'il redémarre (ou si quelqu'un
  // d'autre se connecte) on se reconnecte tout seul.
  static String? _password;

  /// Écart entre l'horloge du serveur et celle de l'appareil.
  static Duration _clockOffset = Duration.zero;

  /// Cale l'horloge sur celle du serveur (utilisé aussi par le côté usager).
  static void syncClock(DateTime serverNow) {
    _clockOffset = serverNow.difference(DateTime.now().toUtc());
  }

  /// Message `detail` d'une réponse d'erreur du serveur.
  static String errorDetail(http.Response res, String fallback) =>
      _detail(res, fallback);

  /// Vrai quand le serveur ne nous reconnaît plus (il faut se reconnecter).
  static bool needsLogin(http.Response res) => _needsLogin(res);

  /// Maintenant, à l'heure du serveur (UTC).
  static DateTime now() => DateTime.now().toUtc().add(_clockOffset);

  /// POST /token (formulaire OAuth2). Renvoie le type du compte (`agent` ou
  /// `user`). Lève [AgentAuthException] si les identifiants sont refusés ;
  /// toute autre exception = serveur injoignable.
  static Future<String> authenticate(String username, String password) async {
    final res = await http
        .post(
          Uri.parse('$_base/token'),
          body: {'username': username, 'password': password},
        )
        .timeout(_timeout);
    if (res.statusCode != 200) {
      throw AgentAuthException(
          _detail(res, 'Identifiant ou mot de passe incorrect.'));
    }
    final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final type = body['type'] as String? ?? 'user';
    if (type == 'agent') {
      agentId = username;
      _password = password;
    } else {
      logout(); // on ne garde rien d'une ancienne session agent
    }
    return type;
  }

  /// Reconnexion d'un agent (réservé aux comptes de type agent).
  static Future<void> login(String username, String password) async {
    final type = await authenticate(username, password);
    if (type != 'agent') {
      throw AgentAuthException("Ce compte n'est pas un compte agent.");
    }
  }

  static void logout() {
    agentId = null;
    _password = null;
  }

  /// Message d'erreur lisible pour l'interface.
  static String describeError(Object e) {
    if (e is AgentAuthException) return e.message;
    if (e is AgentApiException) return e.message;
    return 'Serveur injoignable ($_base). Vérifiez qu\'il est lancé.';
  }

  static String _detail(http.Response res, String fallback) {
    try {
      final detail = (jsonDecode(utf8.decode(res.bodyBytes))
          as Map<String, dynamic>)['detail'];
      if (detail is String && detail.isNotEmpty) return detail;
    } catch (_) {}
    return fallback;
  }

  static bool _needsLogin(http.Response res) {
    if (res.statusCode == 403) return true;
    return res.statusCode == 400 &&
        _detail(res, '').startsWith('Authentifiez');
  }

  /// Envoie une requête d'agent ; si le serveur ne nous reconnaît plus, on
  /// se reconnecte puis on réessaie une fois.
  static Future<http.Response> _send(
      Future<http.Response> Function() request) async {
    var res = await request().timeout(_timeout);
    final id = agentId, pwd = _password;
    if (_needsLogin(res) && id != null && pwd != null) {
      await login(id, pwd);
      res = await request().timeout(_timeout);
    }
    return res;
  }

  static Map<String, dynamic> _json(http.Response res, String errorMessage) {
    if (res.statusCode != 200) {
      throw AgentApiException(_detail(res, '$errorMessage (${res.statusCode})'));
    }
    return jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
  }

  /// Charge le plan (GET /parking) et les places avec leur véhicule
  /// (GET /agent/slots).
  static Future<AgentSnapshot> load() async {
    final mapRes = await http.get(Uri.parse('$_base/parking')).timeout(_timeout);
    final map = ParkingData.fromJson(_json(mapRes, 'Plan indisponible'));

    final res = await _send(() => http.get(Uri.parse('$_base/agent/slots')));
    final body = _json(res, 'Places indisponibles');

    final serverNow = parseServerTime(body['now'] as String?, keepOldDates: true);
    if (serverNow != null) syncClock(serverNow);
    return AgentSnapshot(
      map: map,
      slots: [
        for (final r in (body['data'] as List? ?? const []))
          SlotInfo.fromJson(r as Map<String, dynamic>),
      ],
      fetchedAt: now(),
    );
  }

  /// GET /agent/infractions : la liste déroulante des contraventions.
  static Future<List<Offense>> fetchOffenses() async {
    final res =
        await _send(() => http.get(Uri.parse('$_base/agent/infractions')));
    final body = _json(res, 'Infractions indisponibles');
    return [
      for (final o in (body['data'] as List? ?? const []))
        Offense.fromJson(o as Map<String, dynamic>),
    ];
  }

  /// GET /agent/fines : les contraventions, les plus récentes d'abord.
  static Future<List<Fine>> fetchFines() async {
    final res = await _send(() => http.get(Uri.parse('$_base/agent/fines')));
    final body = _json(res, 'Contraventions indisponibles');
    return [
      for (final f in (body['data'] as List? ?? const []))
        Fine.fromJson(f as Map<String, dynamic>),
    ];
  }

  /// GET /agent/reports : les signalements (à traiter d'abord).
  static Future<List<Report>> fetchReports() async {
    final res = await _send(() => http.get(Uri.parse('$_base/agent/reports')));
    final body = _json(res, 'Signalements indisponibles');
    return [
      for (final r in (body['data'] as List? ?? const []))
        Report.fromJson(r as Map<String, dynamic>),
    ];
  }

  /// GET /agent/vehicles/{plaque} : propriétaire connu ou non.
  static Future<VehicleInfo> lookupVehicle(String plate) async {
    final res =
        await _send(() => http.get(Uri.parse('$_base/agent/vehicles/$plate')));
    return VehicleInfo.fromJson(
        _json(res, 'Recherche impossible')['data'] as Map<String, dynamic>);
  }

  /// Valide un signalement : la place est assignée au véhicule depuis
  /// l'heure du signalement, sans paiement.
  static Future<void> validateReport(int id, {String? plate}) async {
    final res = await _send(() => http.post(
          Uri.parse('$_base/agent/reports/$id/validate'),
          headers: _jsonHeaders,
          body: jsonEncode({'plate': plate}),
        ));
    _json(res, 'Validation refusée');
  }

  static Future<void> dismissReport(int id) async {
    final res = await _send(
        () => http.post(Uri.parse('$_base/agent/reports/$id/dismiss')));
    _json(res, 'Rejet refusé');
  }

  /// Assigne directement une place libre à un véhicule (à partir de maintenant).
  static Future<void> assignSlot(String slotId, String plate) async {
    final id = int.tryParse(slotId);
    if (id == null) throw AgentApiException('Place invalide ($slotId)');
    final res = await _send(() => http.post(
          Uri.parse('$_base/agent/slots/$id/assign'),
          headers: _jsonHeaders,
          body: jsonEncode({'plate': plate}),
        ));
    _json(res, 'Assignation refusée');
  }

  /// POST /agent/fines : dresse une contravention (l'agent, le montant, le
  /// lieu… sont complétés par le serveur).
  static Future<Fine> createFine({
    required String slotId,
    required String offenseCode,
    String? plate,
    String? comment,
  }) async {
    final id = int.tryParse(slotId);
    if (id == null) throw AgentApiException('Place invalide ($slotId)');
    final res = await _send(() => http.post(
          Uri.parse('$_base/agent/fines'),
          headers: _jsonHeaders,
          body: jsonEncode({
            'slot_id': id,
            'offense': offenseCode,
            'plate': plate,
            'comment': comment,
          }),
        ));
    final body = _json(res, 'Contravention refusée');
    return Fine.fromJson(body['data'] as Map<String, dynamic>);
  }
}

// ───────────────────────── Contrôleur partagé par les onglets ─────────────────────────

class AgentController extends ChangeNotifier {
  AgentController({this.agentId = 'agent'});

  /// Identifiant de l'agent connecté.
  final String agentId;

  AgentSnapshot? snapshot;
  List<Offense> offenses = [];
  List<Fine> fines = []; // les plus récentes d'abord
  List<Report> reports = []; // signalements (à traiter d'abord)
  final List<double> occupancyHistory = [];

  bool loading = true;

  /// Dernière erreur de chargement (null quand tout va bien). Si on a déjà
  /// des données, elles restent affichées.
  String? error;

  Timer? _timer;
  bool _busy = false;
  bool _disposed = false;

  // Signalements arrivés depuis le dernier chargement (pour avertir l'agent)
  final Set<int> _knownReports = {};
  final List<Report> _newReports = [];
  bool _firstLoadDone = false;

  List<Report> get pendingReports =>
      reports.where((r) => r.isPending).toList();

  /// Les signalements apparus depuis la dernière fois (et on les vide).
  List<Report> takeNewReports() {
    final list = List<Report>.from(_newReports);
    _newReports.clear();
    return list;
  }

  /// Rafraîchit juste après une action de l'agent.
  Future<void> _refreshAfterAction() async {
    var waited = 0;
    while (_busy && waited++ < 50) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    await refresh();
  }

  void start() {
    refresh();
    _timer = Timer.periodic(const Duration(seconds: 8), (_) => refresh());
  }

  Future<void> refresh() async {
    if (_busy) return;
    _busy = true;
    try {
      final s = await AgentService.load();
      final f = await AgentService.fetchFines();
      final rep = await AgentService.fetchReports();
      if (offenses.isEmpty) offenses = await AgentService.fetchOffenses();
      if (_disposed) return;
      snapshot = s;
      fines = f;
      for (final r in rep) {
        if (_knownReports.add(r.id) && _firstLoadDone && r.isPending) {
          _newReports.add(r);
        }
      }
      _firstLoadDone = true;
      reports = rep;
      error = null;
      occupancyHistory.add(s.stats.occupancyRate);
      if (occupancyHistory.length > 30) occupancyHistory.removeAt(0);
    } catch (e) {
      error = AgentService.describeError(e);
    } finally {
      _busy = false;
      loading = false;
      if (!_disposed) notifyListeners();
    }
  }

  /// Contravention récente (moins de 12 h) déjà dressée pour cette place.
  Fine? recentFineFor(String slotId) {
    final now = AgentService.now();
    for (final f in fines) {
      if (f.slotId == slotId &&
          now.difference(f.issuedAt) < const Duration(hours: 12)) {
        return f;
      }
    }
    return null;
  }

  /// Dresse une contravention sur le serveur. Lève une exception (avec le
  /// message du serveur) si elle est refusée.
  Future<Fine> issueFine({
    required SlotInfo info,
    required Offense offense,
    required String plate,
    String? comment,
  }) async {
    final fine = await AgentService.createFine(
      slotId: info.id,
      offenseCode: offense.code,
      plate: plate,
      comment: comment,
    );
    fines = [fine, ...fines];
    if (!_disposed) notifyListeners();
    return fine;
  }

  // ───── Signalements et assignations ─────

  Future<void> validateReport(Report r, {String? plate}) async {
    await AgentService.validateReport(r.id, plate: plate);
    await _refreshAfterAction();
  }

  Future<void> dismissReport(Report r) async {
    await AgentService.dismissReport(r.id);
    await _refreshAfterAction();
  }

  Future<void> assignSlot(SlotInfo slot, String plate) async {
    await AgentService.assignSlot(slot.id, plate);
    await _refreshAfterAction();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}
