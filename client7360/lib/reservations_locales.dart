class ReservationsLocales {
  // Associe chaque plaque d'immatriculation à une place.
  static final Map<String, String> _reservations = {};

  // Enregistrer une réservation.
  static void reserver(String plaque, String placeId) {
    _reservations[plaque.trim().toUpperCase()] = placeId;
    _surLeServeur.remove(plaque.trim().toUpperCase());
  }

  // Réservations payées sur le serveur : au départ, il faut aussi libérer la
  // place sur le serveur (voir ReprendreLaRoutePage).
  static final Set<String> _surLeServeur = {};

  static void reserverSurLeServeur(String plaque, String placeId) {
    reserver(plaque, placeId);
    _surLeServeur.add(plaque.trim().toUpperCase());
  }

  static bool estSurLeServeur(String plaque) {
    return _surLeServeur.contains(plaque.trim().toUpperCase());
  }

  // Retrouver la place associée à une plaque.
  static String? rechercher(String plaque) {
    return _reservations[plaque.trim().toUpperCase()];
  }

  // Supprimer une réservation après le départ.
  static String? liberer(String plaque) {
    _surLeServeur.remove(plaque.trim().toUpperCase());
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