# 🕹️ Batocera Interface PRO (Native Version)

This version is designed to run **directly on your Batocera device**. No separate PC or SSH configuration is required. Once installed, it starts automatically with your Batocera.

---

## 🖼️ Screenshots

<p align="center">
  <img src="../screenshots/dashboard.png" width="45%" alt="Dashboard Overview">
  <img src="../screenshots/library.png" width="45%" alt="Library Management">
</p>

---

## 🚀 Installation

### 1. Copy Files to Batocera
Copy the `batocera-native` folder to your Batocera device (anywhere in `/userdata/`, for example `/userdata/system/`).

You can do this via Samba (Network Share) or by plugging your SD card/Drive into your PC.

### 2. Run the Installer
Connect to your Batocera via SSH or open the F4 terminal and run:
```bash
cd /path/to/your/batocera-native/
chmod +x install.sh
./install.sh
```
*The installer will automatically move the files to `/userdata/system/interface-pro/`, install dependencies, and set up the autostart.*

### 3. Done!
After the installer finishes, you can restart your Batocera. The interface will be available at:
`http://batocera.local:8989` or `http://[YOUR-BATOCERA-IP]:8989`

---

## ✨ Features (Native Mode)
- **Zero Latency**: Direct filesystem access (no SSH overhead).
- **Auto-Discovery**: No IP or password needed.
- **Standalone**: Your Batocera is now its own web server.

---

*Enjoy your native Batocera Interface PRO!*
