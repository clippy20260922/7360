import 'package:flutter/material.dart';

import '../agent/agent_service.dart' show AgentService;
import '../agent/agent_theme.dart';
import '../agent/agent_widgets.dart';
import 'user_models.dart';
import 'user_service.dart';

/// Onglet « Profil » : identité, véhicule, notifications, déconnexion.
class UserProfileTab extends StatefulWidget {
  const UserProfileTab({
    super.key,
    required this.controller,
    required this.onLogout,
  });

  final UserController controller;
  final VoidCallback onLogout;

  @override
  State<UserProfileTab> createState() => _UserProfileTabState();
}

class _UserProfileTabState extends State<UserProfileTab> {
  final _nom = TextEditingController();
  final _prenom = TextEditingController();
  final _plate = TextEditingController();

  Profile _form = const Profile(); // ce qui est à l'écran
  bool _loaded = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final p = widget.controller.profile;
    if (p != null) _fill(p);
    widget.controller.addListener(_onController);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onController);
    _nom.dispose();
    _prenom.dispose();
    _plate.dispose();
    super.dispose();
  }

  void _fill(Profile p) {
    _loaded = true;
    _nom.text = p.nom;
    _prenom.text = p.prenom;
    _plate.text = p.plate;
    _form = p;
  }

  /// Au premier chargement du profil, on remplit le formulaire.
  void _onController() {
    final p = widget.controller.profile;
    if (_loaded || p == null || !mounted) return;
    setState(() => _fill(p));
  }

  Profile get _current => _form.copyWith(
        nom: _nom.text.trim(),
        prenom: _prenom.text.trim(),
        plate: _plate.text.trim(),
      );

  bool get _dirty {
    final saved = widget.controller.profile;
    return saved != null && !saved.sameAs(_current);
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.controller.saveProfile(_current);
      final saved = widget.controller.profile!;
      _plate.text = saved.plate; // plaque mise au format du serveur
      if (!mounted) return;
      setState(() => _form = saved);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: AgentColors.navy,
          content: Text('Profil enregistré.'),
        ),
      );
    } catch (e) {
      if (mounted) setState(() => _error = AgentService.describeError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
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

  Widget _switch(IconData icon, String title, String subtitle, bool value,
      ValueChanged<bool> onChanged) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      secondary: Icon(icon, color: AgentColors.blue),
      title: Text(
        title,
        style: const TextStyle(
          color: AgentColors.ink,
          fontWeight: FontWeight.w700,
          fontSize: 14.5,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(color: AgentColors.muted, fontSize: 12),
      ),
      value: value,
      activeColor: AgentColors.blue,
      onChanged: onChanged,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        if (widget.controller.profile == null) {
          return const Center(child: CircularProgressIndicator());
        }
        final f = _form;
        return ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
          children: [
            // ── Compte ──
            Container(
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
                      gradient: const LinearGradient(
                        colors: [AgentColors.blue, AgentColors.cyan],
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      (_nom.text.isNotEmpty ? _nom.text : widget.controller.username)
                          .substring(0, 1)
                          .toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${_prenom.text} ${_nom.text}'.trim().isEmpty
                              ? widget.controller.username
                              : '${_prenom.text} ${_nom.text}'.trim(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          'Compte ${widget.controller.username}',
                          style: const TextStyle(
                              color: Color(0xFFB8C6E4), fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ── Identité ──
            AgentCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SectionLabel('Identité'),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _nom,
                    textCapitalization: TextCapitalization.words,
                    onChanged: (_) => setState(() {}),
                    decoration: _field('Nom', Icons.person_outline_rounded),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _prenom,
                    textCapitalization: TextCapitalization.words,
                    onChanged: (_) => setState(() {}),
                    decoration: _field('Prénom', Icons.person_outline_rounded),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // ── Véhicule ──
            AgentCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SectionLabel('Mon véhicule'),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _plate,
                    textCapitalization: TextCapitalization.characters,
                    autocorrect: false,
                    onChanged: (_) => setState(() {}),
                    decoration: _field('Immatriculation', Icons.pin_outlined),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('Voiture'),
                        avatar: const Icon(Icons.directions_car_rounded, size: 18),
                        selected: f.vehicleType == 'voit',
                        onSelected: (_) => setState(
                            () => _form = _current.copyWith(vehicleType: 'voit')),
                      ),
                      ChoiceChip(
                        label: const Text('Moto'),
                        avatar: const Icon(Icons.two_wheeler_rounded, size: 18),
                        selected: f.vehicleType == 'moto',
                        onSelected: (_) => setState(
                            () => _form = _current.copyWith(vehicleType: 'moto')),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  _switch(
                    Icons.bolt_rounded,
                    'Véhicule électrique',
                    'Nécessaire pour réserver une place avec borne',
                    f.elec,
                    (v) => setState(() => _form = _current.copyWith(elec: v)),
                  ),
                  _switch(
                    Icons.accessible_rounded,
                    'Carte mobilité inclusion',
                    'Nécessaire pour réserver une place PMR',
                    f.pmr,
                    (v) => setState(() => _form = _current.copyWith(pmr: v)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // ── Notifications ──
            AgentCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SectionLabel('Notifications'),
                  const SizedBox(height: 4),
                  _switch(
                    Icons.event_available_rounded,
                    'Réservations',
                    'Rappel avant le début d\'une réservation',
                    f.notifReservations,
                    (v) => setState(
                        () => _form = _current.copyWith(notifReservations: v)),
                  ),
                  _switch(
                    Icons.timer_outlined,
                    'Fin de stationnement',
                    'Rappel avant la fin, et en cas de dépassement',
                    f.notifExpiration,
                    (v) => setState(
                        () => _form = _current.copyWith(notifExpiration: v)),
                  ),
                  _switch(
                    Icons.receipt_long_rounded,
                    'Contraventions',
                    'Alerte quand une contravention est dressée',
                    f.notifFines,
                    (v) =>
                        setState(() => _form = _current.copyWith(notifFines: v)),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    "Les rappels s'affichent dans l'application, quand elle est ouverte.",
                    style: TextStyle(color: AgentColors.muted, fontSize: 11.5),
                  ),
                ],
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
              height: 52,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AgentColors.blue,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                ),
                onPressed: (_saving || !_dirty) ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.save_rounded),
                label: Text(
                  _dirty ? 'Enregistrer les modifications' : 'Profil à jour',
                  style: const TextStyle(
                      fontSize: 15.5, fontWeight: FontWeight.w800),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 48,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AgentColors.bad,
                  side: const BorderSide(color: AgentColors.bad),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                ),
                onPressed: widget.onLogout,
                icon: const Icon(Icons.logout_rounded),
                label: const Text('Se déconnecter'),
              ),
            ),
          ],
        );
      },
    );
  }
}
