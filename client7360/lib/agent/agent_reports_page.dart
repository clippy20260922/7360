import 'package:flutter/material.dart';

import 'agent_models.dart';
import 'agent_reports.dart';
import 'agent_service.dart';
import 'agent_theme.dart';
import 'agent_vehicle_lookup.dart';
import 'agent_widgets.dart';

/// Page des signalements : les places que des usagers disent prises.
/// L'agent retrouve le propriétaire par la plaque, puis valide (la place est
/// assignée au véhicule depuis l'heure du signalement) ou rejette.
class AgentReportsPage extends StatefulWidget {
  const AgentReportsPage({super.key, required this.controller});

  final AgentController controller;

  @override
  State<AgentReportsPage> createState() => _AgentReportsPageState();
}

class _AgentReportsPageState extends State<AgentReportsPage> {
  bool _showHandled = false;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: buildAgentTheme(),
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: AgentColors.navy,
          foregroundColor: Colors.white,
          elevation: 0,
          title: const Text(
            'Signalements',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
          ),
        ),
        body: ListenableBuilder(
          listenable: widget.controller,
          builder: (context, _) {
            final c = widget.controller;
            final pending = c.reports.where((r) => r.isPending).toList();
            final handled = c.reports.where((r) => !r.isPending).toList();
            final shown = _showHandled ? handled : pending;

            return RefreshIndicator(
              onRefresh: c.refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                children: [
                  Wrap(
                    spacing: 8,
                    children: [
                      _chip('À traiter (${pending.length})', !_showHandled,
                          () => setState(() => _showHandled = false)),
                      _chip('Traités (${handled.length})', _showHandled,
                          () => setState(() => _showHandled = true)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (shown.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 48),
                      child: Column(
                        children: [
                          Icon(
                            _showHandled
                                ? Icons.history_rounded
                                : Icons.notifications_none_rounded,
                            size: 56,
                            color: AgentColors.muted,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _showHandled
                                ? 'Aucun signalement traité.'
                                : 'Aucun signalement à traiter.',
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
                    for (final r in shown)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: r.isPending
                            ? _PendingCard(
                                key: ValueKey('pending-${r.id}'),
                                report: r,
                                controller: c,
                              )
                            : _HandledCard(report: r),
                      ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) {
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
      onSelected: (_) => onTap(),
    );
  }
}

String _ago(DateTime t) {
  final d = AgentService.now().difference(t);
  return d.inMinutes < 1 ? "à l'instant" : 'il y a ${formatDuration(d)}';
}

// ───────────────────────── À traiter ─────────────────────────

class _PendingCard extends StatefulWidget {
  const _PendingCard({super.key, required this.report, required this.controller});

  final Report report;
  final AgentController controller;

  @override
  State<_PendingCard> createState() => _PendingCardState();
}

class _PendingCardState extends State<_PendingCard> {
  late String _plate = widget.report.plate ?? '';
  bool _busy = false;
  String? _error;

  Future<bool> _confirm(String title, String text, String action) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(text),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Retour'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(action),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _run(Future<void> Function() action, String done) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: AgentColors.navy,
          content: Text(done),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = AgentService.describeError(e);
        });
      }
    }
  }

  Future<void> _validate() async {
    final r = widget.report;
    final ok = await _confirm(
      'Valider le signalement ?',
      'La place ${r.slotId} sera assignée à $_plate depuis '
          '${formatDateTime(r.reportedAt)} (heure du signalement), sans '
          'paiement : le véhicule sera en infraction.',
      'Valider',
    );
    if (!ok) return;
    await _run(
      () => widget.controller.validateReport(r, plate: _plate),
      'Place ${r.slotId} assignée à $_plate : le véhicule est en infraction.',
    );
  }

  Future<void> _dismiss() async {
    final r = widget.report;
    final ok = await _confirm(
      'Rejeter le signalement ?',
      'La place ${r.slotId} restera libre.',
      'Rejeter',
    );
    if (!ok) return;
    await _run(() => widget.controller.dismissReport(r), 'Signalement rejeté.');
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.report;
    return AgentCard(
      accent: AgentColors.warn,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.flag_rounded, color: AgentColors.warn),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Place ${r.slotId} signalée comme prise',
                  style: const TextStyle(
                    color: AgentColors.ink,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            r.location,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AgentColors.muted, fontSize: 13),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Tag(Icons.schedule_rounded,
                  '${formatDateTime(r.reportedAt)} · ${_ago(r.reportedAt)}',
                  color: AgentColors.warn),
              Tag(Icons.person_outline_rounded,
                  r.reporterName ?? r.reporterUsername),
            ],
          ),
          if (r.comment != null) ...[
            const SizedBox(height: 8),
            Text(
              '« ${r.comment} »',
              style: const TextStyle(
                color: AgentColors.ink,
                fontSize: 13,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
          const SizedBox(height: 14),
          SectionLabel(r.plate == null
              ? 'Plaque non fournie : à saisir'
              : 'Plaque signalée'),
          const SizedBox(height: 8),
          VehicleLookup(
            initialPlate: r.plate ?? '',
            initialInfo: r.vehicle,
            onChanged: (plate, _) => setState(() => _plate = plate),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AgentColors.bad.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _error!,
                style: const TextStyle(
                  color: AgentColors.bad,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ),
          ],
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
              onPressed: (_busy || _plate.length < 4) ? null : _validate,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.check_rounded),
              label: const Text('Valider et assigner la place',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: AgentColors.bad,
                side: const BorderSide(color: AgentColors.bad),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: _busy ? null : _dismiss,
              icon: const Icon(Icons.close_rounded),
              label: const Text('Rejeter'),
            ),
          ),
        ],
      ),
    );
  }
}

// ───────────────────────── Traités ─────────────────────────

class _HandledCard extends StatelessWidget {
  const _HandledCard({required this.report});

  final Report report;

  @override
  Widget build(BuildContext context) {
    final r = report;
    final ok = r.status == ReportStatus.validated;
    final color = ok ? AgentColors.ok : AgentColors.muted;
    return AgentCard(
      accent: color,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Place ${r.slotId}',
                  style: const TextStyle(
                    color: AgentColors.ink,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Tag(
                ok ? Icons.task_alt_rounded : Icons.cancel_outlined,
                ok ? 'Validé' : 'Rejeté',
                color: color,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            r.location,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AgentColors.muted, fontSize: 13),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Tag(Icons.schedule_rounded,
                  'Signalée ${formatDateTime(r.reportedAt)}'),
              if (r.assignedPlate != null)
                Tag(Icons.pin_outlined, r.assignedPlate!, color: color),
              if (r.handledBy != null)
                Tag(
                  Icons.badge_outlined,
                  '${r.handledBy}'
                  '${r.handledAt == null ? '' : ' · ${formatDateTime(r.handledAt!)}'}',
                ),
            ],
          ),
        ],
      ),
    );
  }
}
