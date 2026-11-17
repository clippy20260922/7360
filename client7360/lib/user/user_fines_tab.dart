import 'package:flutter/material.dart';

import '../agent/agent_fines.dart';
import '../agent/agent_models.dart';
import '../agent/agent_service.dart' show AgentService;
import '../agent/agent_theme.dart';
import '../agent/agent_widgets.dart';
import 'user_service.dart';

enum _Filter { all, unpaid }

/// Onglet « Amendes » de l'usager : les contraventions reçues sur ses
/// véhicules, avec le paiement.
class UserFinesTab extends StatefulWidget {
  const UserFinesTab({super.key, required this.controller});

  final UserController controller;

  @override
  State<UserFinesTab> createState() => _UserFinesTabState();
}

class _UserFinesTabState extends State<UserFinesTab> {
  _Filter _filter = _Filter.all;
  final Set<int> _paying = {};

  void _toast(String message, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: error ? AgentColors.bad : AgentColors.navy,
        content: Text(message),
      ),
    );
  }

  Future<void> _pay(Fine f) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Payer la contravention ?'),
        content: Text('${f.offenseLabel}\n${f.id} · ${f.plate}\n\n'
            'Montant : ${formatEuro(f.amount)}\n'
            '(paiement simulé : aucun débit réel)'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Retour'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Payer ${formatEuro(f.amount)}'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _paying.add(f.no));
    try {
      await widget.controller.payFine(f);
      if (mounted) _toast('Contravention ${f.id} payée.');
    } catch (e) {
      if (mounted) _toast(AgentService.describeError(e), error: true);
    } finally {
      if (mounted) setState(() => _paying.remove(f.no));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final c = widget.controller;
        if (c.snapshot == null) {
          return const Center(child: CircularProgressIndicator());
        }
        final all = c.fines;
        final unpaid = all.where((f) => !f.paid).toList();
        final due = unpaid.fold<double>(0, (a, f) => a + f.amount);
        final shown = _filter == _Filter.all ? all : unpaid;

        return RefreshIndicator(
          onRefresh: c.refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
            children: [
              _Summary(unpaid: unpaid.length, due: due, total: all.length),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  _chip('Toutes (${all.length})', _Filter.all),
                  _chip('À payer (${unpaid.length})', _Filter.unpaid),
                ],
              ),
              const SizedBox(height: 12),
              if (shown.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 36),
                  child: Column(
                    children: [
                      const Icon(Icons.verified_rounded,
                          size: 56, color: AgentColors.ok),
                      const SizedBox(height: 12),
                      Text(
                        _filter == _Filter.all
                            ? "Aucune contravention. Bravo !"
                            : 'Rien à payer.',
                        style: const TextStyle(
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
                    child: _FineCard(
                      fine: f,
                      paying: _paying.contains(f.no),
                      onPay: () => _pay(f),
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
      side: BorderSide(color: selected ? AgentColors.navy : AgentColors.line),
      labelStyle: TextStyle(
        color: selected ? Colors.white : AgentColors.ink,
        fontWeight: FontWeight.w700,
        fontSize: 12.5,
      ),
      onSelected: (_) => setState(() => _filter = f),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.unpaid, required this.due, required this.total});

  final int unpaid, total;
  final double due;

  @override
  Widget build(BuildContext context) {
    final ok = unpaid == 0;
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
              color: (ok ? AgentColors.ok : AgentColors.bad)
                  .withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              ok ? Icons.verified_rounded : Icons.receipt_long_rounded,
              color: ok ? AgentColors.ok : AgentColors.bad,
              size: 30,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ok
                      ? 'Rien à payer'
                      : '${formatEuro(due)} à payer',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  ok
                      ? '$total contravention${total > 1 ? 's' : ''} au total'
                      : '$unpaid contravention${unpaid > 1 ? 's' : ''} en attente',
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
  const _FineCard({
    required this.fine,
    required this.paying,
    required this.onPay,
  });

  final Fine fine;
  final bool paying;
  final VoidCallback onPay;

  @override
  Widget build(BuildContext context) {
    final f = fine;
    final color = f.paid ? AgentColors.ok : f.color;
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
                  child: PlateBadge(f.plate),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                formatEuro(f.amount),
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
            f.offenseLabel,
            style: const TextStyle(
              color: AgentColors.ink,
              fontSize: 15.5,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Place ${f.slotId} · ${f.location}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AgentColors.muted, fontSize: 13),
          ),
          if (f.comment != null) ...[
            const SizedBox(height: 6),
            Text(
              f.comment!,
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
              Tag(Icons.tag_rounded, f.id, color: color),
              Tag(Icons.schedule_rounded, formatDateTime(f.issuedAt)),
              Tag(Icons.badge_outlined, 'Agent ${f.agentId}'),
              if (f.paid)
                Tag(
                  Icons.task_alt_rounded,
                  f.paidAt == null
                      ? 'Payée'
                      : 'Payée le ${formatDateTime(f.paidAt!)}',
                  color: AgentColors.ok,
                ),
            ],
          ),
          if (!f.paid) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AgentColors.blue,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: paying ? null : onPay,
                icon: paying
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.payments_rounded),
                label: Text('Payer ${formatEuro(f.amount)}',
                    style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
