"""Client helpers that talk to remote slideshow devices."""
from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Dict, Optional
from urllib.parse import urljoin, quote

import requests


class RemoteAPIError(RuntimeError):
    """Raised when the remote slideshow device responds with an error."""

    def __init__(self, message: str, status_code: Optional[int] = None) -> None:
        super().__init__(message)
        self.status_code = status_code


@dataclass
class RemoteDevice:
    base_url: str
    username: str
    password: str


class SlideshowClient:
    """Minimal REST wrapper around the slideshow API."""

    def __init__(self, device: RemoteDevice, timeout: int = 8) -> None:
        self.device = device
        self.timeout = timeout

    def _make_session(self) -> requests.Session:
        session = requests.Session()
        login_url = self._url("/login")
        response = session.post(
            login_url,
            data={"username": self.device.username, "password": self.device.password},
            timeout=self.timeout,
        )
        if response.status_code != 200:
            raise RemoteAPIError(
                f"Login fehlgeschlagen (HTTP {response.status_code})", response.status_code
            )
        if "session" not in response.cookies.get_dict():
            raise RemoteAPIError("Login fehlgeschlagen: Kein Session-Cookie erhalten")
        return session

    def _request(self, method: str, path: str, **kwargs: Any) -> requests.Response:
        session = self._make_session()
        url = self._url(path)
        response = session.request(method, url, timeout=self.timeout, **kwargs)
        if response.status_code >= 400:
            try:
                message = response.json().get("message", response.text)
            except Exception:  # pragma: no cover - defensive path
                message = response.text
            raise RemoteAPIError(
                f"API-Fehler ({response.status_code}): {message}", response.status_code
            )
        return response

    def _url(self, path: str) -> str:
        base = self.device.base_url.rstrip("/") + "/"
        return urljoin(base, path.lstrip("/"))

    def get_state(self) -> Dict[str, Any]:
        response = self._request("GET", "/api/state")
        return response.json()

    def get_config(self) -> Dict[str, Any]:
        response = self._request("GET", "/api/config")
        return response.json()

    def list_sources(self) -> Dict[str, Any]:
        response = self._request("GET", "/api/sources")
        return response.json()

    def create_source(self, payload: Dict[str, Any]) -> Dict[str, Any]:
        response = self._request("POST", "/api/sources", json=payload)
        return response.json()

    def update_source(self, name: str, payload: Dict[str, Any]) -> Dict[str, Any]:
        response = self._request("PUT", f"/api/sources/{quote(name)}", json=payload)
        return response.json()

    def delete_source(self, name: str) -> Dict[str, Any]:
        response = self._request("DELETE", f"/api/sources/{quote(name)}")
        return response.json() if response.content else {"status": "ok"}

    def set_playback(self, payload: Dict[str, Any]) -> Dict[str, Any]:
        response = self._request("PUT", "/api/playback", json=payload)
        return response.json()

    def trigger_player_action(self, action: str) -> Dict[str, Any]:
        response = self._request("POST", f"/api/player/{action}")
        return response.json()

    def toggle_info_screen(self, enabled: bool) -> Dict[str, Any]:
        response = self._request("POST", "/api/player/info-screen", json={"enabled": enabled})
        return response.json()

    def fetch_preview(self, source: str, media_path: str) -> bytes:
        path = f"/media/preview/{quote(source)}/{quote(media_path)}"
        response = self._request("GET", path)
        return response.content
