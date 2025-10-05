"""Tests for the PAM-based authenticator."""
from __future__ import annotations

import sys
from types import SimpleNamespace

import pytest

from slideshow_manager.auth import AuthenticationError, PAMAuthenticator


def test_pam_authenticator_requires_pam_module(monkeypatch: pytest.MonkeyPatch) -> None:
    """Ensure that a missing pam module raises a helpful error."""

    monkeypatch.delitem(sys.modules, "pam", raising=False)
    monkeypatch.setitem(sys.modules, "pam", None)

    with pytest.raises(AuthenticationError) as excinfo:
        PAMAuthenticator()

    assert "python-pam is required" in str(excinfo.value)


def test_pam_authenticator_authenticates_linux_user(monkeypatch: pytest.MonkeyPatch) -> None:
    """Verify that the authenticator delegates to python-pam."""

    calls: list[tuple[str, str, str]] = []

    class DummyPam:
        def authenticate(self, username: str, password: str, service: str = "login") -> bool:
            calls.append((username, password, service))
            return password == "secret"

    dummy_module = SimpleNamespace(pam=lambda: DummyPam())
    monkeypatch.setitem(sys.modules, "pam", dummy_module)

    authenticator = PAMAuthenticator(service="login")

    assert authenticator.authenticate("alice", "secret") is True
    assert authenticator.authenticate("alice", "wrong") is False
    assert calls == [("alice", "secret", "login"), ("alice", "wrong", "login")]
