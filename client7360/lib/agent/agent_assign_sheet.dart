import 'package:flutter/material.dart';

import 'agent_models.dart';
import 'agent_reports.dart';
import 'agent_service.dart';
import 'agent_theme.dart';
import 'agent_vehicle_lookup.dart';
import 'agent_widgets.dart';

/// Ouvre la feuille « Assigner la place à un véhicule » (place libre).
Future<void> showAssignSheet(
  BuildContext context, {
  required AgentController controller,
  required SlotInfo info,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => Theme(
      data: buildAgentTheme(),
      child: _AssignSheet(controller: controller, info: info),
    ),
  );
}

class _AssignSheet extends StatefulWidget {
  const _AssignSheet({required this.controller, required this.info});

  final AgentController controller;
  final SlotInfo info;

  @override
  State<_AssignSheet> createState() => _AssignSheetState();
}

class _AssignSheetState extends State<_AssignSheet> {
  String _plate = '';
  VehicleInfo? _vehicle;
  bool _busy = false;
  String? _error;

  Future<void> _submit() async {
    if (_plate.length < 4) {
      setState(() => _error = "Indiquez l'immatriculation du véhicule.");
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.controller.assignSlot(widget.info, _plate);
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop();
      messenger.showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: AgentColors.navy,
          content: Text(
            'Place ${widget.info.id} assignée à $_plate : sans paiement, '
            'le véhicule est en infraction.',
          ),
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

  @override
  Widget build(BuildContext context) {
    final info = widget.info;
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
                      color: AgentColors.blue.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.assignment_ind_rounded,
                        color: AgentColors.blue),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Assigner la place ${info.id}',
                          style: const TextStyle(
                            color: AgentColors.ink,
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          info.location,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: AgentColors.muted, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const SectionLabel('Véhicule garé sur la place'),
              const SizedBox(height: 8),
              VehicleLookup(
                onChanged: (plate, vehicle) => setState(() {
                  _plate = plate;
                  _vehicle = vehicle;
                }),
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AgentColors.warn.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'La place sera assignée à ce véhicule à partir de maintenant, '
                  'sans aucun paiement : il sera donc en infraction'
                  '${_vehicle?.known == false && _plate.length >= 4 ? " (propriétaire inconnu)" : ""}.',
                  style: const TextStyle(
                    color: Color(0xFF8A5B00),
                    fontWeight: FontWeight.w600,
                    fontSize: 12.5,
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
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
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AgentColors.blue,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
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
                  label: const Text(
                    'Assigner la place',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                  onPressed: (_busy || _plate.length < 4) ? null : _submit,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
