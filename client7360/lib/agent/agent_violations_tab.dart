import 'package:flutter/material.dart';

import 'agent_fine_sheet.dart';
import 'agent_models.dart';
import 'agent_service.dart';
import 'agent_theme.dart';
import 'agent_widgets.dart';

enum _Filter { all, overtime, unpaid }

/// Onglet « Problématiques » : une carte par véhicule en infraction.
class AgentViolationsTab extends StatefulWidget {
  const AgentViolationsTab({super.key, required this.controller});

  final AgentController controller;

  @override
  State<AgentViolationsTab> createState() => _AgentViolationsTabState();
}

class _AgentViolationsTabState extends State<AgentViolationsTab> {
  _Filter _filter = _Filter.all;
  final Set<String> _open = {};

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final snap = widget.controller.snapshot;
        if (snap == null) {
          return const Center(child: CircularProgressIndicator());
        }
        final now = snap.fetchedAt;
        final all = snap.violations;
        final shown = all.where((s) {
          final c = s.complianceAt(now);
          return switch (_filter) {
            _Filter.all => true,
            _Filter.overtime => c == Compliance.overtime,
            _Filter.unpaid => c == Compliance.unpaid,
          };
        }).toList();
        final stats = snap.stats;

        return RefreshIndicator(
          onRefresh: widget.controller.refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
            children: [
              _Summary(total: all.length, stats: stats),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  _chip('Tous (${all.length})', _Filter.all),
                  _chip('Dépassements (${stats.overtime})', _Filter.overtime),
                  _chip('Non payés (${stats.unpaid})', _Filter.unpaid),
                ],
              ),
              const SizedBox(height: 12),
              if (shown.isEmpty)
                const _EmptyState()
              else
                for (final s in shown)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _ViolationCard(
                      info: s,
                      now: now,
                      controller: widget.controller,
                      expanded: _open.contains(s.id),
                      onToggle: () => setState(() {
                        if (!_open.remove(s.id)) _open.add(s.id);
                      }),
                    ),
                  ),
            ],
          ),
        );
      },
    );
  }

  Widget _chip(String label, _Filter f) {
    final selected = _filter == f;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      showCheckmark: false,
      selectedColor: AgentColors.navy,
      backgroundColor: Colors.white,
      side: BorderSide(
        color: selected ? AgentColors.navy : AgentColors.line,
      ),
      labelStyle: TextStyle(
        color: selected ? Colors.white : AgentColors.ink,
        fontWeight: FontWeight.w700,
        fontSize: 12.5,
      ),
      onSelected: (_) => setState(() => _filter = f),
    );
  }
}

// ───────────────────────── Résumé ─────────────────────────

class _Summary extends StatelessWidget {
  const _Summary({required this.total, required this.stats});

  final int total;
  final AgentStats stats;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AgentColors.navy, AgentColors.navyLight],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: (total == 0 ? AgentColors.ok : AgentColors.bad)
                  .withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              total == 0
                  ? Icons.verified_rounded
                  : Icons.report_problem_rounded,
              color: total == 0 ? AgentColors.ok : AgentColors.bad,
              size: 30,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  total == 0
                      ? 'Aucune infraction'
                      : '$total véhicule${total > 1 ? 's' : ''} en infraction',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${stats.occupied} véhicules garés · '
                  '${formatPercent(stats.complianceRate)} en règle',
                  style: const TextStyle(color: Color(0xFFB8C6E4), fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: [
          Icon(Icons.verified_rounded, size: 56, color: AgentColors.ok),
          SizedBox(height: 12),
          Text(
            'Tout est en règle ici.',
            style: TextStyle(
              color: AgentColors.muted,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

// ───────────────────────── Carte d'une infraction ─────────────────────────

class _ViolationCard extends StatelessWidget {
  const _ViolationCard({
    required this.info,
    required this.now,
    required this.controller,
    required this.expanded,
    required this.onToggle,
  });

  final SlotInfo info;
  final DateTime now;
  final AgentController controller;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final c = info.complianceAt(now);
    final overdue = info.overtimeAt(now);

    final fined = controller.recentFineFor(info.id) != null;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onToggle,
      child: AgentCard(
      accent: c.color,
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
              const SizedBox(width: 8),
              ComplianceBadge(c),
              Icon(
                expanded
                    ? Icons.expand_less_rounded
                    : Icons.expand_more_rounded,
                color: AgentColors.muted,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.local_parking_rounded,
                  size: 18, color: AgentColors.blue),
              const SizedBox(width: 6),
              Text(
                'Place ${info.id}',
                style: const TextStyle(
                  color: AgentColors.ink,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  info.location,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      const TextStyle(color: AgentColors.muted, fontSize: 13),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            c == Compliance.overtime
                ? 'Dépassement de ${formatDuration(overdue)}'
                : 'Aucun paiement enregistré',
            style: TextStyle(
              color: c.color,
              fontWeight: FontWeight.w800,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Tag(
                info.type == 'moto'
                    ? Icons.two_wheeler_rounded
                    : Icons.directions_car_rounded,
                info.typeLabel,
              ),
              if (info.endsAt != null)
                Tag(Icons.schedule_rounded,
                    'Fin prévue ${formatDateTime(info.endsAt!)}'),
              if (info.tariff > 0)
                Tag(Icons.euro_rounded,
                    '${info.tariff.toStringAsFixed(2)} €/h'),
              if (info.pmr) const Tag(Icons.accessible_rounded, 'PMR'),
              if (info.elec) const Tag(Icons.bolt_rounded, 'Électrique'),
              if (info.parking != null)
                Tag(Icons.local_parking_rounded, info.parking!),
              if (info.owner != null)
                Tag(Icons.person_rounded, info.owner!),
              if (info.simulated)
                const Tag(Icons.science_outlined, 'Simulé',
                    color: AgentColors.warn),
              if (fined)
                const Tag(Icons.task_alt_rounded, 'Contravention dressée',
                    color: AgentColors.ok),
            ],
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            alignment: Alignment.topCenter,
            child: expanded
                ? Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: FineButton(controller: controller, info: info),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    ),
    );
  }
}
