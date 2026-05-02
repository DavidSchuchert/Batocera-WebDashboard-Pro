import os, sys, json, base64, time, signal, io, xml.etree.ElementTree as ET
import threading, re
from flask import Flask, send_from_directory, jsonify, request, Response, send_file
from urllib.parse import quote
import paramiko

try:
    from dotenv import load_dotenv
    load_dotenv()
except: pass

app = Flask(__name__, static_folder=os.path.join(os.path.dirname(__file__), 'public'))
app.config['MAX_CONTENT_LENGTH'] = 500 * 1024 * 1024

try:
    from flask_compress import Compress
    Compress(app)
except ImportError:
    pass

BATOCERA_HOST = os.getenv('BATOCERA_HOST', '192.168.1.100')
BATOCERA_PORT = int(os.getenv('BATOCERA_PORT', '22'))
BATOCERA_USER = os.getenv('BATOCERA_USER', 'root')
BATOCERA_PASS = os.getenv('BATOCERA_PASS', 'linux')

ssh_client = None
_ssh_lock = threading.Lock()

# ── Per-thread SFTP pool ─────────────────────────────────────────────────────
_thread_local = threading.local()

def get_ssh():
    global ssh_client
    try:
        if ssh_client is None or not ssh_client.get_transport() or not ssh_client.get_transport().is_active():
            print("[SSH] Connecting...")
            ssh_client = paramiko.SSHClient()
            ssh_client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
            ssh_client.connect(BATOCERA_HOST, port=BATOCERA_PORT, username=BATOCERA_USER, password=BATOCERA_PASS, timeout=10)
    except Exception as e:
        print(f"[SSH] Connection failed: {e}")
        ssh_client = None
    return ssh_client

def get_sftp():
    """Return a thread-local SFTP client, reconnecting if needed."""
    sftp = getattr(_thread_local, 'sftp', None)
    if sftp is not None:
        try:
            sftp.stat('/')
            return sftp
        except Exception:
            _thread_local.sftp = None

    with _ssh_lock:
        client = get_ssh()
    if not client:
        return None
    try:
        _thread_local.sftp = client.open_sftp()
        return _thread_local.sftp
    except Exception:
        return None

def ssh_exec(cmd):
    try:
        client = get_ssh()
        if not client: return "", "SSH Connection Failed", 1
        stdin, stdout, stderr = client.exec_command(cmd)
        out = stdout.read().decode('utf-8', errors='replace')
        err = stderr.read().decode('utf-8', errors='replace')
        status = stdout.channel.recv_exit_status()
        return out, err, status
    except Exception as e:
        global ssh_client
        ssh_client = None
        return "", str(e), 1

# ── Gamelist Cache ───────────────────────────────────────────────────────────
_gamelist_cache: dict = {}
_cache_lock = threading.Lock()
CACHE_TTL = 300  # seconds

def invalidate_gamelist_cache(system=None):
    with _cache_lock:
        if system:
            _gamelist_cache.pop(system, None)
        else:
            _gamelist_cache.clear()

def get_gamelist_map_cached(system):
    now = time.time()
    with _cache_lock:
        entry = _gamelist_cache.get(system)
        if entry:
            data, ts = entry
            if now - ts < CACHE_TTL:
                return data
    data = get_gamelist_map(system)
    with _cache_lock:
        _gamelist_cache[system] = (data, now)
    return data

def get_gamelist_map(system):
    mapping = {}
    path = f'/userdata/roms/{system}/gamelist.xml'
    try:
        sftp = get_sftp()
        if not sftp:
            return mapping
        with sftp.open(path, 'r') as f:
            root = ET.fromstring(f.read())
            for game in root.findall('game'):
                r_path = game.findtext('path')
                if r_path:
                    i_path = game.findtext('boxart') or game.findtext('thumbnail') or game.findtext('image')
                    g_name = game.findtext('name')
                    clean_rom = os.path.basename(r_path.replace('./', ''))
                    mapping[clean_rom] = {
                        'img': i_path.replace('./', '') if i_path else None,
                        'name': g_name or clean_rom,
                        'desc': game.findtext('desc') or "No description.",
                        'dev': game.findtext('developer') or "Unknown",
                        'date': game.findtext('releasedate') or ""
                    }
    except: pass
    return mapping

# ── Path Safety ─────────────────────────────────────────────────────────────
SAFE_BASE = '/userdata'

def _safe_path(path: str):
    """Return normalised path if it is under /userdata, else None."""
    if not path:
        return None
    normalised = os.path.normpath('/' + path.lstrip('/'))
    if normalised == SAFE_BASE or normalised.startswith(SAFE_BASE + '/'):
        return normalised
    return None

# ── Command Security ─────────────────────────────────────────────────────────
_DANGEROUS_PATTERNS = [
    re.compile(r'rm\s+-[rf]*r[rf]*\s+[/~]'),   # rm -rf / or rm -fr /
    re.compile(r'\brm\s+--\s+-'),               # rm -- -something suspicious
    re.compile(r'\bmkfs\b'),
    re.compile(r'\bdd\s+if='),
    re.compile(r':\s*\(\s*\)\s*\{.*:\s*\|'),    # fork bomb
    re.compile(r'>\s*/dev/[sh]d[a-z]'),         # overwrite block device
    re.compile(r'\bshred\b'),
    re.compile(r'\bwipefs\b'),
    re.compile(r'\bparted\b'),
    re.compile(r'\bfdisk\b'),
    re.compile(r'\bmkswap\b'),
    re.compile(r'\bchmod\s+.*\s+/\s*$'),        # chmod on root
    re.compile(r'\bchown\s+.*\s+/\s*$'),
]

def is_safe_command(cmd):
    for pattern in _DANGEROUS_PATTERNS:
        if pattern.search(cmd):
            return False
    return True

# ── Routes ────────────────────────────────────────────────────────────────────

@app.route('/api/roms')
def api_roms():
    system = request.args.get('system', 'all')
    limit = min(int(request.args.get('limit', 100)), 500)
    offset = int(request.args.get('offset', 0))
    try:
        base = '/userdata/roms'
        search = f'{base}/{system}' if system != 'all' else base
        cmd = (f'find {search} -maxdepth 3 -type f \\( '
               '-name "*.iso" -o -name "*.bin" -o -name "*.smc" -o -name "*.gba" '
               '-o -name "*.nds" -o -name "*.z64" -o -name "*.n64" -o -name "*.nes" '
               '-o -name "*.sfc" -o -name "*.wbfs" -o -name "*.3ds" -o -name "*.rvz" '
               '-o -name "*.ps3" -o -name "*.zip" -o -name "*.7z" -o -name "*.chd" '
               '-o -name "*.m3u" -o -name "*.cue" -o -name "*.wua" -o -name "*.rpx" '
               '-o -name "*.psx" \\) 2>/dev/null | head -n 5000')
        out, _, _ = ssh_exec(cmd)
        roms_raw = [r.strip() for r in out.split('\n') if r.strip()]

        meta_cache = {}
        if system != 'all':
            meta_cache[system] = get_gamelist_map_cached(system)

        res = []
        for r in roms_raw:
            fname = os.path.basename(r)
            sys_name = r.replace(base + '/', '').split('/')[0]

            if sys_name not in meta_cache:
                meta_cache[sys_name] = get_gamelist_map_cached(sys_name)

            info = meta_cache[sys_name].get(fname, {})
            img_rel = info.get('img')
            if img_rel:
                p = img_rel if img_rel.startswith('/') else f'/userdata/roms/{sys_name}/{img_rel}'
                img_url = f'/api/media?path={quote(p)}'
            else:
                img_url = f'/api/media?path={quote(f"/userdata/roms/{sys_name}/images/{os.path.splitext(fname)[0]}-thumb.png")}'

            res.append({
                'path': r, 'name': info.get('name', os.path.splitext(fname)[0]),
                'system': sys_name, 'image': img_url,
                'desc': info.get('desc', ''), 'dev': info.get('dev', ''), 'date': info.get('date', '')
            })

        total = len(res)
        return jsonify({'roms': res[offset:offset + limit], 'total': total, 'offset': offset, 'limit': limit})
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/media')
def api_media():
    path = request.args.get('path')
    if not path: return "400", 400
    try:
        sftp = get_sftp()
        if not sftp: return "503", 503
        fallbacks = [
            path,
            path.replace('-thumb.png', '-image.png'),
            path.replace('/images/', '/media/images/'),
            path.replace('.png', '.jpg'),
            path.replace('.jpg', '.png')
        ]
        data = None
        found_path = None
        for p in fallbacks:
            try:
                with sftp.open(p, 'rb') as f:
                    data = f.read()
                    found_path = p
                    break
            except: continue
        if data:
            ext = os.path.splitext(found_path)[1].lower()
            mimetype = "image/jpeg" if ext in ['.jpg', '.jpeg'] else "image/png"
            return Response(data, mimetype=mimetype,
                            headers={'Cache-Control': 'public, max-age=3600'})
        return "404", 404
    except: return "500", 500

@app.route('/api/command', methods=['POST'])
def api_command():
    try:
        data = request.get_json()
        cmd = data.get('cmd', '').strip()
        if not cmd:
            return jsonify({'error': 'No command provided'}), 400

        if not is_safe_command(cmd):
            return jsonify({'error': 'Command blocked: potentially destructive operation'}), 403

        out, err, code = ssh_exec(cmd)
        return jsonify({'stdout': out, 'stderr': err, 'code': code})
    except Exception as e:
        return jsonify({'error': str(e)}), 500

# --- Statics & Helpers ---
@app.route('/health')
def health():
    try:
        ssh = get_ssh()
        if ssh:
            ssh.exec_command('echo ok')
            return jsonify({'status': 'ok', 'ssh': 'connected'})
        return jsonify({'status': 'ok', 'ssh': 'disconnected'})
    except: return jsonify({'status': 'ok', 'ssh': 'disconnected'})

@app.route('/')
def index(): return send_from_directory(app.static_folder, 'index.html')

@app.route('/api/stats/stream')
def api_stats_stream():
    def generate():
        last_cpu = [0, 0]
        while True:
            try:
                out, _, _ = ssh_exec("grep 'cpu ' /proc/stat")
                if not out: raise Exception("No output")
                cpu_parts = [int(x) for x in out.split()[1:]]
                idle = cpu_parts[3]
                total = sum(cpu_parts)

                cpu_pct = 0
                if last_cpu[0] > 0:
                    diff_total = total - last_cpu[0]
                    diff_idle = idle - last_cpu[1]
                    if diff_total > 0:
                        cpu_pct = round(100 * (diff_total - diff_idle) / diff_total, 1)

                last_cpu[0] = total
                last_cpu[1] = idle

                ram_out, _, _ = ssh_exec("grep -E 'MemTotal|MemAvailable|MemFree' /proc/meminfo")
                ram_map = {}
                for line in ram_out.split('\n'):
                    if ':' in line:
                        k, v = line.split(':')
                        ram_map[k.strip()] = int(v.split()[0])

                total_ram = ram_map.get('MemTotal', 1)
                avail_ram = ram_map.get('MemAvailable', ram_map.get('MemFree', total_ram))
                ram_pct = round(100 * (total_ram - avail_ram) / total_ram, 1)

                temp_out, _, _ = ssh_exec("find /sys/class/thermal/thermal_zone*/temp -type f 2>/dev/null | xargs cat 2>/dev/null | head -n 1")
                temp = "N/A"
                if temp_out and temp_out.strip().isdigit():
                    temp = str(round(float(temp_out.strip()) / 1000, 1))

                yield f'data: {json.dumps({"cpu": str(cpu_pct), "mem": str(ram_pct), "temp": temp})}\n\n'
            except:
                yield f'data: {{"error": "ssh"}}\n\n'
            time.sleep(2)
    return Response(generate(), mimetype='text/event-stream')

@app.route('/api/systems')
def api_systems():
    out, _, _ = ssh_exec("ls -d /userdata/roms/*/ | xargs -n 1 basename")
    return jsonify({'systems': sorted([s.strip() for s in out.split('\n') if s.strip() and not s.startswith('.')])})

@app.route('/api/systems/all')
def api_systems_all():
    return api_systems()

@app.route('/api/systems/<system>', methods=['GET'])
def api_system_get(system):
    try:
        out, _, _ = ssh_exec("cat /userdata/system/batocera.conf")
        settings = {}
        prefix = f"{system}." if system != 'global' else ""
        for line in out.split('\n'):
            line = line.strip()
            if line and not line.startswith('#') and '=' in line:
                if system == 'global':
                    if '.' not in line.split('=')[0]:
                        k, v = line.split('=', 1)
                        settings[k] = v
                elif line.startswith(prefix):
                    k, v = line.split('=', 1)
                    settings[k.replace(prefix, '', 1)] = v
        return jsonify({'batoceraSettings': settings, 'configContent': out})
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/systems/<system>', methods=['POST'])
def api_system_save(system):
    try:
        data = request.get_json()
        settings = data.get('settings', {})
        cmds = []
        for k, v in settings.items():
            key = f"{system}.{k}" if system != 'global' else k
            val = str(v).replace("'", "'\\''")
            cmds.append(f"batocera-settings-set {key} '{val}'")

        if cmds:
            full_cmd = " ; ".join(cmds) + " ; batocera-save-overlay"
            ssh_exec(full_cmd)
            # Invalidate cache for this system so next fetch is fresh
            invalidate_gamelist_cache(system)

        return jsonify({'ok': True})
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/status')
def api_status():
    df = ssh_exec('df -h /userdata')[0]
    uptime = ssh_exec('uptime')[0].strip()
    return jsonify({'uptime': uptime, 'disk': df})

@app.route('/api/status/system')
def api_status_system():
    ver, _, _ = ssh_exec("batocera-version 2>/dev/null || cat /etc/batocera_version 2>/dev/null || cat /usr/share/batocera/batocera.version 2>/dev/null")
    ver = ver.strip() or "Unknown"
    return jsonify({'cpu': 'System', 'version': ver})

@app.route('/api/system/control', methods=['POST'])
def control():
    a = request.get_json().get('action')
    cmds = {
        'stop-game': 'pkill -9 retroarch; pkill -9 dolphin; pkill -9 pcsx2; pkill -9 yuzu; pkill -9 rpcs3',
        'volume-up': 'batocera-audio setSystemVolume +5',
        'volume-down': 'batocera-audio setSystemVolume -5',
        'reboot': 'reboot',
        'shutdown': 'poweroff'
    }
    if a in cmds: ssh_exec(cmds[a])
    return jsonify({'ok': True})

@app.route('/api/settings', methods=['GET', 'POST'])
def api_settings():
    if request.method == 'GET':
        return jsonify({
            'host': os.getenv('BATOCERA_HOST', '192.168.1.100'),
            'user': os.getenv('BATOCERA_USER', 'root'),
            'pass': os.getenv('BATOCERA_PASS', 'linux')
        })
    else:
        data = request.get_json()
        env_path = os.path.join(os.path.dirname(__file__), '.env')
        with open(env_path, 'w') as f:
            f.write(f"BATOCERA_HOST={data.get('host', '192.168.1.100')}\n")
            f.write(f"BATOCERA_USER={data.get('user', 'root')}\n")
            f.write(f"BATOCERA_PASS={data.get('pass', 'linux')}\n")
            f.write(f"PORT={os.getenv('PORT', '8080')}\n")

        os.environ['BATOCERA_HOST'] = data.get('host', '192.168.1.100')
        os.environ['BATOCERA_USER'] = data.get('user', 'root')
        os.environ['BATOCERA_PASS'] = data.get('pass', 'linux')

        global ssh_client
        ssh_client = None
        invalidate_gamelist_cache()
        return jsonify({'ok': True})

@app.route('/api/logs')
def api_logs():
    log_type = request.args.get('type', 'es')
    paths = {
        'boot': ['/var/log/boot.log', '/var/log/boot'],
        'es': ['/userdata/system/logs/emulationstation.log', '/userdata/system/logs/es_launch_stderr.log', '/userdata/system/logs/es_launch_stdout.log'],
        'syslog': ['/var/log/messages', '/var/log/syslog'],
    }
    candidates = paths.get(log_type, paths['es'])
    for path in candidates:
        out, err, code = ssh_exec(f'tail -n 200 "{path}" 2>/dev/null')
        if out.strip():
            return jsonify({'log': out, 'path': path})
    return jsonify({'log': f"No logs found in: {', '.join(candidates)}", 'error': True})

@app.route('/api/files/download')
def api_files_download():
    path = _safe_path(request.args.get('path', ''))
    if not path: return jsonify({'error': 'Invalid or missing path'}), 400
    try:
        sftp = get_sftp()
        if not sftp: return "SSH unavailable", 503
        f = sftp.open(path, 'rb')
        def generate():
            try:
                while chunk := f.read(8192): yield chunk
            finally:
                f.close()
        return Response(generate(), direct_passthrough=True, headers={
            'Content-Disposition': f'attachment; filename="{os.path.basename(path)}"'
        })
    except Exception as e:
        return str(e), 500

@app.route('/api/files/delete', methods=['POST'])
def api_files_delete():
    try:
        raw = (request.get_json() or {}).get('path', '')
        path = _safe_path(raw)
        if not path: return jsonify({'error': 'Invalid or missing path'}), 400
        if path == SAFE_BASE:
            return jsonify({'error': 'Cannot delete root or userdata'}), 403
        out, err, code = ssh_exec(f'rm -rf "{path}"')
        if code == 0: return jsonify({'ok': True})
        return jsonify({'error': err or 'Delete failed'}), 500
    except Exception as e:
        return str(e), 500

@app.route('/api/files/upload', methods=['POST'])
def api_files_upload():
    dir_path = _safe_path(request.form.get('dir', ''))
    file = request.files.get('file')
    if not dir_path: return jsonify({'error': 'Invalid or missing dir'}), 400
    if not file: return jsonify({'error': 'Missing file'}), 400
    try:
        sftp = get_sftp()
        if not sftp: return "SSH unavailable", 503
        remote_path = (dir_path + '/' + os.path.basename(file.filename)).replace('//', '/')
        sftp.putfo(file.stream, remote_path)
        return jsonify({'ok': True})
    except Exception as e:
        return str(e), 500

@app.route('/api/files/list')
def files():
    d = _safe_path(request.args.get('dir', '/userdata'))
    if not d:
        return jsonify({'error': 'Access denied: path outside /userdata'}), 403
    out, _, _ = ssh_exec(f'ls -la "{d}"')
    res = []
    for line in out.split('\n')[1:]:
        p = line.split(None)
        if len(p) >= 8:
            res.append({'name': ' '.join(p[8:]), 'isDir': p[0].startswith('d'), 'size': p[4]})
    return jsonify({'files': sorted([f for f in res if not f['name'].startswith('.')], key=lambda x: not x['isDir'])})

@app.route('/<path:path>')
def static_files(path): return send_from_directory(app.static_folder, path)

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=int(os.getenv('PORT', 8080)), threaded=True)
