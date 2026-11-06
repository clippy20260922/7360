import 'dart:convert';

import 'package:http/http.dart' as http;

import 'parking_map_page.dart' show ParkingService;

/// Connexion de l'usager (SCRUM-61) : POST /token donne un jeton, renvoyé avec
/// ses requêtes dans l'en-tête Authorization (paiement, départ).
class SessionUsager {
  static String? jeton;
  static String? usager;
  // Gardé en mémoire le temps de la session, comme AgentService : si le serveur
  // redémarre, il oublie les jetons, et on se reconnecte tout seul.
  static String? _motDePasse;

  static const _delai = Duration(seconds: 10);

  static Map<String, String> get entetes =>
      {if (jeton != null) 'Authorization': 'Bearer $jeton'};

  /// POST /token : true si l'identifiant et le mot de passe sont acceptés.
  static Future<bool> connecter(String identifiant, String motDePasse) async {
    final res = await http.post(
      Uri.parse('${ParkingService.baseUrl}/token'),
      body: {'username': identifiant, 'password': motDePasse},
    ).timeout(_delai);
    if (res.statusCode != 200) return false;
    final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    jeton = data['access_token'] as String?;
    usager = identifiant;
    _motDePasse = motDePasse;
    return true;
  }

  static void deconnecter() {
    jeton = null;
    usager = null;
    _motDePasse = null;
  }

  /// Requête de l'usager connecté, avec son jeton ; si le serveur ne le
  /// reconnaît plus, on se reconnecte puis on réessaie une fois.
  static Future<http.Response> envoyer(
      Future<http.Response> Function(Map<String, String> entetes) requete) async {
    var res = await requete(entetes).timeout(_delai);
    final id = usager, mdp = _motDePasse;
    final oublie = res.statusCode == 401 ||
        (res.statusCode == 400 && utf8.decode(res.bodyBytes).contains('Authentifiez'));
    if (oublie && id != null && mdp != null && await connecter(id, mdp)) {
      res = await requete(entetes).timeout(_delai);
    }
    return res;
  }
}
