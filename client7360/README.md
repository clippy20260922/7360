# Plan du parking (Flutter)

Page Flutter qui affiche un plan de ville façon Waze / GPS : routes, bâtiments,
parcs, places de stationnement et parkings. On peut déplacer, zoomer et tourner
la carte avec les doigts, sélectionner une place et la réserver.

Tant que le backend n'est pas prêt (ou injoignable), la page affiche une
**ville de démonstration** générée dans l'app.

## Fichiers

| Fichier | Rôle |
|---|---|
| `parking_map_view.dart` | Composant de carte : modèles de données, caméra, dessin, gestes |
| `parking_map_page.dart` | Page complète : appels au backend, rafraîchissement, données de démo, bouton « Réserver » |


## Adresse du serveur

L'URL est choisie automatiquement :

| Contexte | URL utilisée |
|---|---|
| Émulateur Android | `http://10.0.2.2:8000` (le PC vu depuis l'émulateur) |
| Autres (web, bureau, iOS simulateur) | `http://127.0.0.1:8000` |

Pour la changer sans toucher au code :

```bash
flutter run --dart-define=API_URL=http://192.168.1.20:8000
```

Sur un vrai téléphone, utilise l'adresse IP du PC sur le réseau local.

## Contrat avec le backend

La page appelle toutes les 5 secondes :

### `GET /parking`

Renvoie un JSON avec quatre listes (`roads`, `buildings` et `zones` sont facultatives) :

```json
{
  "spots": [
    { "id": "12", "x": -28.6, "y": -5.5, "width": 2.5, "length": 5,
      "angle": 0, "status": "free" },
    { "id": "P-01", "x": 40, "y": 10, "width": 25, "length": 28,
      "angle": 0, "status": "free", "lot": true }
  ],
  "roads": [
    { "ax": -34, "ay": 0, "bx": 34, "by": 0, "width": 6, "name": "" }
  ],
  "buildings": [
    { "footprint": [ {"x": 0, "y": 0}, {"x": 10, "y": 0}, {"x": 10, "y": 8}, {"x": 0, "y": 8} ],
      "height": 14, "color": 4289379013 }
  ],
  "zones": [
    { "kind": "park", "polygon": [ {"x": 0, "y": 0}, {"x": 50, "y": 0}, {"x": 50, "y": 50} ] },
    { "kind": "water", "polygon": [ {"x": 10, "y": 10}, {"x": 20, "y": 10}, {"x": 20, "y": 20} ] }
  ]
}
```

- Toutes les coordonnées sont en **mètres locaux** (pas du GPS). `x` vers la droite, `y` vers le bas.
- `status` : `"free"`, `"occupied"` ou `"reserved"`.
- `angle` : rotation de la place en radians.
- `lot: true` : la place est un **parking** (voir plus bas).
- Si le serveur répond avec des listes toutes vides, l'app considère qu'il n'est pas prêt et affiche la démo.

### `POST /parking/spots/{id}/reserve`

Réserve la place. Doit répondre `200` ou `204`. Le bouton « Réserver » n'est actif que pour une place `free`.

## Ce qui est affiché

| Élément | Rendu |
|---|---|
| Petites rues | Blanc, contour gris |
| Grands axes (largeur ≥ 6,5) | Jaune, contour doré |
| Bâtiments | Gris clair, léger relief 3D, plus hauts vers le centre dans la démo |
| Parcs / plans d'eau | Vert / bleu clair, dessinés sous les routes |
| Places libres / occupées / réservées | Vert / rouge / orange |
| Parkings | Bleu avec un « P » blanc, bleu pâle quand ils sont occupés |
| Sélection | Contour cyan et épingle « P » au-dessus de la place |

Les couleurs sont regroupées en haut de la classe `ParkingPainter`
(`_land`, `_mainFill`, `_minorFill`, etc.).

### Places et parkings

Un parking est un `ParkingSpot` comme les autres, avec `isLot: true`. Il se
sélectionne et se réserve de la même façon, mais il est plus grand et affiché en
bleu. Dans la démo, il remplace un bâtiment.

## Gestes

| Geste | Effet |
|---|---|
| Glisser à un doigt | Déplacer la carte |
| Pincer à deux doigts | Zoomer (autour des doigts) |
| Tourner à deux doigts | Faire pivoter la carte (autour des doigts) |
| Toucher une place | La sélectionner |
| Molette de la souris (web / bureau) | Zoomer autour du curseur |
| Bouton « Réinitialiser la vue » (barre du haut) | Revenir à la vue de départ |

Sur l'émulateur Android, le pincement se simule avec Ctrl (ou Cmd) + glisser,
la rotation avec Ctrl + Maj + glisser.

Le zoom va de 0,3 (ville entière) à 40 (une place remplit l'écran).

## Données de démonstration

Elles sont générées par `_createDemoData()` dans `parking_map_page.dart`, de
façon reproductible (même graine à chaque lancement) :

- une ville d'environ 800 × 700 m, bien plus grande que l'écran ;
- 17 rues en quadrillage irrégulier légèrement tourné, dont 4 axes principaux, plus un boulevard en diagonale ;
- plusieurs centaines de bâtiments par îlots ;
- 2 parcs avec un plan d'eau ;
- les 7 places de la base du serveur (ids 1 à 7) alignées le long d'une rue du centre ;
- environ 350 autres places en petites rangées le long des rues secondaires ;
- quelques parkings à la place de certains bâtiments.

Réglages utiles dans `_createDemoData()` :

| Réglage | Où |
|---|---|
| Quantité de places | `random.nextInt(100) < 35` (rangées de places) |
| Quantité de parkings | `random.nextInt(100) < 5` |
| Répartition libre / occupée / réservée | fonction `randomStatus()` |
| Taille de la ville | tableaux `xs` et `ys` |
