"""Application factory for the Slideshow Manager dashboard."""
from __future__ import annotations

from flask import Flask

from .auth import bp as auth_bp
from .views import bp as dashboard_bp
from .storage import DeviceStorage


def create_app(config: dict | None = None) -> Flask:
    app = Flask(__name__)
    app.config.from_mapping(
        SECRET_KEY="change-me",
        STORAGE_PATH="slideshow_manager/data/devices.json",
        AUTH_MODE="pam",
        TEST_USERS={},
        REMOTE_TIMEOUT=8,
    )

    if config:
        app.config.update(config)

    storage = DeviceStorage(app.config["STORAGE_PATH"])
    app.storage = storage  # type: ignore[attr-defined]

    app.register_blueprint(auth_bp)
    app.register_blueprint(dashboard_bp)

    @app.context_processor
    def inject_globals():
        return {
            "app_version": "1.0.0",
        }

    return app


__all__ = ["create_app"]
