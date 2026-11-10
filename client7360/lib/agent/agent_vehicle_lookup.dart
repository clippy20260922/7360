import 'package:flutter/material.dart';

import 'agent_reports.dart';
import 'agent_service.dart';
import 'agent_theme.dart';
import 'agent_widgets.dart';

/// « ab-123 cd » → « AB123CD » (même écriture que sur le serveur).
String normalizePlate(String raw) =>
    raw.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

/// Champ « plaque » avec recherche du propriétaire : si la plaque est
/// enregistrée, on affiche la personne ; sinon on prévient que le
/// propriétaire est inconnu.
class VehicleLookup extends StatefulWidget {
  const VehicleLookup({
    super.key,
    required this.onChanged,
    this.initialPlate = '',
    this.initialInfo,
    this.label = 'Immatriculation',
  });

  /// Appelé à chaque changement : plaque normalisée + résultat de la recherche
  /// (null tant qu'on n'a pas cherché cette plaque).
  final void Function(String plate, VehicleInfo? info) onChanged;
  final String initialPlate;
  final VehicleInfo? initialInfo;
  final String label;

  @override
  State<VehicleLookup> createState() => _VehicleLookupState();
}

class _VehicleLookupState extends State<VehicleLookup> {
  late final TextEditingController _plate =
      TextEditingController(text: widget.initialPlate);
  VehicleInfo? _info;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _info = widget.initialInfo;
  }

  @override
  void dispose() {
    _plate.dispose();
    super.dispose();
  }

  String get _normalized => normalizePlate(_plate.text);

  void _typed(String _) {
    // Dès qu'on modifie la plaque, l'ancien résultat ne vaut plus
    setState(() {
      if (_info != null && _info!.plate != _normalized) _info = null;
      _error = null;
    });
    widget.onChanged(_normalized, _info);
  }

  Future<void> _search() async {
    final plate = _normalized;
    if (plate.length < 4) {
      setState(() => _error = "Saisissez l'immatriculation complète.");
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final info = await AgentService.lookupVehicle(plate);
      if (!mounted) return;
      setState(() => _info = info);
      widget.onChanged(plate, info);
    } catch (e) {
      if (mounted) setState(() => _error = AgentService.describeError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = _info;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _plate,
          textCapitalization: TextCapitalization.characters,
          autocorrect: false,
          onChanged: _typed,
          onSubmitted: (_) => _search(),
          decoration: InputDecoration(
            labelText: widget.label,
            errorText: _error,
            prefixIcon: const Icon(Icons.pin_outlined, color: AgentColors.muted),
            suffixIcon: _loading
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    ),
                  )
                : IconButton(
                    tooltip: 'Rechercher le propriétaire',
                    icon: const Icon(Icons.search_rounded),
                    onPressed: _search,
                  ),
            filled: true,
            fillColor: AgentColors.bg,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        if (info != null) ...[
          const SizedBox(height: 10),
          _InfoBox(info: info),
        ],
      ],
    );
  }
}

class _InfoBox extends StatelessWidget {
  const _InfoBox({required this.info});

  final VehicleInfo info;

  @override
  Widget build(BuildContext context) {
    final color = info.known ? AgentColors.ok : AgentColors.warn;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                info.known
                    ? Icons.person_rounded
                    : Icons.person_search_rounded,
                color: color,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  info.known
                      ? (info.ownerName ?? info.ownerUsername ?? 'Propriétaire')
                      : 'Plaque inconnue : aucune information de propriétaire',
                  style: TextStyle(
                    color: info.known ? AgentColors.ink : color,
                    fontWeight: FontWeight.w800,
                    fontSize: 14.5,
                  ),
                ),
              ),
            ],
          ),
          if (info.known || info.vehicleType != null) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (info.ownerUsername != null)
                  Tag(Icons.badge_outlined, 'Compte ${info.ownerUsername}'),
                if (info.vehicleType != null)
                  Tag(
                    info.vehicleType == 'moto'
                        ? Icons.two_wheeler_rounded
                        : Icons.directions_car_rounded,
                    info.vehicleLabel,
                  ),
                if (info.elec) const Tag(Icons.bolt_rounded, 'Électrique'),
                if (info.parkedSlot != null)
                  Tag(Icons.local_parking_rounded,
                      'Déjà garé place ${info.parkedSlot}',
                      color: AgentColors.warn),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
