"""Petits outils de géométrie en mètres (projection locale autour de la Cité Descartes).

À l'échelle d'un campus (1 à 2 km), une projection plane autour d'un point de
référence est précise au décimètre : pas besoin de bibliothèque SIG.
"""
import math

# Point de référence : ESIEE Paris
LAT0, LON0 = 48.8390, 2.5853
KX = 111_320 * math.cos(math.radians(LAT0))  # mètres par degré de longitude
KY = 110_574                                  # mètres par degré de latitude


def vers_xy(lat, lon):
    return ((lon - LON0) * KX, (lat - LAT0) * KY)


def vers_latlon(x, y):
    return (LAT0 + y / KY, LON0 + x / KX)


def aire_centre(poly):
    """Aire (m², positive) et centre de gravité d'un polygone [(x, y), ...]."""
    a = cx = cy = 0.0
    n = len(poly)
    for i in range(n):
        x1, y1 = poly[i]
        x2, y2 = poly[(i + 1) % n]
        c = x1 * y2 - x2 * y1
        a += c
        cx += (x1 + x2) * c
        cy += (y1 + y2) * c
    if abs(a) < 1e-9:
        xs, ys = zip(*poly)
        return 0.0, (sum(xs) / n, sum(ys) / n)
    return abs(a) / 2, (cx / (3 * a), cy / (3 * a))


def dedans(p, poly):
    """Le point p est-il dans le polygone ? (lancer de rayon)"""
    x, y = p
    res = False
    n = len(poly)
    for i in range(n):
        x1, y1 = poly[i]
        x2, y2 = poly[(i + 1) % n]
        if (y1 > y) != (y2 > y):
            xc = x1 + (y - y1) * (x2 - x1) / (y2 - y1)
            if xc > x:
                res = not res
    return res


def enveloppe(points):
    """Enveloppe convexe (chaîne monotone)."""
    pts = sorted(set(points))
    if len(pts) <= 2:
        return pts

    def croix(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])

    bas, haut = [], []
    for p in pts:
        while len(bas) >= 2 and croix(bas[-2], bas[-1], p) <= 0:
            bas.pop()
        bas.append(p)
    for p in reversed(pts):
        while len(haut) >= 2 and croix(haut[-2], haut[-1], p) <= 0:
            haut.pop()
        haut.append(p)
    return bas[:-1] + haut[:-1]


def rectangle_min(points):
    """Rectangle d'aire minimale contenant les points.

    Renvoie (centre, longueur, largeur, angle) : angle en radians de la
    direction du grand côté (depuis l'est, sens trigonométrique), dans [0, pi).
    """
    h = enveloppe(points)
    if len(h) == 1:
        return h[0], 0.0, 0.0, 0.0
    meilleur = None
    for i in range(len(h)):
        x1, y1 = h[i]
        x2, y2 = h[(i + 1) % len(h)]
        a = math.atan2(y2 - y1, x2 - x1)
        c, s = math.cos(a), math.sin(a)
        us = [x * c + y * s for x, y in h]
        vs = [-x * s + y * c for x, y in h]
        aire = (max(us) - min(us)) * (max(vs) - min(vs))
        if meilleur is None or aire < meilleur[0]:
            meilleur = (aire, a, min(us), max(us), min(vs), max(vs))
    _, a, u0, u1, v0, v1 = meilleur
    lu, lv = u1 - u0, v1 - v0
    uc, vc = (u0 + u1) / 2, (v0 + v1) / 2
    c, s = math.cos(a), math.sin(a)
    centre = (uc * c - vc * s, uc * s + vc * c)
    if lv > lu:  # le grand côté est l'autre axe
        a += math.pi / 2
        lu, lv = lv, lu
    return centre, lu, lv, a % math.pi


def coupes(poly, origine, direction):
    """Abscisses s où la droite origine + s * direction coupe les côtés du polygone (triées)."""
    ox, oy = origine
    dx, dy = direction
    res = []
    n = len(poly)
    for i in range(n):
        x1, y1 = poly[i]
        x2, y2 = poly[(i + 1) % n]
        ex, ey = x2 - x1, y2 - y1
        det = dx * (-ey) - dy * (-ex)
        if abs(det) < 1e-12:
            continue
        # origine + s*d = p1 + t*e
        rx, ry = x1 - ox, y1 - oy
        s = (rx * (-ey) - ry * (-ex)) / det
        t = (dx * ry - dy * rx) / det
        if 0 <= t < 1:
            res.append(s)
    return sorted(res)


def dist_segment(p, a, b):
    """Distance du point p au segment [a, b], et position t (0..1) du point le plus proche."""
    px, py = p
    ax, ay = a
    bx, by = b
    ex, ey = bx - ax, by - ay
    l2 = ex * ex + ey * ey
    t = 0.0 if l2 == 0 else max(0.0, min(1.0, ((px - ax) * ex + (py - ay) * ey) / l2))
    qx, qy = ax + t * ex, ay + t * ey
    return math.hypot(px - qx, py - qy), t


def coins(centre, longueur, largeur, angle):
    """Les 4 coins d'une place (rectangle) de grand côté orienté selon angle."""
    cx, cy = centre
    c, s = math.cos(angle), math.sin(angle)
    hl, hw = longueur / 2, largeur / 2
    return [(cx + du * c - dv * s, cy + du * s + dv * c)
            for du, dv in ((-hl, -hw), (hl, -hw), (hl, hw), (-hl, hw))]


class Grille:
    """Index spatial simple pour retrouver les places proches (dédoublonnage)."""

    def __init__(self, pas=5.0):
        self.pas = pas
        self.cases = {}

    def _cle(self, x, y):
        return (int(math.floor(x / self.pas)), int(math.floor(y / self.pas)))

    def ajouter(self, p):
        self.cases.setdefault(self._cle(*p), []).append(p)

    def plus_proche(self, p):
        kx, ky = self._cle(*p)
        d = math.inf
        for i in (-1, 0, 1):
            for j in (-1, 0, 1):
                for q in self.cases.get((kx + i, ky + j), ()):
                    d = min(d, math.hypot(p[0] - q[0], p[1] - q[1]))
        return d
