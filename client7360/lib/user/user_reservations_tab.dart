import 'package:flutter/material.dart';

import '../agent/agent_fines.dart' show formatEuro;
import '../agent/agent_models.dart';
import '../agent/agent_service.dart' show AgentService;
import '../agent/agent_theme.dart';
import '../agent/agent_widgets.dart';
import 'user_models.dart';
import 'user_service.dart';

enum _Filter { live, history }

/// Onglet « Réservations » : celles en cours ou à venir, l'historique, et
/// les véhicules actuellement garés (pour « reprendre la route »).
class UserReservationsTab extends StatefulWidget {
  const UserReservationsTab({super.key, required this.controller});

  final UserController controller;

  @override
  State<UserReservationsTab> createState() => _UserReservationsTabState();
}

class _UserReservationsTabState extends State<UserReservationsTab> {
  _Filter _filter = _Filter.live;
  final Set<int> _busy = {}; // réservations en cours de traitement

  void _toast(String message, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: error ? AgentColors.bad : AgentColors.navy,
        content: Text(message),
      ),
    );
  }

  Future<void> _run(int key, String done, Future<void> Function() action) async {
    setState(() => _busy.add(key));
    try {
      await action();
      if (mounted) _toast(done);
    } catch (e) {
      if (mounted) _toast(AgentService.describeError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy.remove(key));
    }
  }

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

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final c = widget.controller;
        final snap = c.snapshot;
        if (snap == null) {
          return const Center(child: CircularProgressIndicator());
        }
        final now = snap.fetchedAt;
        final live = snap.reservations.where((r) => r.state.isLive).toList()
          ..sort((a, b) => a.start.compareTo(b.start));
        final history =
            snap.reservations.where((r) => !r.state.isLive).toList();
        final shown = _filter == _Filter.live ? live : history;

        // Véhicules garés qui n'ont pas de réservation « garée » associée
        final withReservation = {
          for (final r in snap.reservations)
            if (r.state == ReservationState.parked) r.plate,
        };
        final loose =
            snap.parked.where((v) => !withReservation.contains(v.plate)).toList();

        return RefreshIndicator(
          onRefresh: c.refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
            children: [
              _Summary(live: live.length, total: snap.reservations.length),
              if (c.reports.isNotEmpty) ...[
                const SizedBox(height: 14),
                const SectionLabel('Mes signalements'),
                const SizedBox(height: 8),
                for (final r in c.reports.take(5))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _ReportRow(report: r),
                  ),
              ],
              if (loose.isNotEmpty) ...[
                const SizedBox(height: 14),
                const SectionLabel('Véhicules garés'),
                const SizedBox(height: 8),
                for (final v in loose)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _ParkedCard(
                      vehicle: v,
                      now: now,
                      busy: _busy.contains(v.plate.hashCode),
                      onLeave: () async {
                        final ok = await _confirm(
                          'Reprendre la route ?',
                          'La place ${v.slotId} sera libérée pour '
                              '${v.plate}.',
                          'Confirmer mon départ',
                        );
                        if (ok) {
                          await _run(v.plate.hashCode,
                              'Départ confirmé, place ${v.slotId} libérée.',
                              () => c.leave(v));
                        }
                      },
                    ),
                  ),
              ],
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                children: [
                  _chip('En cours / à venir (${live.length})', _Filter.live),
                  _chip('Historique (${history.length})', _Filter.history),
                ],
              ),
              const SizedBox(height: 12),
              if (shown.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 36),
                  child: Column(
                    children: [
                      const Icon(Icons.event_available_outlined,
                          size: 56, color: AgentColors.muted),
                      const SizedBox(height: 12),
                      Text(
                        _filter == _Filter.live
                            ? 'Aucune réservation en cours.\nRéservez une place depuis la carte.'
                            : "Aucune réservation passée.",
                        textAlign: TextAlign.center,
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
                    child: _ReservationCard(
                      reservation: r,
                      now: now,
                      busy: _busy.contains(r.id),
                      onCheckIn: () => _run(
                          r.id,
                          'Bon stationnement ! Place ${r.slotId} à vous.',
                          () => c.checkIn(r)),
                      onCheckOut: () async {
                        final ok = await _confirm(
                          'Reprendre la route ?',
                          'La place ${r.slotId} sera libérée.',
                          'Confirmer mon départ',
                        );
                        if (ok) {
                          await _run(r.id, 'Départ confirmé, bonne route !',
                              () => c.checkOut(r));
                        }
                      },
                      onCancel: () async {
                        final ok = await _confirm(
                          'Annuler la réservation ?',
                          'La place ${r.slotId} sera remise à disposition.',
                          'Annuler la réservation',
                        );
                        if (ok) {
                          await _run(r.id, 'Réservation annulée.',
                              () => c.cancel(r));
                        }
                      },
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
  const _Summary({required this.live, required this.total});

  final int live, total;

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
            child: const Icon(Icons.event_available_rounded,
                color: AgentColors.cyan, size: 30),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  live == 0
                      ? 'Aucune réservation en cours'
                      : '$live réservation${live > 1 ? 's' : ''} en cours',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$total au total',
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

class _ReservationCard extends StatelessWidget {
  const _ReservationCard({
    required this.reservation,
    required this.now,
    required this.busy,
    required this.onCheckIn,
    required this.onCheckOut,
    required this.onCancel,
  });

  final Reservation reservation;
  final DateTime now;
  final bool busy;
  final VoidCallback onCheckIn, onCheckOut, onCancel;

  @override
  Widget build(BuildContext context) {
    final r = reservation;
    final color = r.state.color;

    Widget? actions;
    if (r.state == ReservationState.parked) {
      actions = _wide(Icons.directions_car_rounded, 'Reprendre la route',
          AgentColors.blue, busy ? null : onCheckOut);
    } else if (r.canCancel) {
      actions = Column(
        children: [
          if (r.canCheckIn(now))
            _wide(Icons.local_parking_rounded, "Je suis arrivé(e)",
                AgentColors.ok, busy ? null : onCheckIn),
          if (r.canCheckIn(now)) const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: AgentColors.bad,
                side: const BorderSide(color: AgentColors.bad),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: busy ? null : onCancel,
              icon: const Icon(Icons.close_rounded),
              label: const Text('Annuler'),
            ),
          ),
        ],
      );
    }

    final remaining = r.end.difference(now);
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
                  child: PlateBadge(r.plate),
                ),
              ),
              const SizedBox(width: 8),
              _StateBadge(r.state),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(categoryIcon(r.category), size: 18, color: AgentColors.blue),
              const SizedBox(width: 6),
              Text(
                'Place ${r.slotId}',
                style: const TextStyle(
                  color: AgentColors.ink,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  r.location,
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
            '${formatDateTime(r.start)}  →  ${formatClock(r.end)}',
            style: const TextStyle(
              color: AgentColors.ink,
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
          if (r.state == ReservationState.parked)
            Text(
              remaining.isNegative
                  ? 'Dépassement de ${formatDuration(remaining)}'
                  : 'Fin dans ${formatDuration(remaining)}',
              style: TextStyle(
                color: remaining.isNegative ? AgentColors.bad : AgentColors.ok,
                fontWeight: FontWeight.w800,
                fontSize: 13.5,
              ),
            ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Tag(Icons.euro_rounded, formatEuro(r.amount),
                  color: AgentColors.blue),
              Tag(Icons.schedule_rounded,
                  formatDuration(r.end.difference(r.start))),
              Tag(categoryIcon(r.category), categoryLabel(r.category)),
              Tag(Icons.tag_rounded, 'N° ${r.id}'),
            ],
          ),
          if (actions != null) ...[
            const SizedBox(height: 14),
            actions,
          ],
        ],
      ),
    );
  }

  Widget _wide(IconData icon, String label, Color color, VoidCallback? onTap) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: color,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        onPressed: onTap,
        icon: Icon(icon),
        label: Text(label,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
      ),
    );
  }
}

class _StateBadge extends StatelessWidget {
  const _StateBadge(this.state);

  final ReservationState state;

  @override
  Widget build(BuildContext context) {
    final c = state.color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(40),
        border: Border.all(color: c.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(state.icon, size: 15, color: c),
          const SizedBox(width: 5),
          Text(
            state.label,
            style: TextStyle(
              color: c,
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

/// Véhicule garé sans réservation associée (ex. stationnement payé à
/// l'horodateur) : on peut tout de même « reprendre la route ».
class _ParkedCard extends StatelessWidget {
  const _ParkedCard({
    required this.vehicle,
    required this.now,
    required this.busy,
    required this.onLeave,
  });

  final ParkedVehicle vehicle;
  final DateTime now;
  final bool busy;
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) {
    final v = vehicle;
    final end = v.endsAt;
    final (color, text) = end == null
        ? (AgentColors.bad, 'Aucun paiement enregistré')
        : (end.isBefore(now)
            ? (AgentColors.bad, 'Dépassement de ${formatDuration(now.difference(end))}')
            : (AgentColors.ok, 'Fin dans ${formatDuration(end.difference(now))}'));

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
                  child: PlateBadge(v.plate),
                ),
              ),
              const _StateBadge(ReservationState.parked),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Place ${v.slotId} · ${v.location}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AgentColors.ink,
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
          Text(
            text,
            style: TextStyle(
                color: color, fontWeight: FontWeight.w800, fontSize: 13.5),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: AgentColors.blue,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: busy ? null : onLeave,
              icon: const Icon(Icons.directions_car_rounded),
              label: const Text('Reprendre la route',
                  style: TextStyle(fontWeight: FontWeight.w800)),
            ),
          ),
        ],
      ),
    );
  }
}

/// Un signalement de place prise envoyé par l'usager, avec la réponse de l'agent.
class _ReportRow extends StatelessWidget {
  const _ReportRow({required this.report});

  final MyReport report;

  @override
  Widget build(BuildContext context) {
    final r = report;
    final color = r.status.color;
    return AgentCard(
      accent: color,
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Icon(r.status.icon, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Place ${r.slotId} · ${r.location}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AgentColors.ink,
                    fontWeight: FontWeight.w800,
                    fontSize: 13.5,
                  ),
                ),
                Text(
                  '${r.status.label} · signalée ${formatDateTime(r.reportedAt)}',
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
