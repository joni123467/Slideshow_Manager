from pathlib import Path

import pytest
import responses

from slideshow_manager import create_app


@pytest.fixture()
def app(tmp_path: Path):
    storage_path = tmp_path / "devices.json"
    app = create_app(
        {
            "TESTING": True,
            "SECRET_KEY": "test-secret",
            "STORAGE_PATH": str(storage_path),
            "AUTH_MODE": "static",
            "TEST_USERS": {"tester": "secret"},
            "REMOTE_TIMEOUT": 2,
        }
    )
    with app.app_context():
        yield app


@pytest.fixture()
def client(app):
    return app.test_client()


def login(client):
    response = client.post(
        "/login",
        data={"username": "tester", "password": "secret"},
        follow_redirects=True,
    )
    assert response.status_code == 200
    return response


@responses.activate
def test_dashboard_lists_devices(app, client):
    storage = app.storage  # type: ignore[attr-defined]
    device = storage.add(
        {
            "name": "Pi 1",
            "base_url": "https://pi1.local",
            "username": "pi",
            "password": "pw",
        }
    )

    responses.add(
        responses.POST,
        "https://pi1.local/login",
        headers={"Set-Cookie": "session=abc"},
        json={"status": "ok"},
    )
    responses.add(
        responses.GET,
        "https://pi1.local/api/state",
        json={
            "primary_status": "playing",
            "primary_source": "local",
            "primary_media_path": "bild.jpg",
            "primary_media_type": "image",
        },
    )

    login(client)
    response = client.get("/")
    assert response.status_code == 200
    assert b"Pi 1" in response.data
    assert b"bild.jpg" in response.data


@responses.activate
def test_playback_update_triggers_remote_call(app, client):
    storage = app.storage  # type: ignore[attr-defined]
    device = storage.add(
        {
            "name": "Pi 2",
            "base_url": "https://pi2.local",
            "username": "pi",
            "password": "pw",
        }
    )

    for _ in range(6):
        responses.add(
            responses.POST,
            "https://pi2.local/login",
            headers={"Set-Cookie": "session=abc"},
            json={"status": "ok"},
        )
    for _ in range(3):
        responses.add(
            responses.GET,
            "https://pi2.local/api/state",
            json={
                "service_status": "active",
                "service_active": True,
                "primary_media_type": "image",
                "primary_media_path": "bild.jpg",
                "primary_source": "local",
            },
        )
        responses.add(
            responses.GET,
            "https://pi2.local/api/config",
            json={
                "playback": {
                    "image_duration": 10,
                    "image_fit": "contain",
                    "image_rotation": 0,
                    "transition_type": "fade",
                    "transition_duration": 1.5,
                }
            },
        )
        responses.add(
            responses.GET,
            "https://pi2.local/api/sources",
            json={"sources": []},
        )
    responses.add(
        responses.PUT,
        "https://pi2.local/api/playback",
        match=[responses.matchers.json_params_matcher({"image_duration": 8})],
        json={"status": "ok"},
    )

    login(client)
    response = client.post(
        f"/devices/{device.id}/playback",
        data={"image_duration": "8"},
        follow_redirects=True,
    )
    assert response.status_code == 200
    assert b"Aktion erfolgreich" in response.data


def test_device_crud(app, client):
    login(client)
    response = client.post(
        "/devices/new",
        data={
            "name": "Neues Gerät",
            "base_url": "https://pi3.local",
            "username": "pi",
            "password": "pw",
        },
        follow_redirects=True,
    )
    assert response.status_code == 200
    storage = app.storage  # type: ignore[attr-defined]
    devices = storage.list_devices()
    assert any(device.name == "Neues Gerät" for device in devices)
