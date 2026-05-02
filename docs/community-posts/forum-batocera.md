# Batocera Forum post

**Suggested category:** Show & Tell / Projects
**Title:** [Release] Batocera Web Dashboard PRO 2.0 — manage your Batocera from any browser

---

Hi everyone 👋

I've been working on a web dashboard for Batocera and just released **v2.0**. Sharing it here in case it's useful to anyone.

## What it is

A retro-styled web dashboard you run alongside Batocera. Open it in any browser on your network and you get:

- Live CPU/RAM/temperature graphs
- A ROM library browser with cover art (reads `gamelist.xml`)
- A file manager for `/userdata` (upload/download/delete)
- A built-in terminal (with safety guards against destructive commands)
- A live log viewer (EmulationStation, boot, syslog)
- Editable per-system `batocera.conf` settings
- Mobile-friendly — works fine on a phone browser

## Two installation modes

- **Remote** — runs on your Mac/PC/server, connects to Batocera via SSH. No install on the Batocera device itself.
- **Native** — runs *directly on Batocera*, auto-starts with the system. Always available, no second machine needed.

The installer auto-detects which one fits your situation:

```bash
git clone https://github.com/DavidSchuchert/Batocera-WebDashboard-Pro.git
cd Batocera-WebDashboard-Pro
./install.sh
```

Windows users can double-click `install.bat` (auto-detects WSL or Git Bash).

## Screenshots

[paste 2-3 screenshots from screenshots/ here, or link the demo GIF]

## Why I built this

I wanted a way to manage my Batocera box from my Mac without keeping a USB keyboard plugged into it, and most existing solutions either felt dated or required setting up a full VPN/SSH client every time.

## Tech / status

- **Open source** under MIT
- **Tests:** 82 API tests + 22 Playwright browser tests, all running on GitHub Actions
- **Security:** path traversal blocked, dangerous-command allowlist on the terminal, XSS hardened
- ⚠️ **Use on your home network only** — it deliberately exposes powerful features (root shell, file management) and is not designed for the public internet

## Links

- 🔗 GitHub: https://github.com/DavidSchuchert/Batocera-WebDashboard-Pro
- 🐛 Issues: please open one if something doesn't work
- 💬 Happy to take feedback / feature requests in this thread

Hope someone finds it useful! Curious what features people would want next.
