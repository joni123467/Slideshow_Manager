# Slideshow Manager (Flask)

Der Slideshow Manager ist eine leichtgewichtige Flask-Anwendung, mit der du Präsentationen im Browser verwaltest und abspielst. Eine Administrationsoberfläche erlaubt das Anlegen, Bearbeiten und Löschen von Slides. Die Daten werden als JSON-Datei gespeichert und können dadurch unkompliziert gesichert oder angepasst werden.

## Funktionsumfang

- Präsentationsansicht mit Tastatur- und Buttonsteuerung
- Administrationsbereich zum Hinzufügen, Bearbeiten und Entfernen von Slides
- REST-API (`/api/slides`) für Integrationen oder Automatisierungen
- JSON-basierter Datenspeicher (Standard: `data/slides.json`)
- Produktionsbetrieb über Gunicorn und `systemd`

## Schnellstart (Entwicklung)

1. **Abhängigkeiten installieren**

   ```bash
   python3 -m venv .venv
   source .venv/bin/activate
   pip install --upgrade pip
   pip install -r requirements.txt
   ```

2. **Entwicklungsserver starten**

   ```bash
   python -m slideshow_manager
   ```

   Die Anwendung läuft anschließend unter <http://localhost:8000>. Der Admin-Bereich ist unter <http://localhost:8000/admin> erreichbar.

## Installation per Installer-Skript

Für produktive Deployments liegt unter `scripts/install.sh` ein Installer, der alle erforderlichen Pakete nachzieht, das Repository nach `/opt/Slideshow_Manager` synchronisiert, eine virtuelle Python-Umgebung einrichtet und einen `systemd`-Dienst konfiguriert.

### Remote-Installation via `wget`

```bash
wget -O install.sh https://raw.githubusercontent.com/joni123467/Slideshow_Manager/main/scripts/install.sh
chmod +x install.sh
sudo ./install.sh
```

Standardmäßig wird der `main`-Branch des Repositories `joni123467/Slideshow_Manager` verwendet. Mit `./install.sh --help` erhältst du eine Übersicht der verfügbaren Optionen (z. B. `--branch`, `--repo`, `--service-user`, `--install-dir`). Zusätzlich stehen die folgenden Umgebungsvariablen zur Verfügung:

- `SLIDESHOW_MANAGER_REPO` – alternatives Git-Remote (z. B. eigener Fork)
- `SLIDESHOW_MANAGER_BRANCH` – Branch oder Tag, der installiert werden soll
- `SLIDESHOW_MANAGER_SERVICE_USER` – Benutzerkonto, unter dem der Dienst laufen soll (Standard: `slideshow`)

### Was der Installer erledigt

- Erkennen eines unterstützten Paketmanagers (`apt`, `dnf`, `yum`, `pacman`, `zypper`)
- Installation von `python3`, `python3-venv`, `python3-pip`, `git`, `curl`, `wget` und `tar`
- Clonen (oder Herunterladen) des Quellcodes in `/opt/Slideshow_Manager`
- Aufbau einer virtuellen Umgebung unter `/opt/Slideshow_Manager/.venv`
- Installation der Python-Abhängigkeiten aus `requirements.txt`
- Initialisierung einer Beispieldatenbank (`data/slides.json`)
- Anlegen eines dedizierten Systembenutzers (`slideshow`), Besitzrechte setzen
- Erstellen eines `systemd`-Dienstes `slideshow-manager.service`, der Gunicorn auf Port 8000 startet

Nach erfolgreicher Installation erreichst du die Anwendung unter `http://<server>:8000`.

### Dienststeuerung

```bash
sudo systemctl status slideshow-manager.service
sudo systemctl restart slideshow-manager.service
sudo systemctl stop slideshow-manager.service
```

## Updates

Mit `scripts/update.sh` aktualisierst du eine bestehende Installation. Das Skript lädt den gewünschten Branch erneut herunter, installiert geänderte Python-Abhängigkeiten und startet den `systemd`-Dienst anschließend neu.

```bash
sudo /opt/Slideshow_Manager/scripts/update.sh
```

Auch hier kannst du `SLIDESHOW_MANAGER_REPO` und `SLIDESHOW_MANAGER_BRANCH` setzen, um beispielsweise auf einen bestimmten Release-Branch zu wechseln.

## Dateistruktur

```
slideshow_manager/
├── __init__.py          # Flask App Factory
├── __main__.py          # Einstiegspunkt für python -m slideshow_manager
├── storage.py           # JSON Speicher-Utility
├── templates/           # Jinja2-Templates für Präsentation & Admin
└── static/              # CSS- und JS-Dateien
scripts/
├── install.sh           # Installer inkl. dependency bootstrap
├── update.sh            # Updater für bestehende Installationen
└── start-service.sh     # Startkommando für systemd / Gunicorn
requirements.txt         # Python-Abhängigkeiten
```

## Entwicklung & Tests

Für automatisierte Tests kannst du beispielsweise `pytest` nutzen. Ein minimales Setup könnte so aussehen:

```bash
pip install pytest
pytest
```

(Tests sind im Repository nicht enthalten und können nach Bedarf ergänzt werden.)

## Lizenz

MIT
