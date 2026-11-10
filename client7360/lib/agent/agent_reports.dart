import 'agent_models.dart';

/// Ce que le serveur sait d'une plaque (`GET /agent/vehicles/{plaque}`) :
/// le propriétaire, s'il est connu, et où le véhicule est garé.
class VehicleInfo {
  const VehicleInfo({
    required this.plate,
    required this.known,
    this.ownerUsername,
    this.ownerName,
    this.vehicleType,
    this.elec = false,
    this.parkedSlot,
  });

  factory VehicleInfo.fromJson(Map<String, dynamic> j) {
    final owner = j['owner'] as Map<String, dynamic>?;
    final name =
        '${owner?['prenom'] ?? ''} ${owner?['nom'] ?? ''}'.trim();
    return VehicleInfo(
      plate: j['plate'] as String,
      known: j['known'] == true,
      ownerUsername: owner?['username'] as String?,
      ownerName: name.isEmpty ? null : name,
      vehicleType: j['vehicle_type'] as String?,
      elec: j['elec'] == true,
      parkedSlot: (j['parked_slot'] as num?)?.toInt(),
    );
  }

  final String plate;

  /// Vrai quand un propriétaire est enregistré pour cette plaque.
  final bool known;
  final String? ownerUsername, ownerName, vehicleType;
  final bool elec;
  final int? parkedSlot;

  String get vehicleLabel => vehicleType == 'moto' ? 'Moto' : 'Voiture';
}

enum ReportStatus { pending, validated, dismissed }

/// Une place signalée comme prise par un usager (`GET /agent/reports`).
class Report {
  const Report({
    required this.id,
    required this.slotId,
    required this.location,
    required this.reportedAt,
    required this.status,
    required this.reporterUsername,
    this.reporterName,
    this.plate,
    this.comment,
    this.handledBy,
    this.handledAt,
    this.assignedPlate,
    this.vehicle,
  });

  factory Report.fromJson(Map<String, dynamic> j) {
    final reporter = j['reporter'] as Map<String, dynamic>? ?? const {};
    final name =
        '${reporter['prenom'] ?? ''} ${reporter['nom'] ?? ''}'.trim();
    final vehicle = j['vehicle'] as Map<String, dynamic>?;
    return Report(
      id: (j['id'] as num).toInt(),
      slotId: j['slot_id'].toString(),
      location: j['location'] as String? ?? '',
      reportedAt:
          parseServerTime(j['reported_at'] as String?, keepOldDates: true) ??
              DateTime.now().toUtc(),
      status: switch (j['status']) {
        'validated' => ReportStatus.validated,
        'dismissed' => ReportStatus.dismissed,
        _ => ReportStatus.pending,
      },
      reporterUsername: reporter['username'] as String? ?? '',
      reporterName: name.isEmpty ? null : name,
      plate: j['plate'] as String?,
      comment: j['comment'] as String?,
      handledBy: j['handled_by'] as String?,
      handledAt:
          parseServerTime(j['handled_at'] as String?, keepOldDates: true),
      assignedPlate: j['assigned_plate'] as String?,
      vehicle: vehicle == null ? null : VehicleInfo.fromJson(vehicle),
    );
  }

  final int id;
  final String slotId, location, reporterUsername;
  final DateTime reportedAt; // UTC : l'heure du signalement
  final ReportStatus status;
  final String? reporterName, plate, comment, handledBy, assignedPlate;
  final DateTime? handledAt;

  /// Le véhicule et son propriétaire, si l'usager a donné une plaque.
  final VehicleInfo? vehicle;

  bool get isPending => status == ReportStatus.pending;
}
