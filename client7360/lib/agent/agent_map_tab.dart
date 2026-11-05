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
                child: _MapCard(
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

class _MapCard extends StatelessWidget {
  const _MapCard({
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
                _RoundButton(
                  icon: Icons.my_location_rounded,
                  tooltip: 'Recentrer la vue',
                  onTap: map.resetView,
                ),
                const SizedBox(height: 8),
                _RoundButton(
                  icon: Icons.refresh_rounded,
                  tooltip: 'Actualiser',
                  onTap: onRefresh,
                ),
              ],
            ),
          ),
          const Positioned(left: 10, bottom: 10, child: _Legend()),
        ],
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
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

class _Legend extends StatelessWidget {
  const _Legend();

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
    required this.spot,
    required this.info,
    required this.now,
  });

  final AgentController controller;
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
            if (spot.isLot) ..._lotBody() else ..._spotBody(i, compliance),
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

  List<Widget> _lotBody() {
    final full = spot.status == SpotStatus.occupied;
    return [
      TileGrid([
        InfoTile(
          full ? Icons.block_rounded : Icons.check_circle_rounded,
          'État',
          full ? 'Complet' : 'Places disponibles',
        ),
      ]),
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
