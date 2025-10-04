"""Slideshow Manager Flask application factory."""
from __future__ import annotations

import os
from pathlib import Path

from flask import Flask

from . import storage
from .views import bp


DEFAULT_DATA_DIR = Path(__file__).resolve().parent / "data"


def create_app() -> Flask:
    """Create and configure the Flask application instance."""
    app = Flask(__name__)

    data_dir = Path(
        os.environ.get("SLIDESHOW_MANAGER_DATA_DIR", DEFAULT_DATA_DIR)
    ).expanduser().resolve()
    data_dir.mkdir(parents=True, exist_ok=True)
    app.config["DATA_DIR"] = data_dir

    storage.ensure_seed_data(data_dir)

    app.register_blueprint(bp)

    @app.route("/healthz")
    def healthcheck() -> tuple[str, int]:
        """Simple health check endpoint for monitoring."""
        return "ok", 200

    return app


__all__ = ["create_app"]
