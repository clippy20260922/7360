import 'package:flutter/material.dart';

import '../agent/agent_service.dart' show AgentService;
import '../agent/agent_theme.dart';
import '../agent/agent_widgets.dart';
import 'user_models.dart';
import 'user_service.dart';

/// Ouvre la feuille « Signaler cette place comme prise ».
Future<void> showReportSheet(
  BuildContext context, {
  required UserController controller,
  required UserSlot slot,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => Theme(
      data: buildAgentTheme(),
      child: _ReportSheet(controller: controller, slot: slot),
    ),
  );
}

class _ReportSheet extends StatefulWidget {
  const _ReportSheet({required this.controller, required this.slot});

  final UserController controller;
  final UserSlot slot;

  @override
  State<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<_ReportSheet> {
  late final DateTime _opened = AgentService.now();
  final _plate = TextEditingController();
  final _comment = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _plate.dispose();
    _comment.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final plate = _plate.text.trim();
      final comment = _comment.text.trim();
      final r = await widget.controller.reportSlot(
        widget.slot,
        plate: plate.isEmpty ? null : plate,
        comment: comment.isEmpty ? null : comment,
      );
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop();
      messenger.showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: AgentColors.navy,
          content: Text(
            'Signalement envoyé à ${formatClock(r.reportedAt)} : '
            'un agent va vérifier la place ${r.slotId}.',
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

  InputDecoration _field(String label, IconData icon) => InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: AgentColors.muted),
        filled: true,
        fillColor: AgentColors.bg,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final slot = widget.slot;
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
                      color: AgentColors.warn.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child:
                        const Icon(Icons.flag_rounded, color: AgentColors.warn),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Signaler la place ${slot.id}',
                          style: const TextStyle(
                            color: AgentColors.ink,
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          slot.location,
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
              const SizedBox(height: 12),
              const Text(
                "Cette place est indiquée libre mais un véhicule s'y trouve ? "
                'Prévenez un agent : il vérifiera et pourra verbaliser '
                'le véhicule.',
                style: TextStyle(
                  color: AgentColors.ink,
                  fontSize: 13.5,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 16),
              const SectionLabel('Immatriculation du véhicule (facultatif)'),
              const SizedBox(height: 8),
              TextField(
                controller: _plate,
                textCapitalization: TextCapitalization.characters,
                autocorrect: false,
                decoration: _field(
                    "Si vous pouvez la lire", Icons.pin_outlined),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _comment,
                maxLines: 2,
                decoration: _field('Précision (facultatif)',
                    Icons.chat_bubble_outline_rounded),
              ),
              const SizedBox(height: 12),
              Tag(Icons.schedule_rounded,
                  'Heure du signalement : ${formatClock(_opened)} '
                  '(enregistrée automatiquement)'),
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
                    backgroundColor: AgentColors.warn,
                    foregroundColor: Colors.white,
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
                      : const Icon(Icons.send_rounded),
                  label: const Text(
                    'Envoyer le signalement',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                  onPressed: _busy ? null : _submit,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
