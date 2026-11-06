# Places réelles de la Cité Descartes (SCRUM-53)

Fabrique `server7360/places_cite_descartes.json` : les places de stationnement **réelles** du campus
(Champs-sur-Marne / Noisy-le-Grand), chargées par le serveur au démarrage (identifiants 1001 et plus)
et affichées sur la vraie carte OpenStreetMap de l'appli.

Résultat au 06/11/2026 : **869 places**.

| Source | Places |
|---|---|
| OSM : bandes de stationnement le long des rues, découpées selon leur capacité | 466 |
| Photo IGN : voitures garées détectées par YOLO | 279 |
| Photo IGN : rangées reconstituées à partir des voitures détectées | 69 |
| OSM : places dessinées une par une | 39 |
| OSM : rue découpée tous les 5,5 m (avenue Blaise Pascal) | 16 |

## Méthode, en 3 étapes

1. **`places_osm.py`** (bibliothèque standard seulement) : interroge OpenStreetMap (Overpass) sur la zone.
   - Places dessinées (`amenity=parking_space`) : prises telles quelles, avec PMR et électrique.
   - Bandes de stationnement des rues (`parking=street_side`) : découpées en `capacity` places, en
     suivant la courbe de la bande (créneau 5,5 m, bataille 2,5 m).
   - Rues marquées « stationnement autorisé » (`parking:left/right/both`) : une place tous les 5,5 m,
     décalée sur le bon côté de la chaussée, 12 m laissés libres aux carrefours.
   - Parkings avec capacité connue : grille de places en bataille (aucun pour l'instant sur le campus).
   - Les parkings **privés** (`access=private`, parkings du personnel) sont écartés : l'appli est pour le public.
   - Les parkings publics sans place ni capacité sont transmis à l'étape 2.
2. **`places_yolo.py`** : pour chacun de ces parkings, assemble la photo aérienne IGN (BD ORTHO,
   20 cm/pixel) et y cherche les voitures avec des modèles **YOLO OBB entraînés sur des vues aériennes
   (DOTA)** : YOLO11l, YOLO11m et YOLO26m, sur des carreaux de 1024 px, photo agrandie 2 à 2,5 fois.
   On garde la meilleure détection de chaque voiture. Une voiture garée dans le contour du parking
   donne une place. Puis on **reconstitue les rangées** : au moins 3 voitures alignées donnent l'axe
   et le pas (≈ 2,5 m). On comble les trous et on prolonge la rangée tant que la photo montre une
   voiture, un marquage ou une bande de places plus claire que l'allée. On s'arrête sur l'herbe, une
   allée ou le bord du parking.
3. **`fusion.py`** : réunit les deux étapes, numérote à partir de 1001 et écrit le fichier du serveur.

`apercu.py` génère `apercu.html` : toutes les places dessinées en vrais rectangles sur la photo IGN,
une couleur par source, pour vérifier qu'elles tombent bien sur les emplacements.
Images de contrôle de YOLO : `cache/yolo/*.jpg` (vert = voiture vue, cyan = place déduite).

## Relancer

```sh
cd outils/places-reelles
python3 places_osm.py --rafraichir        # nouvelles données OSM (sinon : cache/osm_brut.json)
~/.venvs/yolo7360/bin/python places_yolo.py
python3 fusion.py
python3 apercu.py && python3 -m http.server 8080   # puis ouvrir http://127.0.0.1:8080/apercu.html
```

L'étape 2 a besoin d'un Python à part avec Ultralytics (≈ 1,5 Go, PyTorch CPU) :
`python3 -m venv ~/.venvs/yolo7360`, puis
`~/.venvs/yolo7360/bin/pip install torch torchvision --index-url https://download.pytorch.org/whl/cpu`
et `~/.venvs/yolo7360/bin/pip install ultralytics`. Les poids des modèles se téléchargent dans
`cache/` au premier lancement. Il faut environ 3 min sur 12 cœurs.
Le serveur, lui, n'a besoin de rien de plus : il lit seulement le fichier JSON.

Options : `--avec-prives` (traiter aussi les parkings privés), `--parking way/123` (un seul parking,
pour régler), `--sans-rangees`, `--conf 0.2`.

## Limites

- Les modèles DOTA ratent une partie des voitures sombres ou serrées. Les rangées en rattrapent
  beaucoup, mais un parking compte souvent moins de places qu'en vrai (≈ 140 au lieu de ≈ 200 pour
  celui du rond-point avenue Blaise Pascal). On a préféré ne pas inventer de places.
- Un parking vide sur la photo ne donne aucune place : rien ne permet d'y voir des rangées.
- Les rues où des voitures stationnent sans que ce soit cartographié dans OSM n'ont pas de places.
- Les tarifs sont ceux des places de démo de l'équipe (1,60 €/h dans la rue, 2 €/h en parking) :
  ce ne sont pas les vrais tarifs de Champs-sur-Marne.

## Licences

- Données OSM © les contributeurs d'OpenStreetMap, **ODbL** : citer « © OpenStreetMap ». Le fichier
  produit est une base dérivée : à partager sous la même licence s'il est publié.
- Photos © IGN, BD ORTHO, Licence Ouverte Etalab 2.0.
- Modèles Ultralytics YOLO : AGPL-3.0, utilisés seulement pour produire les données, pas dans l'appli.
