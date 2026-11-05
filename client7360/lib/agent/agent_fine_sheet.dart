import 'package:flutter/material.dart';

import 'agent_fines.dart';
import 'agent_models.dart';
import 'agent_service.dart';
import 'agent_theme.dart';
import 'agent_widgets.dart';

/// Bouton « Dresser une contravention » à placer sous une place en infraction.
/// Si une contravention vient déjà d'être dressée pour cette place, il est
/// remplacé par un rappel.
class FineButton extends StatelessWidget {
  const FineButton({super.key, required this.controller, required this.info});

  final AgentController controller;
  final SlotInfo info;

  @override
  Widget build(BuildContext context) {
    final existing = controller.recentFineFor(info.id);
    if (existing != null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AgentColors.ok.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            const Icon(Icons.task_alt_rounded, color: AgentColors.ok),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Contravention ${existing.id} dressée · ${formatEuro(existing.amount)}',
                style: const TextStyle(
                  color: AgentColors.ok,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      );
    }
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: AgentColors.bad,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        icon: const Icon(Icons.receipt_long_rounded),
        label: const Text(
          'Dresser une contravention',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
        ),
        onPressed: () =>
            showFineSheet(context, controller: controller, info: info),
      ),
    );
  }
}

Future<void> showFineSheet(
  BuildContext context, {
  required AgentController controller,
  required SlotInfo info,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    // La feuille s'ouvre au-dessus du thème de la page agent : on le remet.
    builder: (_) => Theme(
      data: buildAgentTheme(),
      child: _FineSheet(controller: controller, info: info),
    ),
  );
}

class _FineSheet extends StatefulWidget {
  const _FineSheet({required this.controller, required this.info});

  final AgentController controller;
  final SlotInfo info;

  @override
  State<_FineSheet> createState() => _FineSheetState();
}

class _FineSheetState extends State<_FineSheet> {
  late final DateTime _now = DateTime.now().toUtc();
  late Offense _offense =
      Offense.defaultFor(widget.info.complianceAt(_now));
  final _plate = TextEditingController();
  final _comment = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _plate.dispose();
    _comment.dispose();
    super.dispose();
  }

  void _submit() {
    final known = widget.info.plate;
    final plate = (known ?? _plate.text).trim().toUpperCase();
    if (plate.isEmpty) {
      setState(() => _error = "Renseignez l'immatriculation du véhicule.");
      return;
    }
    final comment = _comment.text.trim();
    final fine = widget.controller.issueFine(
      info: widget.info,
      offense: _offense,
      plate: plate,
      comment: comment.isEmpty ? null : comment,
    );
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AgentColors.navy,
        content: Text(
          'Contravention ${fine.id} dressée · ${formatEuro(fine.amount)}',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final info = widget.info;
    final compliance = info.complianceAt(_now);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AgentColors.line,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AgentColors.bad.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.receipt_long_rounded,
                        color: AgentColors.bad),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Dresser une contravention',
                      style: TextStyle(
                        color: AgentColors.ink,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // ── Remplissage automatique ──
              const SectionLabel('Véhicule'),
              const SizedBox(height: 8),
              if (info.plate != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: PlateBadge(info.plate),
                )
              else
                TextField(
                  controller: _plate,
                  textCapitalization: TextCapitalization.characters,
                  autocorrect: false,
                  decoration: InputDecoration(
                    labelText: 'Immatriculation (non fournie par le serveur)',
                    errorText: _error,
                    prefixIcon: const Icon(Icons.pin_outlined),
                    filled: true,
                    fillColor: AgentColors.bg,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              TileGrid([
                InfoTile(
                  info.type == 'moto'
                      ? Icons.two_wheeler_rounded
                      : Icons.directions_car_rounded,
                  'Type',
                  info.typeLabel,
                ),
                InfoTile(Icons.local_parking_rounded, 'Place', info.id),
                InfoTile(Icons.place_rounded, 'Lieu', info.location),
                InfoTile(Icons.schedule_rounded, 'Constat',
                    formatDateTime(_now)),
                InfoTile(Icons.badge_outlined, 'Agent',
                    widget.controller.agentId),
                InfoTile(Icons.timer_outlined, 'Situation',
                    info.detailAt(_now)),
              ]),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: ComplianceBadge(compliance),
              ),

              // ── Infraction + montant ──
              const SizedBox(height: 18),
              const SectionLabel('Infraction'),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: AgentColors.bg,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<Offense>(
                    value: _offense,
                    isExpanded: true,
                    borderRadius: BorderRadius.circular(14),
                    icon: const Icon(Icons.expand_more_rounded),
                    items: [
                      for (final o in Offense.values)
                        DropdownMenuItem(
                          value: o,
                          child: Text(
                            '${o.label} · ${formatEuro(o.amount)}',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: AgentColors.ink,
                            ),
                          ),
                        ),
                    ],
                    onChanged: (o) {
                      if (o != null) setState(() => _offense = o);
                    },
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _offense.color.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                      color: _offense.color.withValues(alpha: 0.45)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Montant',
                            style: TextStyle(
                              color: AgentColors.muted,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            formatEuro(_offense.amount),
                            style: TextStyle(
                              color: _offense.color,
                              fontSize: 34,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            _offense.legal,
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                              color: AgentColors.ink,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _offense.majorated != null
                                ? 'Majoré : ${formatEuro(_offense.majorated!)}'
                                : 'Montant fixé par la commune',
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                              color: AgentColors.muted,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),
              TextField(
                controller: _comment,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: 'Observations (facultatif)',
                  filled: true,
                  fillColor: AgentColors.bg,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AgentColors.bad,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  icon: const Icon(Icons.gavel_rounded),
                  label: Text(
                    'Dresser la contravention · ${formatEuro(_offense.amount)}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  onPressed: _submit,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
