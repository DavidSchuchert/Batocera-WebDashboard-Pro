# Changelog

All notable changes to this project are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
versioning follows [SemVer](https://semver.org/spec/v2.0.0.html).

---

## [2.0.0] — 2026-05-02

A major release focused on stability, security, and ease of use.
The project is now production-ready with a full automated test suite,
CI/CD, and a unified installer.

### Added

#### Unified installer
- New `install.sh` auto-detects OS (Batocera, macOS, Linux, WSL, Git Bash)
- New `install.bat` Windows wrapper (auto-detects WSL or Git Bash)
- Interactive guided setup explaining Remote vs Native mode
- Port conflict detection with auto-suggestion of free port
- Unattended mode via ENV vars or `--config` file
- Sub-commands: `--update`, `--status`, `--uninstall`
- **Native install can now be pushed from Mac/PC over SSH** — no need
  to run the script directly on the Batocera device. Auto-detects
  whether you're on Batocera (installs locally) or on another machine
  (asks for SSH credentials, copies files via SCP, runs install
  remotely, optionally starts the dashboard immediately).
- SSH control socket = one password prompt for the entire install
  (not one per `ssh` / `scp` call)

#### Update system
- `./install.sh --update` checks GitHub for new version, pulls + restarts
- v1.x installations are auto-detected and migrated on first run
- `.env` and SSH credentials preserved across updates
- Backups created before any migration (`backup-v1-YYYYMMDD-HHMMSS/`)

#### Test infrastructure
- `tests/batocera-mock/` — Debian + openssh container simulating a
  full Batocera filesystem (5 systems, 10 ROMs, gamelists with metadata,
  fake batocera-* commands)
- `tests/run_tests.py` — 82 automated API tests covering health,
  systems, ROM library, file browser, terminal, logs, security
- `tests/e2e/` — 22 Playwright browser tests across Remote, Native,
  and Mobile viewports
- `docker-compose.test.yml` orchestrates mock + remote + native dashboards
  on ports 2299, 8091, 8092
- `TESTING.md` documents the full test workflow

#### CI/CD
- GitHub Actions workflow (`.github/workflows/ci.yml`)
- Three jobs: `api-tests`, `e2e-tests`, `syntax-check`
- E2E tests upload Playwright HTML reports as artifacts
- Container logs uploaded automatically on failure

#### Documentation
- README rewritten with badges, feature table, screenshots, install one-liner
- `CHANGELOG.md`, `SECURITY.md`, `CONTRIBUTING.md`
- Issue and PR templates under `.github/`

### Changed

#### Performance
- SFTP connection pooling: thread-local clients, reused across requests
  (was: new SFTP per call — 5000 ROMs = 5000 connections)
- Gamelist parsing now cached in-memory with 5-minute TTL
- Cache invalidation on `batocera-settings-set` writes
- Flask response compression via `flask-compress` (when installed)
- Image responses send `Cache-Control: public, max-age=3600`

#### Frontend
- ROM library now paginates (default 100, max 500 per request) instead
  of dumping all 5000 ROMs into the DOM at once
- "Load more" button appears when more ROMs are available
- Search debounced at 300ms (was: one request per keystroke)
- Stats SSE stream auto-reconnects with exponential backoff (1s → 30s)
- Toast deduplicates repeated error messages
- Keyboard shortcuts: Esc closes modal, Ctrl+F focuses search

#### Mobile
- Sidebar collapses into a hamburger menu under 1024px
- Stats grid stacks to 1 column on mobile
- ROM grid switches to 140px (1024px) and 1 column (480px)
- Systems config layout stacks vertically on mobile
- Small action buttons (download/delete) get 44×44px touch targets
- File items wrap and word-break long filenames
- File upload now uses `<label>` element (works on iOS Safari, which
  blocks programmatic `.click()` on file inputs)

### Security

- **Path traversal blocked** in all four file endpoints (`list`,
  `download`, `delete`, `upload`) — paths outside `/userdata` return 403
- **Command allowlist** for terminal: blocks `rm -rf /`, `mkfs`,
  `dd if=`, fork bombs, `parted`, `fdisk`, etc.
- **Filename sanitisation** in upload (basename only — strips `../`)
- **XSS hardening** in file browser: filenames are HTML-escaped, paths
  are JS-escaped before being placed in `onclick` handlers
- **Local fallback CSS** for NES.css (no longer single-point-of-failure
  on CDN downtime)

### Fixed

- Native container's `gamelist.xml` was being shadowed by an empty
  named volume; volume removed (image already contains the data)
- Race condition in stats SSE stream when SSH dropped mid-connection
- `switchTab` JS used `classList.add` and `.remove` for the same class
  in the same call — replaced with `data-active` attribute
- Backwards-compatibility cleanup: removed `start.sh`,
  `batocera-native/install.sh`, `batocera-native/uninstall.sh` (all
  replaced by unified `install.sh`)

### Removed

- `start.sh` (replaced by `install.sh`)
- `batocera-native/install.sh` and `uninstall.sh` (unified into root `install.sh`)

---

## [1.0.0] — 2024

Initial public release.
