import 'package:flutter/material.dart';

import '../agent/agent_fines.dart' show formatEuro;
import '../agent/agent_map_tab.dart' show MapCard;
import '../agent/agent_models.dart';
import '../agent/agent_theme.dart';
import '../agent/agent_widgets.dart';
import '../parking_map_view.dart';
import 'report_sheet.dart';
import 'reserve_sheet.dart';
import 'user_models.dart';
import 'user_service.dart';

/// Onglet « Carte » de l'usager : le plan en haut, la fiche de la place (ou du
/// parking) sélectionnée en dessous, avec le bouton « Réserver ».
class UserMapTab extends StatefulWidget {
  const UserMapTab({super.key, required this.controller});

  final UserController controller;

  @override
  State<UserMapTab> createState() => _UserMapTabState();
}

class _UserMapTabState extends State<UserMapTab> {
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

        Widget panel;
        if (selected == null) {
          panel = const _HintPanel();
        } else if (selected.isLot) {
          panel = _ParkingPanel(
            controller: widget.controller,
            spot: selected,
            parking: snap.parkingByName(selected.id),
          );
        } else {
          panel = _SlotPanel(
            controller: widget.controller,
            spot: selected,
            slot: snap.slotById(selected.id),
          );
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
                  child: panel,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _HintPanel extends StatelessWidget {
  const _HintPanel();

  @override
  Widget build(BuildContext context) {
    return const AgentCard(
      child: Row(
        children: [
          Icon(Icons.touch_app_rounded, size: 30, color: AgentColors.blue),
          SizedBox(width: 14),
          Expanded(
            child: Text(
              'Touchez une place ou un parking sur la carte pour voir ses '
              'informations et le réserver.',
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

Widget _header(String title, String subtitle) {
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
              title,
              style: const TextStyle(
                color: AgentColors.ink,
                fontSize: 19,
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              subtitle,
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

Widget _banner(Color color, IconData icon, String title, String detail) {
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: color.withValues(alpha: 0.45)),
    ),
    child: Row(
      children: [
        Icon(icon, size: 30, color: color),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
              Text(
                detail,
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
  );
}

// ───────────────────────── Place de rue ─────────────────────────

class _SlotPanel extends StatelessWidget {
  const _SlotPanel({
    required this.controller,
    required this.spot,
    required this.slot,
  });

  final UserController controller;
  final ParkingSpot spot;
  final UserSlot? slot;

  @override
  Widget build(BuildContext context) {
    final s = slot;
    final status = s?.status ?? spot.status;
    final (color, icon, title, detail) = switch (status) {
      SpotStatus.free => (
          AgentColors.ok,
          Icons.check_circle_rounded,
          'Place libre',
          'Vous pouvez la réserver.',
        ),
      SpotStatus.occupied => (
          AgentColors.bad,
          Icons.block_rounded,
          'Place occupée',
          "Cette place n'est pas disponible pour le moment.",
        ),
      SpotStatus.reserved => (
          AgentColors.warn,
          Icons.event_busy_rounded,
          'Place réservée',
          'Un autre usager a réservé cette place.',
        ),
    };

    return AgentCard(
      padding: EdgeInsets.zero,
      accent: color,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _header('Place ${spot.id}', s?.location ?? ''),
            const SizedBox(height: 14),
            _banner(color, icon, title, detail),
            if (s != null) ...[
              const SizedBox(height: 16),
              const SectionLabel('Place'),
              const SizedBox(height: 8),
              TileGrid([
                InfoTile(categoryIcon(s.type == 'moto' ? 'moto' : 'standard'),
                    'Type', s.type == 'moto' ? 'Moto' : 'Voiture'),
                InfoTile(Icons.euro_rounded, 'Tarif',
                    '${formatEuro(s.tariff)} / heure'),
                InfoTile(Icons.accessible_rounded, 'PMR',
                    s.pmr ? 'Réservée PMR' : 'Non'),
                InfoTile(
                    Icons.bolt_rounded, 'Borne électrique', s.elec ? 'Oui' : 'Non'),
              ]),
              if (s.booked.isNotEmpty) ...[
                const SizedBox(height: 14),
                const SectionLabel('Créneaux déjà réservés'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final w in s.booked)
                      Tag(Icons.event_busy_rounded,
                          '${formatDateTime(w.start)} → ${formatClock(w.end)}',
                          color: AgentColors.warn),
                  ],
                ),
              ],
              if (status == SpotStatus.free) ...[
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AgentColors.blue,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    icon: const Icon(Icons.event_available_rounded),
                    label: const Text(
                      'Réserver cette place',
                      style:
                          TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                    ),
                    onPressed: () => showReserveSheet(
                      context,
                      controller: controller,
                      slot: s,
                    ),
                  ),
                ),
              ],
              if (status != SpotStatus.occupied) ...[
                const SizedBox(height: 10),
                if (controller.pendingReportFor(s.id) != null)
                  const Tag(Icons.flag_rounded,
                      'Signalement envoyé : un agent va vérifier',
                      color: AgentColors.warn)
                else
                  _ReportButton(controller: controller, slot: s),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

/// « Signaler comme prise » : la place semble libre mais un véhicule s'y trouve.
class _ReportButton extends StatelessWidget {
  const _ReportButton({required this.controller, required this.slot});

  final UserController controller;
  final UserSlot slot;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 46,
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFF8A5B00),
          side: const BorderSide(color: AgentColors.warn),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        icon: const Icon(Icons.flag_rounded),
        label: const Text(
          'Signaler comme prise',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        onPressed: () =>
            showReportSheet(context, controller: controller, slot: slot),
      ),
    );
  }
}

// ───────────────────────── Parking ─────────────────────────

class _ParkingPanel extends StatelessWidget {
  const _ParkingPanel({
    required this.controller,
    required this.spot,
    required this.parking,
  });

  final UserController controller;
  final ParkingSpot spot;
  final ParkingInfo? parking;

  @override
  Widget build(BuildContext context) {
    final p = parking;
    final free = p?.free ?? 0;
    final color = free == 0 ? AgentColors.bad : AgentColors.ok;

    return AgentCard(
      padding: EdgeInsets.zero,
      accent: AgentColors.blue,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _header(spot.id, p?.address ?? 'Parking'),
            const SizedBox(height: 14),
            if (p == null)
              const Text(
                'Informations indisponibles pour ce parking.',
                style: TextStyle(color: AgentColors.muted),
              )
            else ...[
              _banner(
                color,
                free == 0 ? Icons.block_rounded : Icons.check_circle_rounded,
                free == 0
                    ? 'Parking complet'
                    : '$free place${free > 1 ? 's' : ''} disponible${free > 1 ? 's' : ''}',
                'sur ${p.total} places',
              ),
              const SizedBox(height: 16),
              const SectionLabel('Réserver une place'),
              const SizedBox(height: 8),
              for (final c in p.categories)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _CategoryRow(
                    category: c,
                    onReserve: () => showReserveSheet(
                      context,
                      controller: controller,
                      parking: p,
                      category: c,
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({required this.category, required this.onReserve});

  final CategoryAvailability category;
  final VoidCallback onReserve;

  @override
  Widget build(BuildContext context) {
    final c = category;
    final rate = c.total == 0 ? 0.0 : (c.total - c.free) / c.total;
    final color = c.free == 0
        ? AgentColors.bad
        : (rate >= 0.7 ? AgentColors.warn : AgentColors.blue);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AgentColors.bg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(categoryIcon(c.code), size: 22, color: AgentColors.blue),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  c.label,
                  style: const TextStyle(
                    color: AgentColors.ink,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
                Text(
                  '${c.free} libre${c.free > 1 ? 's' : ''} / ${c.total} · '
                  '${formatEuro(c.tariff)} / h',
                  style: const TextStyle(
                    color: AgentColors.muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: rate,
                    minHeight: 6,
                    color: color,
                    backgroundColor: AgentColors.line,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AgentColors.blue,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: c.free > 0 ? onReserve : null,
            child: const Text('Réserver'),
          ),
        ],
      ),
    );
  }
}
