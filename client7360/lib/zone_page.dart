import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

// Adresse du serveur FastAPI (voir server7360)
const String urlServeurZone = 'http://127.0.0.1:8000';

/// Page pour choisir une zone géographique (un rectangle entre deux latitudes
/// et deux longitudes) et voir les places qui s'y trouvent.
class ZonePage extends StatefulWidget {
  const ZonePage({super.key});

  @override
  State<ZonePage> createState() => _ZonePageState();
}

class _ZonePageState extends State<ZonePage> {
  // Valeurs de départ : une zone qui contient les places de test du serveur
  final TextEditingController _latMinController = TextEditingController(text: '1.2');
  final TextEditingController _latMaxController = TextEditingController(text: '1.3');
  final TextEditingController _longMinController = TextEditingController(text: '2.3');
  final TextEditingController _longMaxController = TextEditingController(text: '2.4');

  bool _libresSeulement = true;
  List<dynamic> _places = [];
  String _message = '';

  @override
  void dispose() {
    _latMinController.dispose();
    _latMaxController.dispose();
    _longMinController.dispose();
    _longMaxController.dispose();
    super.dispose();
  }

  Future<void> _chercher() async {
    final chemin = _libresSeulement ? '/data/free/zone' : '/data/zone';
    final url = Uri.parse('$urlServeurZone$chemin').replace(queryParameters: {
      'lat_min': _latMinController.text.trim(),
      'lat_max': _latMaxController.text.trim(),
      'long_min': _longMinController.text.trim(),
      'long_max': _longMaxController.text.trim(),
    });
    try {
      final response = await http.get(url);
      if (!mounted) return;
      // Le serveur renvoie du JSON en UTF-8 : on décode à la main pour garder les accents
      final data = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      setState(() {
        if (response.statusCode == 200) {
          _places = (data['data'] ?? []) as List<dynamic>;
          _message = '${data['N']} place(s) trouvée(s)';
        } else if (response.statusCode == 422) {
          _places = [];
          _message = 'Coordonnées invalides (latitude entre -90 et 90, longitude entre -180 et 180)';
        } else {
          _places = [];
          _message = (data['detail'] ?? 'Erreur ${response.statusCode}').toString();
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _places = [];
        _message = 'Serveur injoignable';
      });
    }
  }

  Widget _champ(String label, TextEditingController controller) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
          decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
        ),
      ),
    );
  }

  // Une place renvoyée par le serveur est une liste :
  // [id, lat, long, type, occupée, pmr, électrique, ...] (voir Doc/documentation.md)
  Widget _lignePlace(List<dynamic> place) {
    final occupee = place[4] == 1 || place[4] == true;
    return ListTile(
      leading: Icon(
        occupee ? Icons.block : Icons.local_parking,
        color: occupee ? Colors.red : Colors.green,
      ),
      title: Text('Place ${place[0]} (${place[3]})'),
      subtitle: Text('lat ${place[1]}, long ${place[2]}'),
      trailing: Text(occupee ? 'occupée' : 'libre'),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('Choisir une zone'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                _champ('Latitude min', _latMinController),
                _champ('Latitude max', _latMaxController),
              ],
            ),
            Row(
              children: [
                _champ('Longitude min', _longMinController),
                _champ('Longitude max', _longMaxController),
              ],
            ),

            CheckboxListTile(
              title: const Text('Seulement les places libres'),
              value: _libresSeulement,
              onChanged: (v) => setState(() => _libresSeulement = v ?? true),
            ),

            ElevatedButton(
              onPressed: _chercher,
              child: const Text('Chercher'),
            ),

            const SizedBox(height: 16),

            Text(_message),

            Expanded(
              child: ListView.builder(
                itemCount: _places.length,
                itemBuilder: (context, index) => _lignePlace(_places[index] as List<dynamic>),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
