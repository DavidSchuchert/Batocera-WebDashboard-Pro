# Security Policy

## Threat model

Batocera Web Dashboard PRO is designed for use on a **trusted local network**.
It deliberately exposes powerful features (root shell access, file management,
emulator config) that would be unsafe on the open internet.

**Do not expose this dashboard's port to the public internet.** If you need
remote access from outside your home network, route it through a VPN
(Tailscale, WireGuard) or an authenticated reverse proxy.

## Built-in protections

The dashboard ships with several defence-in-depth features:

- **Path traversal blocked** in all file endpoints — only paths under
  `/userdata` are accepted
- **Dangerous-command allowlist** in the terminal — blocks `rm -rf /`,
  `mkfs`, `dd if=`, fork bombs, `parted`/`fdisk`, etc.
- **Filename sanitisation** on upload — `../` and absolute paths stripped
- **XSS hardening** — all filenames and user-supplied strings are
  HTML-escaped before insertion into the DOM

## Reporting a vulnerability

If you discover a security issue, **please do not open a public GitHub issue**.
Instead, report it privately:

- **Preferred:** [GitHub Security Advisory](https://github.com/DavidSchuchert/Batocera-WebDashboard-Pro/security/advisories/new)
- **Alternatively:** open a normal issue marked `[security]` describing the
  problem at a high level, and request a private channel for the details

Please include:
- A description of the issue and its impact
- Steps to reproduce (or a minimal proof of concept)
- Affected version(s)
- Any suggested fix, if you have one

## What to expect

- We aim to acknowledge security reports within **72 hours**
- We will keep you informed about our progress
- Once a fix is ready, we will release a patched version and credit
  you in the release notes (unless you prefer to remain anonymous)

## Supported versions

Only the latest minor release receives security fixes. Older versions
should update via `./install.sh --update`.

| Version | Supported          |
|---------|--------------------|
| 2.x     | ✅ Yes             |
| 1.x     | ❌ Please upgrade  |
