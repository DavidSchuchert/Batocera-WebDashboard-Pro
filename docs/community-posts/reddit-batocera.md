# Reddit post

**Subreddit:** r/batocera (primary) / r/emulation (secondary)
**Flair:** Project / Show & Tell (whatever fits the sub)
**Title (under 100 chars):**
> I built a web dashboard for Batocera — manage ROMs, stats, files from any browser [Open Source]

---

I just shipped **v2.0** of a web dashboard for Batocera and figured this sub might be interested.

**Demo:**
[upload screenshots/demo.gif as the post image — or link to GitHub]

**What it does:**
- Live CPU / RAM / temperature stats
- ROM library with cover art from your gamelist.xml
- File browser for /userdata (upload/download/delete)
- Built-in terminal (with safety guards)
- Live log viewer
- Edit batocera.conf per-system in the browser
- Mobile responsive

**Two ways to install:**
1. **Remote mode** — runs on your Mac/PC/server, talks to Batocera over SSH. Nothing installed on the device.
2. **Native mode** — runs directly on Batocera, auto-starts with the system.

The unified installer figures out which one you want:

```
./install.sh
```

(Windows: `install.bat` — uses WSL or Git Bash)

**Tech:** Python/Flask backend, vanilla JS frontend with NES.css, paramiko for SSH. Open source (MIT). Tests run on GitHub Actions (104 total — 82 API + 22 browser).

**Note:** Designed for home network use. Don't expose the port to the internet — it's effectively root access to your Batocera machine.

GitHub: https://github.com/DavidSchuchert/Batocera-WebDashboard-Pro

Happy to answer questions or take feature requests in the comments. What would you want it to do that it doesn't?
