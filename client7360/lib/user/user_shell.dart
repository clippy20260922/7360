import 'package:flutter/material.dart';

import '../agent/agent_service.dart' show AgentService;
import '../agent/agent_shell.dart' show ConnectionBanner, ErrorState;
import '../agent/agent_theme.dart';
import '../page_connexion.dart';
import 'user_fines_tab.dart';
import 'user_map_tab.dart';
import 'user_profile_tab.dart';
import 'user_reservations_tab.dart';
import 'user_service.dart';
import 'user_models.dart';

/// Page principale de l'usager : quatre onglets en bas
/// (Carte · Réservations · Amendes · Profil), même style que l'espace agent.
class UserShell extends StatefulWidget {
  const UserShell({super.key, required this.userName});

  final String userName;

  @override
  State<UserShell> createState() => _UserShellState();
}

class _UserShellState extends State<UserShell> {
  late final UserController _controller =
      UserController(username: widget.userName);
  int _index = 0;

  static const _titles = ['Carte', 'Mes réservations', 'Mes amendes', 'Profil'];

  @override
  void initState() {
    super.initState();
    _controller.addListener(_showNotices);
    _controller.start();
  }

  @override
  void dispose() {
    _controller.removeListener(_showNotices);
    _controller.dispose();
    super.dispose();
  }

  /// Affiche les rappels (réservation qui commence, fin de stationnement,
  /// nouvelle contravention) quand ils sont activés dans le profil.
  void _showNotices() {
    final notes = _controller.takeNotices();
    if (notes.isEmpty || !mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: AgentColors.navy,
          duration: const Duration(seconds: 6),
          content: Row(
            children: [
              const Icon(Icons.notifications_active_rounded,
                  color: AgentColors.cyan),
              const SizedBox(width: 12),
              Expanded(child: Text(notes.join('\n'))),
            ],
          ),
        ),
      );
  }

  void _logout() {
    UserService.logout();
    AgentService.logout();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const PageConnexion()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: buildAgentTheme(),
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: AgentColors.navy,
          foregroundColor: Colors.white,
          elevation: 0,
          automaticallyImplyLeading: false,
          titleSpacing: 16,
          title: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AgentColors.blue, AgentColors.cyan],
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: const Text(
                  'P',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 19,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _titles[_index],
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      'Usager · ${widget.userName}',
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: Color(0xFF9FB0D0),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            IconButton(
              tooltip: 'Se déconnecter',
              icon: const Icon(Icons.logout_rounded),
              onPressed: _logout,
            ),
          ],
        ),
        body: ListenableBuilder(
          listenable: _controller,
          builder: (context, _) {
            final c = _controller;
            if (c.snapshot == null) {
              if (c.loading) {
                return const Center(child: CircularProgressIndicator());
              }
              return ErrorState(
                message: c.error ?? 'Erreur inconnue',
                onRetry: c.refresh,
              );
            }
            return Column(
              children: [
                if (c.error != null) ConnectionBanner(message: c.error!),
                Expanded(
                  // IndexedStack : la carte garde son zoom / sa rotation
                  // quand on passe sur un autre onglet.
                  child: IndexedStack(
                    index: _index,
                    children: [
                      UserMapTab(controller: c),
                      UserReservationsTab(controller: c),
                      UserFinesTab(controller: c),
                      UserProfileTab(controller: c, onLogout: _logout),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
        bottomNavigationBar: ListenableBuilder(
          listenable: _controller,
          builder: (context, _) {
            final live = _controller.snapshot?.reservations
                    .where((r) => r.state.isLive)
                    .length ??
                0;
            final due = _controller.fines.where((f) => !f.paid).length;
            return NavigationBar(
              selectedIndex: _index,
              onDestinationSelected: (i) => setState(() => _index = i),
              destinations: [
                const NavigationDestination(
                  icon: Icon(Icons.map_outlined),
                  selectedIcon: Icon(Icons.map_rounded),
                  label: 'Carte',
                ),
                NavigationDestination(
                  icon: Badge(
                    isLabelVisible: live > 0,
                    label: Text('$live'),
                    child: const Icon(Icons.event_available_outlined),
                  ),
                  selectedIcon: Badge(
                    isLabelVisible: live > 0,
                    label: Text('$live'),
                    child: const Icon(Icons.event_available_rounded),
                  ),
                  label: 'Réservations',
                ),
                NavigationDestination(
                  icon: Badge(
                    isLabelVisible: due > 0,
                    label: Text('$due'),
                    child: const Icon(Icons.receipt_long_outlined),
                  ),
                  selectedIcon: Badge(
                    isLabelVisible: due > 0,
                    label: Text('$due'),
                    child: const Icon(Icons.receipt_long_rounded),
                  ),
                  label: 'Amendes',
                ),
                const NavigationDestination(
                  icon: Icon(Icons.person_outline_rounded),
                  selectedIcon: Icon(Icons.person_rounded),
                  label: 'Profil',
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
