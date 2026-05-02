# Testing Guide — Batocera WebDashboard Pro

## Übersicht

Das Dashboard hat **zwei Betriebsmodi**, die beide testbar sind:

| Modus | Beschreibung | Port |
|-------|-------------|------|
| **Remote** | Läuft auf einem externen Gerät (z.B. Mac), verbindet sich per SSH zu Batocera | `8081` |
| **Native** | Läuft direkt auf der Batocera-Maschine, liest Dateien lokal | `8082` |

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
# Alle Container bauen und starten
docker compose -f docker-compose.test.yml up --build

# Nur einzelnen Modus starten
docker compose -f docker-compose.test.yml up --build dashboard-remote
docker compose -f docker-compose.test.yml up --build dashboard-native
```

### Erreichbare Services nach dem Start:

| Service | URL | Was testen |
|---------|-----|-----------|
| Remote-Dashboard | http://localhost:8081 | Vollständige SSH-basierte Verbindung |
| Native-Dashboard | http://localhost:8082 | Direkter Dateizugriff |
| Mock SSH direkt | `ssh root@localhost -p 2299` (PW: `linux`) | Mock-Filesystem prüfen |

---

## Manuelle Test-Checkliste

### Remote-Modus (http://localhost:8081)

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

### Native-Modus (http://localhost:8082)

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
