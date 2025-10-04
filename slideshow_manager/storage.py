"""Persistence helpers for device metadata."""
from __future__ import annotations

import json
import threading
import uuid
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Dict, Iterable, List, Optional


@dataclass
class Device:
    """Represents a remote slideshow device."""

    id: str
    name: str
    base_url: str
    username: str
    password: str
    notes: str | None = None
    tags: List[str] = field(default_factory=list)

    def to_dict(self) -> Dict[str, object]:
        payload = asdict(self)
        if self.notes is None:
            payload["notes"] = ""
        return payload

    @classmethod
    def from_dict(cls, data: Dict[str, object]) -> "Device":
        return cls(
            id=str(data.get("id")),
            name=str(data.get("name", "")),
            base_url=str(data.get("base_url", "")),
            username=str(data.get("username", "")),
            password=str(data.get("password", "")),
            notes=(str(data["notes"]) if data.get("notes") else None),
            tags=list(data.get("tags", [])),
        )


class DeviceStorage:
    """Simple JSON backed storage for devices."""

    def __init__(self, path: str) -> None:
        self.path = Path(path)
        self._lock = threading.Lock()
        self.path.parent.mkdir(parents=True, exist_ok=True)
        if not self.path.exists():
            self._write([])

    def _read(self) -> List[Dict[str, object]]:
        with self.path.open("r", encoding="utf-8") as handle:
            return json.load(handle)

    def _write(self, data: Iterable[Dict[str, object]]) -> None:
        tmp_path = self.path.with_suffix(".tmp")
        with tmp_path.open("w", encoding="utf-8") as handle:
            json.dump(list(data), handle, indent=2, ensure_ascii=False)
        tmp_path.replace(self.path)

    def list_devices(self) -> List[Device]:
        with self._lock:
            return [Device.from_dict(item) for item in self._read()]

    def get(self, device_id: str) -> Optional[Device]:
        with self._lock:
            for item in self._read():
                if str(item.get("id")) == device_id:
                    return Device.from_dict(item)
        return None

    def add(self, data: Dict[str, object]) -> Device:
        with self._lock:
            devices = self._read()
            new_device = Device(
                id=uuid.uuid4().hex,
                name=str(data.get("name", "")).strip(),
                base_url=str(data.get("base_url", "")).strip(),
                username=str(data.get("username", "")).strip(),
                password=str(data.get("password", "")),
                notes=(str(data["notes"]).strip() if data.get("notes") else None),
                tags=[tag.strip() for tag in data.get("tags", []) if tag.strip()],
            )
            devices.append(new_device.to_dict())
            self._write(devices)
        return new_device

    def update(self, device_id: str, updates: Dict[str, object]) -> Optional[Device]:
        with self._lock:
            devices = self._read()
            updated_device: Optional[Device] = None
            for index, item in enumerate(devices):
                if str(item.get("id")) == device_id:
                    merged = {**item, **updates}
                    merged["id"] = item.get("id")
                    merged["tags"] = [tag.strip() for tag in merged.get("tags", []) if tag]
                    devices[index] = merged
                    updated_device = Device.from_dict(merged)
                    break
            if updated_device:
                self._write(devices)
            return updated_device

    def delete(self, device_id: str) -> bool:
        with self._lock:
            devices = self._read()
            filtered = [item for item in devices if str(item.get("id")) != device_id]
            if len(filtered) == len(devices):
                return False
            self._write(filtered)
            return True
