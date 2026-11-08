import 'package:flutter/material.dart';

import 'agent_fines_tab.dart';
import '../page_connexion.dart';
import 'agent_map_tab.dart';
import 'agent_service.dart';
import 'agent_stats_tab.dart';
import 'agent_theme.dart';
import 'agent_violations_tab.dart';

/// Page principale de l'agent : trois onglets en bas
/// (Carte · Problématiques · Stats). Elle arrive directement sur la carte.
class AgentShell extends StatefulWidget {
  const AgentShell({super.key, this.agentName = 'Agent'});

  final String agentName;

  @override
  State<AgentShell> createState() => _AgentShellState();
}

class _AgentShellState extends State<AgentShell> {
  late final AgentController _controller =
      AgentController(agentId: widget.agentName);
  int _index = 0;

  static const _titles = [
    'Carte',
    'Stationnements problématiques',
    'Statistiques',
    'Contraventions',
  ];

  @override
  void initState() {
    super.initState();
    _controller.start();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _logout() {
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
                      'Agent · ${widget.agentName}',
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
              // Premier chargement : spinner, ou erreur avec bouton « Réessayer »
              if (c.loading) {
                return const Center(child: CircularProgressIndicator());
              }
              return _ErrorState(
                message: c.error ?? 'Erreur inconnue',
                onRetry: c.refresh,
              );
            }
            return Column(
              children: [
                if (c.error != null) _ConnectionBanner(message: c.error!),
                Expanded(
                  // IndexedStack : la carte garde son zoom / sa rotation
                  // quand on passe sur un autre onglet.
                  child: IndexedStack(
                    index: _index,
                    children: [
                      AgentMapTab(controller: c),
                      AgentViolationsTab(controller: c),
                      AgentStatsTab(controller: c),
                      AgentFinesTab(controller: c),
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
            final n = _controller.snapshot?.violations.length ?? 0;
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
                    isLabelVisible: n > 0,
                    label: Text('$n'),
                    child: const Icon(Icons.warning_amber_rounded),
                  ),
                  selectedIcon: Badge(
                    isLabelVisible: n > 0,
                    label: Text('$n'),
                    child: const Icon(Icons.warning_rounded),
                  ),
                  label: 'Infractions',
                ),
                const NavigationDestination(
                  icon: Icon(Icons.insights_outlined),
                  selectedIcon: Icon(Icons.insights_rounded),
                  label: 'Stats',
                ),
                const NavigationDestination(
                  icon: Icon(Icons.receipt_long_outlined),
                  selectedIcon: Icon(Icons.receipt_long_rounded),
                  label: 'Amendes',
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Bandeau affiché quand un rafraîchissement échoue : les dernières données
/// restent à l'écran.
class _ConnectionBanner extends StatelessWidget {
  const _ConnectionBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: AgentColors.bad.withValues(alpha: 0.14),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Row(
        children: [
          const Icon(Icons.cloud_off_rounded, size: 16, color: AgentColors.bad),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Connexion perdue : $message',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AgentColors.bad,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Écran affiché quand le tout premier chargement échoue.
class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded,
                size: 56, color: AgentColors.muted),
            const SizedBox(height: 14),
            const Text(
              'Impossible de charger les données',
              style: TextStyle(
                color: AgentColors.ink,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AgentColors.muted),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Réessayer'),
            ),
          ],
        ),
      ),
    );
  }
}
