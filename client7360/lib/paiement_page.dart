import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'parking_map_page.dart' show ParkingService;
import 'reservations_locales.dart';
import 'session_usager.dart';

/// Page pour payer une place (SCRUM-13) : on se connecte, on choisit un de
/// ses véhicules et une durée, le serveur donne le prix puis enregistre le
/// paiement. La place passe alors occupée jusqu'à la fin de la durée payée.
/// Si le véhicule est déjà garé sur cette place, le paiement la prolonge.
class PaiementPage extends StatefulWidget {
  const PaiementPage({super.key, required this.idPlace});

  final int idPlace;

  @override
  State<PaiementPage> createState() => _PaiementPageState();
}

class _PaiementPageState extends State<PaiementPage> {
  // Durées proposées, en minutes (le serveur accepte jusqu'à 24 h)
  static const List<int> _durees = [15, 30, 60, 120, 240];

  static String get _base => ParkingService.baseUrl;

  final TextEditingController _identifiantController = TextEditingController();
  final TextEditingController _motDePasseController = TextEditingController();

  int _duree = 60;
  String? _typePlace; // voit, moto... (renvoyé par le serveur avec le prix)
  double? _prix;
  double? _tarifHoraire;

  String? _utilisateur; // identifiant connecté
  List<String> _plaques = []; // véhicules de l'utilisateur compatibles avec la place
  String? _plaque;

  bool _occupe = false;
  bool _paye = false;
  String _message = '';
  bool _erreur = false;

  @override
  void initState() {
    super.initState();
    _reprendreSession();
  }

  @override
  void dispose() {
    _identifiantController.dispose();
    _motDePasseController.dispose();
    super.dispose();
  }

  // Le serveur renvoie du JSON en UTF-8 : on décode à la main pour garder les accents
  dynamic _lireJson(http.Response response) {
    try {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } catch (_) {
      return null;
    }
  }

  String _texteErreur(http.Response response, dynamic data) {
    if (response.statusCode == 401) return 'Connectez-vous avant de payer';
    if (response.statusCode == 422) return 'Plaque ou durée invalide';
    if (data is Map && data['detail'] is String) return data['detail'] as String;
    return 'Erreur ${response.statusCode}';
  }

  void _afficher(String message, {bool erreur = false}) {
    setState(() {
      _message = message;
      _erreur = erreur;
    });
  }

  String _texteDuree(int minutes) {
    if (minutes < 60) return '$minutes min';
    final h = minutes ~/ 60, m = minutes % 60;
    return m == 0 ? '$h h' : '$h h ${m.toString().padLeft(2, '0')}';
  }

  String _texteEuros(double montant) =>
      '${montant.toStringAsFixed(2).replaceAll('.', ',')} €';

  // Les heures de la base sont en UTC (yyyy-mm-dd hh:mm:ss) : on les affiche à l'heure locale
  String _heureLocale(String utc) {
    final date = DateTime.tryParse('${utc.replaceFirst(' ', 'T')}Z');
    if (date == null) return utc;
    final l = date.toLocal();
    String deux(int n) => n.toString().padLeft(2, '0');
    return '${deux(l.day)}/${deux(l.month)} à ${deux(l.hour)}h${deux(l.minute)}';
  }

  Future<void> _demanderPrix() async {
    final url = Uri.parse('$_base/data/${widget.idPlace}/prix')
        .replace(queryParameters: {'duree': '$_duree'});
    try {
      final response = await http.get(url).timeout(const Duration(seconds: 10));
      if (!mounted) return;
      final data = _lireJson(response);
      if (response.statusCode == 200 && data is Map) {
        setState(() {
          _typePlace = data['type'] as String?;
          _prix = (data['prix'] as num?)?.toDouble();
          _tarifHoraire = (data['tarif_horaire'] as num?)?.toDouble();
        });
      } else {
        setState(() => _prix = null);
        _afficher(_texteErreur(response, data), erreur: true);
      }
    } catch (_) {
      if (mounted) _afficher('Serveur injoignable', erreur: true);
    }
  }

  Future<void> _seConnecter() async {
    final identifiant = _identifiantController.text.trim();
    final motDePasse = _motDePasseController.text;
    if (identifiant.isEmpty || motDePasse.isEmpty) {
      _afficher('Renseignez votre identifiant et votre mot de passe', erreur: true);
      return;
    }
    setState(() => _occupe = true);
    try {
      // Le jeton reçu est gardé par SessionUsager pour les autres pages (départ)
      final accepte = await SessionUsager.connecter(identifiant, motDePasse);
      if (!mounted) return;
      if (!accepte) {
        _afficher('Identifiant ou mot de passe incorrect', erreur: true);
        return;
      }
      _motDePasseController.clear();
      await _chargerVehicules(identifiant);
    } catch (_) {
      if (mounted) _afficher('Serveur injoignable', erreur: true);
    } finally {
      if (mounted) setState(() => _occupe = false);
    }
  }

  // Déjà connecté sur une autre place : on reprend la session
  Future<void> _reprendreSession() async {
    await _demanderPrix(); // donne le type de la place, pour filtrer les véhicules
    final usager = SessionUsager.usager;
    if (!mounted || usager == null || SessionUsager.jeton == null) return;
    try {
      await _chargerVehicules(usager);
    } catch (_) {
      if (mounted) _afficher('Serveur injoignable', erreur: true);
    }
  }

  void _changerDeCompte() {
    SessionUsager.deconnecter();
    setState(() {
      _utilisateur = null;
      _plaques = [];
      _plaque = null;
    });
    _afficher('');
  }

  Future<void> _chargerVehicules(String identifiant) async {
    // Véhicules de l'utilisateur : [plaque, propriétaire, type, électrique, place actuelle]
    final reponse = await SessionUsager.envoyer((entetes) => http.get(
        Uri.parse('$_base/user/${Uri.encodeComponent(identifiant)}'),
        headers: entetes));
    if (!mounted) return;
    final data = _lireJson(reponse);
    if (reponse.statusCode != 200) {
      _changerDeCompte(); // session perdue : on redemande l'identifiant
      _afficher('Reconnectez-vous (${_texteErreur(reponse, data)})', erreur: true);
      return;
    }
    final vehicules = (data is Map ? data['data'] as List<dynamic>? : null) ?? [];
    final compatibles = [
      for (final v in vehicules)
        if (v is List && (_typePlace == null || v[2] == _typePlace)) v[0] as String,
    ];
    setState(() {
      _utilisateur = identifiant;
      _plaques = compatibles;
      _plaque = compatibles.isEmpty ? null : compatibles.first;
    });
    _afficher(compatibles.isEmpty
        ? 'Aucun de vos véhicules ne correspond à cette place'
        : '');
  }

  Future<void> _payer() async {
    final plaque = _plaque;
    if (plaque == null) return;
    setState(() => _occupe = true);
    final url = Uri.parse('$_base/data/${widget.idPlace}/payer')
        .replace(queryParameters: {'plaque': plaque, 'duree': '$_duree'});
    try {
      final response = await SessionUsager.envoyer((entetes) => http.post(url, headers: entetes));
      if (!mounted) return;
      final data = _lireJson(response);
      if (response.statusCode == 200 && data is Map) {
        final prix = (data['prix'] as num).toDouble();
        final fin = _heureLocale(data['fin_occupation'] as String);
        // Pour « Reprendre la route » : la plaque et la place, à libérer sur le serveur
        ReservationsLocales.effacerLiberation('${widget.idPlace}');
        ReservationsLocales.reserverSurLeServeur(plaque, '${widget.idPlace}');
        setState(() => _paye = true);
        _afficher(data['prolongation'] == true
            ? 'Stationnement prolongé (${_texteEuros(prix)}) : '
                'place ${data['place']} payée jusqu\'au $fin'
            : 'Paiement accepté (${_texteEuros(prix)}) : '
                'place ${data['place']} payée jusqu\'au $fin');
      } else {
        _afficher(_texteErreur(response, data), erreur: true);
      }
    } catch (_) {
      if (mounted) _afficher('Serveur injoignable', erreur: true);
    } finally {
      if (mounted) setState(() => _occupe = false);
    }
  }

  Widget _blocConnexion() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('1. Connexion', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        TextField(
          controller: _identifiantController,
          decoration: const InputDecoration(
            labelText: 'Identifiant',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.person),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _motDePasseController,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Mot de passe',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.lock),
          ),
          onSubmitted: (_) => _seConnecter(),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _occupe ? null : _seConnecter,
          child: const Text('Se connecter'),
        ),
      ],
    );
  }

  Widget _blocPaiement() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.green),
            const SizedBox(width: 8),
            Expanded(child: Text('Connecté : $_utilisateur')),
            TextButton(
              onPressed: _occupe ? null : _changerDeCompte,
              child: const Text('Changer de compte'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text('2. Véhicule et durée', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _plaque,
          decoration: const InputDecoration(
            labelText: 'Véhicule',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.directions_car),
          ),
          items: [
            for (final p in _plaques) DropdownMenuItem(value: p, child: Text(p)),
          ],
          onChanged: _paye ? null : (p) => setState(() => _plaque = p),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<int>(
          initialValue: _duree,
          decoration: const InputDecoration(
            labelText: 'Durée',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.timer),
          ),
          items: [
            for (final d in _durees)
              DropdownMenuItem(value: d, child: Text(_texteDuree(d))),
          ],
          onChanged: _paye
              ? null
              : (d) {
                  if (d == null) return;
                  setState(() => _duree = d);
                  _demanderPrix();
                },
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: _paye || _occupe || _plaque == null || _prix == null ? null : _payer,
          icon: const Icon(Icons.euro),
          label: Text(_prix == null ? 'Payer' : 'Payer ${_texteEuros(_prix!)}'),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text('Payer la place ${widget.idPlace}'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Place n°${widget.idPlace}',
                            style: Theme.of(context).textTheme.titleLarge),
                        const SizedBox(height: 8),
                        Text('Tarif : ${_tarifHoraire == null ? '-' : '${_texteEuros(_tarifHoraire!)} / h'}'),
                        Text('Prix pour ${_texteDuree(_duree)} : '
                            '${_prix == null ? '-' : _texteEuros(_prix!)}'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _utilisateur == null ? _blocConnexion() : _blocPaiement(),
                const SizedBox(height: 16),
                if (_message.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _erreur ? Colors.red.shade50 : Colors.green.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(_message, textAlign: TextAlign.center),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
