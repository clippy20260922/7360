import 'package:flutter/material.dart';

import 'agent_models.dart';
import 'agent_theme.dart';

/// Montant du forfait post-stationnement (FPS) utilisé par défaut.
/// En réalité il est fixé par chaque commune (de l'ordre de 10 à 50 €) :
/// à remplacer par la valeur de la ville quand elle sera en base.
const double kFpsAmount = 35;

/// Infractions proposées dans la liste déroulante, avec leur montant forfaitaire
/// (barème national du Code de la route ; [majorated] = montant majoré).
enum Offense {
  overtime('Dépassement de la durée payée', kFpsAmount,
      'Forfait post-stationnement (FPS)'),
  unpaid('Absence de paiement', kFpsAmount, 'Forfait post-stationnement (FPS)'),
  nuisance('Stationnement gênant', 35, 'Contravention de 2e classe',
      majorated: 75),
  abusive('Stationnement abusif (plus de 7 jours)', 35,
      'Contravention de 2e classe',
      majorated: 75),
  veryNuisance('Stationnement très gênant', 135, 'Contravention de 4e classe',
      majorated: 375),
  pmr('Place PMR sans carte', 135, 'Contravention de 4e classe (très gênant)',
      majorated: 375);

  const Offense(this.label, this.amount, this.legal, {this.majorated});

  final String label;
  final double amount;
  final String legal;
  final double? majorated;

  bool get isFps => this == overtime || this == unpaid;

  Color get color => isFps
      ? AgentColors.blue
      : (amount >= 100 ? AgentColors.bad : AgentColors.warn);

  /// Infraction proposée par défaut selon le constat.
  static Offense defaultFor(Compliance c) =>
      c == Compliance.unpaid ? Offense.unpaid : Offense.overtime;
}

String formatEuro(double v) {
  final whole = v == v.roundToDouble();
  return '${whole ? v.round().toString() : v.toStringAsFixed(2).replaceAll('.', ',')} €';
}

/// Une contravention dressée par un agent.
class Fine {
  const Fine({
    required this.id,
    required this.plate,
    required this.vehicleType,
    required this.slotId,
    required this.location,
    required this.agentId,
    required this.offense,
    required this.amount,
    required this.issuedAt,
    this.comment,
    this.simulated = false,
  });

  final String id; // ex. PV-2026-01042
  final String plate;
  final String vehicleType; // 'voit' | 'moto'
  final String slotId;
  final String location;
  final String agentId;
  final Offense offense;
  final double amount;
  final DateTime issuedAt; // UTC
  final String? comment;

  /// Vrai pour les contraventions d'exemple du mode démo.
  final bool simulated;

  String get vehicleLabel => vehicleType == 'moto' ? 'Moto' : 'Voiture';
}

/// Contraventions d'exemple, le temps de brancher la base de données.
List<Fine> buildDemoFines(DateTime now) {
  final y = now.year;
  Fine f(int n, String plate, String type, String slot, String where,
      String agent, Offense o, Duration ago,
      {String? comment}) {
    return Fine(
      id: 'PV-$y-${n.toString().padLeft(5, '0')}',
      plate: plate,
      vehicleType: type,
      slotId: slot,
      location: where,
      agentId: agent,
      offense: o,
      amount: o.amount,
      issuedAt: now.subtract(ago),
      comment: comment,
      simulated: true,
    );
  }

  return [
    f(1041, 'GH-482-KL', 'voit', '23', "Rue de l'ESIEE", 'OSS117',
        Offense.overtime, const Duration(hours: 20)),
    f(1040, 'AB-123-CD', 'voit', '9', 'Le Parking', 'OSS117', Offense.unpaid,
        const Duration(days: 1, hours: 3)),
    f(1039, 'FT-907-ZR', 'voit', '41', 'Rue du test', 'AG-204',
        Offense.veryNuisance, const Duration(days: 1, hours: 9),
        comment: 'Véhicule sur passage piéton.'),
    f(1038, 'WK-330-PM', 'moto', '6', 'Rue du test', 'AG-204',
        Offense.nuisance, const Duration(days: 2, hours: 2)),
    f(1037, 'EX-615-BN', 'voit', '3', "Rue de l'ESIEE", 'OSS117', Offense.pmr,
        const Duration(days: 3, hours: 5),
        comment: 'Aucune carte mobilité inclusion visible.'),
    f(1036, 'LD-278-QS', 'voit', '17', 'Le Parking', 'AG-204',
        Offense.abusive, const Duration(days: 4, hours: 1)),
  ];
}
