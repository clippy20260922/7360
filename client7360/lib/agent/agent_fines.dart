import 'package:flutter/material.dart';

import 'agent_models.dart';
import 'agent_theme.dart';

/// Les deux infractions « de paiement » : ce sont des forfaits post-stationnement
/// (FPS), dont le montant est fixé par la commune.
bool isFpsCode(String code) => code == 'overtime' || code == 'unpaid';

Color offenseColor(String code, double amount) => isFpsCode(code)
    ? AgentColors.blue
    : (amount >= 100 ? AgentColors.bad : AgentColors.warn);

String formatEuro(double v) {
  final whole = v == v.roundToDouble();
  return '${whole ? v.round().toString() : v.toStringAsFixed(2).replaceAll('.', ',')} €';
}

/// Infraction proposée dans la liste déroulante, avec son montant forfaitaire
/// (une ligne de `offense_table`, via `GET /agent/infractions`).
class Offense {
  const Offense({
    required this.code,
    required this.label,
    required this.amount,
    required this.legal,
    this.majorated,
  });

  factory Offense.fromJson(Map<String, dynamic> j) => Offense(
        code: j['code'] as String,
        label: j['label'] as String,
        amount: (j['amount'] as num).toDouble(),
        legal: j['legal'] as String? ?? '',
        majorated: (j['majorated'] as num?)?.toDouble(),
      );

  final String code, label, legal;
  final double amount;
  final double? majorated;

  bool get isFps => isFpsCode(code);
  Color get color => offenseColor(code, amount);
}

/// Infraction proposée par défaut selon le constat (null si la liste est vide).
Offense? defaultOffenseFor(List<Offense> offenses, Compliance c) {
  final code = c == Compliance.unpaid ? 'unpaid' : 'overtime';
  for (final o in offenses) {
    if (o.code == code) return o;
  }
  return offenses.isEmpty ? null : offenses.first;
}

/// Une contravention dressée par un agent (une ligne de `fine_table`,
/// via `GET /agent/fines`).
class Fine {
  const Fine({
    required this.id,
    required this.plate,
    required this.vehicleType,
    required this.slotId,
    required this.location,
    required this.agentId,
    required this.offenseCode,
    required this.offenseLabel,
    required this.amount,
    required this.issuedAt,
    this.comment,
  });

  factory Fine.fromJson(Map<String, dynamic> j) => Fine(
        id: j['id'] as String,
        plate: j['plate'] as String,
        vehicleType: j['vehicle_type'] as String? ?? 'voit',
        slotId: j['slot_id'].toString(),
        location: j['location'] as String? ?? '',
        agentId: j['agent'] as String,
        offenseCode: j['offense'] as String,
        offenseLabel: (j['offense_label'] ?? j['offense']) as String,
        amount: (j['amount'] as num).toDouble(),
        issuedAt: parseServerTime(j['issued_at'] as String?, keepOldDates: true) ??
            DateTime.now().toUtc(),
        comment: j['comment'] as String?,
      );

  final String id; // ex. PV-2026-00042
  final String plate;
  final String vehicleType; // 'voit' | 'moto'
  final String slotId;
  final String location;
  final String agentId;
  final String offenseCode, offenseLabel;
  final double amount;
  final DateTime issuedAt; // UTC
  final String? comment;

  String get vehicleLabel => vehicleType == 'moto' ? 'Moto' : 'Voiture';
  Color get color => offenseColor(offenseCode, amount);
}
