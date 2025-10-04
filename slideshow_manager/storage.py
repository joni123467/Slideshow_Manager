"""Utilities for reading and writing slideshow data."""
from __future__ import annotations

import json
from pathlib import Path
from threading import Lock
from typing import Any

DEFAULT_SLIDES = [
    {
        "title": "Willkommen",
        "description": "Starte deine erste Präsentation in wenigen Sekunden.",
        "image_url": "https://via.placeholder.com/800x450.png?text=Slideshow+Manager",
    },
    {
        "title": "Verwalten",
        "description": "Füge Folien hinzu, ändere Inhalte und sortiere sie nach Bedarf.",
        "image_url": "https://via.placeholder.com/800x450.png?text=Folien+verwalten",
    },
    {
        "title": "Präsentieren",
        "description": "Nutze den Präsentationsmodus für Meetings oder Infobildschirme.",
        "image_url": "https://via.placeholder.com/800x450.png?text=Los+geht's",
    },
]

_LOCK = Lock()


def _data_file(data_dir: Path) -> Path:
    return data_dir / "slides.json"


def ensure_seed_data(data_dir: Path) -> None:
    """Populate the data directory with a default dataset if necessary."""
    data_dir.mkdir(parents=True, exist_ok=True)
    data_file = _data_file(data_dir)
    if data_file.exists():
        return

    with _LOCK:
        if data_file.exists():
            return
        payload = {"slides": DEFAULT_SLIDES}
        data_file.write_text(json.dumps(payload, indent=2), encoding="utf-8")


def load_slides(data_dir: Path) -> list[dict[str, Any]]:
    data_file = _data_file(data_dir)
    if not data_file.exists():
        ensure_seed_data(data_dir)

    with data_file.open("r", encoding="utf-8") as fh:
        payload = json.load(fh)
    return list(payload.get("slides", []))


def save_slides(data_dir: Path, slides: list[dict[str, Any]]) -> None:
    data_file = _data_file(data_dir)
    data_dir.mkdir(parents=True, exist_ok=True)

    with _LOCK:
        with data_file.open("w", encoding="utf-8") as fh:
            json.dump({"slides": slides}, fh, indent=2, ensure_ascii=False)
