import 'package:flutter/material.dart';

import 'agent_fines.dart';
import 'agent_models.dart';
import 'agent_service.dart';
import 'agent_theme.dart';
import 'agent_widgets.dart';

enum _Scope { all, mine }

/// Onglet « Amendes » : liste des contraventions dressées.
class AgentFinesTab extends StatefulWidget {
  const AgentFinesTab({super.key, required this.controller});

  final AgentController controller;

  @override
  State<AgentFinesTab> createState() => _AgentFinesTabState();
}

class _AgentFinesTabState extends State<AgentFinesTab> {
  _Scope _scope = _Scope.all;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final c = widget.controller;
        final shown = c.fines
            .where((f) => _scope == _Scope.all || f.agentId == c.agentId)
            .toList();
        final total = shown.fold<double>(0, (a, f) => a + f.amount);
        final mineCount = c.fines.where((f) => f.agentId == c.agentId).length;

        return ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
          children: [
            _Summary(count: shown.length, total: total),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                _chip('Toutes (${c.fines.length})', _Scope.all),
                _chip('Les miennes ($mineCount)', _Scope.mine),
              ],
            ),
            const SizedBox(height: 12),
            if (shown.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Column(
                  children: [
                    Icon(Icons.receipt_long_outlined,
                        size: 56, color: AgentColors.muted),
                    SizedBox(height: 12),
                    Text(
                      'Aucune contravention pour le moment.',
                      style: TextStyle(
                        color: AgentColors.muted,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              )
            else
              for (final f in shown)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _FineCard(fine: f),
                ),
          ],
        );
      },
    );
  }

  Widget _chip(String label, _Scope s) {
    final selected = _scope == s;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      showCheckmark: false,
      selectedColor: AgentColors.navy,
      backgroundColor: Colors.white,
      side: BorderSide(color: selected ? AgentColors.navy : AgentColors.line),
      labelStyle: TextStyle(
        color: selected ? Colors.white : AgentColors.ink,
        fontWeight: FontWeight.w700,
        fontSize: 12.5,
      ),
      onSelected: (_) => setState(() => _scope = s),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.count, required this.total});

  final int count;
  final double total;

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
              color: AgentColors.cyan.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.receipt_long_rounded,
                color: AgentColors.cyan, size: 30),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$count contravention${count > 1 ? 's' : ''}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Total : ${formatEuro(total)}',
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

class _FineCard extends StatelessWidget {
  const _FineCard({required this.fine});

  final Fine fine;

  @override
  Widget build(BuildContext context) {
    final color = fine.offense.color;
    return AgentCard(
      accent: color,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: PlateBadge(fine.plate),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                formatEuro(fine.amount),
                style: TextStyle(
                  color: color,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            fine.offense.label,
            style: const TextStyle(
              color: AgentColors.ink,
              fontSize: 15.5,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Place ${fine.slotId} · ${fine.location}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AgentColors.muted, fontSize: 13),
          ),
          if (fine.comment != null) ...[
            const SizedBox(height: 6),
            Text(
              fine.comment!,
              style: const TextStyle(
                color: AgentColors.ink,
                fontSize: 12.5,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Tag(Icons.tag_rounded, fine.id, color: color),
              Tag(Icons.schedule_rounded, formatDateTime(fine.issuedAt)),
              Tag(Icons.badge_outlined, fine.agentId),
              Tag(
                fine.vehicleType == 'moto'
                    ? Icons.two_wheeler_rounded
                    : Icons.directions_car_rounded,
                fine.vehicleLabel,
              ),
              if (fine.simulated)
                const Tag(Icons.science_outlined, 'Démo',
                    color: AgentColors.warn),
            ],
          ),
        ],
      ),
    );
  }
}
