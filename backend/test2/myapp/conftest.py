# Préparation commune des tests du backend
# Lancer tous les tests : uv run --with pytest pytest

import pytest
from fastapi.testclient import TestClient

import main


@pytest.fixture
def client(tmp_path, monkeypatch):
    #toutes les bases (DB_PATH, VEHICULE_DB_PATH...) vont dans un dossier temporaire pour ne pas toucher /data
    for nom in dir(main):
        if nom.endswith("DB_PATH"):
            monkeypatch.setattr(main, nom, tmp_path / f"{nom.lower()}.db")
    #personne n'est connecté au début de chaque test
    monkeypatch.setattr(main, "current_user", main.User())
    with TestClient(main.app) as c:
        yield c
