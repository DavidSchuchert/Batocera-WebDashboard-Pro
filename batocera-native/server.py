import os, subprocess, json, time, re
from flask import Flask, jsonify, request, send_from_directory, Response
from urllib.parse import unquote, quote
import xml.etree.ElementTree as ET

app = Flask(__name__, static_folder='public')
VERSION = "1.0.0"

# Helper for local command execution
def local_exec(cmd):
    try:
        res = subprocess.run(cmd, shell=True, capture_output=True, text=True)
        return res.stdout, res.stderr, res.returncode
    except Exception as e:
        return "", str(e), 1

def get_gamelist_data(system):
    path = f'/userdata/roms/{system}/gamelist.xml'
    data_map = {}
    if os.path.exists(path):
        try:
            tree = ET.parse(path)
            root = tree.getroot()
            for game in root.findall('game'):
                p = game.find('path')
                if p is not None:
                    p_text = p.text.strip('./') if p.text.startswith('./') else p.text
                    dev = game.find('developer')
                    desc = game.find('desc')
                    data_map[p_text] = {
                        'dev': dev.text if dev is not None else 'Unknown',
                        'desc': desc.text if desc is not None else 'No description available.'
                    }
        except: pass
    return data_map

@app.route('/')
def index(): return send_from_directory(app.static_folder, 'index.html')

@app.route('/health')
def health(): return jsonify({'status': 'ok', 'mode': 'native', 'version': VERSION})

@app.route('/api/update/check')
def api_update_check():
    remote_url = "https://raw.githubusercontent.com/DavidSchuchert/Batocera-Dashboard/main/version.txt"
    try:
        import urllib.request
        with urllib.request.urlopen(remote_url, timeout=5) as response:
            remote_version = response.read().decode('utf-8').strip()
            return jsonify({
                'current': VERSION,
                'remote': remote_version,
                'updateAvailable': remote_version != VERSION
            })
    except:
        return jsonify({'error': 'Could not check for updates'}), 500

@app.route('/api/status')
def api_status():
    uptime = local_exec("uptime")[0].strip()
    disk = local_exec("df -h /userdata | tail -n 1")[0].strip()
    return jsonify({'uptime': uptime, 'disk': disk})

@app.route('/api/status/system')
@app.route('/api/system/status')
def api_status_system():
    ver = local_exec("batocera-version")[0].strip() or "Unknown"
    return jsonify({'cpu': 'Local System', 'version': ver})

@app.route('/api/stats/stream')
def api_stats_stream():
    def generate():
        last_cpu = [0, 0]
        while True:
            try:
                # CPU load
                with open('/proc/stat', 'r') as f: line = f.readline()
                cpu_parts = [int(x) for x in line.split()[1:]]
                idle, total = cpu_parts[3], sum(cpu_parts)
                cpu_pct = 0
                if last_cpu[0] > 0:
                    dt, di = total - last_cpu[0], idle - last_cpu[1]
                    if dt > 0: cpu_pct = round(100 * (dt - di) / dt, 1)
                last_cpu[0], last_cpu[1] = total, idle

                # RAM
                rm = {}
                with open('/proc/meminfo', 'r') as f:
                    for l in f:
                        if ':' in l: k, v = l.split(':'); rm[k.strip()] = int(v.split()[0])
                tr, ar = rm.get('MemTotal', 1), rm.get('MemAvailable', rm.get('MemFree', 1))
                ram_pct = round(100 * (tr - ar) / tr, 1)

                # Thermal
                temp = "N/A"
                for i in range(10):
                    p = f'/sys/class/thermal/thermal_zone{i}/temp'
                    if os.path.exists(p):
                        with open(p, 'r') as f:
                            t = f.read().strip()
                            if t.isdigit(): temp = str(round(float(t)/1000, 1)); break
                
                yield f"data: {json.dumps({'cpu': str(cpu_pct), 'mem': str(ram_pct), 'temp': temp})}\n\n"
            except: yield f"data: {json.dumps({'error': 'local_stats'})}\n\n"
            time.sleep(2)
    return Response(generate(), mimetype='text/event-stream')

@app.route('/api/systems', methods=['GET'])
@app.route('/api/systems/all', methods=['GET'])
def api_systems_all():
    base = '/userdata/roms'
    if not os.path.exists(base): return jsonify({'systems': []})
    systems = [d for d in os.listdir(base) if os.path.isdir(os.path.join(base, d)) and not d.startswith('.')]
    return jsonify({'systems': sorted(systems)})

@app.route('/api/systems/<system>', methods=['GET', 'POST'])
def api_system_config(system):
    cp = '/userdata/system/batocera.conf'
    if request.method == 'GET':
        try:
            with open(cp, 'r') as f: content = f.read()
            settings, prefix = {}, (f"{system}." if system != 'global' else "")
            for l in content.split('\n'):
                l = l.strip()
                if l and not l.startswith('#') and '=' in l:
                    if system == 'global' and '.' not in l.split('=')[0]:
                        k, v = l.split('=', 1); settings[k] = v
                    elif l.startswith(prefix):
                        k, v = l.split('=', 1); settings[k.replace(prefix, '', 1)] = v
            return jsonify({'batoceraSettings': settings})
        except: return "Not found", 404
    else:
        new_settings = request.get_json()
        try:
            with open(cp, 'r') as f: lines = f.readlines()
            prefix = f"{system}." if system != 'global' else ""
            for k, v in new_settings.items():
                fk, found = f"{prefix}{k}", False
                for i, l in enumerate(lines):
                    if l.strip().startswith(fk + "="): lines[i] = f"{fk}={v}\n"; found = True; break
                if not found: lines.append(f"{fk}={v}\n")
            with open(cp, 'w') as f: f.writelines(lines)
            local_exec("batocera-save-overlay")
            return jsonify({'ok': True})
        except: return "Error", 500

@app.route('/api/system/control', methods=['POST'])
def control():
    a = request.get_json().get('action')
    cmds = {'stop-game': 'pkill -9 retroarch; pkill -9 dolphin; pkill -9 pcsx2; pkill -9 yuzu; pkill -9 rpcs3', 'reboot': 'reboot', 'shutdown': 'poweroff'}
    if a in cmds: local_exec(cmds[a])
    return jsonify({'ok': True})

@app.route('/api/roms')
def api_roms():
    sys_req = request.args.get('system', 'all')
    base = '/userdata/roms'
    search = os.path.join(base, sys_req) if sys_req != 'all' else base
    cmd = f'find {search} -maxdepth 3 -type f \\( -name "*.iso" -o -name "*.bin" -o -name "*.gba" -o -name "*.nds" -o -name "*.z64" -o -name "*.n64" -o -name "*.nes" -o -name "*.sfc" -o -name "*.wbfs" -o -name "*.3ds" -o -name "*.rvz" -o -name "*.ps3" -o -name "*.zip" -o -name "*.7z" -o -name "*.chd" -o -name "*.m3u" -o -name "*.cue" -o -name "*.wua" -o -name "*.rpx" -o -name "*.psx" \\) 2>/dev/null | head -n 5000'
    out, _, _ = local_exec(cmd)
    
    # Load metadata maps for all relevant systems
    meta_cache = {}
    roms = []
    for r in out.split('\n'):
        if r.strip():
            rel_path = r.replace(base + '/', '')
            sys_name = rel_path.split('/')[0]
            game_rel = rel_path.replace(sys_name + '/', '', 1)
            
            if sys_name not in meta_cache: meta_cache[sys_name] = get_gamelist_data(sys_name)
            meta = meta_cache[sys_name].get(game_rel, {'dev': 'Unknown', 'desc': 'No description available.'})
            
            fname = os.path.basename(r)
            roms.append({
                'name': fname, 'system': sys_name, 'path': r, 
                'dev': meta['dev'], 'desc': meta['desc'],
                'image': f'/api/media?path={quote(f"/userdata/roms/{sys_name}/images/{os.path.splitext(fname)[0]}-thumb.png")}'
            })
    return jsonify({'roms': roms})

@app.route('/api/media')
def api_media():
    p = request.args.get('path')
    if not p or not os.path.exists(p): return "Not found", 404
    return send_from_directory(os.path.dirname(p), os.path.basename(p))

@app.route('/api/logs')
def api_logs():
    t = request.args.get('type', 'es')
    ps = {'boot': ['/var/log/boot.log'], 'es': ['/userdata/system/logs/emulationstation.log', '/userdata/system/logs/es_launch_stderr.log'], 'syslog': ['/var/log/messages']}
    for p in ps.get(t, []):
        if os.path.exists(p):
            o, _, _ = local_exec(f'tail -n 200 "{p}"')
            return jsonify({'log': o})
    return jsonify({'log': "No logs found."})

@app.route('/api/command', methods=['POST'])
def api_command():
    # Harmonize with app.js (expects res.stdout/stderr, sends 'cmd' or 'command')
    req = request.get_json()
    c = req.get('cmd') or req.get('command')
    o, e, _ = local_exec(c)
    return jsonify({'stdout': o, 'stderr': e, 'output': o + e})

@app.route('/api/files/list')
def files_list():
    d = request.args.get('dir', '/userdata')
    try:
        items = []
        for e in os.scandir(d):
            if e.name.startswith('.'): continue
            items.append({'name': e.name, 'isDir': e.is_dir(), 'size': f"{e.stat().st_size/1024:.1f} KB" if e.is_file() else '--'})
        return jsonify({'files': sorted(items, key=lambda x: not x['isDir'])})
    except: return "Error", 500

@app.route('/api/files/delete', methods=['POST'])
def files_delete():
    p = request.get_json().get('path')
    local_exec(f'rm -rf "{p}"')
    return jsonify({'ok': True})

@app.route('/api/files/upload', methods=['POST'])
def files_upload():
    d, f = request.form.get('dir'), request.files.get('file')
    f.save(os.path.join(d, f.filename))
    return jsonify({'ok': True})

@app.route('/api/files/download')
def files_download():
    p = request.args.get('path')
    return send_from_directory(os.path.dirname(p), os.path.basename(p), as_attachment=True)

@app.route('/<path:path>')
def static_files(path): return send_from_directory(app.static_folder, path)

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8989, threaded=True)
