# Tests de la recherche de places par zone géographique
# Lancer : uv run --with pytest pytest test_zone.py

import pytest

#la fixture "client" est dans conftest.py


def ids(reponse):
    return sorted(p[0] for p in reponse.json().get("data", []))


# Zone qui contient les places 1, 2 et 3 des données de départ
ZONE_CENTRE = {"lat_min": 1.2, "lat_max": 1.3, "long_min": 2.3, "long_max": 2.4}
# Zone qui ne contient que la place 4, occupée au départ
ZONE_OCCUPEE = {"lat_min": 1.4, "lat_max": 1.5, "long_min": 2.1, "long_max": 2.2}


def test_toutes_les_places_d_une_zone(client):
    r = client.get("/data/zone", params=ZONE_CENTRE)
    assert r.status_code == 200
    assert r.json()["N"] == 3
    assert ids(r) == [1, 2, 3]


def test_places_libres_d_une_zone(client):
    r = client.get("/data/free/zone", params=ZONE_OCCUPEE)
    assert r.json() == {"N": 0}
    #la place est bien dans la zone, mais occupée
    assert ids(client.get("/data/zone", params=ZONE_OCCUPEE)) == [4]


def test_zone_vide(client):
    r = client.get("/data/zone", params={"lat_min": 10, "lat_max": 11, "long_min": 10, "long_max": 11})
    assert r.json() == {"N": 0}


def test_zone_min_plus_grand_que_max(client):
    r = client.get("/data/zone", params={**ZONE_CENTRE, "lat_min": 1.3, "lat_max": 1.2})
    assert r.status_code == 400


@pytest.mark.parametrize("param, valeur", [("lat_max", 91), ("lat_min", -91), ("long_max", 181), ("long_min", -181)])
def test_coordonnees_hors_limites(client, param, valeur):
    r = client.get("/data/free/zone", params={**ZONE_CENTRE, param: valeur})
    assert r.status_code == 422


def test_zone_sans_parametre(client):
    assert client.get("/data/zone").status_code == 422


def test_info_d_une_place_toujours_accessible(client):
    #la route /data/zone ne doit pas casser /data/{id}
    assert client.get("/data/3").json()["Place"] == 3
