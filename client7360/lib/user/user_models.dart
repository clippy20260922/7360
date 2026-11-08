import 'package:flutter/material.dart';

import '../agent/agent_models.dart';
import '../agent/agent_theme.dart';
import '../parking_map_view.dart';

// ───────────────────────── Outils ─────────────────────────

/// « 2026-11-08 15:20:00 » en UTC : le format attendu par le serveur.
String toServerTime(DateTime t) {
  final u = t.toUtc();
  String p(int n) => n.toString().padLeft(2, '0');
  return '${u.year}-${p(u.month)}-${p(u.day)} ${p(u.hour)}:${p(u.minute)}:${p(u.second)}';
}

/// « 15:20 » (heure locale).
String formatClock(DateTime t) {
  final l = t.toLocal();
  return '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
}

String categoryLabel(String code) => switch (code) {
      'pmr' => 'PMR',
      'elec' => 'Électrique',
      'moto' => 'Moto',
      _ => 'Voiture',
    };

IconData categoryIcon(String code) => switch (code) {
      'pmr' => Icons.accessible_rounded,
      'elec' => Icons.bolt_rounded,
      'moto' => Icons.two_wheeler_rounded,
      _ => Icons.directions_car_rounded,
    };

DateTime _time(dynamic raw) =>
    parseServerTime(raw as String?, keepOldDates: true) ?? DateTime.now().toUtc();

// ───────────────────────── Places et parkings ─────────────────────────

class TimeWindow {
  const TimeWindow(this.start, this.end);
  final DateTime start, end; // UTC

  bool overlaps(DateTime s, DateTime e) => s.isBefore(end) && e.isAfter(start);
}

/// Place de rue (une entrée de `GET /me/slots`). Pas d'info sur le véhicule.
class UserSlot {
  const UserSlot({
    required this.id,
    required this.type,
    required this.pmr,
    required this.elec,
    required this.category,
    required this.tariff,
    required this.status,
    this.address,
    this.city,
    this.booked = const [],
  });

  factory UserSlot.fromJson(Map<String, dynamic> j) => UserSlot(
        id: j['id'].toString(),
        type: j['type'] as String? ?? 'voit',
        pmr: j['pmr'] == true,
        elec: j['elec'] == true,
        category: j['category'] as String? ?? 'standard',
        tariff: (j['tariff'] as num?)?.toDouble() ?? 0,
        status: switch (j['status']) {
          'occupied' => SpotStatus.occupied,
          'reserved' => SpotStatus.reserved,
          _ => SpotStatus.free,
        },
        address: j['address'] as String?,
        city: j['city'] as String?,
        booked: [
          for (final b in (j['booked'] as List? ?? const []))
            TimeWindow(_time((b as Map)['start']), _time(b['end'])),
        ],
      );

  final String id, type, category;
  final bool pmr, elec;
  final double tariff; // € / heure
  final SpotStatus status;
  final String? address, city;
  final List<TimeWindow> booked; // créneaux déjà pris

  String get location {
    final parts = [address, city].whereType<String>().toList();
    return parts.isEmpty ? 'Adresse non renseignée' : parts.join(', ');
  }
}

/// Une catégorie de places d'un parking (voiture, PMR, électrique, moto).
class CategoryAvailability {
  const CategoryAvailability({
    required this.code,
    required this.total,
    required this.free,
    required this.tariff,
  });

  factory CategoryAvailability.fromJson(Map<String, dynamic> j) =>
      CategoryAvailability(
        code: j['code'] as String,
        total: (j['total'] as num).toInt(),
        free: (j['free'] as num).toInt(),
        tariff: (j['tariff'] as num?)?.toDouble() ?? 0,
      );

  final String code;
  final int total, free;
  final double tariff;

  String get label => categoryLabel(code);
}

/// Un parking et ses disponibilités (une entrée de `GET /me/parkings`).
class ParkingInfo {
  const ParkingInfo({
    required this.name,
    required this.total,
    required this.free,
    required this.categories,
    this.address,
  });

  factory ParkingInfo.fromJson(Map<String, dynamic> j) => ParkingInfo(
        name: j['name'] as String,
        address: j['address'] as String?,
        total: (j['total'] as num).toInt(),
        free: (j['free'] as num).toInt(),
        categories: [
          for (final c in (j['categories'] as List? ?? const []))
            CategoryAvailability.fromJson(c as Map<String, dynamic>),
        ],
      );

  final String name;
  final String? address;
  final int total, free;
  final List<CategoryAvailability> categories;
}

// ───────────────────────── Réservations ─────────────────────────

enum ReservationState { upcoming, active, parked, finished, cancelled, expired }

extension ReservationStateX on ReservationState {
  String get label => switch (this) {
        ReservationState.upcoming => 'À venir',
        ReservationState.active => 'En cours',
        ReservationState.parked => 'Garé',
        ReservationState.finished => 'Terminée',
        ReservationState.cancelled => 'Annulée',
        ReservationState.expired => 'Expirée',
      };

  Color get color => switch (this) {
        ReservationState.upcoming => AgentColors.blue,
        ReservationState.active => AgentColors.warn,
        ReservationState.parked => AgentColors.ok,
        ReservationState.finished => AgentColors.muted,
        ReservationState.cancelled => AgentColors.muted,
        ReservationState.expired => AgentColors.bad,
      };

  IconData get icon => switch (this) {
        ReservationState.upcoming => Icons.event_rounded,
        ReservationState.active => Icons.hourglass_top_rounded,
        ReservationState.parked => Icons.local_parking_rounded,
        ReservationState.finished => Icons.check_circle_outline_rounded,
        ReservationState.cancelled => Icons.cancel_outlined,
        ReservationState.expired => Icons.timer_off_rounded,
      };

  /// Réservation encore à honorer ou en cours (onglet « En cours »).
  bool get isLive =>
      this == ReservationState.upcoming ||
      this == ReservationState.active ||
      this == ReservationState.parked;
}

class Reservation {
  const Reservation({
    required this.id,
    required this.slotId,
    required this.category,
    required this.location,
    required this.plate,
    required this.vehicleType,
    required this.start,
    required this.end,
    required this.amount,
    required this.tariff,
    required this.state,
    this.parking,
  });

  factory Reservation.fromJson(Map<String, dynamic> j) => Reservation(
        id: (j['id'] as num).toInt(),
        slotId: j['slot_id'].toString(),
        parking: j['parking'] as String?,
        category: j['category'] as String? ?? 'standard',
        location: j['location'] as String? ?? '',
        plate: j['plate'] as String,
        vehicleType: j['vehicle_type'] as String? ?? 'voit',
        start: _time(j['start']),
        end: _time(j['end']),
        amount: (j['amount'] as num).toDouble(),
        tariff: (j['tariff'] as num?)?.toDouble() ?? 0,
        state: switch (j['state']) {
          'upcoming' => ReservationState.upcoming,
          'active' => ReservationState.active,
          'parked' => ReservationState.parked,
          'cancelled' => ReservationState.cancelled,
          'expired' => ReservationState.expired,
          _ => ReservationState.finished,
        },
      );

  final int id;
  final String slotId, category, location, plate, vehicleType;
  final String? parking;
  final DateTime start, end; // UTC
  final double amount, tariff;
  final ReservationState state;

  bool canCheckIn(DateTime now) =>
      (state == ReservationState.upcoming || state == ReservationState.active) &&
      now.isAfter(start.subtract(const Duration(minutes: 10))) &&
      now.isBefore(end);

  bool get canCancel =>
      state == ReservationState.upcoming || state == ReservationState.active;
}

/// Véhicule de l'usager actuellement garé (avec ou sans réservation).
class ParkedVehicle {
  const ParkedVehicle({
    required this.plate,
    required this.vehicleType,
    required this.slotId,
    required this.location,
    this.parking,
    this.endsAt,
  });

  factory ParkedVehicle.fromJson(Map<String, dynamic> j) => ParkedVehicle(
        plate: j['plate'] as String,
        vehicleType: j['vehicle_type'] as String? ?? 'voit',
        slotId: j['slot_id'].toString(),
        parking: j['parking'] as String?,
        location: j['location'] as String? ?? '',
        endsAt: parseServerTime(j['fin_occupation'] as String?),
      );

  final String plate, vehicleType, slotId, location;
  final String? parking;
  final DateTime? endsAt; // null = rien de payé
}

// ───────────────────────── Profil ─────────────────────────

class Profile {
  const Profile({
    this.nom = '',
    this.prenom = '',
    this.plate = '',
    this.vehicleType = 'voit',
    this.elec = false,
    this.pmr = false,
    this.notifReservations = true,
    this.notifExpiration = true,
    this.notifFines = true,
  });

  factory Profile.fromJson(Map<String, dynamic> j) {
    final n = (j['notifications'] as Map?) ?? const {};
    return Profile(
      nom: j['nom'] as String? ?? '',
      prenom: j['prenom'] as String? ?? '',
      plate: j['plate'] as String? ?? '',
      vehicleType: j['vehicle_type'] as String? ?? 'voit',
      elec: j['elec'] == true,
      pmr: j['pmr'] == true,
      notifReservations: n['reservations'] != false,
      notifExpiration: n['expiration'] != false,
      notifFines: n['fines'] != false,
    );
  }

  final String nom, prenom, plate, vehicleType;
  final bool elec, pmr;
  final bool notifReservations, notifExpiration, notifFines;

  Map<String, dynamic> toJson() => {
        'nom': nom,
        'prenom': prenom,
        'plate': plate,
        'vehicle_type': vehicleType,
        'elec': elec,
        'pmr': pmr,
        'notif_reservations': notifReservations,
        'notif_expiration': notifExpiration,
        'notif_fines': notifFines,
      };

  Profile copyWith({
    String? nom,
    String? prenom,
    String? plate,
    String? vehicleType,
    bool? elec,
    bool? pmr,
    bool? notifReservations,
    bool? notifExpiration,
    bool? notifFines,
  }) =>
      Profile(
        nom: nom ?? this.nom,
        prenom: prenom ?? this.prenom,
        plate: plate ?? this.plate,
        vehicleType: vehicleType ?? this.vehicleType,
        elec: elec ?? this.elec,
        pmr: pmr ?? this.pmr,
        notifReservations: notifReservations ?? this.notifReservations,
        notifExpiration: notifExpiration ?? this.notifExpiration,
        notifFines: notifFines ?? this.notifFines,
      );

  bool sameAs(Profile o) => toJson().toString() == o.toJson().toString();
}
