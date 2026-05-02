# Testing Guide — Batocera WebDashboard Pro

## Übersicht

Das Dashboard hat **zwei Betriebsmodi**, die beide testbar sind:

| Modus | Beschreibung | Port |
|-------|-------------|------|
| **Remote** | Läuft auf einem externen Gerät (z.B. Mac), verbindet sich per SSH zu Batocera | `8091` |
| **Native** | Läuft direkt auf der Batocera-Maschine, liest Dateien lokal | `8092` |

Für Tests wird kein echtes Batocera-System benötigt — ein Mock-Container simuliert die Batocera-Umgebung vollständig.

---

## Projektstruktur

```
Batocera-WebDashboard-Pro/
│
├── server.py                    # Remote-Server (Flask + paramiko SSH)
├── Dockerfile                   # Docker-Image für Remote-Modus
├── requirements.txt             # Python-Abhängigkeiten (Flask, paramiko, ...)
├── public/                      # Frontend (HTML/CSS/JS)
│   ├── index.html
│   ├── js/app.js                # Haupt-Frontend-Logik
│   ├── js/systems.js            # System-Konfiguration
│   └── css/main.css
│
├── batocera-native/             # Native-Modus (läuft auf Batocera selbst)
│   ├── server.py                # Liest /proc, /userdata/ direkt — kein SSH
│   ├── Dockerfile               # Docker-Image für Native-Modus
│   ├── public/                  # Eigenes Frontend (leicht abweichend)
│   ├── install.sh               # Installations-Script für echtes Batocera
│   └── uninstall.sh
│
├── tests/
│   └── batocera-mock/           # Mock-Container der Batocera simuliert
│       ├── Dockerfile           # Debian + openssh-server + fake filesystem
│       └── roms/
│           ├── snes/gamelist.xml
│           └── nes/gamelist.xml
│
├── docker-compose.test.yml      # Test-Umgebung (alle 3 Container)
├── docker-compose.yml           # Produktion (nur Remote-Modus)
└── TESTING.md                   # Diese Datei
```

---

## Was der Mock simuliert

Der `batocera-mock`-Container ist ein Debian-Container mit:

- **SSH-Server** auf Port `22` (intern) / `2299` (Host)
  - User: `root`, Passwort: `linux`
- **Fake-Filesystem:**
  ```
  /userdata/roms/snes/     → SuperMarioWorld.sfc, DonkeyKongCountry.sfc, Zelda.sfc
  /userdata/roms/nes/      → SuperMarioBros.nes, Contra.nes, Castlevania.nes
  /userdata/roms/gba/      → PokemonFireRed.gba, MetroidFusion.gba
  /userdata/roms/n64/      → MarioKart64.z64
  /userdata/roms/psx/      → FinalFantasy7.chd
  /userdata/system/batocera.conf
  /userdata/system/logs/emulationstation.log
  /sys/class/thermal/thermal_zone0/temp  → 55000 (= 55°C)
  ```
- **Gamelist-Metadaten** in `gamelist.xml` für snes + nes (Name, Developer, Beschreibung)
- **Fake-Batocera-Befehle:** `batocera-version`, `batocera-settings-set`, `batocera-save-overlay`, `batocera-audio`
- **Echte `/proc/stat` und `/proc/meminfo`** (vom Container-OS) → CPU/RAM-Stats sind real

---

## Test-Umgebung starten

```bash
# Alle Container bauen und starten (im Hintergrund)
docker compose -f docker-compose.test.yml up --build -d

# Nur einzelnen Modus starten
docker compose -f docker-compose.test.yml up --build -d dashboard-remote
docker compose -f docker-compose.test.yml up --build -d dashboard-native

# Container stoppen
docker compose -f docker-compose.test.yml down
```

### Erreichbare Services nach dem Start:

| Service | URL | Was testen |
|---------|-----|-----------|
| Remote-Dashboard | http://localhost:8091 | Vollständige SSH-basierte Verbindung |
| Native-Dashboard | http://localhost:8092 | Direkter Dateizugriff |
| Mock SSH direkt | `ssh root@localhost -p 2299` (PW: `linux`) | Mock-Filesystem prüfen |

> **Hinweis:** Der Native-Server läuft intern auf Port 8989 (hardcoded in `batocera-native/server.py`).
> Das Mapping `8092:8989` im Compose-File macht ihn auf Port 8092 erreichbar.

---

## Automatische Tests

Das Test-Script `tests/run_tests.py` prüft alle API-Endpunkte beider Modi automatisch.

### Voraussetzungen

- Python 3.8+ (kein Install nötig — nur stdlib)
- Laufende Container (Stack muss vorher gestartet sein)
- Optional: `sshpass` für SSH-Tests (`brew install sshpass` auf Mac)

### Tests ausführen

```bash
# Stack starten + Tests + Stack stoppen (alles in einem)
docker compose -f docker-compose.test.yml up --build -d
python3 tests/run_tests.py
docker compose -f docker-compose.test.yml down

# Oder: Tests + automatischer Stopp
python3 tests/run_tests.py --stop-after

# Stack automatisch starten, testen und stoppen
python3 tests/run_tests.py --start-stack --stop-after

# Nur einen Modus testen
python3 tests/run_tests.py --remote-only
python3 tests/run_tests.py --native-only
```

### Was getestet wird

| Test | Beschreibung |
|------|-------------|
| Health / SSH-Status | Remote ist mit Mock verbunden |
| Systeme-Liste | snes, nes, gba, n64, psx vorhanden |
| ROMs laden | Spielliste erscheint mit Metadaten aus gamelist.xml |
| Datei-Browser | /userdata-Listing funktioniert |
| Logs | EmulationStation-Log lesbar |
| Batocera-Version | `batocera-linux 40 (20240101)` |
| Settings | Host/User-Felder vorhanden |
| Native Health | Mode = "native" |
| Native ROMs | Metadaten aus gamelist.xml korrekt |
| SSH-Mock | Port 2299 erreichbar, Filesystem sichtbar |

### Beispiel-Ausgabe

```
Batocera WebDashboard Pro — Automated Tests
Remote: http://localhost:8091  |  Native: http://localhost:8092

Remote Mode (http://localhost:8091)
  [PASS] Health endpoint returns 200
  [PASS] SSH status is 'connected'
  [PASS] SNES ROMs list is non-empty — got 3 ROMs
  [PASS] ROM developer not 'Unknown' — dev=Nintendo
  ...

Results: 34/34 passed  All tests passed!
```

---

## Manuelle Test-Checkliste

### Remote-Modus (http://localhost:8091)

- [ ] **Dashboard lädt** — Batocera-Version, CPU%, RAM%, Temperatur sichtbar
- [ ] **ROM-Bibliothek** — Alle 5 Systeme (snes, nes, gba, n64, psx) erscheinen im Dropdown
- [ ] **ROM laden** → System wählen → Spielliste erscheint mit Namen aus gamelist.xml
- [ ] **Suchfunktion** → "mario" eingeben → nur Mario-Spiele
- [ ] **Game-Modal** → ROM anklicken → Popup mit Name, Developer, Beschreibung
- [ ] **Datei-Browser** → `/userdata` navigieren → Ordner und Dateien sichtbar
- [ ] **Terminal** → Befehl eingeben (z.B. `ls /userdata/roms`) → Ausgabe erscheint
- [ ] **Logs** → Log-Typ wechseln → Inhalt erscheint
- [ ] **SSH-Status** → Oben rechts zeigt "Connected"
- [ ] **Settings** → Host/User/Pass anzeigen (kein echtes Passwort sichtbar)
- [ ] **Controls** → Vol+/Vol-/Reboot/Shutdown Buttons vorhanden (Reboot/Shutdown **nicht** klicken im Test)

### Native-Modus (http://localhost:8092)

- [ ] **Dashboard lädt** — Settings-Tab nicht sichtbar (kein SSH-Setup nötig)
- [ ] **ROM-Bibliothek** — Systeme aus `/userdata/roms/` werden geladen
- [ ] **Stats-Stream** — CPU/RAM/Temp aktualisieren sich alle 2 Sekunden
- [ ] **Batocera-Version** — Zeigt "batocera-linux 40 (20240101)"

---

## API-Endpunkte (Remote-Server)

| Methode | Pfad | Beschreibung |
|---------|------|-------------|
| GET | `/health` | SSH-Verbindungsstatus |
| GET | `/api/stats/stream` | SSE-Stream: CPU, RAM, Temp (alle 2s) |
| GET | `/api/systems` | Liste aller ROM-Ordner |
| GET | `/api/roms?system=snes` | ROMs eines Systems mit Metadaten |
| GET | `/api/media?path=/userdata/...` | Bild-Datei über SFTP |
| GET | `/api/status` | Uptime + Disk-Nutzung |
| GET | `/api/status/system` | Batocera-Version |
| GET | `/api/logs?type=es` | Logs (es, boot, syslog) |
| POST | `/api/command` | SSH-Befehl ausführen (body: `{"cmd": "..."}`) |
| GET | `/api/files/list?dir=/userdata` | Verzeichnis-Listing |
| POST | `/api/files/delete` | Datei löschen (body: `{"path": "..."}`) |
| POST | `/api/files/upload` | Datei hochladen (multipart) |
| GET | `/api/files/download?path=...` | Datei herunterladen |
| GET | `/api/settings` | SSH-Zugangsdaten anzeigen |
| POST | `/api/settings` | SSH-Zugangsdaten speichern |
| GET | `/api/systems/<system>` | batocera.conf-Settings für System |
| POST | `/api/systems/<system>` | Settings schreiben |
| POST | `/api/system/control` | Action: stop-game, volume-up/down, reboot, shutdown |

---

## Umgebungsvariablen (Remote-Modus)

| Variable | Standard | Beschreibung |
|----------|----------|-------------|
| `BATOCERA_HOST` | `192.168.1.100` | IP/Hostname der Batocera-Maschine |
| `BATOCERA_PORT` | `22` | SSH-Port |
| `BATOCERA_USER` | `root` | SSH-Benutzer |
| `BATOCERA_PASS` | `linux` | SSH-Passwort |
| `PORT` | `8080` | Web-Server-Port |

Für die Test-Umgebung sind diese bereits in `docker-compose.test.yml` gesetzt (`BATOCERA_HOST=batocera-mock`).

---

## Bekannte Einschränkungen im Test

- **Cover-Bilder:** Die Mock-ROMs haben keine echten Bilder — der Placeholder `🎮` erscheint statt Covers (erwartetes Verhalten)
- **Reboot/Shutdown:** Funktionieren im Mock-Container (`batocera-mock` startet neu / fährt herunter) — **nicht im Test klicken**
- **GameLauncher:** Es kann kein Spiel wirklich gestartet werden, `retroarch` ist nicht installiert
- **Batocera.conf schreiben:** Funktioniert im Mock, Änderungen verschwinden beim Container-Neustart

---

## Branch-Strategie

- `main` — Produktions-Branch
- `feature/fixes-and-tests` — Aktueller Entwicklungs-Branch (Security-Fixes + Test-Setup)

Vor einem Merge nach `main`:
1. Alle Punkte der manuellen Checkliste durchgehen
2. `python3 -m py_compile server.py` — keine Syntax-Fehler
3. Beide Modi (Remote + Native) müssen sauber starten
