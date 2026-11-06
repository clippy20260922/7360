class ReservationsLocales {
  // Associe chaque plaque d'immatriculation à une place.
  static final Map<String, String> _reservations = {};

  // Enregistrer une réservation.
  static void reserver(String plaque, String placeId) {
    _reservations[plaque.trim().toUpperCase()] = placeId;
  }

  // Retrouver la place associée à une plaque.
  static String? rechercher(String plaque) {
    return _reservations[plaque.trim().toUpperCase()];
  }

  // Supprimer une réservation après le départ.
  static String? liberer(String plaque) {
    return _reservations.remove(plaque.trim().toUpperCase());
  }

  // Vérifier si une place est réservée localement.
  static bool estOccupee(String placeId) {
    return _reservations.containsValue(placeId);
  }

  static final Set<String> _placesLiberees = {};

  static void marquerPlaceLiberee(String placeId) {
    _placesLiberees.add(placeId);
  }

  static bool estLiberee(String placeId) {
    return _placesLiberees.contains(placeId);
  }

  static void effacerLiberation(String placeId) {
    _placesLiberees.remove(placeId);
  }

}