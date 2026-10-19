# Tests du paiement d'une place
# Lancer : uv run --with pytest pytest test_paiement.py

import pytest
from fastapi.testclient import TestClient

import main


@pytest.fixture
def client(tmp_path, monkeypatch):
    #bases dans un dossier temporaire pour ne pas toucher /data
    monkeypatch.setattr(main, "DB_PATH", tmp_path / "la-base.db")
    monkeypatch.setattr(main, "VEHICULE_DB_PATH", tmp_path / "l-autre-database.db")
    monkeypatch.setattr(main, "USER_DB_PATH", tmp_path / "database-user.db")
    monkeypatch.setattr(main, "PAIEMENT_DB_PATH", tmp_path / "database-paiement.db")
    #personne n'est connecté au début de chaque test
    monkeypatch.setattr(main, "current_user", main.User())
    with TestClient(main.app) as c:
        yield c


def login(client, username="ab123456", password="Mon_mdp123"):
    r = client.post("/token", data={"username": username, "password": password})
    assert r.status_code == 200


def test_prix_voiture_une_heure(client):
    r = client.get("/data/1/prix", params={"duree": 60})
    assert r.status_code == 200
    assert r.json() == {"place": 1, "duree": 60, "prix": 2.0}


def test_prix_moto_au_prorata(client):
    #place 6 = moto, 1 euro de l'heure
    r = client.get("/data/6/prix", params={"duree": 90})
    assert r.json()["prix"] == 1.5


def test_prix_place_inconnue(client):
    assert client.get("/data/999/prix", params={"duree": 60}).status_code == 404


@pytest.mark.parametrize("duree", [0, -10, main.DUREE_MAX + 1])
def test_prix_duree_invalide(client, duree):
    assert client.get("/data/1/prix", params={"duree": duree}).status_code == 422


def test_payer_sans_connexion(client):
    r = client.post("/data/1/payer", params={"plaque": "AB123CD", "duree": 60})
    assert r.status_code == 401


def test_payer_place_libre(client):
    login(client)
    r = client.post("/data/1/payer", params={"plaque": "AB123CD", "duree": 30})
    assert r.status_code == 200
    body = r.json()
    assert body["place"] == 1
    assert body["prix"] == 1.0
    assert body["paiement"] == 1

    #la place est maintenant occupée jusqu'à la fin payée
    place = client.get("/data/1").json()
    assert place["occupé"] == 1
    free_ids = [p[0] for p in client.get("/data/free").json()["data"]]
    assert 1 not in free_ids


def test_payer_deux_fois_la_meme_place(client):
    login(client)
    client.post("/data/1/payer", params={"plaque": "AB123CD", "duree": 30})
    r = client.post("/data/1/payer", params={"plaque": "AB123CD", "duree": 30})
    assert r.status_code == 409


def test_payer_place_deja_occupee(client):
    #place 4 est occupée dans les données de départ
    login(client)
    r = client.post("/data/4/payer", params={"plaque": "AB123CD", "duree": 30})
    assert r.status_code == 409


def test_payer_avec_le_vehicule_d_un_autre(client):
    #cd789 n'a pas de véhicule, AB123CD appartient à ab123456
    login(client, "cd789", "autre_MDP666")
    r = client.post("/data/1/payer", params={"plaque": "AB123CD", "duree": 30})
    assert r.status_code == 403


def test_payer_place_moto_avec_une_voiture(client):
    login(client)
    r = client.post("/data/6/payer", params={"plaque": "AB123CD", "duree": 30})
    assert r.status_code == 400


def test_payer_place_inconnue(client):
    login(client)
    r = client.post("/data/999/payer", params={"plaque": "AB123CD", "duree": 30})
    assert r.status_code == 404
