import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

// Adresse du serveur FastAPI (voir server7360)
const String urlServeurPaiement = 'http://127.0.0.1:8000';

/// Page pour payer une place : on choisit la plaque et la durée,
/// le serveur donne le prix puis enregistre le paiement.
class PaiementPage extends StatefulWidget {
  const PaiementPage({super.key, required this.idPlace});

  final int idPlace;

  @override
  State<PaiementPage> createState() => _PaiementPageState();
}

class _PaiementPageState extends State<PaiementPage> {
  // Durées proposées, en minutes
  static const List<int> _durees = [15, 30, 60, 120, 240];

  final TextEditingController _plaqueController = TextEditingController();
  int _duree = 60;
  String _prix = '-';
  String _message = '';
  bool _paye = false;

  @override
  void initState() {
    super.initState();
    _demanderPrix();
  }

  @override
  void dispose() {
    _plaqueController.dispose();
    super.dispose();
  }

  // Le serveur renvoie du JSON en UTF-8 : on décode à la main pour garder les accents
  Map<String, dynamic> _lireJson(http.Response response) {
    return jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
  }

  String _texteErreur(http.Response response, Map<String, dynamic> data) {
    if (response.statusCode == 401) return 'Connectez-vous avant de payer';
    if (response.statusCode == 422) return 'Plaque ou durée invalide';
    return (data['detail'] ?? 'Erreur ${response.statusCode}').toString();
  }

  String _texteDuree(int minutes) {
    return minutes < 60 ? '$minutes min' : '${minutes ~/ 60} h';
  }

  Future<void> _demanderPrix() async {
    final url = Uri.parse('$urlServeurPaiement/data/${widget.idPlace}/prix')
        .replace(queryParameters: {'duree': '$_duree'});
    try {
      final response = await http.get(url);
      if (!mounted) return;
      final data = _lireJson(response);
      setState(() {
        if (response.statusCode == 200) {
          _prix = '${data['prix']} €';
        } else {
          _prix = '-';
          _message = _texteErreur(response, data);
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _message = 'Serveur injoignable');
    }
  }

  Future<void> _payer() async {
    final plaque = _plaqueController.text.trim().toUpperCase();
    if (plaque.isEmpty) {
      setState(() => _message = 'Indiquez la plaque du véhicule');
      return;
    }
    final url = Uri.parse('$urlServeurPaiement/data/${widget.idPlace}/payer')
        .replace(queryParameters: {'plaque': plaque, 'duree': '$_duree'});
    try {
      final response = await http.post(url);
      if (!mounted) return;
      final data = _lireJson(response);
      setState(() {
        if (response.statusCode == 200) {
          _paye = true;
          _message = 'Paiement accepté : ${data['prix']} €\n'
              'Place ${data['place']} payée jusqu\'à ${data['fin_occupation']}';
        } else {
          _message = _texteErreur(response, data);
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _message = 'Serveur injoignable');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text('Payer la place ${widget.idPlace}'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _plaqueController,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'Plaque du véhicule (ex : AB123CD)',
                  border: OutlineInputBorder(),
                ),
              ),

              const SizedBox(height: 16),

              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Durée : '),
                  DropdownButton<int>(
                    value: _duree,
                    items: [
                      for (final d in _durees)
                        DropdownMenuItem(value: d, child: Text(_texteDuree(d))),
                    ],
                    onChanged: _paye
                        ? null
                        : (d) {
                            if (d == null) return;
                            setState(() {
                              _duree = d;
                              _message = '';
                            });
                            _demanderPrix();
                          },
                  ),
                ],
              ),

              const SizedBox(height: 16),

              Text('Prix : $_prix', style: Theme.of(context).textTheme.titleLarge),

              const SizedBox(height: 32),

              ElevatedButton(
                onPressed: _paye ? null : _payer,
                child: const Text('Payer'),
              ),

              const SizedBox(height: 16),

              Text(_message, textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}
