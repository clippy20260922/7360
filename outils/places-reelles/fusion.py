#!/usr/bin/env python3
"""Étape 3 : fusionne places_osm.json et places_yolo.json en un seul fichier pour le serveur.

Sortie : server7360/places_cite_descartes.json, une place par ligne de slot_table
(identifiants à partir de 1001 pour ne pas toucher aux places de démo 1 à 9).
Usage : python3 fusion.py
"""
import json
import math
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path

ICI = Path(__file__).resolve().parent
SORTIE = ICI.parent.parent / "server7360" / "places_cite_descartes.json"
PREMIER_ID = 1001


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


def main():
    places = []
    for nom in ("places_osm.json", "places_yolo.json"):
        f = ICI / nom
        if f.exists():
            places += json.loads(f.read_text(encoding="utf-8"))["places"]
    # Ordre stable : du nord au sud puis d'ouest en est, pour des identifiants lisibles
    places.sort(key=lambda p: (-round(p["lat"], 4), p["long"]))
    lignes = []
    for i, p in enumerate(places):
        lignes.append({
            "slot_id": PREMIER_ID + i,
            "slot_adresse": p.get("adresse") or p.get("parking"),
            "slot_ville": p.get("ville"),
            "slot_lat": p["lat"],
            "slot_long": p["long"],
            "slot_type": p["type"],
            "slot_pmr": p["pmr"],
            "slot_elec": p["elec"],
            "parking": p.get("parking"),
            "slot_tarif": p["tarif"],
            "slot_angle": round(math.radians(p["angle"]), 4),  # radians, comme le plan de l'équipe
            "source": p["source"],
        })
    sources = Counter(famille(p["source"]) for p in places)
    resultat = {
        "description": "Places de stationnement réelles de la Cité Descartes (Champs-sur-Marne / Noisy-le-Grand)",
        "genere_le": datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S"),
        "methode": "outils/places-reelles (OpenStreetMap puis détection YOLO sur photo IGN)",
        "licence": "Données © les contributeurs d'OpenStreetMap (ODbL) ; photos © IGN (Licence Ouverte 2.0)",
        "nombre": len(lignes),
        "par_source": dict(sources),
        "par_commune": dict(Counter(p.get("ville") for p in places)),
        "places": lignes,
    }
    # Une place par ligne : lisible et diff git propre
    corps = ",\n".join("  " + json.dumps(l, ensure_ascii=False) for l in lignes)
    entete = {k: v for k, v in resultat.items() if k != "places"}
    texte = json.dumps(entete, ensure_ascii=False, indent=1)[:-2] + ',\n "places": [\n' + corps + "\n ]\n}\n"
    json.loads(texte)  # vérifie que le fichier est un JSON valide
    SORTIE.write_text(texte, encoding="utf-8")
    print(f"{len(lignes)} places -> {SORTIE.relative_to(ICI.parent.parent)}")
    for k, v in sources.most_common():
        print(f"  {v:>4}  {k}")
    print("  par commune :", resultat["par_commune"])


if __name__ == "__main__":
    main()
