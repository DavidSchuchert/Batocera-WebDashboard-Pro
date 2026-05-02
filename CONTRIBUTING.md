# Contributing to Batocera Web Dashboard PRO

Thanks for your interest in improving the project! This guide covers
how to set up a dev environment, run the tests, and submit changes.

## Quick start

```bash
git clone https://github.com/DavidSchuchert/Batocera-WebDashboard-Pro.git
cd Batocera-WebDashboard-Pro

# Start the test environment (no real Batocera required)
docker compose -f docker-compose.test.yml up --build -d

# Open the running dashboard
open http://localhost:8091    # Remote mode (SSH-based)
open http://localhost:8092    # Native mode (direct filesystem)
```

You now have a fully functional dashboard talking to a mocked Batocera
container. See [TESTING.md](TESTING.md) for the full workflow.

## Project layout

```
.
├── server.py                    # Flask backend (Remote mode)
├── public/                      # Frontend (HTML/CSS/JS, vanilla, NES.css)
├── batocera-native/             # Native-mode variant (runs on Batocera)
├── tests/
│   ├── batocera-mock/           # Mock Debian+SSH container with fake /userdata
│   ├── run_tests.py             # 82 API tests (Python stdlib only)
│   └── e2e/                     # 22 Playwright browser tests
├── install.sh                   # Unified cross-platform installer
├── docker-compose.test.yml      # Test stack (mock + remote + native)
└── docker-compose.yml           # Production (remote only)
```

## Running the tests

Every PR must keep all tests green.

```bash
# API tests — fast, no extra dependencies
python3 tests/run_tests.py

# Or start the stack first if it isn't running
python3 tests/run_tests.py --start-stack --stop-after

# Browser tests (requires Node.js)
cd tests/e2e
npm install
npx playwright install chromium
npx playwright test
```

CI runs both suites on every push (see `.github/workflows/ci.yml`).

## Code style

- **Python** — PEP 8, no auto-formatter enforced. Keep functions small.
- **JavaScript** — Vanilla JS, no build step. 2-space indent.
- **CSS** — Use the CSS custom properties in `:root` (`--primary`,
  `--dark`, etc.) instead of hardcoding colours.
- **Comments** — only when the *why* isn't obvious from the code.

## Pull request flow

1. Fork the repo and create a feature branch from `main`:
   ```bash
   git checkout -b feature/my-improvement
   ```
2. Make your change. Keep it focused — one concern per PR.
3. Run the tests locally (both API and E2E if you touched the frontend).
4. Commit with a clear message:
   ```
   feat: add XYZ
   fix: resolve ABC

   Optional longer description.
   ```
5. Push and open a PR against `main`. The CI workflow will run automatically.
6. Address review feedback, then we merge.

## What to work on

- Check [open issues](https://github.com/DavidSchuchert/Batocera-WebDashboard-Pro/issues)
- Look for `good first issue` and `help wanted` labels
- Or propose something new — open an issue first if it's a larger change
  so we can align on the approach

## Reporting bugs

Use the bug-report issue template. Include:
- What you expected vs. what happened
- Mode (Remote / Native), Python version, OS
- Browser if it's a frontend issue
- Logs from `docker logs dashboard-remote` if applicable

## Reporting security issues

See [SECURITY.md](SECURITY.md) — please don't open public issues for
vulnerabilities.

---

Thanks again, and welcome aboard!
