import 'package:flutter/material.dart';

import '../agent/agent_fines.dart' show formatEuro;
import '../agent/agent_models.dart';
import '../agent/agent_service.dart' show AgentService;
import '../agent/agent_theme.dart';
import '../agent/agent_widgets.dart';
import 'user_models.dart';
import 'user_service.dart';

/// Ouvre la feuille de réservation : soit pour une place de rue précise
/// ([slot]), soit pour une catégorie de places d'un parking ([parking] +
/// [category]) : dans ce cas le serveur choisit la place.
Future<void> showReserveSheet(
  BuildContext context, {
  required UserController controller,
  UserSlot? slot,
  ParkingInfo? parking,
  CategoryAvailability? category,
}) {
  assert(slot != null || (parking != null && category != null));
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    // La feuille s'ouvre au-dessus du thème de la page : on le remet.
    builder: (_) => Theme(
      data: buildAgentTheme(),
      child: _ReserveSheet(
        controller: controller,
        slot: slot,
        parking: parking,
        category: category,
      ),
    ),
  );
}

enum _Start { now, in30, in60, in120, custom }

class _ReserveSheet extends StatefulWidget {
  const _ReserveSheet({
    required this.controller,
    this.slot,
    this.parking,
    this.category,
  });

  final UserController controller;
  final UserSlot? slot;
  final ParkingInfo? parking;
  final CategoryAvailability? category;

  @override
  State<_ReserveSheet> createState() => _ReserveSheetState();
}

class _ReserveSheetState extends State<_ReserveSheet> {
  static const _durations = [30, 60, 120, 240, 480, 1440];

  late final DateTime _opened = AgentService.now();
  late final TextEditingController _nom;
  late final TextEditingController _prenom;
  late final TextEditingController _plate;

  _Start _startKind = _Start.now;
  DateTime? _customStart; // UTC
  int _minutes = 120;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final p = widget.controller.profile ?? const Profile();
    _nom = TextEditingController(text: p.nom);
    _prenom = TextEditingController(text: p.prenom);
    _plate = TextEditingController(text: p.plate);
  }

  @override
  void dispose() {
    _nom.dispose();
    _prenom.dispose();
    _plate.dispose();
    super.dispose();
  }

  // ───── Ce que la réservation concerne ─────

  String get _code => widget.slot?.category ?? widget.category!.code;
  bool get _needsPmr => widget.slot?.pmr ?? _code == 'pmr';
  bool get _needsElec => widget.slot?.elec ?? _code == 'elec';
  String get _vehicleType =>
      (widget.slot?.type ?? (_code == 'moto' ? 'moto' : 'voit'));
  double get _tariff => widget.slot?.tariff ?? widget.category!.tariff;

  DateTime get _start => switch (_startKind) {
        _Start.now => _opened,
        _Start.in30 => _opened.add(const Duration(minutes: 30)),
        _Start.in60 => _opened.add(const Duration(hours: 1)),
        _Start.in120 => _opened.add(const Duration(hours: 2)),
        _Start.custom => _customStart ?? _opened,
      };

  DateTime get _end => _start.add(Duration(minutes: _minutes));
  double get _amount => (_tariff * _minutes / 60 * 100).round() / 100;

  TimeWindow? get _conflict {
    for (final w in widget.slot?.booked ?? const <TimeWindow>[]) {
      if (w.overlaps(_start, _end)) return w;
    }
    return null;
  }

  String? get _blocker {
    final p = widget.controller.profile ?? const Profile();
    if (_needsPmr && !p.pmr) {
      return 'Place réservée aux titulaires de la carte mobilité inclusion : '
          "activez-la dans l'onglet Profil.";
    }
    if (_needsElec && !p.elec) {
      return 'Place équipée d\'une borne de recharge : indiquez dans '
          "l'onglet Profil que votre véhicule est électrique.";
    }
    final c = _conflict;
    if (c != null) {
      return 'Cette place est déjà réservée de ${formatClock(c.start)} '
          'à ${formatClock(c.end)}.';
    }
    return null;
  }

  // ───── Actions ─────

  Future<void> _pickTime() async {
    final base = _opened.toLocal().add(const Duration(minutes: 30));
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(base),
    );
    if (picked == null || !mounted) return;
    final nowLocal = _opened.toLocal();
    var t = DateTime(
        nowLocal.year, nowLocal.month, nowLocal.day, picked.hour, picked.minute);
    if (t.isBefore(nowLocal)) t = t.add(const Duration(days: 1));
    setState(() {
      _customStart = t.toUtc();
      _startKind = _Start.custom;
    });
  }

  Future<void> _submit() async {
    final plate = _plate.text.trim();
    if (_nom.text.trim().isEmpty || _prenom.text.trim().isEmpty) {
      setState(() => _error = 'Renseignez votre nom et votre prénom.');
      return;
    }
    if (plate.isEmpty) {
      setState(() => _error = "Renseignez l'immatriculation du véhicule.");
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await widget.controller.reserve(
        slotId: widget.slot == null ? null : int.tryParse(widget.slot!.id),
        parking: widget.parking?.name,
        category: widget.category?.code,
        start: _startKind == _Start.now ? null : toServerTime(_start),
        minutes: _minutes,
        plate: plate,
        vehicleType: _vehicleType,
        nom: _nom.text.trim(),
        prenom: _prenom.text.trim(),
      );
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop();
      messenger.showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: AgentColors.navy,
          content: Text(
            'Réservation confirmée · place ${r.slotId}'
            '${r.parking != null ? ' (${r.parking})' : ''} · '
            '${formatEuro(r.amount)}',
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

  // ───── Interface ─────

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

  Widget _chip(String label, bool selected, VoidCallback onTap) => ChoiceChip(
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

  @override
  Widget build(BuildContext context) {
    final slot = widget.slot;
    final blocker = _blocker;
    final title = slot != null
        ? 'Réserver la place ${slot.id}'
        : 'Réserver · ${widget.parking!.name}';
    final subtitle = slot != null
        ? slot.location
        : '${categoryLabel(_code)} · ${widget.category!.free} libre'
            '${widget.category!.free > 1 ? 's' : ''} sur ${widget.category!.total}';

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
                    child: Icon(categoryIcon(_code), color: AgentColors.blue),
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

              // ── Informations (préremplies avec le profil) ──
              const SizedBox(height: 16),
              const SectionLabel('Conducteur et véhicule'),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _nom,
                      textCapitalization: TextCapitalization.words,
                      decoration: _field('Nom', Icons.person_outline_rounded),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _prenom,
                      textCapitalization: TextCapitalization.words,
                      decoration: _field('Prénom', Icons.person_outline_rounded),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _plate,
                textCapitalization: TextCapitalization.characters,
                autocorrect: false,
                decoration: _field('Immatriculation', Icons.pin_outlined),
              ),
              const SizedBox(height: 8),
              Tag(
                _vehicleType == 'moto'
                    ? Icons.two_wheeler_rounded
                    : Icons.directions_car_rounded,
                _vehicleType == 'moto'
                    ? 'Place pour moto'
                    : 'Place pour voiture',
              ),

              // ── Créneau ──
              const SizedBox(height: 18),
              const SectionLabel('Début'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  _chip('Maintenant', _startKind == _Start.now,
                      () => setState(() => _startKind = _Start.now)),
                  _chip('Dans 30 min', _startKind == _Start.in30,
                      () => setState(() => _startKind = _Start.in30)),
                  _chip('Dans 1 h', _startKind == _Start.in60,
                      () => setState(() => _startKind = _Start.in60)),
                  _chip('Dans 2 h', _startKind == _Start.in120,
                      () => setState(() => _startKind = _Start.in120)),
                  _chip(
                    _startKind == _Start.custom
                        ? 'À ${formatClock(_start)}'
                        : 'Choisir l\'heure…',
                    _startKind == _Start.custom,
                    _pickTime,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const SectionLabel('Durée'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final m in _durations)
                    _chip(formatDuration(Duration(minutes: m)), _minutes == m,
                        () => setState(() => _minutes = m)),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton.filledTonal(
                    onPressed: _minutes > 30
                        ? () => setState(() => _minutes -= 30)
                        : null,
                    icon: const Icon(Icons.remove_rounded),
                  ),
                  SizedBox(
                    width: 120,
                    child: Text(
                      formatDuration(Duration(minutes: _minutes)),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AgentColors.ink,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton.filledTonal(
                    onPressed: _minutes < 1440
                        ? () => setState(() => _minutes += 30)
                        : null,
                    icon: const Icon(Icons.add_rounded),
                  ),
                ],
              ),

              // ── Récapitulatif et montant ──
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AgentColors.blue.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                      color: AgentColors.blue.withValues(alpha: 0.35)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Montant à payer',
                            style: TextStyle(
                              color: AgentColors.muted,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            formatEuro(_amount),
                            style: const TextStyle(
                              color: AgentColors.blue,
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
                            '${formatDateTime(_start)}\n→ ${formatDateTime(_end)}',
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                              color: AgentColors.ink,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${formatEuro(_tariff)} / heure',
                            style: const TextStyle(
                                color: AgentColors.muted, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Paiement simulé : aucun débit réel.',
                style: TextStyle(color: AgentColors.muted, fontSize: 11.5),
              ),

              if (blocker != null || _error != null) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AgentColors.bad.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _error ?? blocker!,
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
                      : const Icon(Icons.event_available_rounded),
                  label: Text(
                    'Réserver · ${formatEuro(_amount)}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  onPressed: (_busy || blocker != null) ? null : _submit,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
