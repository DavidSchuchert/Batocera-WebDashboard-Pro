/**
 * Batocera Web UI — app.js
 */

const state = {
  sshConnected: false,
  currentPath: '/userdata',
  roms: [],
  filteredRoms: [],
  systems: [],
  statsSource: null,
  romsTotal: 0,
  romsOffset: 0,
  romsLimit: 100,
  romsLoading: false,
  activeToastId: null,
  retryDelay: 1000
};

// ── Utilities ──────────────────────────────────────────────────────────────

function escapeHtml(s) {
  return String(s)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

// Encode a path for safe use inside a single-quoted JS string in onclick="..."
function escapePath(p) {
  return p.replace(/\\/g, '\\\\').replace(/'/g, "\\'");
}

// ── Init ───────────────────────────────────────────────────────────────────

async function init() {
  setupNav();
  setupKeyboardShortcuts();
  const health = await checkHealth();

  if (state.sshConnected || health.mode === 'native') {
    if (health.mode === 'native') {
      state.isNative = true;
      const settingsBtn = document.querySelector('[data-view="settings"]');
      if (settingsBtn) settingsBtn.style.display = 'none';
    } else {
      await loadSettings();
    }

    await loadSystemsList();
    const savedView = localStorage.getItem('batocera_view') || 'dashboard';
    showView(savedView);
    document.querySelectorAll('.nav-btn').forEach(b => b.classList.toggle('active', b.dataset.view === savedView));
    startStatsStream();
    refreshDashboard();
  } else {
    showView('settings');
  }
}

function setupKeyboardShortcuts() {
  document.addEventListener('keydown', (e) => {
    // Esc: close modal
    if (e.key === 'Escape') {
      const modal = document.getElementById('game-modal');
      if (modal && modal.open) modal.close();
    }
    // Ctrl+F: focus ROM search if library view is active
    if ((e.ctrlKey || e.metaKey) && e.key === 'f') {
      const searchEl = document.getElementById('rom-search');
      const romsView = document.getElementById('view-roms');
      if (searchEl && romsView && romsView.classList.contains('active')) {
        e.preventDefault();
        searchEl.focus();
      }
    }
  });
}

function setupNav() {
  const toggle = document.getElementById('menu-toggle');
  const nav = document.getElementById('nav-menu');

  if (toggle) {
    toggle.addEventListener('click', (e) => {
      e.stopPropagation();
      nav.classList.toggle('open');
    });
  }

  document.querySelectorAll('.nav-btn').forEach(btn => {
    btn.addEventListener('click', () => {
      document.querySelectorAll('.nav-btn').forEach(b => b.classList.remove('active'));
      btn.classList.add('active');
      const view = btn.dataset.view;
      localStorage.setItem('batocera_view', view);
      showView(view);
      if (nav) nav.classList.remove('open');
    });
  });

  document.addEventListener('click', () => {
    if (nav) nav.classList.remove('open');
  });
}

function showView(name) {
  document.querySelectorAll('.view').forEach(v => v.classList.remove('active'));
  const el = document.getElementById('view-' + name);
  if (el) el.classList.add('active');
  if (name === 'dashboard') refreshDashboard();
  else if (name === 'roms') loadRoms();
  else if (name === 'files') loadFiles(state.currentPath);
  else if (name === 'terminal') document.getElementById('terminal-input').focus();
  else if (name === 'systems') showSystems();
  else if (name === 'logs') loadLogs();
}

// ── Systems List ────────────────────────────────────────────────────────────

async function loadSystemsList() {
  try {
    const data = await fetchJSON('/api/systems');
    state.systems = data.systems;
    const sel = document.getElementById('rom-system');
    sel.innerHTML = '<option value="all">ALL SYSTEMS</option>';
    state.systems.forEach(s => sel.innerHTML += `<option value="${escapeHtml(s)}">${escapeHtml(s.toUpperCase())}</option>`);
  } catch {}
}

// ── Dashboard ───────────────────────────────────────────────────────────────

async function refreshDashboard() {
  const infoEl = document.getElementById('sysinfo');
  try {
    const [status, sys] = await Promise.all([fetchJSON('/api/status'), fetchJSON('/api/status/system')]);
    const upStr = status.uptime.includes('up') ? status.uptime.split('up')[1].split(',')[0].trim() : status.uptime;
    const diskLine = status.disk.split('\n').find(l => l.includes('/userdata')) || status.disk.split('\n')[1] || '';
    infoEl.textContent = `BATOCERA: ${sys.version}\nUP: ${upStr}\n\nSTORAGE:\n${diskLine.trim()}`;
  } catch { infoEl.textContent = 'SSH CONNECTION LOST'; }
}

// ── Stats Stream with reconnect ─────────────────────────────────────────────

function startStatsStream() {
  if (state.statsSource) state.statsSource.close();

  const connect = () => {
    const src = new EventSource('/api/stats/stream');

    src.onmessage = (evt) => {
      try {
        const data = JSON.parse(evt.data);
        document.getElementById('stat-cpu').textContent = data.cpu + '%';
        document.getElementById('stat-mem').textContent = data.mem + '%';
        document.getElementById('stat-temp').textContent = data.temp + '°C';
        document.getElementById('bar-cpu').value = parseFloat(data.cpu);
        document.getElementById('bar-mem').value = parseFloat(data.mem);
        const t = parseFloat(data.temp);
        if (!isNaN(t)) document.getElementById('bar-temp').value = Math.min(100, (t / 90) * 100);
      } catch {}
    };

    src.onopen = () => {
      state.retryDelay = 1000;
    };

    src.onerror = () => {
      src.close();
      const delay = Math.min(30000, state.retryDelay);
      state.retryDelay = delay * 2;
      setTimeout(connect, delay);
    };

    state.statsSource = src;
  };

  connect();
}

// ── ROM Library ─────────────────────────────────────────────────────────────

async function loadRoms(append = false) {
  if (state.romsLoading) return;
  state.romsLoading = true;

  if (!append) {
    state.romsOffset = 0;
    state.roms = [];
    state.filteredRoms = [];
  }

  const system = document.getElementById('rom-system').value;
  const grid = document.getElementById('rom-list');

  if (!append) {
    grid.innerHTML = getLoadingHtml('SYNCING LIBRARY...');
  }

  try {
    const url = `/api/roms?system=${encodeURIComponent(system)}&limit=${state.romsLimit}&offset=${state.romsOffset}`;
    const data = await fetchJSON(url);

    state.romsTotal = data.total;
    state.romsOffset = data.offset + data.roms.length;

    if (append) {
      state.roms = state.roms.concat(data.roms);
    } else {
      state.roms = data.roms;
    }
    state.filteredRoms = state.roms;

    renderRoms(state.filteredRoms, append);

    const remaining = state.romsTotal - state.romsOffset;
    updateLoadMoreButton(remaining);

    if (!append) {
      toast(`Library: ${data.roms.length} games loaded (${state.romsTotal} total).`);
    } else if (data.roms.length > 0) {
      toast(`Loaded ${data.roms.length} more games.`);
    }
  } catch (err) {
    if (!append) grid.innerHTML = '<div class="loading">Failed to load ROMs</div>';
    toast(`Sync failed: ${err.message}`, true);
  } finally {
    state.romsLoading = false;
  }
}

function updateLoadMoreButton(remaining) {
  let btn = document.getElementById('load-more-btn');
  const grid = document.getElementById('rom-list');

  if (remaining > 0) {
    if (!btn) {
      btn = document.createElement('button');
      btn.id = 'load-more-btn';
      btn.className = 'nes-btn is-primary load-more-btn';
      btn.onclick = () => loadRoms(true);
      grid.parentNode.insertBefore(btn, grid.nextSibling);
    }
    btn.textContent = `Load ${Math.min(remaining, state.romsLimit)} more (${remaining} remaining)`;
    btn.style.display = '';
  } else if (btn) {
    btn.style.display = 'none';
  }
}

function renderRoms(roms, append = false) {
  const grid = document.getElementById('rom-list');
  if (!roms.length && !append) {
    grid.innerHTML = '<div class="loading">No games found</div>';
    return;
  }

  const startIdx = append ? (grid.querySelectorAll('.rom-card').length) : 0;

  const html = roms.slice(append ? grid.querySelectorAll('.rom-card').length : 0).map((r, i) => {
    const idx = startIdx + i;
    return `
      <div class="rom-card" onclick="openGameModal(${idx})">
        <div class="rom-image-container">
          <div class="rom-placeholder" id="placeholder-${idx}">🎮</div>
          <img src="${escapeHtml(r.image)}" loading="lazy"
               onload="const p=document.getElementById('placeholder-${idx}'); if(p) p.style.display='none'"
               onerror="this.style.display='none'">
        </div>
        <div class="rom-info">
          <span class="rom-system-badge">${escapeHtml(r.system)}</span>
          <span class="rom-name" title="${escapeHtml(r.name)}">${escapeHtml(r.name)}</span>
        </div>
      </div>
    `;
  }).join('');

  if (append) {
    grid.insertAdjacentHTML('beforeend', html);
  } else {
    grid.innerHTML = html;
  }
}

// Search with 300ms debounce
let _searchTimeout = null;
function filterRoms() {
  clearTimeout(_searchTimeout);
  _searchTimeout = setTimeout(() => {
    const query = document.getElementById('rom-search').value.toLowerCase().trim();
    const normalize = (str) => str.normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase();

    if (!query) {
      state.filteredRoms = state.roms;
    } else {
      const words = normalize(query).split(/\s+/);
      state.filteredRoms = state.roms.filter(r => {
        const combined = `${normalize(r.name || '')} ${normalize(r.system || '')}`;
        return words.every(w => combined.includes(w));
      });
    }
    renderRoms(state.filteredRoms);
    updateLoadMoreButton(0); // hide load-more when filtering
  }, 300);
}

function openGameModal(idx) {
  const game = state.filteredRoms[idx];
  document.getElementById('modal-game-img').src = game.image;
  document.getElementById('modal-game-name').textContent = game.name;
  document.getElementById('modal-game-system').innerHTML = `<span class="is-warning">${escapeHtml(game.system.toUpperCase())}</span>`;
  document.getElementById('modal-game-dev').textContent = game.dev || 'Unknown Developer';
  document.getElementById('modal-game-date').textContent = (game.date || 'Unknown Date').substring(0, 4);
  document.getElementById('modal-game-desc').textContent = game.desc;
  document.getElementById('game-modal').showModal();
}

function closeGameModal() { document.getElementById('game-modal').close(); }

async function doAction(action) {
  try {
    await postJSON('/api/system/control', { action });
    toast(`[SUCCESS] Execution: ${action.replace('-', ' ')}`);
  } catch (e) { toast(`[ERROR] Command failed: ${e.message}`, true); }
}

// ── File Browser ────────────────────────────────────────────────────────────

async function loadFiles(dir) {
  state.currentPath = dir;

  const bar = document.getElementById('current-path-bar');
  const parts = dir.split('/').filter(p => p && p !== 'userdata');
  let pathAcc = '/userdata';
  bar.innerHTML = `<span class="breadcrumb-item" onclick="loadFiles('/userdata')">🏠 userdata</span>`;
  parts.forEach(p => {
    pathAcc += '/' + p;
    const safePath = escapePath(pathAcc);
    bar.innerHTML += ` / <span class="breadcrumb-item" onclick="loadFiles('${safePath}')">${escapeHtml(p)}</span>`;
  });

  const el = document.getElementById('file-list');
  el.innerHTML = getLoadingHtml('READING STORAGE...');
  try {
    const data = await fetchJSON('/api/files/list?dir=' + encodeURIComponent(dir));
    el.innerHTML = data.files.map(f => {
      const fullPath = (state.currentPath + '/' + f.name).replace(/\/\//g, '/');
      const safePath = escapePath(fullPath);
      const safeEncodedPath = encodeURIComponent(fullPath);
      return `
        <div class="file-item">
          <span class="file-icon">${f.isDir ? '📁' : '📄'}</span>
          <span class="file-name ${f.isDir ? 'is-dir' : ''}"
                ${f.isDir ? `onclick="loadFiles('${safePath}')"` : ''}>${escapeHtml(f.name)}</span>
          <span class="file-size">${f.isDir ? '--' : escapeHtml(f.size)}</span>
          <div class="file-actions" style="display:flex; gap:10px">
            ${!f.isDir ? `<button class="nes-btn is-primary btn-sm" onclick="window.location='/api/files/download?path=${safeEncodedPath}'">⬇️</button>` : ''}
            <button class="nes-btn is-error btn-sm" onclick="deleteFile('${safePath}')">🗑️</button>
          </div>
        </div>
      `;
    }).join('');
  } catch (err) {
    el.innerHTML = '<div class="loading">Error loading directory</div>';
    toast(`Access denied: ${err.message}`, true);
  }
}

async function performUpload() {
  const input = document.getElementById('file-upload-input');
  if (!input.files.length) return;
  const file = input.files[0];
  const formData = new FormData();
  formData.append('file', file);
  formData.append('dir', state.currentPath);

  toast('Uploading ' + escapeHtml(file.name) + '...');
  try {
    const r = await fetch('/api/files/upload', { method: 'POST', body: formData });
    if (!r.ok) throw new Error(await r.text());
    toast('Upload successful!');
    loadFiles(state.currentPath);
  } catch (e) { toast('Upload failed: ' + e.message, true); }
  input.value = '';
}

async function deleteFile(path) {
  if (!confirm(`Are you sure you want to delete:\n${path}?`)) return;
  toast('[WAIT] Deleting file...');
  try {
    await postJSON('/api/files/delete', { path });
    toast('[SUCCESS] File deleted successfully');
    loadFiles(state.currentPath);
  } catch (e) {
    toast(`[ERROR] Delete failed: ${e.message}`, true);
  }
}

// ── Health & Settings ────────────────────────────────────────────────────────

async function checkHealth() {
  try {
    const data = await fetchJSON('/health');
    state.sshConnected = (data.status === 'ok');
    updateSshStatus(state.sshConnected, data.mode);
    return data;
  } catch {
    state.sshConnected = false;
    updateSshStatus(false);
    return { status: 'error' };
  }
}

async function loadLogs() {
  const type = document.getElementById('log-type').value;
  const el = document.getElementById('log-output');
  el.textContent = 'Fetching logs from remote...';
  try {
    const data = await fetchJSON('/api/logs?type=' + type);
    el.textContent = data.log || 'Log is empty.';
    el.scrollTop = el.scrollHeight;
  } catch (e) { el.textContent = 'Error loading logs: ' + e.message; }
}

async function loadSettings() {
  try {
    const data = await fetchJSON('/api/settings');
    document.getElementById('cfg-host').value = data.host || '';
    document.getElementById('cfg-user').value = data.user || '';
    document.getElementById('cfg-pass').value = data.pass || '';
  } catch (e) { console.warn('Failed to fetch settings:', e.message); }
}

async function saveSettings() {
  const host = document.getElementById('cfg-host').value;
  const user = document.getElementById('cfg-user').value;
  const pass = document.getElementById('cfg-pass').value;
  if (!host || !user) return toast('Host and Username are required', true);

  toast('[WAIT] Saving SSH credentials...');
  try {
    await postJSON('/api/settings', { host, user, pass });
    toast('[SUCCESS] SSH settings updated! Reconnecting...');
    setTimeout(() => location.reload(), 1500);
  } catch (e) { toast(`[ERROR] Setup failed: ${e.message}`, true); }
}

function updateSshStatus(c, mode) {
  const el = document.getElementById('ssh-status');
  if (el) {
    if (mode === 'native') {
      el.innerHTML = '<span class="is-success">ONLINE</span>';
    } else {
      el.innerHTML = c ? '<span class="is-success">Connected</span>' : '<span class="is-error">Offline</span>';
    }
  }
}

// ── Terminal ────────────────────────────────────────────────────────────────

async function handleTerminalKey(e) {
  if (e.key === 'Enter') {
    const input = document.getElementById('terminal-input');
    const cmd = input.value.trim();
    if (!cmd) return;

    appendTerminal(`\n> ${cmd}`);
    input.value = '';

    try {
      const res = await postJSON('/api/command', { cmd });
      if (res.stdout) appendTerminal(res.stdout);
      if (res.stderr) appendTerminal(res.stderr, true);
    } catch (err) {
      appendTerminal(`Error: ${err.message}`, true);
    }
  }
}

function appendTerminal(txt, isError = false) {
  const out = document.getElementById('terminal-output');
  const span = document.createElement('span');
  if (isError) span.style.color = 'var(--error)';
  span.textContent = txt;
  out.appendChild(span);
  out.scrollTop = out.scrollHeight;
}

function clearTerminal() {
  document.getElementById('terminal-output').textContent = 'Ready...';
}

// ── Helpers ─────────────────────────────────────────────────────────────────

window.fetchJSON = async function(u) {
  const r = await fetch(u);
  if (!r.ok) { const err = await r.json(); throw new Error(err.error || r.statusText); }
  return r.json();
};

window.postJSON = async function(u, b) {
  const r = await fetch(u, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(b) });
  const res = await r.json();
  if (!r.ok) throw new Error(res.error || 'Server Error');
  return res;
};

// Toast: max one error toast at a time, tracked by id
window.toast = function(m, isError = false) {
  const el = document.getElementById('toast');
  const id = Date.now();

  if (isError && state.activeToastId) {
    // Replace existing error toast immediately
  }
  state.activeToastId = id;

  const now = new Date().toLocaleTimeString();
  el.innerHTML = `<span style="opacity:0.5; font-size: 8px;">${now}</span><br>${escapeHtml(m)}`;
  el.className = 'toast' + (isError ? ' error' : '') + ' show';

  setTimeout(() => {
    if (state.activeToastId === id) {
      el.className = 'toast';
      state.activeToastId = null;
    }
  }, 5000);
};

window.getLoadingHtml = function(m = 'LOADING...') {
  return `
    <div class="loading-container">
      <div class="pixel-loader"></div>
      <div class="loading-text">${escapeHtml(m)}</div>
    </div>
  `;
};

function navigateUp() {
  const p = state.currentPath.split('/').filter(Boolean);
  p.pop();
  loadFiles('/' + p.join('/') || '/userdata');
}
function navigateHome() { loadFiles('/userdata'); }

// refreshGamelist is an alias used by the Refresh button in the ROM view
function refreshGamelist() { loadRoms(); }

init();
