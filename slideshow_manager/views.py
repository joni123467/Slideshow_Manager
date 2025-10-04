"""Flask routes for the Slideshow Manager."""
from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Any

from flask import Blueprint, Response, current_app, jsonify, render_template, request

from . import storage

bp = Blueprint("slideshow", __name__)


@dataclass
class Slide:
    title: str
    description: str
    image_url: str

    @classmethod
    def from_payload(cls, payload: dict[str, Any]) -> "Slide":
        return cls(
            title=str(payload.get("title", "")).strip(),
            description=str(payload.get("description", "")).strip(),
            image_url=str(payload.get("image_url", "")).strip(),
        )

    def to_dict(self) -> dict[str, str]:
        return {
            "title": self.title,
            "description": self.description,
            "image_url": self.image_url,
        }


def _data_dir() -> Path:
    return Path(current_app.config["DATA_DIR"])


@bp.get("/")
def index() -> str:
    slides = storage.load_slides(_data_dir())
    return render_template("index.html", slides=slides)


@bp.get("/admin")
def admin() -> str:
    slides = storage.load_slides(_data_dir())
    return render_template("admin.html", slides=slides)


@bp.get("/api/slides")
def api_get_slides() -> Response:
    slides = storage.load_slides(_data_dir())
    return jsonify({"slides": slides})


@bp.post("/api/slides")
def api_create_slide() -> tuple[Response, int]:
    payload = request.get_json(force=True, silent=True) or {}
    slide = Slide.from_payload(payload)

    if not slide.title:
        return jsonify({"error": "title is required"}), 400
    if not slide.image_url:
        return jsonify({"error": "image_url is required"}), 400

    slides = storage.load_slides(_data_dir())
    slides.append(slide.to_dict())
    storage.save_slides(_data_dir(), slides)

    return jsonify({"slides": slides}), 201


@bp.put("/api/slides/<int:index>")
def api_update_slide(index: int) -> tuple[Response, int]:
    payload = request.get_json(force=True, silent=True) or {}
    slide = Slide.from_payload(payload)

    slides = storage.load_slides(_data_dir())
    if index < 0 or index >= len(slides):
        return jsonify({"error": "slide not found"}), 404

    if not slide.title or not slide.image_url:
        return jsonify({"error": "title and image_url are required"}), 400

    slides[index] = slide.to_dict()
    storage.save_slides(_data_dir(), slides)
    return jsonify({"slides": slides}), 200


@bp.delete("/api/slides/<int:index>")
def api_delete_slide(index: int) -> tuple[Response, int]:
    slides = storage.load_slides(_data_dir())
    if index < 0 or index >= len(slides):
        return jsonify({"error": "slide not found"}), 404

    slides.pop(index)
    storage.save_slides(_data_dir(), slides)
    return jsonify({"slides": slides}), 200
