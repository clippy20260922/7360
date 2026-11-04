import 'package:flutter/material.dart';

import 'agent_theme.dart';

// ───────────────────────── Conformité ─────────────────────────

enum Compliance { ok, expiringSoon, overtime, unpaid, none }

extension ComplianceX on Compliance {
  /// Vrai pour les stationnements à signaler (onglet « problématiques »).
  bool get isViolation =>
      this == Compliance.overtime || this == Compliance.unpaid;

  String get label => switch (this) {
        Compliance.ok => 'En règle',
        Compliance.expiringSoon => 'Expire bientôt',
        Compliance.overtime => 'Dépassement',
        Compliance.unpaid => 'Non payé',
        Compliance.none => 'Aucun véhicule',
      };

  Color get color => switch (this) {
        Compliance.ok => AgentColors.ok,
        Compliance.expiringSoon => AgentColors.warn,
        Compliance.overtime => AgentColors.bad,
        Compliance.unpaid => AgentColors.bad,
        Compliance.none => AgentColors.muted,
      };

  IconData get icon => switch (this) {
        Compliance.ok => Icons.verified_rounded,
        Compliance.expiringSoon => Icons.timelapse_rounded,
        Compliance.overtime => Icons.alarm_off_rounded,
        Compliance.unpaid => Icons.money_off_rounded,
        Compliance.none => Icons.local_parking_rounded,
      };
}

// ───────────────────────── Formatage ─────────────────────────

String _two(int n) => n.toString().padLeft(2, '0');

/// « 5 min », « 1 h 12 », « 2 j 3 h ».
String formatDuration(Duration d) {
  final m = d.inMinutes.abs();
  if (m < 1) return "moins d'1 min";
  if (m < 60) return '$m min';
  final h = m ~/ 60;
  if (h < 24) return m % 60 == 0 ? '$h h' : '$h h ${_two(m % 60)}';
  final days = h ~/ 24;
  return h % 24 == 0 ? '$days j' : '$days j ${h % 24} h';
}

/// « 20/10 à 14:05 » (heure locale).
String formatDateTime(DateTime utc) {
  final l = utc.toLocal();
  return '${_two(l.day)}/${_two(l.month)} à ${_two(l.hour)}:${_two(l.minute)}';
}

String formatPercent(double ratio) => '${(ratio * 100).round()} %';

// ───────────────────────── Place + véhicule ─────────────────────────

/// Informations de contrôle d'une place : la place elle-même (ligne de
/// `slot_table`) et le véhicule qui y est garé s'il y en a un.
class SlotInfo {
  const SlotInfo({
    required this.id,
    this.type = 'voit',
    this.pmr = false,
    this.elec = false,
    this.occupied = false,
    this.reserved = false,
    this.address,
    this.city,
    this.parking,
    this.tariff = 0,
    this.plate,
    this.owner,
    this.endsAt,
    this.simulated = false,
  });

  /// Une ligne de `GET /data` :
  /// [slot_id, adresse, ville, lat, long, type, pmr, elec, parking,
  ///  tarif, occupée, fin_occupation].
  factory SlotInfo.fromRow(List<dynamic> r) {
    bool b(dynamic v) => v == true || v == 1 || v == '1' || v == 'true';
    String? s(dynamic v) =>
        (v == null || v.toString().trim().isEmpty) ? null : v.toString();

    DateTime? end;
    final raw = s(r[11]);
    if (raw != null) {
      // La base stocke des CURRENT_TIMESTAMP, donc de l'UTC.
      final parsed = DateTime.tryParse(raw.endsWith('Z') ? raw : '${raw}Z');
      // 1900-01-01 = valeur par défaut : aucun paiement enregistré.
      if (parsed != null && parsed.year > 2000) end = parsed;
    }
    return SlotInfo(
      id: r[0].toString(),
      address: s(r[1]),
      city: s(r[2]),
      type: s(r[5]) ?? 'voit',
      pmr: b(r[6]),
      elec: b(r[7]),
      parking: s(r[8]),
      tariff: (r[9] as num?)?.toDouble() ?? 0,
      occupied: b(r[10]),
      endsAt: end,
    );
  }

  final String id;
  final String type; // 'voit' | 'moto'
  final bool pmr, elec, occupied, reserved;
  final String? address, city, parking;
  final double tariff;

  /// Véhicule garé (null quand l'API ne le fournit pas).
  final String? plate, owner;

  /// Fin du stationnement payé, en UTC (null = aucun paiement).
  final DateTime? endsAt;

  /// Vrai quand la fiche a été fabriquée côté client (mode démo).
  final bool simulated;

  String get typeLabel => type == 'moto' ? 'Moto' : 'Voiture';

  String get location {
    final parts = [address, city].whereType<String>().toList();
    if (parts.isNotEmpty) return parts.join(', ');
    return parking ?? 'Adresse non renseignée';
  }

  Compliance complianceAt(DateTime now) {
    if (!occupied) return Compliance.none;
    final end = endsAt;
    if (end == null) return Compliance.unpaid;
    final left = end.difference(now);
    if (left.isNegative) return Compliance.overtime;
    if (left.inMinutes < 10) return Compliance.expiringSoon;
    return Compliance.ok;
  }

  /// Durée de dépassement (zéro si pas en dépassement).
  Duration overtimeAt(DateTime now) {
    final end = endsAt;
    if (!occupied || end == null || !now.isAfter(end)) return Duration.zero;
    return now.difference(end);
  }

  String detailAt(DateTime now) => switch (complianceAt(now)) {
        Compliance.ok =>
          'Paiement valide encore ${formatDuration(endsAt!.difference(now))}',
        Compliance.expiringSoon =>
          'Expire dans ${formatDuration(endsAt!.difference(now))}',
        Compliance.overtime =>
          'Dépassement de ${formatDuration(now.difference(endsAt!))}',
        Compliance.unpaid => 'Aucun paiement enregistré',
        Compliance.none => reserved ? 'Place réservée' : 'Place libre',
      };
}
