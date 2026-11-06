#!/usr/bin/env python3
"""Étape 2 : compléter les parkings sans places dans OSM, à partir de la photo aérienne (YOLO).

Pour chaque parking de `places_osm.json` -> `a_completer` (parking public en surface,
sans place dessinée ni capacité) :
  1. on assemble la photo aérienne IGN (BD ORTHO, 20 cm/pixel) autour du parking ;
  2. plusieurs modèles YOLO OBB entraînés sur des vues aériennes (DOTA) cherchent les
     voitures, sur des carreaux de 1024 px (la taille de leur entraînement), photo agrandie ;
     on garde la meilleure détection de chaque voiture ;
  3. chaque voiture garée dans le contour du parking donne une place ;
  4. reconstitution des rangées : les voitures alignées donnent l'axe et le pas de la
     rangée ; on comble les trous et on prolonge la rangée tant que la photo montre une
     voiture ou un marquage au sol (on s'arrête sur une allée, de l'herbe, le bord du parking).

Les modèles DOTA ratent une partie des voitures (sombres, serrées) : l'étape 4 rattrape
l'essentiel, mais le compte reste une estimation. Contrôle visuel : cache/yolo/*.jpg.

À lancer avec le Python qui a ultralytics (environnement à part, pas celui du serveur) :
  ~/.venvs/yolo7360/bin/python places_yolo.py [--conf 0.2] [--sans-rangees] [--avec-prives]
Photos © IGN (Licence Ouverte Etalab 2.0). Modèles Ultralytics YOLO (AGPL-3.0).
"""
import argparse
import io
import json
import math
import statistics
import time
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

from geo import aire_centre, coins, dedans, vers_latlon, vers_xy
from places_osm import (AGENT, PRIVES, TARIF_PARKING, Collecte, contour, lire,
                        requete_overpass)

ICI = Path(__file__).resolve().parent
CACHE = ICI / "cache"
TUILES = CACHE / "ign"
CONTROLES = CACHE / "yolo"
SORTIE = ICI / "places_yolo.json"
ZOOM = 19  # niveau natif de la BD ORTHO (≈ 20 cm/pixel à cette latitude)
URL_IGN = ("https://data.geopf.fr/wmts?SERVICE=WMTS&REQUEST=GetTile&VERSION=1.0.0"
           "&LAYER=ORTHOIMAGERY.ORTHOPHOTOS&STYLE=normal&TILEMATRIXSET=PM"
           "&TILEMATRIX={z}&TILEROW={y}&TILECOL={x}&FORMAT=image/jpeg")
# (modèle, agrandissement) : chacun rate des voitures différentes, on les combine
ENSEMBLE = [("yolo11l-obb.pt", 2.5), ("yolo26m-obb.pt", 2.5), ("yolo11m-obb.pt", 2.5), ("yolo11l-obb.pt", 2.0)]
CARREAU, RECOUVREMENT = 1024, 256
VOITURE = "small vehicle"  # classe DOTA
PLACE = (5.0, 2.5)          # place en bataille : longueur, largeur (m)


# ---------- Photo IGN ----------

def tuile_xy(lat, lon, z=ZOOM):
    n = 2 ** z
    return ((lon + 180) / 360 * n,
            (1 - math.asinh(math.tan(math.radians(lat))) / math.pi) / 2 * n)


def pixel_latlon(px, py, z=ZOOM):
    n = 256 * 2 ** z
    return (math.degrees(math.atan(math.sinh(math.pi * (1 - 2 * py / n)))), px / n * 360 - 180)


def tuile(x, y, z=ZOOM):
    f = TUILES / str(z) / str(x) / f"{y}.jpg"
    if not f.exists():
        f.parent.mkdir(parents=True, exist_ok=True)
        req = urllib.request.Request(URL_IGN.format(x=x, y=y, z=z), headers={"User-Agent": AGENT})
        for essai in range(3):
            try:
                with urllib.request.urlopen(req, timeout=30) as r:
                    f.write_bytes(r.read())
                break
            except Exception:
                time.sleep(2 + 3 * essai)
        else:
            raise RuntimeError(f"tuile IGN {z}/{x}/{y} introuvable")
        time.sleep(0.05)  # on reste poli avec le service
    return Image.open(io.BytesIO(f.read_bytes())).convert("RGB")


def mosaique(contour_ll, marge_m=20):
    """Photo IGN couvrant le contour (+ marge) ; renvoie l'image et le coin haut-gauche en pixels globaux."""
    lats = [p[0] for p in contour_ll]
    lons = [p[1] for p in contour_ll]
    dlat = marge_m / 110_574
    dlon = marge_m / (111_320 * math.cos(math.radians(sum(lats) / len(lats))))
    x0, y0 = tuile_xy(max(lats) + dlat, min(lons) - dlon)
    x1, y1 = tuile_xy(min(lats) - dlat, max(lons) + dlon)
    tx0, ty0, tx1, ty1 = int(x0), int(y0), int(x1), int(y1)
    img = Image.new("RGB", ((tx1 - tx0 + 1) * 256, (ty1 - ty0 + 1) * 256))
    for tx in range(tx0, tx1 + 1):
        for ty in range(ty0, ty1 + 1):
            img.paste(tuile(tx, ty), ((tx - tx0) * 256, (ty - ty0) * 256))
    return img, (tx0 * 256, ty0 * 256)


# ---------- Détection des voitures ----------

def positions_carreaux(taille):
    if taille <= CARREAU:
        return [0]
    pos = list(range(0, taille - CARREAU + 1, CARREAU - RECOUVREMENT))
    if pos[-1] + CARREAU < taille:
        pos.append(taille - CARREAU)
    return pos


def detecter(modeles, img, conf):
    """Voitures vues sur la photo : [(u, v, angle_image, conf)] en pixels de la photo d'origine."""
    dets = []
    for modele, e in modeles:
        g = img.resize((round(img.width * e), round(img.height * e)), Image.LANCZOS)
        for x in positions_carreaux(g.width):
            for y in positions_carreaux(g.height):
                r = modele.predict(g.crop((x, y, x + CARREAU, y + CARREAU)), imgsz=CARREAU,
                                   conf=conf, verbose=False)[0]
                for pts, k, cf in zip(r.obb.xyxyxyxy.tolist(), r.obb.cls.tolist(), r.obb.conf.tolist()):
                    if modele.names[int(k)] != VOITURE:
                        continue
                    (ax, ay), (bx, by), (cx, cy), _ = pts
                    c1, c2 = math.hypot(bx - ax, by - ay), math.hypot(cx - bx, cy - by)
                    dx, dy = (bx - ax, by - ay) if c1 >= c2 else (cx - bx, cy - by)
                    u = (sum(p[0] for p in pts) / 4 + x) / e
                    v = (sum(p[1] for p in pts) / 4 + y) / e
                    dets.append((u, v, math.atan2(dy, dx), cf, max(c1, c2) / e, min(c1, c2) / e))
    # Même voiture vue plusieurs fois : on garde la détection la plus sûre
    dets.sort(key=lambda d: -d[3])
    gardees = []
    for d in dets:
        if all(math.hypot(d[0] - g[0], d[1] - g[1]) > 7 for g in gardees):  # 7 px ≈ 1,4 m
            gardees.append(d)
    return gardees


# ---------- Reconstitution des rangées ----------

class Photo:
    """Lecture de la photo en mètres locaux (pour juger si une place est plausible)."""

    def __init__(self, img, gx, gy):
        self.rgb = np.asarray(img, dtype=np.float32)
        self.gris = self.rgb.mean(axis=2)
        self.gx, self.gy = gx, gy

    def px(self, p):
        lat, lon = vers_latlon(*p)
        tx, ty = tuile_xy(lat, lon)
        return tx * 256 - self.gx, ty * 256 - self.gy

    def valeurs(self, points, canal=None):
        h, w = self.gris.shape
        res = []
        for p in points:
            u, v = self.px(p)
            if 0 <= u < w and 0 <= v < h:
                res.append(self.gris[int(v), int(u)] if canal is None else self.rgb[int(v), int(u)])
        return res


def points_place(c, a, longueur, largeur, nu=7, nv=4, marge=0.8):
    ca, sa = math.cos(a), math.sin(a)
    pts = []
    for i in range(nu):
        for j in range(nv):
            du = (i / (nu - 1) - 0.5) * longueur * marge
            dv = (j / (nv - 1) - 0.5) * largeur * marge
            pts.append((c[0] + du * ca - dv * sa, c[1] + du * sa + dv * ca))
    return pts


def indice_place(photo, c, a, r, pas, ref_bitume):
    """Que montre la photo à cet endroit ? 'herbe', 'voiture', 'marquage' ou 'vide'.

    a : axe de la place (sens de la voiture) ; r : axe de la rangée ; pas : écart entre places.
    """
    rgb = photo.valeurs(points_place(c, a, *PLACE), canal=True)
    if len(rgb) < 10:
        return "vide"
    moy = np.mean(rgb, axis=0)
    if moy[1] > moy[0] + 8 and moy[1] > moy[2] + 8:
        return "herbe"
    gris = [float(np.mean(x)) for x in rgb]
    if statistics.pstdev(gris) > 30 and abs(statistics.fmean(gris) - ref_bitume) > 20:
        return "voiture"
    # Marquage : la ligne entre deux places est plus claire que le bitume juste à côté
    ur, vr = math.cos(r), math.sin(r)
    for cote in (-1, 1):
        o = (c[0] + cote * pas / 2 * ur, c[1] + cote * pas / 2 * vr)
        ligne = photo.valeurs(points_place(o, a, PLACE[0], 0.0, nu=9, nv=2, marge=0.7))
        decal = (c[0] + cote * (pas / 2 - 0.5) * ur, c[1] + cote * (pas / 2 - 0.5) * vr)
        a_cote = photo.valeurs(points_place(decal, a, PLACE[0], 0.0, nu=9, nv=2, marge=0.7))
        if ligne and a_cote and statistics.fmean(ligne) - statistics.fmean(a_cote) > 10:
            return "marquage"
    # Bande de places vides : surface unie mais d'une autre teinte que l'allée devant elle.
    # Dans une allée transversale, la place et ses voisines (dans l'axe a) ont la même teinte.
    ua, va = math.cos(a), math.sin(a)
    moy_place = statistics.fmean(gris)
    if statistics.pstdev(gris) < 20:
        for cote in (-1, 1):
            o = (c[0] + cote * (PLACE[0] / 2 + 3.0) * ua, c[1] + cote * (PLACE[0] / 2 + 3.0) * va)
            allee = photo.valeurs(points_place(o, a, 2.0, PLACE[1], nu=3, nv=3))
            if len(allee) >= 5 and abs(moy_place - statistics.fmean(allee)) > 25 \
                    and statistics.pstdev(allee) < 25:
                return "bande"
    return "vide"


def rangees(voitures):
    """Regroupe les voitures (position m, axe rad) en rangées de places en bataille."""
    n = len(voitures)
    parent = list(range(n))

    def racine(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i

    for i in range(n):
        pi, ai = voitures[i]
        for j in range(i + 1, n):
            pj, aj = voitures[j]
            da = abs((ai - aj + math.pi / 2) % math.pi - math.pi / 2)
            if da > math.radians(14):
                continue
            dx, dy = pj[0] - pi[0], pj[1] - pi[1]
            le_long = abs(dx * math.cos(ai) + dy * math.sin(ai))      # décalage dans l'axe des voitures
            en_travers = abs(-dx * math.sin(ai) + dy * math.cos(ai))  # écart le long de la rangée
            if le_long < 1.3 and en_travers < 9.0:
                parent[racine(i)] = racine(j)
    groupes = {}
    for i in range(n):
        groupes.setdefault(racine(i), []).append(voitures[i])
    res = []
    for g in groupes.values():
        if len(g) < 3:  # deux voitures ne suffisent pas à affirmer une rangée
            continue
        a = math.atan2(sum(math.sin(2 * x) for _, x in g), sum(math.cos(2 * x) for _, x in g)) / 2
        ecarts_axe = [abs((x - a + math.pi / 2) % math.pi - math.pi / 2) for _, x in g]
        decalages = [p[0] * math.cos(a) + p[1] * math.sin(a) for p, _ in g]
        moy = statistics.fmean(decalages)
        # Toutes les voitures doivent avoir le même axe et être bien alignées
        if max(ecarts_axe) < math.radians(14) and max(abs(d - moy) for d in decalages) < 1.0:
            res.append(g)
    return res


def completer_rangees(voitures, poly, photo, col, ajouter_place):
    """Comble et prolonge les rangées. Renvoie le nombre de places ajoutées."""
    gris_parking = [g for g in photo.valeurs(
        [(x, y) for x, y in _grille_points(poly, 1.5) if dedans((x, y), poly)])]
    ref = statistics.median(gris_parking) if gris_parking else 110.0
    ajoutees = 0
    for groupe in rangees(voitures):
        # axe moyen des voitures (angles modulo pi)
        s = sum(math.sin(2 * a) for _, a in groupe)
        c = sum(math.cos(2 * a) for _, a in groupe)
        a = math.atan2(s, c) / 2
        r = a + math.pi / 2
        ur, vr = math.cos(r), math.sin(r)
        ua, va = math.cos(a), math.sin(a)
        ts = sorted(p[0] * ur + p[1] * vr for p, _ in groupe)
        o = statistics.fmean(p[0] * ua + p[1] * va for p, _ in groupe)
        ecarts = [b - a_ for a_, b in zip(ts, ts[1:]) if 1.8 < b - a_ < 3.4]
        pas = statistics.median(ecarts) if ecarts else 2.5

        def centre(t):
            return (o * ua + t * ur, o * va + t * vr)

        def possible(cp):
            # dans le parking, et sans chevaucher une autre place (rangée voisine, allée)
            return all(dedans(q, poly) for q in coins(cp, *PLACE, a)) and col.grille.plus_proche(cp) > 0.85 * pas

        # Trous entre deux voitures de la rangée (au plus 3 places manquantes d'affilée)
        for t0, t1 in zip(ts, ts[1:]):
            k = round((t1 - t0) / pas)
            if k > 4:
                continue
            for i in range(1, k):
                cp = centre(t0 + i * (t1 - t0) / k)
                if possible(cp) and indice_place(photo, cp, a, r, pas, ref) != "herbe":
                    ajoutees += ajouter_place(cp, a)
        # Prolongement aux deux bouts, tant que la photo montre une place
        for depart, sens in ((ts[0], -1), (ts[-1], 1)):
            for i in range(1, 30):
                cp = centre(depart + sens * i * pas)
                if not possible(cp) or indice_place(photo, cp, a, r, pas, ref) not in ("voiture", "marquage", "bande"):
                    break
                ajoutees += ajouter_place(cp, a)
    return ajoutees


def _grille_points(poly, pas):
    xs = [p[0] for p in poly]
    ys = [p[1] for p in poly]
    x = min(xs)
    while x <= max(xs):
        y = min(ys)
        while y <= max(ys):
            yield x, y
            y += pas
        x += pas


# ---------- Programme ----------

def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--conf", type=float, default=0.2, help="confiance minimale d'une détection")
    ap.add_argument("--sans-rangees", action="store_true", help="seulement les voitures vues")
    ap.add_argument("--avec-prives", action="store_true", help="traiter aussi les parkings privés")
    ap.add_argument("--parking", help="ne traiter que ce parking (ex. way/1024301356), pour régler")
    args = ap.parse_args()

    from ultralytics import YOLO  # import lourd : seulement ici
    CACHE.mkdir(exist_ok=True)
    charges = {}
    modeles = []
    for nom, e in ENSEMBLE:
        if nom not in charges:
            charges[nom] = YOLO(str(CACHE / nom))  # téléchargé dans cache/ au premier lancement
        modeles.append((charges[nom], e))

    osm = json.loads((ICI / "places_osm.json").read_text(encoding="utf-8"))
    objets, commune_de = lire(requete_overpass(False))
    routes = [(e["tags"].get("name"), [vers_xy(p["lat"], p["lon"]) for p in e["geometry"]], k)
              for k, e in objets.items()
              if e["type"] == "way" and e.get("tags", {}).get("name") and "highway" in e["tags"] and e.get("geometry")]
    col = Collecte(routes, commune_de)
    for p in osm["places"]:  # les places OSM sont prioritaires : pas de doublon par-dessus
        col.grille.ajouter(vers_xy(p["lat"], p["long"]))

    a_traiter = [(z["osm"], z.get("nom"), [tuple(c) for c in z["contour"]]) for z in osm["a_completer"]]
    if args.avec_prives:
        for k, e in objets.items():
            t = e.get("tags", {})
            c = contour(e)
            if t.get("amenity") == "parking" and t.get("access") in PRIVES and c \
                    and t.get("parking", "surface") == "surface" and aire_centre(c)[0] >= 150:
                a_traiter.append((k, t.get("name"), [vers_latlon(x, y) for x, y in c]))
    if args.parking:
        a_traiter = [z for z in a_traiter if z[0] == args.parking]

    CONTROLES.mkdir(parents=True, exist_ok=True)
    bilan = []
    for cle, nom, contour_ll in a_traiter:
        t0 = time.time()
        poly = [vers_xy(*p) for p in contour_ll]
        img, (gx, gy) = mosaique(contour_ll)
        photo = Photo(img, gx, gy)
        m_par_px = math.cos(math.radians(contour_ll[0][0])) * 2 * math.pi * 6_378_137 / (256 * 2 ** ZOOM)
        voitures, avant = [], len(col.places)

        def ajouter_place(p, angle, source):
            return int(col.ajouter(p, angle, PLACE, f"{source}:{cle}", parking=nom,
                                   tarif=TARIF_PARKING, cle_commune=cle))

        for u, v, ang_img, cf, lg, la in detecter(modeles, img, args.conf):
            if not (3.0 <= lg * m_par_px <= 6.5 and 1.3 <= la * m_par_px <= 2.8):
                continue  # pas une voiture (camion, ombre, objet)
            p = vers_xy(*pixel_latlon(u + gx, v + gy))
            if not dedans(p, poly):
                continue  # voiture hors du parking (rue voisine, roule peut-être)
            angle = -ang_img  # l'axe y de l'image descend vers le sud
            voitures.append((p, angle))
            ajouter_place(p, angle, "yolo_voiture")
        vues = len(col.places) - avant
        deduites = 0 if args.sans_rangees else completer_rangees(
            voitures, poly, photo, col, lambda p, a: ajouter_place(p, a, "yolo_rangee"))

        # Image de contrôle : contour du parking, voitures vues (vert), places déduites (cyan)
        d = ImageDraw.Draw(img)
        d.line([photo.px(p) for p in poly + poly[:1]], fill=(255, 140, 0), width=3)
        for pl in col.places[avant:]:
            pts = [photo.px(q) for q in coins(vers_xy(pl["lat"], pl["long"]), pl["longueur"],
                                              pl["largeur"], math.radians(pl["angle"]))]
            d.polygon(pts, outline=(0, 255, 0) if pl["source"].startswith("yolo_voiture") else (0, 220, 255))
        img.save(CONTROLES / f"{cle.replace('/', '_')}.jpg", quality=88)
        bilan.append({"osm": cle, "nom": nom, "voitures_vues": vues, "places_deduites": deduites})
        print(f"{cle:<16} {(nom or '')[:28]:<28} {vues:>4} voitures vues, {deduites:>4} places déduites"
              f"  ({time.time() - t0:.0f} s)", flush=True)

    resultat = {
        "genere_le": datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S"),
        "licence": "Photos © IGN (Licence Ouverte 2.0) ; contours de parkings © contributeurs OpenStreetMap (ODbL)",
        "modeles": ENSEMBLE, "conf": args.conf, "rangees": not args.sans_rangees,
        "bilan": bilan,
        "places": col.places,
    }
    ecrire_compact(SORTIE, resultat)
    print(f"{len(col.places)} places -> {SORTIE.name}")


def ecrire_compact(chemin, resultat):
    """JSON avec une place par ligne : lisible, et un diff git court."""
    entete = {k: v for k, v in resultat.items() if k != "places"}
    corps = ",\n".join("  " + json.dumps(p, ensure_ascii=False) for p in resultat["places"])
    texte = json.dumps(entete, ensure_ascii=False, indent=1)[:-2] + ',\n "places": [\n' + corps + "\n ]\n}\n"
    json.loads(texte)  # vérifie que le fichier reste un JSON valide
    chemin.write_text(texte, encoding="utf-8")


if __name__ == "__main__":
    main()
