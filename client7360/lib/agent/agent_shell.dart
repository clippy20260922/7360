import 'package:flutter/material.dart';

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
  final AgentController _controller = AgentController();
  int _index = 0;

  static const _titles = ['Carte', 'Stationnements problématiques', 'Statistiques'];

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
    Navigator.of(context).pop();
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
        body: Column(
          children: [
            _DemoBanner(controller: _controller),
            Expanded(
              // IndexedStack : la carte garde son zoom / sa rotation
              // quand on passe sur un autre onglet.
              child: IndexedStack(
                index: _index,
                children: [
                  AgentMapTab(controller: _controller),
                  AgentViolationsTab(controller: _controller),
                  AgentStatsTab(controller: _controller),
                ],
              ),
            ),
          ],
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
                  label: 'Problématiques',
                ),
                const NavigationDestination(
                  icon: Icon(Icons.insights_outlined),
                  selectedIcon: Icon(Icons.insights_rounded),
                  label: 'Stats',
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Bandeau affiché quand le serveur ne fournit pas le plan : on travaille
/// alors sur des données de démonstration.
class _DemoBanner extends StatelessWidget {
  const _DemoBanner({required this.controller});

  final AgentController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final snap = controller.snapshot;
        if (snap == null || !snap.mapIsDemo) return const SizedBox.shrink();
        return Container(
          width: double.infinity,
          color: AgentColors.warn.withValues(alpha: 0.18),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          child: Row(
            children: [
              const Icon(Icons.science_outlined,
                  size: 16, color: Color(0xFF8A5B00)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Mode démo : plan simulé (${snap.error ?? "API indisponible"})',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF8A5B00),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
