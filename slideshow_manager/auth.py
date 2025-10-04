"""Authentication blueprint providing Linux user backed login."""
from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Callable, Dict

from flask import (
    Blueprint,
    Response,
    current_app,
    flash,
    g,
    redirect,
    render_template,
    request,
    session,
    url_for,
)


bp = Blueprint("auth", __name__)


class AuthenticationError(RuntimeError):
    """Raised when the configured authentication backend cannot validate credentials."""


class Authenticator:
    """Abstract base authenticator."""

    def authenticate(self, username: str, password: str) -> bool:
        raise NotImplementedError


class PAMAuthenticator(Authenticator):
    """Authenticator that uses PAM via the python-pam package."""

    def __init__(self, service: str = "login") -> None:
        try:
            from pam import pam  # type: ignore
        except ImportError as exc:  # pragma: no cover - executed only when dependency missing
            raise AuthenticationError("python-pam is required for PAM authentication") from exc

        self._pam = pam()
        self._service = service

    def authenticate(self, username: str, password: str) -> bool:
        if not username or not password:
            return False
        return bool(self._pam.authenticate(username, password, service=self._service))


@dataclass
class StaticUser:
    username: str
    password: str


class StaticAuthenticator(Authenticator):
    """Simple authenticator for tests and non-system environments."""

    def __init__(self, users: Dict[str, str]) -> None:
        self._users = {name: pwd for name, pwd in users.items() if name and pwd}

    def authenticate(self, username: str, password: str) -> bool:
        expected = self._users.get(username)
        return bool(expected) and password == expected


def _get_authenticator() -> Authenticator:
    if "authenticator" not in g:
        mode = current_app.config.get("AUTH_MODE", "pam")
        if mode == "pam":
            authenticator: Authenticator = PAMAuthenticator()
        elif mode == "static":
            authenticator = StaticAuthenticator(current_app.config.get("TEST_USERS", {}))
        else:
            raise AuthenticationError(f"Unsupported AUTH_MODE '{mode}'")
        g.authenticator = authenticator
    return g.authenticator  # type: ignore[return-value]


def login_required(view: Callable[..., Response]) -> Callable[..., Response]:
    from functools import wraps

    @wraps(view)
    def wrapped(*args: Any, **kwargs: Any) -> Response:
        if not session.get("user_id"):
            return redirect(url_for("auth.login", next=request.url))
        return view(*args, **kwargs)

    return wrapped


@bp.route("/login", methods=["GET", "POST"])
def login() -> Response:
    if request.method == "POST":
        username = request.form.get("username", "").strip()
        password = request.form.get("password", "")
        try:
            authenticator = _get_authenticator()
            if authenticator.authenticate(username, password):
                session.clear()
                session["user_id"] = username
                flash("Erfolgreich angemeldet.", "success")
                target = request.args.get("next") or url_for("dashboard.index")
                return redirect(target)
        except AuthenticationError as exc:
            flash(str(exc), "danger")
        flash("Anmeldung fehlgeschlagen.", "danger")
    return render_template("login.html")


@bp.route("/logout")
def logout() -> Response:
    session.clear()
    flash("Abgemeldet.", "info")
    return redirect(url_for("auth.login"))
