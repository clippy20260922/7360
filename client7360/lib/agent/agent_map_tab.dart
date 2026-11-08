import 'package:flutter/material.dart';

import '../parking_map_view.dart';
import 'agent_fine_sheet.dart';
import 'agent_models.dart';
import 'agent_service.dart';
import 'agent_theme.dart';
import 'agent_widgets.dart';

/// Onglet « Carte » : le plan en haut, la fiche de la place sélectionnée
/// (et du véhicule garé dessus) en dessous.
class AgentMapTab extends StatefulWidget {
  const AgentMapTab({super.key, required this.controller});

  final AgentController controller;

  @override
  State<AgentMapTab> createState() => _AgentMapTabState();
}

class _AgentMapTabState extends State<AgentMapTab> {
  final ParkingMapController _map = ParkingMapController();
  String? _selectedId;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final snap = widget.controller.snapshot;
        if (snap == null) {
          return const Center(child: CircularProgressIndicator());
        }

        ParkingSpot? selected;
        for (final s in snap.map.spots) {
          if (s.id == _selectedId) selected = s;
        }

        return Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                child: MapCard(
                  map: _map,
                  data: snap.map,
                  onSelected: (id) => setState(() => _selectedId = id),
                  onRefresh: widget.controller.refresh,
                ),
              ),
            ),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.42,
              ),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: Padding(
                  key: ValueKey(selected?.id),
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: selected == null
                      ? const _EmptyPanel()
                      : _SpotPanel(
                          controller: widget.controller,
                          lotSlots: [
                            for (final s in snap.slots)
                              if (s.parking == selected.id) s,
                          ],
                          spot: selected,
                          info: snap.slotById(selected.id),
                          now: snap.fetchedAt,
                        ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ───────────────────────── Carte ─────────────────────────

class MapCard extends StatelessWidget {
  const MapCard({
    required this.map,
    required this.data,
    required this.onSelected,
    required this.onRefresh,
  });

  final ParkingMapController map;
  final ParkingData data;
  final ValueChanged<String?> onSelected;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AgentColors.navy, width: 2.5),
        boxShadow: const [
          BoxShadow(
            color: Color(0x330B1B3A),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: ParkingMapView(
              controller: map,
              initialTilt: 0,
              spots: data.spots,
              roads: data.roads,
              buildings: data.buildings,
              zones: data.zones,
              onSpotSelected: onSelected,
            ),
          ),
          Positioned(
            top: 10,
            right: 10,
            child: Column(
              children: [
                MapRoundButton(
                  icon: Icons.my_location_rounded,
                  tooltip: 'Recentrer la vue',
                  onTap: map.resetView,
                ),
                const SizedBox(height: 8),
                MapRoundButton(
                  icon: Icons.refresh_rounded,
                  tooltip: 'Actualiser',
                  onTap: onRefresh,
                ),
              ],
            ),
          ),
          const Positioned(left: 10, bottom: 10, child: MapLegend()),
        ],
      ),
    );
  }
}

class MapRoundButton extends StatelessWidget {
  const MapRoundButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.white,
        elevation: 3,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Icon(icon, size: 22, color: AgentColors.navy),
          ),
        ),
      ),
    );
  }
}

class MapLegend extends StatelessWidget {
  const MapLegend();

  @override
  Widget build(BuildContext context) {
    Widget dot(Color c, String t) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: c, shape: BoxShape.circle),
            ),
            const SizedBox(width: 4),
            Text(
              t,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: AgentColors.navy.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Wrap(
        spacing: 10,
        children: [
          dot(const Color(0xFF34C759), 'Libre'),
          dot(const Color(0xFFFF5A5F), 'Occupée'),
          dot(const Color(0xFFFFB020), 'Réservée'),
          dot(const Color(0xFF1E6FE8), 'Parking'),
        ],
      ),
    );
  }
}

// ───────────────────────── Panneau d'infos ─────────────────────────

class _EmptyPanel extends StatelessWidget {
  const _EmptyPanel();

  @override
  Widget build(BuildContext context) {
    return const AgentCard(
      child: Row(
        children: [
          Icon(Icons.touch_app_rounded, size: 30, color: AgentColors.blue),
          SizedBox(width: 14),
          Expanded(
            child: Text(
              'Touchez une place sur la carte pour afficher ses informations '
              'et celles du véhicule garé dessus.',
              style: TextStyle(
                color: AgentColors.muted,
                fontWeight: FontWeight.w600,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SpotPanel extends StatelessWidget {
  const _SpotPanel({
    required this.controller,
    required this.lotSlots,
    required this.spot,
    required this.info,
    required this.now,
  });

  final AgentController controller;
  final List<SlotInfo> lotSlots; // places du parking sélectionné
  final ParkingSpot spot;
  final SlotInfo? info;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final i = info;
    final compliance = i?.complianceAt(now) ?? Compliance.none;

    return AgentCard(
      padding: EdgeInsets.zero,
      accent: spot.isLot ? AgentColors.blue : compliance.color,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _header(i),
            const SizedBox(height: 14),
            if (spot.isLot) ..._lotBody(lotSlots) else ..._spotBody(i, compliance),
          ],
        ),
      ),
    );
  }

  Widget _header(SlotInfo? i) {
    return Row(
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AgentColors.blue, AgentColors.cyan],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(14),
          ),
          alignment: Alignment.center,
          child: const Text(
            'P',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                spot.isLot ? spot.id : 'Place ${spot.id}',
                style: const TextStyle(
                  color: AgentColors.ink,
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                spot.isLot ? 'Parking à plusieurs places' : (i?.location ?? ''),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AgentColors.muted, fontSize: 13),
              ),
            ],
          ),
        ),
      ],
    );
  }

  List<Widget> _lotBody(List<SlotInfo> places) {
    final parked = places.where((p) => p.occupied).toList()
      ..sort((a, b) {
        final va = a.complianceAt(now).isViolation ? 0 : 1;
        final vb = b.complianceAt(now).isViolation ? 0 : 1;
        return va != vb ? va.compareTo(vb) : a.id.compareTo(b.id);
      });
    final reserved = places.where((p) => p.reserved).length;
    final free = places.length - parked.length - reserved;
    final violations =
        parked.where((p) => p.complianceAt(now).isViolation).length;

    // Catégories, dans un ordre fixe
    const order = ['standard', 'pmr', 'elec', 'moto'];
    final cats = <Widget>[];
    for (final code in order) {
      final inCat = places.where((p) => p.category == code).toList();
      if (inCat.isEmpty) continue;
      final catFree = inCat.where((p) => !p.occupied && !p.reserved).length;
      cats.add(_AvailabilityRow(
        code: code,
        free: catFree,
        total: inCat.length,
        reserved: inCat.where((p) => p.reserved).length,
      ));
    }

    final color = free == 0 ? AgentColors.bad : AgentColors.ok;
    return [
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.45)),
        ),
        child: Row(
          children: [
            Icon(free == 0 ? Icons.block_rounded : Icons.check_circle_rounded,
                size: 30, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    free == 0 ? 'Parking complet' : '$free place${free > 1 ? 's' : ''} libre${free > 1 ? 's' : ''}',
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                  Text(
                    '${parked.length} garé${parked.length > 1 ? 's' : ''} · '
                    '$reserved réservée${reserved > 1 ? 's' : ''} · '
                    '${places.length} au total',
                    style: const TextStyle(
                      color: AgentColors.ink,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      const SectionLabel('Disponibilités'),
      const SizedBox(height: 8),
      ...cats,
      const SizedBox(height: 16),
      SectionLabel('Véhicules stationnés (${parked.length})'
          '${violations > 0 ? ' · $violations en infraction' : ''}'),
      const SizedBox(height: 8),
      if (parked.isEmpty)
        const Text(
          'Aucun véhicule stationné dans ce parking.',
          style: TextStyle(
            color: AgentColors.muted,
            fontWeight: FontWeight.w600,
          ),
        )
      else
        for (final p in parked)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _LotVehicleRow(
              controller: controller,
              info: p,
              now: now,
            ),
          ),
    ];
  }

  List<Widget> _spotBody(SlotInfo? i, Compliance compliance) {
    final mapStatus = switch (spot.status) {
      SpotStatus.free => 'Libre',
      SpotStatus.occupied => 'Occupée',
      SpotStatus.reserved => 'Réservée',
    };

    return [
      // Indicateur de conformité, bien visible
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: compliance.color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: compliance.color.withValues(alpha: 0.45)),
        ),
        child: Row(
          children: [
            Icon(compliance.icon, size: 32, color: compliance.color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    switch (compliance) {
                      Compliance.ok => 'Stationnement en règle',
                      Compliance.expiringSoon => 'En règle, expire bientôt',
                      Compliance.overtime => 'Stationnement non réglementaire',
                      Compliance.unpaid => 'Stationnement non réglementaire',
                      Compliance.none => mapStatus,
                    },
                    style: TextStyle(
                      color: compliance.color,
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    i?.detailAt(now) ?? mapStatus,
                    style: const TextStyle(
                      color: AgentColors.ink,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      if (i != null && compliance.isViolation) ...[
        const SizedBox(height: 12),
        FineButton(controller: controller, info: i),
      ],
      if (i != null) ...[
        const SizedBox(height: 16),
        const SectionLabel('Place'),
        const SizedBox(height: 8),
        TileGrid([
          InfoTile(
            i.type == 'moto'
                ? Icons.two_wheeler_rounded
                : Icons.directions_car_rounded,
            'Type',
            i.typeLabel,
          ),
          InfoTile(
            Icons.euro_rounded,
            'Tarif',
            i.tariff > 0 ? '${i.tariff.toStringAsFixed(2)} €/h' : 'Non renseigné',
          ),
          InfoTile(
            Icons.accessible_rounded,
            'PMR',
            i.pmr ? 'Réservée PMR' : 'Non',
          ),
          InfoTile(
            Icons.bolt_rounded,
            'Borne électrique',
            i.elec ? 'Oui' : 'Non',
          ),
          if (i.parking != null)
            InfoTile(Icons.local_parking_rounded, 'Parking', i.parking!),
          InfoTile(
            Icons.schedule_rounded,
            'Fin du stationnement',
            i.endsAt == null ? '—' : formatDateTime(i.endsAt!),
          ),
        ]),
        const SizedBox(height: 16),
        const SectionLabel('Véhicule'),
        const SizedBox(height: 8),
        if (i.occupied) ...[
          Row(
            children: [
              PlateBadge(i.plate),
              const SizedBox(width: 10),
              Tag(
                i.type == 'moto'
                    ? Icons.two_wheeler_rounded
                    : Icons.directions_car_rounded,
                i.typeLabel,
              ),
            ],
          ),
          if (i.owner != null) ...[
            const SizedBox(height: 10),
            InfoTile(Icons.person_rounded, 'Propriétaire', i.owner!),
          ],
          if (i.plate == null) ...[
            const SizedBox(height: 10),
            const Text(
              "Aucun véhicule n'est enregistré sur cette place : "
              "l'immatriculation n'est pas connue.",
              style: TextStyle(color: AgentColors.muted, fontSize: 12),
            ),
          ],
        ] else
          Text(
            i.reserved
                ? 'Place réservée : aucun véhicule stationné pour le moment.'
                : 'Aucun véhicule stationné sur cette place.',
            style: const TextStyle(
              color: AgentColors.muted,
              fontWeight: FontWeight.w600,
            ),
          ),
      ],
    ];
  }
}

/// Une catégorie de places d'un parking : libres / total.
class _AvailabilityRow extends StatelessWidget {
  const _AvailabilityRow({
    required this.code,
    required this.free,
    required this.total,
    required this.reserved,
  });

  final String code;
  final int free, total, reserved;

  @override
  Widget build(BuildContext context) {
    final rate = total == 0 ? 0.0 : (total - free) / total;
    final color = free == 0
        ? AgentColors.bad
        : (rate >= 0.7 ? AgentColors.warn : AgentColors.blue);
    final icon = switch (code) {
      'pmr' => Icons.accessible_rounded,
      'elec' => Icons.bolt_rounded,
      'moto' => Icons.two_wheeler_rounded,
      _ => Icons.directions_car_rounded,
    };
    final label = switch (code) {
      'pmr' => 'PMR',
      'elec' => 'Électriques',
      'moto' => 'Motos',
      _ => 'Voitures',
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Column(
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: AgentColors.muted),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: AgentColors.ink,
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                  ),
                ),
              ),
              Text(
                '$free libre${free > 1 ? 's' : ''} / $total'
                '${reserved > 0 ? ' · $reserved réservée${reserved > 1 ? 's' : ''}' : ''}',
                style: const TextStyle(
                  color: AgentColors.muted,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: rate,
              minHeight: 7,
              color: color,
              backgroundColor: AgentColors.line,
            ),
          ),
        ],
      ),
    );
  }
}

/// Un véhicule garé dans un parking, avec son état et (s'il est en infraction)
/// le bouton pour dresser une contravention.
class _LotVehicleRow extends StatelessWidget {
  const _LotVehicleRow({
    required this.controller,
    required this.info,
    required this.now,
  });

  final AgentController controller;
  final SlotInfo info;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final c = info.complianceAt(now);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AgentColors.bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.color.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: PlateBadge(info.plate),
                ),
              ),
              ComplianceBadge(c),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Place ${info.id} · ${info.typeLabel}'
            '${info.pmr ? ' · PMR' : ''}${info.elec ? ' · borne' : ''}',
            style: const TextStyle(
              color: AgentColors.ink,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
          Text(
            info.detailAt(now),
            style: TextStyle(
              color: c.isViolation ? c.color : AgentColors.muted,
              fontWeight: FontWeight.w600,
              fontSize: 12.5,
            ),
          ),
          if (c.isViolation) ...[
            const SizedBox(height: 10),
            FineButton(controller: controller, info: info),
          ],
        ],
      ),
    );
  }
}
