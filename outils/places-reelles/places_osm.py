#!/usr/bin/env python3
"""Étape 1 : les places réelles de la Cité Descartes depuis OpenStreetMap.

Bibliothèque standard seulement. Sources, de la plus sûre à la plus estimée :
  1. amenity=parking_space         : place dessinée une par une (point ou contour)
  2. amenity=parking, street_side  : bande le long d'une rue, découpée en `capacity` places
                                     (ou longueur / pas si la capacité manque)
  3. rues avec parking:left/right/both : rue découpée tous les 5,5 m (créneau) ou 2,5 m (bataille)
  4. amenity=parking en surface avec `capacity` et sans place dessinée : grille de places
  5. amenity=motorcycle_parking    : places moto
Les parkings publics en surface sans place ni capacité sont listés dans
`a_completer` pour l'étape 2 (détection des voitures par YOLO sur photo IGN). Un parking
où OSM n'a dessiné que quelques places (souvent les places handicapés) y va aussi.
Les contours des parkings publics sont gardés dans `parkings` : fusion.py s'en sert
pour regrouper les places par parking.
Les parkings privés (access=private) sont écartés : l'appli est pour le public.

Usage : python3 places_osm.py [--rafraichir] [--avec-prives]
Données © les contributeurs d'OpenStreetMap, licence ODbL.
"""
import argparse
import json
import math
import sys
import time
import urllib.parse
import urllib.request
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path

from geo import (Grille, aire_centre, coins, coupes, dedans, dist_segment,
                 rectangle_min, vers_latlon, vers_xy)

ICI = Path(__file__).resolve().parent
CACHE = ICI / "cache"
SORTIE = ICI / "places_osm.json"

# Cité Descartes (Champs-sur-Marne / Noisy-le-Grand) : sud, ouest, nord, est
ZONE = (48.8345, 2.5740, 48.8460, 2.5960)
COMMUNES = ["Champs-sur-Marne", "Noisy-le-Grand", "Noisiel"]
OVERPASS = "https://overpass-api.de/api/interpreter"
AGENT = "client7360-projet-etudiant-ESIEE (places-reelles)"

# Dimensions d'une place (m) : (longueur, largeur, pas le long de la rue)
DIM = {
    "parallel": (5.5, 2.0, 5.5),       # créneau
    "perpendicular": (5.0, 2.5, 2.5),  # bataille
    "diagonal": (5.0, 2.5, 3.0),       # épi
}
MOTO = (2.2, 1.0, 1.2)
ROUTES = "primary|secondary|tertiary|unclassified|residential|living_street|service|primary_link|secondary_link|tertiary_link"
OUI_STATIONNEMENT = {"yes", "lane", "street_side", "on_kerb", "half_on_kerb", "shoulder",
                     "parallel", "diagonal", "perpendicular", "marked", "inline"}
PRIVES = {"private", "no", "permit", "delivery"}
TARIF_RUE, TARIF_PARKING = 1.6, 2.0  # mêmes valeurs que les places de démo de l'équipe
M2_PAR_PLACE = 25  # surface d'un parking par place, allées comprises


def requete_overpass(rafraichir):
    CACHE.mkdir(exist_ok=True)
    cache = CACHE / "osm_brut.json"
    if cache.exists() and not rafraichir:
        return json.loads(cache.read_text(encoding="utf-8"))
    b = ",".join(str(v) for v in ZONE)
    q = [f"[out:json][timeout:120][bbox:{b}];",
         '(nwr["amenity"~"^(parking|parking_space|motorcycle_parking|charging_station)$"];'
         f'way["highway"~"^({ROUTES})$"];);',
         "out body geom;"]
    # Pour chaque commune : un repère, puis les identifiants des objets qui s'y trouvent
    for i, nom in enumerate(COMMUNES):
        q.append(f'area["name"="{nom}"]["admin_level"="8"]->.c{i};')
        q.append(f'make commune nom="{nom}"; out;')
        q.append(f'(nwr(area.c{i})["amenity"~"^(parking|parking_space|motorcycle_parking)$"];'
                 f'way(area.c{i})["highway"~"^({ROUTES})$"];); out ids;')
    data = urllib.parse.urlencode({"data": "\n".join(q)}).encode()
    req = urllib.request.Request(OVERPASS, data=data, headers={"User-Agent": AGENT})
    for essai in range(3):
        try:
            with urllib.request.urlopen(req, timeout=180) as r:
                brut = json.loads(r.read().decode("utf-8"))
            cache.write_text(json.dumps(brut), encoding="utf-8")
            return brut
        except Exception as e:  # serveur Overpass chargé : on réessaie
            print(f"Overpass : {e}, nouvel essai dans 20 s", file=sys.stderr)
            time.sleep(20)
    raise SystemExit("Overpass injoignable")


def lire(brut):
    """Sépare les objets complets et la commune de chaque objet."""
    objets, commune_de = {}, {}
    commune = None
    for e in brut["elements"]:
        if e["type"] == "commune":
            commune = e["tags"]["nom"]
            continue
        cle = f'{e["type"]}/{e["id"]}'
        if commune is None:
            objets[cle] = e
        else:
            commune_de.setdefault(cle, commune)
    return objets, commune_de


def contour(e):
    """Contour en mètres d'un chemin fermé, ou None."""
    g = e.get("geometry")
    if e["type"] != "way" or not g or len(g) < 4:
        return None
    pts = [vers_xy(p["lat"], p["lon"]) for p in g]
    if pts[0] == pts[-1]:
        pts = pts[:-1]
    return pts if len(pts) >= 3 else None


def position(e):
    if e["type"] == "node":
        return vers_xy(e["lat"], e["lon"])
    c = contour(e)
    if c:
        return aire_centre(c)[1]
    b = e.get("bounds")
    if b:
        return vers_xy((b["minlat"] + b["maxlat"]) / 2, (b["minlon"] + b["maxlon"]) / 2)
    return None


def entier(v, defaut=None):
    try:
        return int(str(v).split(";")[0])
    except (TypeError, ValueError):
        return defaut


class Collecte:
    def __init__(self, routes, commune_de):
        self.places = []
        self.grille = Grille()
        self.routes = routes          # [(nom, [(x, y)...], clé osm)]
        self.commune_de = commune_de
        self.ecartees = Counter()

    def rue_proche(self, p, max_m=60):
        meilleur = (max_m, None, None)
        for nom, pts, cle in self.routes:
            for a, b in zip(pts, pts[1:]):
                d, _ = dist_segment(p, a, b)
                if d < meilleur[0]:
                    meilleur = (d, nom, cle)
        return meilleur[1], meilleur[2]

    def ajouter(self, p, angle, dim, source, tags_parent=None, type_="voit",
                pmr=False, elec=False, parking=None, tarif=TARIF_RUE, cle_commune=None):
        lat, lon = vers_latlon(*p)
        if not (ZONE[0] <= lat <= ZONE[2] and ZONE[1] <= lon <= ZONE[3]):
            self.ecartees["hors_zone"] += 1  # rue qui continue au-delà du campus
            return False
        if self.grille.plus_proche(p) < 2.0:  # déjà une place à moins de 2 m
            self.ecartees["doublon"] += 1
            return False
        nom_rue, cle_rue = self.rue_proche(p)
        ville = self.commune_de.get(cle_commune) or self.commune_de.get(cle_rue)
        self.places.append({
            "lat": round(lat, 7), "long": round(lon, 7),
            "angle": round(math.degrees(angle) % 180, 1),
            "longueur": dim[0], "largeur": dim[1],
            "type": type_, "pmr": pmr, "elec": elec,
            "adresse": nom_rue, "ville": ville, "parking": parking,
            "tarif": tarif, "source": source,
        })
        self.grille.ajouter(p)
        return True


def orientation_bande(tags, largeur):
    o = tags.get("orientation") or tags.get("parking:orientation")
    if o in DIM:
        return o
    return "perpendicular" if largeur >= 4.2 else "parallel"


def decouper_bande(col, e, poly, tags, cle, source):
    """Bande de stationnement le long d'une rue (même courbe) découpée en places."""
    centre, L, W, a = rectangle_min(poly)
    o = orientation_bande(tags, W)
    lp, wp, pas = DIM[o]
    n = entier(tags.get("capacity")) or max(1, int(L // pas))
    u = (math.cos(a), math.sin(a))
    v = (-u[1], u[0])
    nb_pmr = entier(tags.get("capacity:disabled"), 0)
    nb_elec = entier(tags.get("capacity:charging"), 0)
    angle_place = a if o == "parallel" else a + math.pi / 2
    poses = 0
    for i in range(n):
        t = -L / 2 + L * (i + 0.5) / n
        o_pt = (centre[0] + t * u[0], centre[1] + t * u[1])
        # Milieu de la bande sur la perpendiculaire : suit les bandes courbes
        s = coupes(poly, o_pt, v)
        if len(s) >= 2:
            m = (s[0] + s[-1]) / 2
            o_pt = (o_pt[0] + m * v[0], o_pt[1] + m * v[1])
        if col.ajouter(o_pt, angle_place, (lp, wp), source, pmr=i < nb_pmr,
                       elec=nb_pmr <= i < nb_pmr + nb_elec, cle_commune=cle):
            poses += 1
    return poses


def capacite_estimee(poly, tags, bande, aire):
    """Nombre de places que peut contenir un parking ou une bande (capacité OSM si elle est donnée)."""
    if entier(tags.get("capacity")):
        return entier(tags["capacity"])
    if bande:  # même calcul que decouper_bande
        _, L, W, _ = rectangle_min(poly)
        return max(1, int(L // DIM[orientation_bande(tags, W)][2]))
    return aire / M2_PAR_PLACE


def grille_parking(col, poly, capacite, nom, cle):
    """Parking en surface dont on connaît la capacité : rangées de places en bataille."""
    centre, L, W, a = rectangle_min(poly)
    u = (math.cos(a), math.sin(a))
    v = (-u[1], u[0])
    candidats = []
    # Module de 16 m en travers : place 5 m + allée 6 m + place 5 m
    for j in range(int(W // 16) + 1):
        for dv in (2.5 + 16 * j, 13.5 + 16 * j):
            if dv + 2.5 > W:
                continue
            for k in range(int(L // 2.5)):
                du = 1.25 + 2.5 * k
                p = (centre[0] + (du - L / 2) * u[0] + (dv - W / 2) * v[0],
                     centre[1] + (du - L / 2) * u[1] + (dv - W / 2) * v[1])
                if all(dedans(q, poly) for q in coins(p, 5.0, 2.5, a + math.pi / 2)):
                    candidats.append(p)
    if not candidats:
        return 0
    if len(candidats) > capacite:  # on en garde `capacite`, réparties
        candidats = [candidats[int(i * len(candidats) / capacite)] for i in range(capacite)]
    return sum(col.ajouter(p, a + math.pi / 2, (5.0, 2.5), "osm:grille_capacite",
                           parking=nom, tarif=TARIF_PARKING, cle_commune=cle) for p in candidats)


def decouper_rue(col, route, tags, cle):
    """Rue marquée « stationnement autorisé » : une place tous les `pas` mètres, côté par côté."""
    pts = route
    largeur = None
    try:
        largeur = float(tags.get("width", "").replace(",", "."))
    except ValueError:
        pass
    if not largeur:
        largeur = 3.0 * (entier(tags.get("lanes"), 2))
    poses = 0
    for cote, signe in (("left", 1), ("right", -1)):
        val = tags.get(f"parking:{cote}") or tags.get("parking:both") \
            or tags.get(f"parking:lane:{cote}") or tags.get("parking:lane:both")
        if val not in OUI_STATIONNEMENT:
            continue
        o = tags.get(f"parking:{cote}:orientation") or tags.get("parking:both:orientation") or \
            (val if val in DIM else "parallel")
        lp, wp, pas = DIM.get(o, DIM["parallel"])
        decalage = largeur / 2 + (wp / 2 if o == "parallel" else lp / 2)
        # Longueur cumulée ; on laisse 12 m libres aux deux bouts (carrefours)
        segs = list(zip(pts, pts[1:]))
        total = sum(math.dist(a, b) for a, b in segs)
        d = 12.0
        while d < total - 12.0:
            reste = d
            for a, b in segs:
                l = math.dist(a, b)
                if reste <= l:
                    ux, uy = (b[0] - a[0]) / l, (b[1] - a[1]) / l
                    # côté gauche = normale (-uy, ux) ; côté droit = l'opposé
                    p = (a[0] + ux * reste + signe * -uy * decalage,
                         a[1] + uy * reste + signe * ux * decalage)
                    ang = math.atan2(uy, ux) + (0 if o == "parallel" else math.pi / 2)
                    if col.ajouter(p, ang, (lp, wp), "osm:rue_decoupee", cle_commune=cle):
                        poses += 1
                    break
                reste -= l
            d += pas
    return poses


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--rafraichir", action="store_true", help="refaire la requête Overpass")
    ap.add_argument("--avec-prives", action="store_true", help="garder les parkings privés")
    args = ap.parse_args()

    objets, commune_de = lire(requete_overpass(args.rafraichir))
    routes = [(e["tags"].get("name"), [vers_xy(p["lat"], p["lon"]) for p in e["geometry"]], k)
              for k, e in objets.items()
              if e["type"] == "way" and "highway" in e.get("tags", {}) and e.get("geometry")]
    routes_nommees = [r for r in routes if r[0]]
    col = Collecte(routes_nommees, commune_de)

    def prive(tags):
        return not args.avec_prives and tags.get("access") in PRIVES

    parkings = {k: (e, contour(e)) for k, e in objets.items()
                if e.get("tags", {}).get("amenity") == "parking"}
    bornes = [position(e) for e in objets.values()
              if e.get("tags", {}).get("amenity") == "charging_station"]
    stats = Counter()

    # 1. Places dessinées une par une
    places_dessinees = []
    for k, e in objets.items():
        t = e.get("tags", {})
        if t.get("amenity") != "parking_space":
            continue
        p = position(e)
        if p is None:
            continue
        parent = next(((pk, pe) for pk, (pe, pc) in parkings.items() if pc and dedans(p, pc)), None)
        tags_parent = parent[1]["tags"] if parent else {}
        if prive(t) or (prive(tags_parent) and "access" not in t):
            col.ecartees["privee"] += 1
            continue
        places_dessinees.append(p)
        c = contour(e)
        if c:
            _, L, W, a = rectangle_min(c)
            dim = (round(max(L, 4.0), 1), round(max(W, 1.8), 1))
        else:
            a, dim = 0.0, DIM["perpendicular"][:2]
            nom, cle_rue = col.rue_proche(p)
            # orientation d'un point : perpendiculaire à la rue la plus proche
            for n_, pts, k2 in routes_nommees:
                if k2 == cle_rue:
                    seg = min(zip(pts, pts[1:]), key=lambda s: dist_segment(p, *s)[0])
                    a = math.atan2(seg[1][1] - seg[0][1], seg[1][0] - seg[0][0]) + math.pi / 2
        ps = t.get("parking_space")
        moto = ps == "motorcycle" or t.get("motorcycle") == "designated"
        elec = ps == "charging" or any(b and math.dist(b, p) < 4 for b in bornes)
        pmr = ps == "disabled" or t.get("wheelchair") == "designated" or t.get("disabled") == "designated"
        if col.ajouter(p, a, MOTO[:2] if moto else dim, f"osm:{k}", type_="moto" if moto else "voit",
                       pmr=pmr, elec=elec, parking=tags_parent.get("name"),
                       tarif=TARIF_PARKING if parent else TARIF_RUE, cle_commune=k):
            stats["1_places_dessinees"] += 1

    def places_dans(poly):
        return sum(dedans(p, poly) for p in places_dessinees)

    a_completer, prives_sans_places, lots_publics = [], 0, []
    # 2. Bandes le long des rues, puis 4. parkings en surface avec capacité
    for k, (e, poly) in sorted(parkings.items()):
        t = e["tags"]
        if poly is None:
            continue
        dessinees = places_dans(poly)
        if prive(t):
            if not dessinees:
                col.ecartees["parking_prive"] += 1
                prives_sans_places += 1
            continue
        genre = t.get("parking", "surface")
        if genre in ("underground", "multi-storey", "rooftop"):
            col.ecartees["parking_ferme_ou_souterrain"] += 1
            continue
        bande = genre in ("street_side", "lane", "layby")
        aire, c = aire_centre(poly)
        contour_ll = [[round(v, 7) for v in vers_latlon(x, y)] for x, y in poly]
        if not bande:  # un vrai parking : fusion.py y regroupe les places qu'il contient
            lots_publics.append({"osm": k, "nom": t.get("name"), "access": t.get("access"),
                                 "fee": t.get("fee"), "aire_m2": round(aire), "contour": contour_ll})
        # Déjà dessiné place par place ? Il en faut au moins la moitié de ce qu'il peut contenir :
        # souvent OSM n'a dessiné que les places handicapés, et le reste du parking manquerait.
        if dessinees and dessinees >= capacite_estimee(poly, t, bande, aire) / 2:
            continue
        if bande:
            stats["2_bandes_de_rue"] += decouper_bande(col, e, poly, t, k, f"osm:{k}:bande")
        elif entier(t.get("capacity")):
            stats["4_grilles_capacite"] += grille_parking(col, poly, entier(t["capacity"]), t.get("name"), k)
        elif aire >= 150:  # moins de 150 m² : pas un vrai parking
            lat, lon = vers_latlon(*c)
            a_completer.append({"osm": k, "nom": t.get("name"), "aire_m2": round(aire),
                                "places_osm": dessinees, "centre": [round(lat, 6), round(lon, 6)],
                                "contour": contour_ll})

    # 3. Rues marquées « stationnement autorisé »
    for k, e in objets.items():
        t = e.get("tags", {})
        if "highway" in t and e.get("geometry") and any(x.startswith("parking:") for x in t):
            pts = [vers_xy(p["lat"], p["lon"]) for p in e["geometry"]]
            stats["3_rues_decoupees"] += decouper_rue(col, pts, t, k)

    # 5. Parkings motos
    for k, e in objets.items():
        t = e.get("tags", {})
        if t.get("amenity") != "motorcycle_parking" or prive(t):
            continue
        p = position(e)
        n = entier(t.get("capacity"), 4)
        for i in range(n):
            q = (p[0] + (i - (n - 1) / 2) * MOTO[2], p[1])
            if col.ajouter(q, math.pi / 2, MOTO[:2], f"osm:{k}", type_="moto", cle_commune=k):
                stats["5_motos"] += 1

    resultat = {
        "zone": {"sud": ZONE[0], "ouest": ZONE[1], "nord": ZONE[2], "est": ZONE[3]},
        "genere_le": datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S"),
        "licence": "Données © les contributeurs d'OpenStreetMap (ODbL)",
        "angle": "degrés, direction du grand côté de la place, depuis l'est dans le sens trigonométrique",
        "stats": {**stats, "ecartees": dict(col.ecartees), "parkings_prives_ignores": prives_sans_places},
        "places": col.places,
        "a_completer": a_completer,
        "parkings": lots_publics,
    }
    SORTIE.write_text(json.dumps(resultat, ensure_ascii=False, indent=1), encoding="utf-8")
    print(f"{len(col.places)} places -> {SORTIE.name}")
    for k, v in sorted(resultat["stats"].items()):
        print(f"  {k} : {v}")
    print(f"  parkings publics à compléter par YOLO : {len(a_completer)}")
    villes = Counter(p["ville"] for p in col.places)
    print("  par commune :", dict(villes))


if __name__ == "__main__":
    main()
