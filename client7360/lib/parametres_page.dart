import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ParametresPage extends StatefulWidget {
  const ParametresPage({super.key});

  @override
  State<ParametresPage> createState() => _ParametresPageState();
}

class _ParametresPageState extends State<ParametresPage> {
  final _addressController = TextEditingController();
  String? _result;
  bool? _connectionSucceeded;
  bool _isTesting = false;

  @override
  void initState() {
    super.initState();
    _loadAddress();
  }

  Future<void> _loadAddress() async {
    final preferences = await SharedPreferences.getInstance();
    _addressController.text = preferences.getString('serverAddress') ?? '';
  }

  Future<void> _testConnection() async {
    final address = _addressController.text.trim();
    final uri = Uri.tryParse(address);

    if (uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty) {
      setState(() {
        _result = 'Veuillez entrer une adresse HTTP ou HTTPS valide.';
        _connectionSucceeded = false;
      });
      return;
    }

    setState(() {
      _isTesting = true;
      _result = null;
      _connectionSucceeded = null;
    });

    final client = HttpClient();

    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString('serverAddress', address);

      final request = await client
          .getUrl(uri)
          .timeout(const Duration(seconds: 5));
      final response = await request.close().timeout(
        const Duration(seconds: 5),
      );
      final body = await utf8.decoder.bind(response).join().timeout(
        const Duration(seconds: 5),
      );

      final succeeded = response.statusCode >= 200 &&
          response.statusCode < 300;

      setState(() {
        _connectionSucceeded = succeeded;
        _result = succeeded
            ? 'Connexion réussie (HTTP ${response.statusCode})\n$body'
            : 'Échec de la connexion (HTTP ${response.statusCode})\n$body';
      });
    } catch (error) {
      setState(() {
        _connectionSucceeded = false;
        _result = 'Échec de la connexion : $error';
      });
    } finally {
      client.close(force: true);
      setState(() => _isTesting = false);
    }
  }

  @override
  void dispose() {
    _addressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Paramètres de l\'application'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Center(
        child: SizedBox(
          width: 340,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _addressController,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Adresse du serveur',
                  hintText: 'http://127.0.0.1:60000',
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: _isTesting ? null : _testConnection,
                  child: Text(_isTesting ? 'Test en cours...' : 'Tester la connexion'),
                ),
              ),
              if (_result != null) ...[
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  color: _connectionSucceeded == true
                      ? Colors.green.shade100
                      : Colors.red.shade100,
                  child: Text(_result!),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
