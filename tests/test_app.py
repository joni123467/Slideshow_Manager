from __future__ import annotations

import json
import os
from pathlib import Path

from slideshow_manager import create_app


def test_slides_api(tmp_path: Path) -> None:
    data_dir = tmp_path / "data"
    os.environ["SLIDESHOW_MANAGER_DATA_DIR"] = str(data_dir)
    try:
        app = create_app()
    finally:
        os.environ.pop("SLIDESHOW_MANAGER_DATA_DIR", None)

    client = app.test_client()

    # Seed slides should be created automatically
    response = client.get("/api/slides")
    assert response.status_code == 200
    payload = response.get_json()
    assert "slides" in payload

    new_slide = {
        "title": "Test",
        "description": "Beschreibung",
        "image_url": "https://example.com/image.png",
    }

    response = client.post("/api/slides", data=json.dumps(new_slide), content_type="application/json")
    assert response.status_code == 201
    assert len(response.get_json()["slides"]) >= 1

    response = client.put(
        "/api/slides/0",
        data=json.dumps({"title": "Neu", "description": "", "image_url": "https://example.com/new.png"}),
        content_type="application/json",
    )
    assert response.status_code == 200

    response = client.delete("/api/slides/0")
    assert response.status_code == 200
