"""Dashboard and device management views."""
from __future__ import annotations

from typing import Any, Callable, Dict, Optional

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

from .auth import login_required
from .clients import RemoteAPIError, RemoteDevice, SlideshowClient
from .storage import Device


bp = Blueprint("dashboard", __name__)


@bp.before_app_request
def _load_logged_in_user() -> None:
    g.user = session.get("user_id")


def _client_from_device(device: Device) -> SlideshowClient:
    remote = RemoteDevice(device.base_url, device.username, device.password)
    timeout = int(current_app.config.get("REMOTE_TIMEOUT", 8))
    return SlideshowClient(remote, timeout=timeout)


@bp.route("/")
@login_required
def index() -> Response:
    storage = current_app.storage  # type: ignore[attr-defined]
    devices = storage.list_devices()
    summaries: list[dict[str, Any]] = []
    for device in devices:
        summary: Dict[str, Any] = {"device": device, "state": None, "error": None}
        try:
            client = _client_from_device(device)
            summary["state"] = client.get_state()
        except RemoteAPIError as exc:
            summary["error"] = str(exc)
        summaries.append(summary)
    return render_template("dashboard.html", summaries=summaries)


@bp.route("/devices")
@login_required
def devices() -> Response:
    storage = current_app.storage  # type: ignore[attr-defined]
    return render_template("devices/list.html", devices=storage.list_devices())


@bp.route("/devices/new", methods=["GET", "POST"])
@login_required
def device_create() -> Response:
    if request.method == "POST":
        form = request.form
        required = [form.get("name", "").strip(), form.get("base_url", "").strip(), form.get("username", "").strip()]
        if not all(required):
            flash("Name, Basis-URL und Benutzername sind erforderlich.", "danger")
        else:
            storage = current_app.storage  # type: ignore[attr-defined]
            storage.add(
                {
                    "name": form.get("name"),
                    "base_url": form.get("base_url"),
                    "username": form.get("username"),
                    "password": form.get("password", ""),
                    "notes": form.get("notes", ""),
                    "tags": [tag.strip() for tag in form.get("tags", "").split(",") if tag.strip()],
                }
            )
            flash("Gerät hinzugefügt.", "success")
            return redirect(url_for("dashboard.devices"))
    return render_template("devices/form.html", device=None)


@bp.route("/devices/<device_id>/edit", methods=["GET", "POST"])
@login_required
def device_edit(device_id: str) -> Response:
    storage = current_app.storage  # type: ignore[attr-defined]
    device = storage.get(device_id)
    if not device:
        flash("Gerät nicht gefunden.", "danger")
        return redirect(url_for("dashboard.devices"))

    if request.method == "POST":
        form = request.form
        updates = {
            "name": form.get("name", device.name),
            "base_url": form.get("base_url", device.base_url),
            "username": form.get("username", device.username),
            "password": form.get("password", device.password),
            "notes": form.get("notes", ""),
            "tags": [tag.strip() for tag in form.get("tags", "").split(",") if tag.strip()],
        }
        storage.update(device_id, updates)
        flash("Gerät aktualisiert.", "success")
        return redirect(url_for("dashboard.devices"))

    tag_value = ", ".join(device.tags)
    return render_template("devices/form.html", device=device, tag_value=tag_value)


@bp.route("/devices/<device_id>/delete", methods=["POST"])
@login_required
def device_delete(device_id: str) -> Response:
    storage = current_app.storage  # type: ignore[attr-defined]
    if storage.delete(device_id):
        flash("Gerät gelöscht.", "info")
    else:
        flash("Gerät konnte nicht gelöscht werden.", "danger")
    return redirect(url_for("dashboard.devices"))


@bp.route("/devices/<device_id>")
@login_required
def device_detail(device_id: str) -> Response:
    storage = current_app.storage  # type: ignore[attr-defined]
    device = storage.get(device_id)
    if not device:
        flash("Gerät nicht gefunden.", "danger")
        return redirect(url_for("dashboard.devices"))

    state: Optional[Dict[str, Any]] = None
    config: Optional[Dict[str, Any]] = None
    sources: Optional[Dict[str, Any]] = None
    errors: list[str] = []

    try:
        client = _client_from_device(device)
        state = client.get_state()
        config = client.get_config()
        sources = client.list_sources()
    except RemoteAPIError as exc:
        errors.append(str(exc))

    return render_template(
        "devices/detail.html",
        device=device,
        state=state,
        config=config,
        sources=sources,
        errors=errors,
    )


@bp.route("/devices/<device_id>/player", methods=["POST"])
@login_required
def device_player(device_id: str) -> Response:
    action = request.form.get("action")
    if action not in {"start", "stop", "reload"}:
        flash("Unbekannte Aktion.", "danger")
        return redirect(url_for("dashboard.device_detail", device_id=device_id))

    return _invoke_device_action(device_id, lambda client: client.trigger_player_action(action))


@bp.route("/devices/<device_id>/info-screen", methods=["POST"])
@login_required
def device_info_screen(device_id: str) -> Response:
    enabled = request.form.get("enabled") == "true"
    return _invoke_device_action(device_id, lambda client: client.toggle_info_screen(enabled))


@bp.route("/devices/<device_id>/playback", methods=["POST"])
@login_required
def device_playback(device_id: str) -> Response:
    payload = {
        "image_duration": _safe_int(request.form.get("image_duration")),
        "transition_type": request.form.get("transition_type"),
        "transition_duration": _safe_float(request.form.get("transition_duration")),
        "image_fit": request.form.get("image_fit"),
        "image_rotation": _safe_int(request.form.get("image_rotation")),
    }
    cleaned = {key: value for key, value in payload.items() if value not in {None, ""}}
    return _invoke_device_action(device_id, lambda client: client.set_playback(cleaned))


@bp.route("/devices/<device_id>/sources", methods=["POST"])
@login_required
def device_sources_create(device_id: str) -> Response:
    payload = {
        "name": request.form.get("name"),
        "server": request.form.get("server"),
        "share": request.form.get("share"),
        "smb_path": request.form.get("smb_path"),
        "username": request.form.get("source_username"),
        "password": request.form.get("source_password"),
        "domain": request.form.get("domain"),
        "subpath": request.form.get("subpath"),
        "auto_scan": request.form.get("auto_scan") == "on",
    }
    cleaned = {key: value for key, value in payload.items() if value not in {None, ""}}
    return _invoke_device_action(device_id, lambda client: client.create_source(cleaned))


@bp.route("/devices/<device_id>/sources/<name>/update", methods=["POST"])
@login_required
def device_sources_update(device_id: str, name: str) -> Response:
    payload = {
        "name": request.form.get("name") or name,
        "smb_path": request.form.get("smb_path"),
        "username": request.form.get("source_username"),
        "password": request.form.get("source_password"),
        "domain": request.form.get("domain"),
        "subpath": request.form.get("subpath"),
        "auto_scan": request.form.get("auto_scan") == "on",
    }
    cleaned = {key: value for key, value in payload.items() if value not in {None, ""}}
    cleaned.setdefault("name", name)
    return _invoke_device_action(device_id, lambda client: client.update_source(name, cleaned))


@bp.route("/devices/<device_id>/sources/<name>/delete", methods=["POST"])
@login_required
def device_sources_delete(device_id: str, name: str) -> Response:
    return _invoke_device_action(device_id, lambda client: client.delete_source(name))


@bp.route("/devices/<device_id>/preview")
@login_required
def device_preview(device_id: str) -> Response:
    storage = current_app.storage  # type: ignore[attr-defined]
    device = storage.get(device_id)
    if not device:
        flash("Gerät nicht gefunden.", "danger")
        return redirect(url_for("dashboard.index"))

    source = request.args.get("source")
    media_path = request.args.get("path")
    if not source or not media_path:
        flash("Vorschau-Parameter fehlen.", "warning")
        return redirect(url_for("dashboard.device_detail", device_id=device_id))

    try:
        client = _client_from_device(device)
        content = client.fetch_preview(source, media_path)
    except RemoteAPIError as exc:
        flash(str(exc), "danger")
        return redirect(url_for("dashboard.device_detail", device_id=device_id))
    return Response(content, mimetype="image/jpeg")


def _invoke_device_action(device_id: str, func: Callable[[SlideshowClient], Any]) -> Response:
    storage = current_app.storage  # type: ignore[attr-defined]
    device = storage.get(device_id)
    if not device:
        flash("Gerät nicht gefunden.", "danger")
        return redirect(url_for("dashboard.devices"))

    try:
        client = _client_from_device(device)
        func(client)
        flash("Aktion erfolgreich.", "success")
    except RemoteAPIError as exc:
        flash(str(exc), "danger")
    return redirect(url_for("dashboard.device_detail", device_id=device_id))


def _safe_int(value: Optional[str]) -> Optional[int]:
    try:
        return int(value) if value else None
    except (TypeError, ValueError):
        return None


def _safe_float(value: Optional[str]) -> Optional[float]:
    try:
        return float(value) if value else None
    except (TypeError, ValueError):
        return None
