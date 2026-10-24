import hashlib
from dataclasses import replace

import pytest
from app import api
from app.api import PassContent
from app.auth import authenticated_user
from app.database import get_connection
from app.main import app
from fastapi.testclient import TestClient


def test_liveness_and_editorial_gallery_work_without_production_secrets() -> None:
    with TestClient(app) as client:
        assert client.get("/api/v1/health/live").json()["status"] == "ok"
        response = client.get("/api/v1/gallery/templates")

    assert response.status_code == 200
    assert len(response.json()) == 8
    assert response.json()[0]["license"] == "CC0 1.0"


def test_unsigned_wallet_issuance_is_never_simulated() -> None:
    class FakeCursor:
        def fetchone(self):
            return {"uses": 1}

    class FakeConnection:
        def execute(self, *_args):
            return FakeCursor()

    previous_overrides = app.dependency_overrides.copy()
    app.dependency_overrides[get_connection] = lambda: FakeConnection()
    app.dependency_overrides[authenticated_user] = lambda: "00000000-0000-4000-8000-000000000001"
    content = PassContent(
        type="generic",
        title="Pase de prueba",
        organization="Estudio de prueba",
        barcodeKind="qr",
        backgroundHex="40356F",
        foregroundHex="FFFFFF",
    )
    with TestClient(app) as client:
        response = client.post(
            "/api/v1/passes",
            json=content.model_dump(mode="json"),
            headers={"Authorization": "Bearer token-de-prueba"},
        )
    app.dependency_overrides = previous_overrides

    assert response.status_code == 503
    assert "modo demo" in response.json()["detail"].lower()
    assert response.headers.get("content-type", "").startswith("application/json")
    assert response.headers.get("content-type") != "application/vnd.apple.pkpass"


def test_community_assets_are_not_public_when_database_is_unconfigured() -> None:
    with TestClient(app) as client:
        response = client.get("/api/v1/community/assets")

    assert response.status_code == 503
    assert "base de datos" in response.json()["detail"].lower()


def test_wallet_device_registration_requires_the_pass_authentication_token(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    pass_type = "pass.app.lumapass"
    token = "wallet-token-for-test-only"
    inserted_tokens: list[str] = []

    class FakeCursor:
        def __init__(self, row=None):
            self.row = row

        def fetchone(self):
            return self.row

    class FakeConnection:
        def execute(self, query, parameters=()):
            if "SELECT authentication_token_hash, revoked_at" in query:
                return FakeCursor(
                    {
                        "authentication_token_hash": hashlib.sha256(
                            token.encode("utf-8")
                        ).hexdigest(),
                        "revoked_at": None,
                    }
                )
            if "SELECT 1 FROM wallet_devices" in query:
                return FakeCursor(None)
            if "INSERT INTO wallet_devices" in query:
                inserted_tokens.append(parameters[-1])
                return FakeCursor()
            raise AssertionError("Unexpected SQL query in wallet registration test.")

    previous_overrides = app.dependency_overrides.copy()
    app.dependency_overrides[get_connection] = lambda: FakeConnection()
    monkeypatch.setattr(api, "settings", replace(api.settings, pass_type_identifier=pass_type))
    url = f"/apple-wallet/v1/devices/device-test/registrations/{pass_type}/pass-123"
    body = {"pushToken": "a" * 64}
    try:
        with TestClient(app) as client:
            rejected = client.post(
                url,
                json=body,
                headers={"Authorization": "ApplePass wrong-token"},
            )
            accepted = client.post(
                url,
                json=body,
                headers={"Authorization": f"ApplePass {token}"},
            )
    finally:
        app.dependency_overrides = previous_overrides

    assert rejected.status_code == 401
    assert accepted.status_code == 201
    assert inserted_tokens == [body["pushToken"]]
