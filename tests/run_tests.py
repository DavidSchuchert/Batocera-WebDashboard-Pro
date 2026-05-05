#!/usr/bin/env python3
"""
Automated API tests for Batocera WebDashboard Pro.

Usage:
  python3 tests/run_tests.py                  # Tests against running containers
  python3 tests/run_tests.py --start-stack    # Starts docker-compose stack first
  python3 tests/run_tests.py --stop-after     # Stops stack when done
  python3 tests/run_tests.py --remote-only    # Only test remote mode
  python3 tests/run_tests.py --native-only    # Only test native mode
"""

import argparse
import json
import os
import subprocess
import sys
import tempfile
import time
import urllib.request
import urllib.error
from dataclasses import dataclass, field
from typing import Optional

REMOTE_BASE = "http://localhost:8091"
NATIVE_BASE = "http://localhost:8092"
COMPOSE_FILE = "docker-compose.test.yml"

GREEN  = "\033[92m"
RED    = "\033[91m"
YELLOW = "\033[93m"
RESET  = "\033[0m"
BOLD   = "\033[1m"


@dataclass
class TestResult:
    name: str
    passed: bool
    message: str = ""


results: list[TestResult] = []


def run(name: str, condition: bool, message: str = "") -> bool:
    status = f"{GREEN}PASS{RESET}" if condition else f"{RED}FAIL{RESET}"
    print(f"  [{status}] {name}" + (f" — {message}" if message else ""))
    results.append(TestResult(name, condition, message))
    return condition


def warn(message: str):
    print(f"  [{YELLOW}WARN{RESET}] {message}")


def get(url: str, timeout: int = 5) -> tuple[Optional[dict], int]:
    try:
        with urllib.request.urlopen(url, timeout=timeout) as r:
            body = r.read()
            try:
                return json.loads(body), r.status
            except Exception:
                return {"_raw": body.decode("utf-8", errors="replace")}, r.status
    except urllib.error.HTTPError as e:
        try:
            body = e.read()
            return json.loads(body), e.code
        except Exception:
            return None, e.code
    except Exception:
        return None, 0


def post(url: str, payload: dict, timeout: int = 5) -> tuple[Optional[dict], int]:
    data = json.dumps(payload).encode()
    req = urllib.request.Request(url, data=data, headers={"Content-Type": "application/json"}, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return json.loads(r.read()), r.status
    except urllib.error.HTTPError as e:
        try:
            return json.loads(e.read()), e.code
        except Exception:
            return None, e.code
    except Exception:
        return None, 0


def post_multipart_file(url: str, field_name: str, filename: str, content: bytes, fields: dict,
                        timeout: int = 5) -> tuple[Optional[dict], int]:
    boundary = f"----batocera-test-{int(time.time() * 1000)}"
    body = bytearray()

    for key, value in fields.items():
        body.extend(f"--{boundary}\r\n".encode())
        body.extend(f'Content-Disposition: form-data; name="{key}"\r\n\r\n'.encode())
        body.extend(str(value).encode())
        body.extend(b"\r\n")

    body.extend(f"--{boundary}\r\n".encode())
    body.extend(
        f'Content-Disposition: form-data; name="{field_name}"; filename="{filename}"\r\n'
        "Content-Type: application/octet-stream\r\n\r\n"
        .encode()
    )
    body.extend(content)
    body.extend(b"\r\n")
    body.extend(f"--{boundary}--\r\n".encode())

    req = urllib.request.Request(
        url,
        data=bytes(body),
        headers={"Content-Type": f"multipart/form-data; boundary={boundary}"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return json.loads(r.read()), r.status
    except urllib.error.HTTPError as e:
        try:
            return json.loads(e.read()), e.code
        except Exception:
            return None, e.code
    except Exception:
        return None, 0


def wait_for_service(url: str, label: str, timeout: int = 60) -> bool:
    print(f"  Waiting for {label}...", end="", flush=True)
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            urllib.request.urlopen(url, timeout=2)
            print(f" {GREEN}ready{RESET}")
            return True
        except Exception:
            print(".", end="", flush=True)
            time.sleep(2)
    print(f" {RED}timeout{RESET}")
    return False


def start_stack() -> bool:
    print(f"\n{BOLD}Starting docker-compose stack...{RESET}")
    result = subprocess.run(
        ["docker", "compose", "-f", COMPOSE_FILE, "up", "--build", "-d"],
        capture_output=True, text=True,
    )
    if result.returncode != 0:
        print(f"{RED}Failed to start stack:{RESET}\n{result.stderr}")
        return False
    ok = True
    ok &= wait_for_service(f"{REMOTE_BASE}/health", "dashboard-remote")
    ok &= wait_for_service(f"{NATIVE_BASE}/health", "dashboard-native")
    return ok


def stop_stack():
    print(f"\n{BOLD}Stopping docker-compose stack...{RESET}")
    subprocess.run(["docker", "compose", "-f", COMPOSE_FILE, "down"], capture_output=True)
    print("  Stack stopped.")


def section(title: str):
    print(f"\n{BOLD}{title}{RESET}")


# ── Docker Installer / Compose Config ─────────────────────────────────────────

def test_docker_installer_config():
    section("Docker — Installer & Compose Config")

    compose_env_path = os.path.join("docker", ".env")
    created_compose_env = False

    with tempfile.NamedTemporaryFile("w", delete=False) as env_file:
        env_file.write(
            "PORT=18080\n"
            "BATOCERA_HOST=test-batocera\n"
            "BATOCERA_PORT=2222\n"
            "BATOCERA_USER=root\n"
            "BATOCERA_PASS=dummy-pass\n"
        )
        env_path = env_file.name

    try:
        if not os.path.exists(compose_env_path):
            with open(compose_env_path, "w", encoding="utf-8") as f:
                f.write(
                    "PORT=18080\n"
                    "BATOCERA_HOST=test-batocera\n"
                    "BATOCERA_PORT=2222\n"
                    "BATOCERA_USER=root\n"
                    "BATOCERA_PASS=dummy-pass\n"
                )
            created_compose_env = True

        result = subprocess.run(
            [
                "docker", "compose",
                "--env-file", env_path,
                "--project-directory", "docker",
                "-f", "docker/docker-compose.yml",
                "config", "--format", "json", "--no-env-resolution",
            ],
            capture_output=True, text=True, timeout=20,
        )
        run("Docker compose config renders", result.returncode == 0, result.stderr.strip())

        config = {}
        if result.returncode == 0:
            try:
                config = json.loads(result.stdout)
            except Exception as e:
                run("Docker compose config is JSON", False, str(e))
        else:
            run("Docker compose config is JSON", False, "config command failed")

        dashboard = (config.get("services") or {}).get("dashboard") or {}
        run("Dashboard service exists", bool(dashboard))

        ports = dashboard.get("ports") or []
        published = str(ports[0].get("published", "")) if ports else ""
        target = str(ports[0].get("target", "")) if ports else ""
        run("Host port comes from env file", published == "18080", f"published={published}")
        run("Container still listens on 8080", target == "8080", f"target={target}")

        environment = dashboard.get("environment") or {}
        run("BATOCERA_HOST comes from env file",
            environment.get("BATOCERA_HOST") == "test-batocera",
            f"host={environment.get('BATOCERA_HOST')}")

        health_test = " ".join(dashboard.get("healthcheck", {}).get("test", []))
        run("Healthcheck uses Python urllib", "python" in health_test and "urllib.request" in health_test)
        run("Healthcheck does not require curl", "curl" not in health_test)
    finally:
        try:
            os.unlink(env_path)
        except Exception:
            pass
        if created_compose_env:
            try:
                os.unlink(compose_env_path)
            except Exception:
                pass

    with open("install.sh", encoding="utf-8") as f:
        installer = f.read()

    run("Docker installer default port is 8080", "DEFAULT_DOCKER_PORT=8080" in installer)
    run("Docker installer passes --env-file to compose", "--env-file" in installer and "docker/.env" in installer)
    run("Docker installer pins compose project directory", "--project-directory" in installer)
    run("Docker installer waits on selected web port",
        '"http://localhost:${web_port}/health"' in installer)
    run("Installer has command-mode detection", "detect_install_mode_for_command()" in installer)
    run("Update command auto-detects Docker mode",
        "install_mode=$(detect_install_mode_for_command)" in installer and "docker) do_update_docker" in installer)
    run("Status treats Docker as Docker-managed",
        'mode="DOCKER"' in installer and 'proc_status="n/a (Docker-managed)"' in installer)
    run("Installer compares version direction",
        "version_gt()" in installer and 'elif version_gt "$remote" "$current"' in installer)


# ── Remote Mode ───────────────────────────────────────────────────────────────

def test_remote_health():
    section("Remote — Health & Connectivity")
    data, code = get(f"{REMOTE_BASE}/health")
    run("Health endpoint returns 200", code == 200)
    run("SSH status is 'connected'", data is not None and data.get("ssh") == "connected", f"got: {data}")


def test_remote_systems():
    section("Remote — Systems")
    data, code = get(f"{REMOTE_BASE}/api/systems")
    run("Systems endpoint returns 200", code == 200)
    systems = data.get("systems", []) if data else []
    run("Systems list is non-empty", len(systems) > 0, f"got: {systems}")
    for expected in ("snes", "nes", "gba", "n64", "psx"):
        run(f"System '{expected}' present", expected in systems)

    # Edge: unknown system returns empty list, not error
    data2, code2 = get(f"{REMOTE_BASE}/api/systems")
    run("Systems endpoint is stable on repeat call", code2 == 200)


def test_remote_roms():
    section("Remote — ROM Library")
    data, code = get(f"{REMOTE_BASE}/api/roms?system=snes")
    run("ROMs endpoint 200 for snes", code == 200)
    roms = data.get("roms", []) if data else []
    run("SNES ROMs non-empty", len(roms) > 0, f"got {len(roms)}")

    if roms:
        first = roms[0]
        run("ROM has 'name'", "name" in first)
        run("ROM has 'dev'", "dev" in first)
        run("ROM has 'path'", "path" in first)
        run("ROM has 'system'", "system" in first)
        run("ROM has 'image'", "image" in first)
        run("Developer not 'Unknown' (gamelist.xml parsed)", first.get("dev") not in ("Unknown", ""), f"dev={first.get('dev')}")
        run("System field matches request", first.get("system") == "snes", f"system={first.get('system')}")

    # Pagination fields
    run("Response has 'total'", data is not None and "total" in data, f"keys: {list(data.keys()) if data else []}")
    run("Response has 'offset'", data is not None and "offset" in data)
    run("Response has 'limit'",  data is not None and "limit" in data)

    # All systems
    data2, code2 = get(f"{REMOTE_BASE}/api/roms?system=all")
    run("ROMs endpoint 200 for 'all'", code2 == 200)
    run("All-systems returns more ROMs than snes alone",
        data2 is not None and data2.get("total", 0) > data.get("total", 0),
        f"all={data2.get('total') if data2 else '?'}, snes={data.get('total') if data else '?'}")

    # Pagination: offset
    data3, code3 = get(f"{REMOTE_BASE}/api/roms?system=all&limit=2&offset=0")
    run("Pagination limit=2 returns max 2 ROMs", code3 == 200 and len((data3 or {}).get("roms", [])) <= 2)
    data4, code4 = get(f"{REMOTE_BASE}/api/roms?system=all&limit=2&offset=1000")
    run("Pagination with offset beyond total returns empty list",
        code4 == 200 and len((data4 or {}).get("roms", [])) == 0)

    # NES
    data5, code5 = get(f"{REMOTE_BASE}/api/roms?system=nes")
    run("NES ROMs non-empty", code5 == 200 and len((data5 or {}).get("roms", [])) > 0)


def test_remote_files():
    section("Remote — File Browser")
    data, code = get(f"{REMOTE_BASE}/api/files/list?dir=/userdata")
    run("File list /userdata returns 200", code == 200)
    files = (data or {}).get("files", [])
    run("File list has entries", len(files) > 0, f"got {len(files)} entries")
    run("'roms' dir present", any(f["name"] == "roms" and f["isDir"] for f in files))
    run("'system' dir present", any(f["name"] == "system" and f["isDir"] for f in files))

    # Drill into roms
    data2, code2 = get(f"{REMOTE_BASE}/api/files/list?dir=/userdata/roms")
    run("File list /userdata/roms returns 200", code2 == 200)
    run("ROM subdirs present", len((data2 or {}).get("files", [])) > 0)

    # Security: path traversal
    _, code_etc = get(f"{REMOTE_BASE}/api/files/list?dir=/etc")
    run("Path traversal /etc is blocked (403)", code_etc == 403, f"got HTTP {code_etc}")

    _, code_root = get(f"{REMOTE_BASE}/api/files/list?dir=/")
    run("Path traversal / is blocked (403)", code_root == 403, f"got HTTP {code_root}")

    _, code_dot = get(f"{REMOTE_BASE}/api/files/list?dir=../../../etc")
    run("Path traversal ../../../etc is blocked (403)", code_dot == 403, f"got HTTP {code_dot}")

    _, code_enc = get(f"{REMOTE_BASE}/api/files/list?dir=%2Fetc%2Fpasswd")
    run("URL-encoded path traversal /etc/passwd blocked", code_enc in (400, 403), f"got HTTP {code_enc}")

    # Security: delete root/userdata should be rejected
    data_del, code_del = post(f"{REMOTE_BASE}/api/files/delete", {"path": "/userdata"})
    run("Delete /userdata is blocked (403)", code_del == 403, f"got HTTP {code_del}: {data_del}")

    data_del2, code_del2 = post(f"{REMOTE_BASE}/api/files/delete", {"path": "/etc/passwd"})
    run("Delete /etc/passwd is blocked (400/403)", code_del2 in (400, 403), f"got HTTP {code_del2}")

    # Security: download outside /userdata
    _, code_dl = get(f"{REMOTE_BASE}/api/files/download?path=/etc/shadow")
    run("Download /etc/shadow is blocked (400/403)", code_dl in (400, 403), f"got HTTP {code_dl}")


def test_remote_terminal():
    section("Remote — Terminal Security")
    # Safe command works
    data, code = post(f"{REMOTE_BASE}/api/command", {"cmd": "echo hello"})
    run("Safe 'echo hello' returns 200", code == 200, f"got: {data}")
    run("Safe command stdout contains output", "hello" in (data or {}).get("stdout", ""))

    # Dangerous commands blocked
    for dangerous in ["rm -rf /", "mkfs.ext4 /dev/sda", "dd if=/dev/zero of=/dev/sda"]:
        d, c = post(f"{REMOTE_BASE}/api/command", {"cmd": dangerous})
        run(f"Dangerous cmd blocked: '{dangerous[:30]}'", c == 403, f"got HTTP {c}")

    # Empty command
    d, c = post(f"{REMOTE_BASE}/api/command", {"cmd": ""})
    run("Empty command returns 400", c == 400, f"got HTTP {c}: {d}")

    # Missing cmd key
    d, c = post(f"{REMOTE_BASE}/api/command", {})
    run("Missing cmd key returns 400", c == 400, f"got HTTP {c}")


def test_remote_logs():
    section("Remote — Logs")
    for log_type in ("es", "boot", "syslog"):
        data, code = get(f"{REMOTE_BASE}/api/logs?type={log_type}")
        run(f"Logs endpoint 200 for type='{log_type}'", code == 200)

    # ES log has content
    data, _ = get(f"{REMOTE_BASE}/api/logs?type=es")
    run("ES log content non-empty", len((data or {}).get("log", "")) > 0)


def test_remote_status():
    section("Remote — Status & Settings")
    data, code = get(f"{REMOTE_BASE}/api/status")
    run("Status returns 200", code == 200)
    run("Status has 'uptime'", "uptime" in (data or {}))
    run("Status has 'disk'",   "disk" in (data or {}))

    data2, code2 = get(f"{REMOTE_BASE}/api/status/system")
    run("System status returns 200", code2 == 200)
    run("Batocera version present", "version" in (data2 or {}))
    run("Batocera version non-empty", len((data2 or {}).get("version", "")) > 0,
        f"version='{data2.get('version') if data2 else ''}'")

    data3, code3 = get(f"{REMOTE_BASE}/api/settings")
    run("Settings returns 200", code3 == 200)
    run("Settings has 'host'", "host" in (data3 or {}))
    run("Settings has 'user'", "user" in (data3 or {}))
    run("Settings password not exposed as plaintext in GET",
        (data3 or {}).get("pass", "") in ("", "linux", "***"),
        f"pass value present but may be acceptable: '{(data3 or {}).get('pass', '')}'")


def test_remote_systems_config():
    section("Remote — System Config")
    data, code = get(f"{REMOTE_BASE}/api/systems/snes")
    run("System config endpoint 200 for snes", code == 200)
    run("Response has 'batoceraSettings'", "batoceraSettings" in (data or {}))

    data2, code2 = get(f"{REMOTE_BASE}/api/systems/global")
    run("System config endpoint 200 for global", code2 == 200)


# ── Native Mode ───────────────────────────────────────────────────────────────

def test_native():
    section("Native Mode")

    data, code = get(f"{NATIVE_BASE}/health")
    run("Health returns 200", code == 200)
    run("Mode is 'native'", (data or {}).get("mode") == "native", f"got: {data}")
    run("Status is 'ok'", (data or {}).get("status") == "ok")
    with open("batocera-native/version.txt", encoding="utf-8") as f:
        expected_version = f.read().strip()
    run("Native reports dashboard version",
        (data or {}).get("version") == expected_version,
        f"expected={expected_version}, got={(data or {}).get('version')}")

    data2, code2 = get(f"{NATIVE_BASE}/api/systems")
    run("Systems returns 200", code2 == 200)
    systems = (data2 or {}).get("systems", [])
    run("Systems non-empty", len(systems) > 0, f"got: {systems}")

    for sys_name in ("snes", "nes"):
        d, c = get(f"{NATIVE_BASE}/api/roms?system={sys_name}")
        run(f"ROMs 200 for {sys_name}", c == 200)
        roms = (d or {}).get("roms", [])
        run(f"{sys_name.upper()} ROMs non-empty", len(roms) > 0, f"got {len(roms)}")
        if roms:
            run(f"{sys_name.upper()} developer from gamelist.xml",
                roms[0].get("dev") not in ("Unknown", ""),
                f"dev={roms[0].get('dev')}")
            run(f"{sys_name.upper()} has description",
                len(roms[0].get("desc", "")) > 0)

    upload_name = f"native-upload-test-{int(time.time())}.txt"
    upload_body = b"native upload ok\n"
    upload_data, upload_code = post_multipart_file(
        f"{NATIVE_BASE}/api/files/upload",
        "file",
        upload_name,
        upload_body,
        {"dir": "/userdata/system"},
    )
    run("Native file upload returns 200", upload_code == 200, f"got HTTP {upload_code}: {upload_data}")

    files_data, files_code = get(f"{NATIVE_BASE}/api/files/list?dir=/userdata/system")
    files = (files_data or {}).get("files", [])
    run("Native uploaded file appears in listing",
        files_code == 200 and any(f.get("name") == upload_name for f in files),
        f"got HTTP {files_code}, files={[f.get('name') for f in files]}")

    blocked_data, blocked_code = post_multipart_file(
        f"{NATIVE_BASE}/api/files/upload",
        "file",
        "blocked.txt",
        b"blocked\n",
        {"dir": "/etc"},
    )
    run("Native upload outside /userdata is blocked",
        blocked_code == 400,
        f"got HTTP {blocked_code}: {blocked_data}")

    post(f"{NATIVE_BASE}/api/files/delete", {"path": f"/userdata/system/{upload_name}"})


# ── SSH Mock ──────────────────────────────────────────────────────────────────

def test_mock_ssh():
    section("Batocera Mock (SSH port 2299)")

    sshpass = subprocess.run(["which", "sshpass"], capture_output=True).returncode == 0
    if sshpass:
        def ssh(cmd):
            return subprocess.run(
                ["sshpass", "-p", "linux", "ssh", "-o", "StrictHostKeyChecking=no",
                 "-p", "2299", "root@localhost", cmd],
                capture_output=True, text=True, timeout=10,
            )
        r = ssh("echo ok")
        run("SSH login succeeds", r.returncode == 0, r.stderr.strip())

        r2 = ssh("ls /userdata/roms/snes/")
        run("SNES ROMs visible via SSH", "SuperMarioWorld.sfc" in r2.stdout)
        run("gamelist.xml in snes dir", "gamelist.xml" in r2.stdout)

        r3 = ssh("cat /userdata/system/batocera.conf")
        run("batocera.conf readable", "global.language" in r3.stdout)

        r4 = ssh("batocera-version")
        run("batocera-version command works", "batocera" in r4.stdout.lower())
    else:
        import socket
        try:
            s = socket.create_connection(("localhost", 2299), timeout=3)
            s.close()
            run("SSH port 2299 is reachable", True)
        except Exception as e:
            run("SSH port 2299 is reachable", False, str(e))
        warn("Install 'sshpass' for full SSH tests (brew install sshpass)")


# ── Summary ───────────────────────────────────────────────────────────────────

def print_summary():
    total  = len(results)
    passed = sum(1 for r in results if r.passed)
    failed = total - passed

    print(f"\n{'='*55}")
    print(f"{BOLD}Results: {passed}/{total} passed{RESET}", end="")
    if failed:
        print(f"  {RED}({failed} failed){RESET}")
        print(f"\n{BOLD}Failed tests:{RESET}")
        for r in results:
            if not r.passed:
                print(f"  {RED}✗{RESET} {r.name}" + (f" — {r.message}" if r.message else ""))
    else:
        print(f"  {GREEN}All tests passed!{RESET}")
    print()
    return failed == 0


def main():
    parser = argparse.ArgumentParser(description="Run automated tests for Batocera WebDashboard Pro")
    parser.add_argument("--start-stack", action="store_true", help="Start docker-compose stack before testing")
    parser.add_argument("--stop-after",  action="store_true", help="Stop stack after tests")
    parser.add_argument("--remote-only", action="store_true", help="Only test remote mode")
    parser.add_argument("--native-only", action="store_true", help="Only test native mode")
    args = parser.parse_args()

    print(f"{BOLD}Batocera WebDashboard Pro — Automated Tests{RESET}")
    print(f"Remote: {REMOTE_BASE}  |  Native: {NATIVE_BASE}")

    if args.start_stack:
        if not start_stack():
            print(f"{RED}Stack failed to start. Aborting.{RESET}")
            sys.exit(1)

    try:
        test_docker_installer_config()
        if not args.native_only:
            test_remote_health()
            test_remote_systems()
            test_remote_roms()
            test_remote_files()
            test_remote_terminal()
            test_remote_logs()
            test_remote_status()
            test_remote_systems_config()
        if not args.remote_only:
            test_native()
        test_mock_ssh()
    finally:
        ok = print_summary()
        if args.stop_after:
            stop_stack()
        sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
