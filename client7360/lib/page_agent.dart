import 'package:flutter/material.dart';

import 'agent/agent_service.dart';
import 'agent/agent_shell.dart';
import 'agent/agent_theme.dart';

/// Connexion de l'agent (écran « Je suis agent »). Une fois connecté, on
/// arrive directement sur la page agent : carte, problématiques, stats.
class PageAgent extends StatefulWidget {
  const PageAgent({super.key});

  @override
  State<PageAgent> createState() => _PageAgentState();
}

class _PageAgentState extends State<PageAgent> {
  final _id = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _hidePassword = true;
  String? _error;

  @override
  void dispose() {
    _id.dispose();
    _password.dispose();
    super.dispose();
  }

  void _openAgentPage(String name) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => AgentShell(agentName: name)),
    );
  }

  Future<void> _submit() async {
    final id = _id.text.trim();
    if (id.isEmpty || _password.text.isEmpty) {
      setState(() => _error = 'Renseignez votre identifiant et votre mot de passe.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AgentService.login(id, _password.text);
      if (!mounted) return;
      _openAgentPage(id);
    } on AgentAuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Serveur injoignable. Vérifiez la connexion '
            "ou l'adresse de l'API.");
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  InputDecoration _decoration(String label, IconData icon, {Widget? suffix}) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: AgentColors.muted),
      suffixIcon: suffix,
      filled: true,
      fillColor: AgentColors.bg,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AgentColors.blue, width: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: buildAgentTheme(),
      child: Scaffold(
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [AgentColors.navy, AgentColors.navyLight],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 380),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 84,
                        height: 84,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [AgentColors.blue, AgentColors.cyan],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(26),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x6633CCFF),
                              blurRadius: 30,
                              offset: Offset(0, 10),
                            ),
                          ],
                        ),
                        alignment: Alignment.center,
                        child: const Text(
                          'P',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 50,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      const Text(
                        'Espace agent',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Contrôle du stationnement',
                        style: TextStyle(color: Color(0xFF9FB0D0), fontSize: 15),
                      ),
                      const SizedBox(height: 28),
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: Column(
                          children: [
                            TextField(
                              controller: _id,
                              enabled: !_busy,
                              textInputAction: TextInputAction.next,
                              autocorrect: false,
                              decoration: _decoration(
                                "Numéro d'identification",
                                Icons.badge_outlined,
                              ),
                            ),
                            const SizedBox(height: 14),
                            TextField(
                              controller: _password,
                              enabled: !_busy,
                              obscureText: _hidePassword,
                              onSubmitted: (_) => _submit(),
                              decoration: _decoration(
                                'Mot de passe',
                                Icons.lock_outline_rounded,
                                suffix: IconButton(
                                  icon: Icon(
                                    _hidePassword
                                        ? Icons.visibility_outlined
                                        : Icons.visibility_off_outlined,
                                  ),
                                  onPressed: () => setState(
                                      () => _hidePassword = !_hidePassword),
                                ),
                              ),
                            ),
                            if (_error != null) ...[
                              const SizedBox(height: 14),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: AgentColors.bad.withValues(alpha: 0.10),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.error_outline_rounded,
                                        color: AgentColors.bad, size: 20),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        _error!,
                                        style: const TextStyle(
                                          color: AgentColors.bad,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            const SizedBox(height: 18),
                            SizedBox(
                              width: double.infinity,
                              height: 52,
                              child: FilledButton(
                                style: FilledButton.styleFrom(
                                  backgroundColor: AgentColors.blue,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                ),
                                onPressed: _busy ? null : _submit,
                                child: _busy
                                    ? const SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.5,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Text(
                                        'Se connecter',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
