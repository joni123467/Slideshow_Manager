# Slideshow Manager Dashboard

Der Slideshow Manager stellt ein webbasiertes Cockpit bereit, um mehrere Raspberry-Pi-Player mit der vorhandenen Slideshow-REST-API zentral zu überwachen und zu steuern. Statt einer eigenen Präsentationslogik konzentriert sich die Anwendung vollständig auf Geräteverwaltung, Statusüberwachung und die Fernsteuerung der bereits installierten Slideshow-App.

## Funktionsumfang

- **Geräteübersicht**: Dashboard mit allen hinterlegten Playern, aktuellem Status, Quelle und Vorschaubild.
- **Detailansicht**: Einsicht in Gerätekonfiguration, Playback-Parameter und verfügbare Quellen.
- **Player-Steuerung**: Start, Stop, Reload sowie Schalten des Infobildschirms und Anpassen zentraler Wiedergabeeinstellungen.
- **Quellenverwaltung**: SMB-Quellen anlegen, bearbeiten oder löschen – soweit von der Slideshow-REST-API unterstützt.
- **Linux-Authentifizierung**: Zugriff auf das Dashboard erfolgt über eine PAM-gestützte Anmeldung mit bestehenden Systemkonten (optional auf statische Nutzer für Tests umstellbar).
- **Systemd-Service**: Die Installation richtet einen Gunicorn-Dienst ein, damit das Dashboard nach dem Booten automatisch startet.

## Architekturüberblick

- Flask-Anwendung mit klassischem Server-Side-Rendering (Jinja2).
- JSON-basierte Geräteverwaltung (`slideshow_manager/data/devices.json`).
- HTTP-Kommunikation mit den Slideshow-Playern über `requests` und die veröffentlichte REST-API.
- Authentifizierung über `python-pam` (Produktivbetrieb) oder einen statischen Test-Authenticator (`AUTH_MODE=static`).
- Bereitstellung via Gunicorn hinter einem systemd-Dienst (`slideshow-manager.service`).

## Lokale Entwicklung

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt
export FLASK_ENV=development
export AUTH_MODE=static
export TEST_USERS='{"tester": "secret"}'
python -m slideshow_manager
```

Die Anwendung lauscht standardmäßig auf `http://127.0.0.1:5000`. Mit `AUTH_MODE=static` kannst du dich mit Benutzer `tester` und Passwort `secret` anmelden, ohne PAM zu benötigen.

### Tests

```bash
source .venv/bin/activate
pytest
```

Die Tests simulieren die externe REST-API mithilfe der Bibliothek [`responses`](https://github.com/getsentry/responses).

## Produktion: Installer & Dienstbetrieb

Ein Installer-Skript übernimmt alle notwendigen Schritte auf einem Zielsystem (z. B. Debian, Ubuntu, Fedora, openSUSE, Arch): Paketabhängigkeiten, Quellcode-Synchronisation, Python-Virtualenv, Konfiguration sowie systemd-Dienst.

### Schnellinstallation per `wget`

```bash
wget -O install.sh https://raw.githubusercontent.com/joni123467/Slideshow_Manager/main/scripts/install.sh
chmod +x install.sh
sudo ./install.sh
```

Standardwerte:

- Installationspfad: `/opt/Slideshow_Manager`
- Dienstname: `slideshow-manager.service`
- Dienstnutzer: `slideshowmgr`
- HTTP-Port: `5000`
- Repository: `https://github.com/joni123467/Slideshow_Manager`
- Branch: `main`

Über Umgebungsvariablen lassen sich diese Werte anpassen:

| Variable | Beschreibung |
| --- | --- |
| `SLIDESHOW_MANAGER_DEFAULT_REPO` | Alternatives Git-Remote oder eigener Fork |
| `SLIDESHOW_MANAGER_BRANCH` | Branch oder Tag, der deployt werden soll |
| `SLIDESHOW_MANAGER_USER` | Dienstnutzer (Standard `slideshowmgr`) |
| `SLIDESHOW_MANAGER_PORT` | Wird in `/etc/slideshow-manager.env` gesetzt, um den Gunicorn-Port zu ändern |

Während der Installation wird – falls nicht vorhanden – die Datei `/etc/slideshow-manager.env` angelegt. Dort liegen sensible Konfigurationswerte wie das Flask-`SECRET_KEY` und optionale Anpassungen (Port, Worker-Anzahl, Log-Level). Diese Datei wird vom systemd-Dienst automatisch eingelesen.

### Dienstverwaltung

```bash
sudo systemctl status slideshow-manager.service
sudo systemctl restart slideshow-manager.service
sudo journalctl -u slideshow-manager.service -f
```

## Updates

Für Aktualisierungen steht `scripts/update.sh` bereit. Das Skript lädt den gewünschten Branch erneut, synchronisiert den Inhalt nach `/opt/Slideshow_Manager/current`, installiert geänderte Python-Abhängigkeiten in der bestehenden virtuellen Umgebung und startet den Dienst neu.

```bash
sudo /opt/Slideshow_Manager/current/scripts/update.sh
```

Auch hier kannst du die Umgebungsvariablen `SLIDESHOW_MANAGER_DEFAULT_REPO` und `SLIDESHOW_MANAGER_BRANCH` setzen, um auf andere Branches oder Forks zu wechseln.

## Interaktion mit der Slideshow-REST-API

Jede Geräteaktion erfolgt über die in der Aufgabenstellung beschriebenen Endpunkte:

- `GET /api/state` für Status- und Vorschaudaten
- `GET /api/config` für Playback- und Netzwerkeinstellungen
- `POST /api/player/<action>` (`start`, `stop`, `reload`)
- `POST /api/player/info-screen` zum Aktivieren/Deaktivieren des Infobildschirms
- `PUT /api/playback` zur Anpassung von Wiedergabeparametern
- `GET/POST/PUT/DELETE /api/sources` für SMB-Quellen

Die Anwendung meldet sich für jeden Aufruf beim Player via `POST /login` an und verwaltet die Session-Cookies pro Request. Fehlermeldungen der Geräte werden im Dashboard sichtbar gemacht.

## Verzeichnisstruktur

```
slideshow_manager/
├── __init__.py        # Flask App Factory
├── __main__.py        # Einstieg für python -m slideshow_manager
├── auth.py            # PAM-Authentifizierung & Login-Routen
├── clients.py         # REST-Client für die Slideshow-Geräte
├── storage.py         # JSON-basierte Geräteverwaltung
├── views.py           # Dashboard- und Geräte-Routen
├── templates/         # Jinja2-Templates
└── static/            # CSS-Assets
scripts/
├── install.sh         # Installer (Dependencies + systemd)
├── update.sh          # Updater
└── start-service.sh   # Startkommando für Gunicorn
requirements.txt       # Python-Abhängigkeiten
pytest.ini             # Pytest-Konfiguration
```

## Sicherheitshinweise

- Gerätelogins werden im Klartext in `devices.json` gespeichert. Stelle sicher, dass der Host abgesichert und der Zugriff auf das Dashboard eingeschränkt ist.
- Für produktive Deployments empfiehlt sich ein vorgeschalteter Reverse-Proxy (z. B. Nginx) mit TLS-Termination.
- Die PAM-Authentifizierung benötigt das Paket `python-pam`. Auf Systemen ohne PAM-Unterstützung kann vorübergehend `AUTH_MODE=static` mit Testnutzer verwendet werden.

Viel Erfolg beim zentralen Steuern deiner Slideshow-Geräte!
