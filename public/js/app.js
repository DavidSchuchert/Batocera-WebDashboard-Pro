/**
 * Batocera Web UI - Ultimate Fix (Images & Game Launch)
 */

const state = {
  sshConnected: false,
  currentPath: '/userdata',
  roms: [],
  filteredRoms: [],
  systems: [],
  statsSource: null
};

async function init() {
  setupNav();
  const health = await checkHealth();
  
  if (state.sshConnected || health.mode === 'native') {
    if (health.mode === 'native') {
      state.isNative = true;
      document.querySelector('[data-view="settings"]').style.display = 'none'; // Hide SSH Setup
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
      if (nav) nav.classList.remove('open'); // Close on click
    });
  });

  // Close menu when clicking outside
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

async function loadSystemsList() {
  try {
    const data = await fetchJSON('/api/systems');
    state.systems = data.systems;
    const sel = document.getElementById('rom-system');
    sel.innerHTML = '<option value="all">ALL SYSTEMS</option>';
    state.systems.forEach(s => sel.innerHTML += `<option value="${s}">${s.toUpperCase()}</option>`);
  } catch {}
}

async function refreshDashboard() {
  const infoEl = document.getElementById('sysinfo');
  try {
    const [status, sys] = await Promise.all([fetchJSON('/api/status'), fetchJSON('/api/status/system')]);
    // Extract uptime more cleanly: "11:06:40 up 1:04" -> "UP: 1:04"
    const upStr = status.uptime.includes('up') ? status.uptime.split('up')[1].split(',')[0].trim() : status.uptime;
    // Extract relevant disk info
    const diskLine = status.disk.split('\n').find(l => l.includes('/userdata')) || status.disk.split('\n')[1] || '';
    
    infoEl.textContent = `BATOCERA: ${sys.version}\nUP: ${upStr}\n\nSTORAGE:\n${diskLine.trim()}`;
  } catch { infoEl.textContent = 'SSH CONNECTION LOST'; }
}

function startStatsStream() {
  if (state.statsSource) state.statsSource.close();
  const src = new EventSource('/api/stats/stream');
  src.onmessage = (evt) => {
    try {
      const data = JSON.parse(evt.data);
      document.getElementById('stat-cpu').textContent = data.cpu + '%';
      document.getElementById('stat-mem').textContent = data.mem + '%';
      document.getElementById('stat-temp').textContent = data.temp + '°C';
      
      // NES-Progress elements use .value instead of .style.width
      document.getElementById('bar-cpu').value = parseFloat(data.cpu);
      document.getElementById('bar-mem').value = parseFloat(data.mem);
      const t = parseFloat(data.temp);
      if (!isNaN(t)) document.getElementById('bar-temp').value = Math.min(100, (t/90)*100);
    } catch {}
  };
  state.statsSource = src;
}

async function loadRoms() {
  const system = document.getElementById('rom-system').value;
  const grid = document.getElementById('rom-list');
  grid.innerHTML = getLoadingHtml('SYNCING LIBRARY...');
  try {
    const data = await fetchJSON('/api/roms?system=' + system);
    state.roms = data.roms;
    state.filteredRoms = data.roms;
    renderRoms(state.filteredRoms);
    toast(`Library updated: ${data.roms.length} games found.`);
  } catch (err) { 
    grid.innerHTML = '<div class="loading">Failed to load ROMs</div>'; 
    toast(`Sync failed: ${err.message}`, true);
  }
}

function renderRoms(roms) {
  const grid = document.getElementById('rom-list');
  if (!roms.length) { grid.innerHTML = '<div class="loading">No games found</div>'; return; }
  grid.innerHTML = roms.map((r, idx) => `
    <div class="rom-card" onclick="openGameModal(${idx})">
      <div class="rom-image-container">
        <div class="rom-placeholder" id="placeholder-${idx}">🎮</div>
        <img src="${r.image}" loading="lazy" onload="const p=document.getElementById('placeholder-${idx}'); if(p) p.style.display='none'" onerror="this.style.display='none'">
      </div>
      <div class="rom-info">
        <span class="rom-system-badge">${r.system}</span>
        <span class="rom-name" title="${r.name}">${r.name}</span>
      </div>
    </div>
  `).join('');
}

function filterRoms() {
  const query = document.getElementById('rom-search').value.toLowerCase().trim();
  const normalize = (str) => str.normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase();
  
  if (!query) {
    state.filteredRoms = state.roms;
  } else {
    const searchWords = normalize(query).split(/\s+/);
    state.filteredRoms = state.roms.filter(r => {
      const name = normalize(r.name || '');
      const system = normalize(r.system || '');
      const combined = `${name} ${system}`;
      return searchWords.every(word => combined.includes(word));
    });
  }
  renderRoms(state.filteredRoms);
}

function openGameModal(idx) {
  const game = state.filteredRoms[idx];
  document.getElementById('modal-game-img').src = game.image;
  document.getElementById('modal-game-name').textContent = game.name;
  document.getElementById('modal-game-system').innerHTML = `<span class="is-warning">${game.system.toUpperCase()}</span>`;
  document.getElementById('modal-game-dev').textContent = game.dev || 'Unknown Developer';
  document.getElementById('modal-game-date').textContent = (game.date || 'Unknown Date').substring(0,4);
  document.getElementById('modal-game-desc').textContent = game.desc;
  document.getElementById('game-modal').showModal();
}

function closeGameModal() { document.getElementById('game-modal').close(); }

async function doAction(action) {
  try { 
    await postJSON('/api/system/control', { action }); 
    toast(`[SUCCESS] Execution: ${action.replace('-', ' ')}`); 
  }
  catch (e) { toast(`[ERROR] Command failed: ${e.message}`, true); }
}

async function loadFiles(dir) {
  state.currentPath = dir;
  
  // Update Breadcrumbs
  const bar = document.getElementById('current-path-bar');
  const parts = dir.split('/').filter(p => p && p !== 'userdata');
  let pathAcc = '/userdata';
  bar.innerHTML = '<span class="breadcrumb-item" onclick="loadFiles(\'/userdata\')">🏠 userdata</span>';
  parts.forEach(p => {
    pathAcc += '/' + p;
    bar.innerHTML += ` / <span class="breadcrumb-item" onclick="loadFiles('${pathAcc}')">${p}</span>`;
  });

  const el = document.getElementById('file-list');
  el.innerHTML = getLoadingHtml('READING STORAGE...');
  try {
    const data = await fetchJSON('/api/files/list?dir=' + encodeURIComponent(dir));
    el.innerHTML = data.files.map(f => {
      const fullPath = (state.currentPath + '/' + f.name).replace(/\/\//g, '/');
      return `
        <div class="file-item">
          <span class="file-icon">${f.isDir ? '📁' : '📄'}</span>
          <span class="file-name ${f.isDir ? 'is-dir' : ''}" onclick="${f.isDir ? `loadFiles('${fullPath}')` : ''}">${f.name}</span>
          <span class="file-size">${f.isDir ? '--' : f.size}</span>
          <div class="file-actions" style="display:flex; gap:10px">
            ${!f.isDir ? `<button class="nes-btn is-primary btn-sm" onclick="window.location='/api/files/download?path=${encodeURIComponent(fullPath)}'">⬇️</button>` : ''}
            <button class="nes-btn is-error btn-sm" onclick="deleteFile('${fullPath}')">🗑️</button>
          </div>
        </div>
      `;
    }).join('');
  } catch (err) { 
    el.innerHTML = '<div class="loading">Error loading directory</div>'; 
    toast(`Access denied: ${err.message}`, true);
  }
}

function uploadFile() { document.getElementById('file-upload-input').click(); }

async function performUpload() {
  const input = document.getElementById('file-upload-input');
  if (!input.files.length) return;
  const file = input.files[0];
  const formData = new FormData();
  formData.append('file', file);
  formData.append('dir', state.currentPath);
  
  toast('Uploading ' + file.name + '...');
  try {
    const r = await fetch('/api/files/upload', { method: 'POST', body: formData });
    if (!r.ok) throw new Error(await r.text());
    toast('Upload successful!');
    loadFiles(state.currentPath);
  } catch(e) { toast('Upload failed: ' + e.message, true); }
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
    el.scrollTop = el.scrollHeight; // Auto scroll to bottom
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

// --- Terminal ---
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

window.fetchJSON = async function(u) {
  const r = await fetch(u);
  if (!r.ok) { const err = await r.json(); throw new Error(err.error || r.statusText); }
  return r.json();
}

window.postJSON = async function(u, b) {
  const r = await fetch(u, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(b) });
  const res = await r.json();
  if (!r.ok) throw new Error(res.error || 'Server Error');
  return res;
}

window.toast = function(m, e = false) {
  const el = document.getElementById('toast');
  const now = new Date().toLocaleTimeString();
  el.innerHTML = `<span style="opacity:0.5; font-size: 8px;">${now}</span><br>${m}`;
  el.className = 'toast' + (e ? ' error' : '') + ' show';
  setTimeout(() => el.className = 'toast', 5000);
}

window.getLoadingHtml = function(m = 'LOADING...') {
  return `
    <div class="loading-container">
      <div class="pixel-loader"></div>
      <div class="loading-text">${m}</div>
    </div>
  `;
}

function navigateUp() { const p = state.currentPath.split('/').filter(Boolean); p.pop(); loadFiles('/' + p.join('/') || '/userdata'); }
function navigateHome() { loadFiles('/userdata'); }

init();
