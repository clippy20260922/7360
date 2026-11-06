#!/usr/bin/env python3
"""Étape 3 : fusionne places_osm.json et places_yolo.json en un seul fichier pour le serveur.

Chaque place est rangée dans un groupe (colonne `parking` de slot_table) :
  - dans un parking OSM (contour amenity=parking) -> ce parking ;
  - sinon dans sa rue (bandes le long des rues, rues découpées, places isolées) ;
  - sans rue connue -> pas de groupe.
Les groupes vont dans `parkings` (lignes de parking_table, genre « parking » ou « rue »).

Sortie : server7360/places_cite_descartes.json, une place par ligne. Les identifiants
partent de 1001 (les places de démo de l'équipe sont 1 à 9) et une place déjà présente dans
l'ancien fichier garde son identifiant : les paiements en cours restent sur la bonne place.
Usage : python3 fusion.py
"""
import json
import math
from collections import Counter, defaultdict
from datetime import datetime, timezone
from pathlib import Path

from geo import aire_centre, dedans, vers_latlon, vers_xy

ICI = Path(__file__).resolve().parent
SORTIE = ICI.parent.parent / "server7360" / "places_cite_descartes.json"
PREMIER_ID = 1001
MEME_PLACE_M = 0.5  # une place qui n'a pas bougé de plus de 50 cm garde son identifiant


def famille(source):
    if source.startswith("yolo_rangee"):
        return "photo IGN : rangée reconstituée"
    if source.startswith("yolo"):
        return "photo IGN : voiture détectée (YOLO)"
    if source.endswith(":bande"):
        return "OSM : bande de stationnement découpée"
    if "rue_decoupee" in source:
        return "OSM : rue découpée"
    if "grille" in source:
        return "OSM : grille d'un parking"
    return "OSM : place dessinée"


def lire(nom):
    f = ICI / nom
    return json.loads(f.read_text(encoding="utf-8")) if f.exists() else {"places": []}


def ville_principale(places):
    return Counter(p.get("ville") for p in places).most_common(1)[0][0]


def rue_principale(places):
    rues = Counter(p["adresse"] for p in places if p.get("adresse"))
    return rues.most_common(1)[0][0] if rues else None


def grouper(places, lots):
    """{clé du parking OSM ou None: [places]}, chaque place dans le plus petit parking qui la contient."""
    def lot_de(p):
        src = p["source"]
        if src.endswith(":bande") or "rue_decoupee" in src:
            return None  # stationnement le long de la rue
        cle = src.split(":", 1)[1] if src.startswith("yolo") else None
        if cle in lots:
            return cle  # YOLO sait dans quel parking il a vu la voiture
        q = vers_xy(p["lat"], p["long"])
        autour = [(z["aire"], k) for k, z in lots.items() if dedans(q, z["poly"])]
        return min(autour)[1] if autour else None

    groupes = defaultdict(list)
    for p in places:
        groupes[lot_de(p)].append(p)
    return groupes


def departager(noms, centres):
    """Deux parkings du même nom : on ajoute (nord)/(sud) ou (est)/(ouest) ; au-delà, un numéro."""
    par_nom = defaultdict(list)
    for k, n in noms.items():
        par_nom[n].append(k)
    for n, ks in par_nom.items():
        if len(ks) == 2:
            (xa, ya), (xb, yb) = centres[ks[0]], centres[ks[1]]
            if abs(ya - yb) >= abs(xa - xb):
                hauts = ("nord", "sud") if ya > yb else ("sud", "nord")
            else:
                hauts = ("est", "ouest") if xa > xb else ("ouest", "est")
            for k, h in zip(ks, hauts):
                noms[k] = f"{n} ({h})"
        elif len(ks) > 2:
            for i, k in enumerate(ks, 1):
                noms[k] = f"{n} {i}"
    return noms


def construire_groupes(places, lots):
    groupes = grouper(places, lots)
    sans_lot = groupes.pop(None, [])
    nom_de, fiches = {}, []

    # Parkings : nom OSM, sinon la rue la plus proche ; position = centre du contour
    noms, centres = {}, {}
    for k, ps in groupes.items():
        z = lots[k]
        rue = rue_principale(ps)
        noms[k] = z.get("nom") or (f"Parking {rue}" if rue else "Parking")
        centres[k] = z["centre"]
    noms = departager(noms, centres)
    for k, ps in sorted(groupes.items(), key=lambda kv: -len(kv[1])):
        z, rue = lots[k], rue_principale(ps)
        lat, lon = vers_latlon(*z["centre"])
        fiches.append({
            "parking_name": noms[k],
            "parking_adresse": ", ".join(x for x in (rue or "Cité Descartes", ville_principale(ps)) if x),
            "parking_lat": round(lat, 7), "parking_long": round(lon, 7),
            "parking_genre": "parking", "places": len(ps), "source": f"osm:{k}",
            "parking_contour": [[round(a, 6), round(b, 6)] for a, b in z["contour"]],
        })
        for p in ps:
            nom_de[id(p)] = noms[k]

    # Rues : toutes les places hors parking d'une même rue (et d'une même commune)
    rues = defaultdict(list)
    for p in sans_lot:
        if p.get("adresse"):
            rues[(p["adresse"], p.get("ville"))].append(p)
    communes_par_rue = Counter(rue for rue, _ in rues)
    for (rue, ville), ps in sorted(rues.items(), key=lambda kv: -len(kv[1])):
        nom = f"{rue} ({ville})" if communes_par_rue[rue] > 1 else rue
        # repère sur la place la plus proche du milieu du groupe : il reste sur la rue
        mx = sum(p["lat"] for p in ps) / len(ps)
        my = sum(p["long"] for p in ps) / len(ps)
        repere = min(ps, key=lambda p: math.hypot(p["lat"] - mx, (p["long"] - my) * 0.66))
        fiches.append({
            "parking_name": nom,
            "parking_adresse": ", ".join(x for x in (rue, ville) if x),
            "parking_lat": repere["lat"], "parking_long": repere["long"],
            "parking_genre": "rue", "places": len(ps), "source": "rue",
            "parking_contour": None,
        })
        for p in ps:
            nom_de[id(p)] = nom
    return fiches, nom_de


def identifiants(places, anciens):
    """Garde l'identifiant de l'ancien fichier pour une place restée au même endroit."""
    grille = defaultdict(list)
    for a in anciens:
        x, y = vers_xy(a["slot_lat"], a["slot_long"])
        grille[(round(x), round(y))].append((x, y, a))
    pris, ids, nouvelles = set(), {}, []
    for p in places:
        x, y = vers_xy(p["lat"], p["long"])
        proches = [(math.hypot(x - ax, y - ay), a["slot_id"])
                   for dx in (-1, 0, 1) for dy in (-1, 0, 1)
                   for ax, ay, a in grille[(round(x) + dx, round(y) + dy)]
                   if a["slot_id"] not in pris and a["slot_type"] == p["type"]]
        d, i = min(proches, default=(None, None))
        if d is not None and d <= MEME_PLACE_M:
            pris.add(i)
            ids[id(p)] = i
        else:
            nouvelles.append(p)
    suivant = max([a["slot_id"] for a in anciens] + [PREMIER_ID - 1]) + 1
    for i, p in enumerate(nouvelles):
        ids[id(p)] = suivant + i
    return ids, len(anciens) - len(pris)


def main():
    osm, yolo = lire("places_osm.json"), lire("places_yolo.json")
    places = osm["places"] + yolo["places"]
    # Ordre stable : du nord au sud puis d'ouest en est, pour des identifiants lisibles
    places.sort(key=lambda p: (-round(p["lat"], 4), p["long"]))

    lots = {}
    for z in osm.get("parkings", []):
        poly = [vers_xy(a, b) for a, b in z["contour"]]
        aire, centre = aire_centre(poly)
        lots[z["osm"]] = {**z, "poly": poly, "aire": aire, "centre": centre}
    fiches, nom_de = construire_groupes(places, lots)

    anciens = json.loads(SORTIE.read_text(encoding="utf-8"))["places"] if SORTIE.exists() else []
    ids, disparues = identifiants(places, anciens)

    lignes = sorted(({
        "slot_id": ids[id(p)],
        "slot_adresse": p.get("adresse") or nom_de.get(id(p)) or p.get("parking"),
        "slot_ville": p.get("ville"),
        "slot_lat": p["lat"],
        "slot_long": p["long"],
        "slot_type": p["type"],
        "slot_pmr": p["pmr"],
        "slot_elec": p["elec"],
        "parking": nom_de.get(id(p)),
        "slot_tarif": p["tarif"],
        "slot_angle": round(math.radians(p["angle"]), 4),  # radians, comme le plan de l'équipe
        "source": p["source"],
    } for p in places), key=lambda l: l["slot_id"])

    sources = Counter(famille(p["source"]) for p in places)
    en_parking = sum(f["places"] for f in fiches if f["parking_genre"] == "parking")
    en_rue = sum(f["places"] for f in fiches if f["parking_genre"] == "rue")
    resultat = {
        "description": "Places de stationnement réelles de la Cité Descartes (Champs-sur-Marne / Noisy-le-Grand)",
        "genere_le": datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S"),
        "methode": "outils/places-reelles (OpenStreetMap puis détection YOLO sur photo IGN)",
        "licence": "Données © les contributeurs d'OpenStreetMap (ODbL) ; photos © IGN (Licence Ouverte 2.0)",
        "nombre": len(lignes),
        "par_source": dict(sources),
        "par_commune": dict(Counter(p.get("ville") for p in places)),
        "par_groupe": {
            "parkings": sum(f["parking_genre"] == "parking" for f in fiches), "places_en_parking": en_parking,
            "rues": sum(f["parking_genre"] == "rue" for f in fiches), "places_en_rue": en_rue,
            "places_seules": len(lignes) - en_parking - en_rue,
        },
        "parkings": fiches,
        "places": lignes,
    }
    # Un parking puis une place par ligne : lisible et diff git propre
    entete = {k: v for k, v in resultat.items() if k not in ("parkings", "places")}
    def bloc(nom, elements):
        return f' "{nom}": [\n' + ",\n".join("  " + json.dumps(e, ensure_ascii=False) for e in elements) + "\n ]"
    texte = json.dumps(entete, ensure_ascii=False, indent=1)[:-2] + ",\n" + bloc("parkings", fiches) \
        + ",\n" + bloc("places", lignes) + "\n}\n"
    json.loads(texte)  # vérifie que le fichier est un JSON valide
    SORTIE.write_text(texte, encoding="utf-8")
    print(f"{len(lignes)} places -> {SORTIE.relative_to(ICI.parent.parent)}"
          f" ({len(lignes) - len(anciens) + disparues} nouvelles, {disparues} disparues)")
    for k, v in sources.most_common():
        print(f"  {v:>4}  {k}")
    print("  par commune :", resultat["par_commune"])
    print("  par groupe :", resultat["par_groupe"])


if __name__ == "__main__":
    main()
