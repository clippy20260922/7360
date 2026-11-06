#!/usr/bin/env python3
"""Aperçu des places sur la photo aérienne IGN : génère apercu.html (Leaflet).

Chaque place est dessinée en vrai rectangle (longueur x largeur, orientée),
coloriée selon sa source. Les parkings à compléter sont entourés en orange.
Usage : python3 apercu.py [fichier.json ...]   (par défaut : places_osm.json, places_yolo.json)
"""
import html
import json
import math
import sys
from pathlib import Path

from geo import coins, vers_latlon, vers_xy

ICI = Path(__file__).resolve().parent

COULEURS = {
    "dessinee": "#00e5ff",   # place dessinée dans OSM
    "bande": "#ffd600",      # bande de stationnement découpée
    "rue": "#ff4081",        # rue découpée tous les 5,5 m
    "grille": "#b388ff",     # grille d'un parking de capacité connue
    "yolo": "#76ff03",       # voiture détectée par YOLO
    "rangee": "#ff9100",     # place déduite d'une rangée de voitures
}


def famille(source):
    if source.startswith("yolo_rangee"):
        return "rangee"
    if source.startswith("yolo"):
        return "yolo"
    if source.endswith(":bande"):
        return "bande"
    if "rue_decoupee" in source:
        return "rue"
    if "grille" in source:
        return "grille"
    return "dessinee"


def main():
    fichiers = [Path(f) for f in sys.argv[1:]] or [p for p in (ICI / "places_osm.json", ICI / "places_yolo.json") if p.exists()]
    rects, zones = [], []
    for f in fichiers:
        d = json.loads(f.read_text(encoding="utf-8"))
        for p in d.get("places", []):
            x, y = vers_xy(p["lat"], p["long"])
            cs = [vers_latlon(*c) for c in coins((x, y), p["longueur"], p["largeur"], math.radians(p["angle"]))]
            rects.append({"c": [[round(a, 7), round(b, 7)] for a, b in cs], "f": famille(p["source"]),
                          "t": f'{p["source"]} | {p.get("adresse") or ""} | {p["type"]}'
                               f'{" PMR" if p["pmr"] else ""}{" élec" if p["elec"] else ""}'})
        for z in d.get("a_completer", []):
            zones.append({"c": z["contour"], "t": f'{z["osm"]} {z.get("nom") or ""} ({z["aire_m2"]} m²)'})
    donnees = json.dumps({"rects": rects, "zones": zones, "couleurs": COULEURS}, ensure_ascii=False)
    legende = "".join(f'<span><i style="background:{c}"></i>{html.escape(k)}</span>' for k, c in COULEURS.items())
    page = f"""<!doctype html>
<html lang="fr"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Places réelles — Cité Descartes</title>
<link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css">
<script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"></script>
<style>
 html,body,#carte{{height:100%;margin:0}}
 #legende{{position:absolute;z-index:1000;top:8px;right:8px;background:#fffd;padding:6px 10px;font:13px sans-serif;border-radius:6px}}
 #legende span{{display:block}} #legende i{{display:inline-block;width:12px;height:12px;margin-right:6px;vertical-align:-1px}}
</style></head><body>
<div id="carte"></div><div id="legende"><b>{len(rects)} places</b>{legende}<span><i style="background:none;border:2px solid orange"></i>à compléter (YOLO)</span></div>
<script>
const D = {donnees};
const carte = L.map('carte', {{maxZoom: 22}});
L.tileLayer('https://data.geopf.fr/wmts?SERVICE=WMTS&REQUEST=GetTile&VERSION=1.0.0&LAYER=ORTHOIMAGERY.ORTHOPHOTOS&STYLE=normal&TILEMATRIXSET=PM&TILEMATRIX={{z}}&TILEROW={{y}}&TILECOL={{x}}&FORMAT=image/jpeg',
  {{maxNativeZoom: 19, maxZoom: 22, attribution: 'Photo © IGN — places © contributeurs OpenStreetMap'}}).addTo(carte);
const groupe = L.featureGroup().addTo(carte);
for (const z of D.zones) L.polygon(z.c, {{color: 'orange', weight: 2, fill: false}}).bindTooltip(z.t).addTo(groupe);
for (const r of D.rects) L.polygon(r.c, {{color: D.couleurs[r.f], weight: 1, fillOpacity: 0.45}}).bindTooltip(r.t).addTo(groupe);
const vue = new URLSearchParams(location.hash.slice(1));
if (vue.get('lat')) carte.setView([+vue.get('lat'), +vue.get('lon')], +vue.get('z') || 19);
else carte.fitBounds(groupe.getBounds());
</script></body></html>"""
    (ICI / "apercu.html").write_text(page, encoding="utf-8")
    print(f"apercu.html : {len(rects)} places, {len(zones)} parkings à compléter")


if __name__ == "__main__":
    main()
