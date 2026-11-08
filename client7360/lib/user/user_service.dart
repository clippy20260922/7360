import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show ChangeNotifier;
import 'package:http/http.dart' as http;

import '../agent/agent_fines.dart';
import '../agent/agent_models.dart';
import '../agent/agent_service.dart';
import '../parking_map_page.dart' show ParkingService;
import '../parking_map_view.dart';
import 'user_models.dart';

// ───────────────────────── Instantané ─────────────────────────

/// Tout ce que les onglets de la carte et des réservations affichent.
class UserSnapshot {
  UserSnapshot({
    required this.map,
    required this.slots,
    required this.parkings,
    required this.reservations,
    required this.parked,
    required this.fetchedAt,
  })  : _slotsById = {for (final s in slots) s.id: s},
        _parkingsByName = {for (final p in parkings) p.name: p};

  final ParkingData map;
  final List<UserSlot> slots;
  final List<ParkingInfo> parkings;
  final List<Reservation> reservations;
  final List<ParkedVehicle> parked;
  final DateTime fetchedAt; // heure du serveur, UTC
  final Map<String, UserSlot> _slotsById;
  final Map<String, ParkingInfo> _parkingsByName;

  UserSlot? slotById(String id) => _slotsById[id];
  ParkingInfo? parkingByName(String name) => _parkingsByName[name];
}

// ───────────────────────── Service (appels au serveur) ─────────────────────────

class UserService {
  static const _timeout = Duration(seconds: 10);
  static const _jsonHeaders = {'Content-Type': 'application/json'};

  static String get _base => ParkingService.baseUrl;

  static String? username;
  // Gardé en mémoire le temps de la session, pour se reconnecter tout seul si
  // le serveur redémarre ou si quelqu'un d'autre s'y connecte.
  static String? _password;

  static void remember(String user, String password) {
    username = user;
    _password = password;
  }

  static void logout() {
    username = null;
    _password = null;
  }

  static Future<http.Response> _send(
      Future<http.Response> Function() request) async {
    var res = await request().timeout(_timeout);
    final u = username, p = _password;
    if (AgentService.needsLogin(res) && u != null && p != null) {
      await AgentService.authenticate(u, p);
      res = await request().timeout(_timeout);
    }
    return res;
  }

  static Map<String, dynamic> _json(http.Response res, String errorMessage) {
    if (res.statusCode != 200) {
      throw AgentApiException(
          AgentService.errorDetail(res, '$errorMessage (${res.statusCode})'));
    }
    return jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> _get(String path, String error) async =>
      _json(await _send(() => http.get(Uri.parse('$_base$path'))), error);

  static Future<Map<String, dynamic>> _post(String path, String error,
          {Object? body}) async =>
      _json(
        await _send(() => http.post(
              Uri.parse('$_base$path'),
              headers: _jsonHeaders,
              body: body == null ? null : jsonEncode(body),
            )),
        error,
      );

  static List<T> _list<T>(
          Map<String, dynamic> body, T Function(Map<String, dynamic>) f) =>
      [
        for (final e in (body['data'] as List? ?? const []))
          f(e as Map<String, dynamic>),
      ];

  /// Plan + places + parkings + réservations.
  static Future<UserSnapshot> load() async {
    final mapRes = await http.get(Uri.parse('$_base/parking')).timeout(_timeout);
    final map = ParkingData.fromJson(_json(mapRes, 'Plan indisponible'));
    final slots = await _get('/me/slots', 'Places indisponibles');
    final parkings = await _get('/me/parkings', 'Parkings indisponibles');
    final reservations =
        await _get('/me/reservations', 'Réservations indisponibles');

    final serverNow =
        parseServerTime(slots['now'] as String?, keepOldDates: true);
    if (serverNow != null) AgentService.syncClock(serverNow);

    return UserSnapshot(
      map: map,
      slots: _list(slots, UserSlot.fromJson),
      parkings: _list(parkings, ParkingInfo.fromJson),
      reservations: _list(reservations, Reservation.fromJson),
      parked: [
        for (final p in (reservations['parked'] as List? ?? const []))
          ParkedVehicle.fromJson(p as Map<String, dynamic>),
      ],
      fetchedAt: AgentService.now(),
    );
  }

  static Future<List<Fine>> fetchFines() async =>
      _list(await _get('/me/fines', 'Contraventions indisponibles'),
          Fine.fromJson);

  static Future<Profile> fetchProfile() async => Profile.fromJson(
      (await _get('/me/profile', 'Profil indisponible'))['data']
          as Map<String, dynamic>);

  static Future<Profile> saveProfile(Profile p) async {
    final res = await _send(() => http.put(
          Uri.parse('$_base/me/profile'),
          headers: _jsonHeaders,
          body: jsonEncode(p.toJson()),
        ));
    return Profile.fromJson(
        _json(res, 'Profil non enregistré')['data'] as Map<String, dynamic>);
  }

  static Future<Reservation> reserve({
    int? slotId,
    String? parking,
    String? category,
    String? start, // null = maintenant
    required int minutes,
    required String plate,
    required String vehicleType,
    required String nom,
    required String prenom,
  }) async {
    final body = await _post('/me/reservations', 'Réservation refusée', body: {
      'slot_id': slotId,
      'parking': parking,
      'category': category,
      'start': start,
      'duration_minutes': minutes,
      'plate': plate,
      'vehicle_type': vehicleType,
      'nom': nom,
      'prenom': prenom,
    });
    return Reservation.fromJson(body['data'] as Map<String, dynamic>);
  }

  static Future<void> checkIn(int id) =>
      _post('/me/reservations/$id/checkin', 'Arrivée refusée');

  static Future<void> checkOut(int id) =>
      _post('/me/reservations/$id/checkout', 'Départ refusé');

  static Future<void> cancel(int id) =>
      _post('/me/reservations/$id/cancel', 'Annulation refusée');

  static Future<void> leave(String plate) =>
      _post('/me/vehicles/$plate/leave', 'Départ refusé');

  static Future<void> payFine(int no) =>
      _post('/me/fines/$no/pay', 'Paiement refusé');
}

// ───────────────────────── Contrôleur partagé par les onglets ─────────────────────────

class UserController extends ChangeNotifier {
  UserController({required this.username});

  final String username;

  UserSnapshot? snapshot;
  List<Fine> fines = [];
  Profile? profile;

  bool loading = true;

  /// Dernière erreur de chargement (null = tout va bien).
  String? error;

  Timer? _timer;
  bool _busy = false;
  bool _disposed = false;

  // Rappels affichés dans l'application (SnackBar), selon les réglages du profil
  final List<String> _notices = [];
  final Set<String> _announced = {};
  bool _firstLoadDone = false;

  void start() {
    refresh();
    _timer = Timer.periodic(const Duration(seconds: 8), (_) => refresh());
  }

  Future<void> refresh() async {
    if (_busy) return;
    _busy = true;
    try {
      final s = await UserService.load();
      final f = await UserService.fetchFines();
      final p = profile ?? await UserService.fetchProfile();
      if (_disposed) return;
      _collectNotices(s, f, p);
      _firstLoadDone = true;
      snapshot = s;
      fines = f;
      profile = p;
      error = null;
    } catch (e) {
      error = AgentService.describeError(e);
    } finally {
      _busy = false;
      loading = false;
      if (!_disposed) notifyListeners();
    }
  }

  /// Rafraîchit juste après une action (en attendant la fin d'un chargement
  /// éventuellement en cours).
  Future<void> _refreshAfterAction() async {
    var waited = 0;
    while (_busy && waited++ < 50) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    await refresh();
  }

  /// Les rappels en attente (et on les vide).
  List<String> takeNotices() {
    final list = List<String>.from(_notices);
    _notices.clear();
    return list;
  }

  void _collectNotices(UserSnapshot s, List<Fine> f, Profile p) {
    final now = s.fetchedAt;

    for (final fine in f) {
      final isNew = _announced.add('fine-${fine.id}');
      if (_firstLoadDone && isNew && p.notifFines && !fine.paid) {
        _notices.add('Nouvelle contravention : ${fine.offenseLabel} · '
            '${formatEuro(fine.amount)}');
      }
    }

    for (final r in s.reservations) {
      final toStart = r.start.difference(now);
      final toEnd = r.end.difference(now);
      if (p.notifReservations &&
          r.state == ReservationState.upcoming &&
          !toStart.isNegative &&
          toStart.inMinutes <= 10 &&
          _announced.add('start-${r.id}')) {
        _notices.add('Votre réservation (place ${r.slotId}) commence dans '
            '${formatDuration(toStart)}.');
      }
      if (p.notifExpiration && r.state == ReservationState.parked) {
        if (!toEnd.isNegative &&
            toEnd.inMinutes <= 10 &&
            _announced.add('end-${r.id}')) {
          _notices.add('Votre stationnement (place ${r.slotId}) se termine '
              'dans ${formatDuration(toEnd)}.');
        } else if (toEnd.isNegative && _announced.add('over-${r.id}')) {
          _notices.add('Stationnement dépassé (place ${r.slotId}) : '
              'libérez la place pour éviter une contravention.');
        }
      }
    }
  }

  // ───── Actions ─────

  Future<Reservation> reserve({
    int? slotId,
    String? parking,
    String? category,
    String? start,
    required int minutes,
    required String plate,
    required String vehicleType,
    required String nom,
    required String prenom,
  }) async {
    final r = await UserService.reserve(
      slotId: slotId,
      parking: parking,
      category: category,
      start: start,
      minutes: minutes,
      plate: plate,
      vehicleType: vehicleType,
      nom: nom,
      prenom: prenom,
    );
    await _refreshAfterAction();
    return r;
  }

  Future<void> checkIn(Reservation r) async {
    await UserService.checkIn(r.id);
    await _refreshAfterAction();
  }

  Future<void> checkOut(Reservation r) async {
    await UserService.checkOut(r.id);
    await _refreshAfterAction();
  }

  Future<void> cancel(Reservation r) async {
    await UserService.cancel(r.id);
    await _refreshAfterAction();
  }

  Future<void> leave(ParkedVehicle v) async {
    await UserService.leave(v.plate);
    await _refreshAfterAction();
  }

  Future<void> payFine(Fine fine) async {
    await UserService.payFine(fine.no);
    await _refreshAfterAction();
  }

  Future<void> saveProfile(Profile p) async {
    profile = await UserService.saveProfile(p);
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}
