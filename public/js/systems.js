/**
 * Batocera Web UI - Systems Settings Module (NES.css version)
 */

const SYSTEM_DEFS = {
  global: {
    name: 'Global Settings',
    icon: '🌐',
    description: 'General emulation and system-wide configurations.',
    configs: [
      { key: 'emulator', label: 'Default Emulator', type: 'select', options: ['default', 'libretro', 'standalone'], default: 'default' },
      { key: 'video_filter', label: 'Global Video Filter', type: 'select', options: ['none', 'scanlines', 'retro-v2', 'smooth'], default: 'none' },
      { key: 'rewind', label: 'Rewind Support', type: 'bool', default: 'false' },
      { key: 'bezel', label: 'Bezel Decoration', type: 'bool', default: 'true' },
      { key: 'language', label: 'Language', type: 'select', options: ['en_US', 'de_DE', 'fr_FR', 'es_ES'], default: 'en_US' },
    ],
  },
  wiiu: {
    name: 'Wii U',
    icon: '🕹️',
    description: 'Nintendo Wii U',
    configs: [
      { key: 'emulator', label: 'Emulator', type: 'select', options: ['cemu', 'dolphin', 'default'], default: 'cemu' },
      { key: 'core', label: 'Core', type: 'select', options: ['default', 'fast', 'compatibility'], default: 'default' },
      { key: 'gamelist', label: 'Use Gamelist', type: 'bool', default: 'true' },
    ],
  },
  ps2: {
    name: 'PS2',
    icon: '🎮',
    description: 'Sony PlayStation 2',
    configs: [
      { key: 'emulator', label: 'Emulator', type: 'select', options: ['pcsx2', 'default'], default: 'pcsx2' },
      { key: 'gs', label: 'Graphics Backend', type: 'select', options: ['default', 'vulkan', 'opengl'], default: 'vulkan' },
      { key: 'upscaling', label: 'Upscaling', type: 'select', options: ['native', '2x', '3x', '4x'], default: '2x' },
    ],
  },
  ps3: {
    name: 'PS3',
    icon: '🎮',
    description: 'Sony PlayStation 3',
    configs: [
      { key: 'emulator', label: 'Emulator', type: 'select', options: ['rpcs3', 'default'], default: 'rpcs3' },
      { key: 'renderer', label: 'Renderer', type: 'select', options: ['default', 'vulkan', 'opengl'], default: 'vulkan' },
    ],
  },
  switch: {
    name: 'Switch',
    icon: '🎮',
    description: 'Nintendo Switch',
    configs: [
      { key: 'emulator', label: 'Emulator', type: 'select', options: ['yuzu', 'sudachi', 'default'], default: 'yuzu' },
      { key: 'backend', label: 'GPU Backend', type: 'select', options: ['default', 'vulkan', 'opengl'], default: 'vulkan' },
    ],
  },
};

let activeSystems = [];
let currentSystem = null;
let systemSettings = {};

async function showSystems() {
  const el = document.getElementById('systems-list');
  el.innerHTML = getLoadingHtml('SYNCING...');
  try {
    const data = await fetchJSON('/api/systems/all');
    activeSystems = ['global', ...data.systems];
    renderSystemsList(activeSystems);
    toast(`Systems list updated: ${data.systems.length} platforms found.`);
  } catch (err) {
    activeSystems = Object.keys(SYSTEM_DEFS);
    renderSystemsList(activeSystems);
    toast(`Syncing systems failed. Using offline list.`, true);
  }
}

function renderSystemsList(systems) {
  const el = document.getElementById('systems-list');
  el.innerHTML = systems.map(s => {
    const def = SYSTEM_DEFS[s];
    const name = def ? def.name : s.toUpperCase();
    return `
      <div class="system-item ${currentSystem === s ? 'active' : ''}" data-system="${s}" onclick="selectSystem('${s}')">
        ${name}
      </div>
    `;
  }).join('');
}

function filterSystems() {
  const q = document.getElementById('sys-search').value.toLowerCase();
  const filtered = activeSystems.filter(s => s.toLowerCase().includes(q));
  renderSystemsList(filtered);
}

async function selectSystem(system) {
  currentSystem = system;
  const def = SYSTEM_DEFS[system] || {
    name: system.toUpperCase(),
    configs: [{ key: 'emulator', label: 'Emulator', type: 'select', options: ['default'], default: 'default' }],
  };

  const detail = document.getElementById('systems-detail');
  let formHtml = `
    <div class="config-header">
      <h2 class="nes-text is-primary">${def.name}</h2>
      <p style="font-size: 10px; opacity: 0.7;">${def.description || 'System configuration'}</p>
    </div>
    <div class="config-grid">`;

  def.configs.forEach(cfg => {
    const currentVal = systemSettings[cfg.key] || cfg.default;
    if (cfg.type === 'bool') {
      formHtml += `
        <div class="form-group">
          <label>
            <input type="checkbox" class="nes-checkbox is-dark" id="cfg-${cfg.key}" ${currentVal === 'true' || currentVal === true ? 'checked' : ''} />
            <span>${cfg.label}</span>
          </label>
        </div>
      `;
    } else if (cfg.type === 'select') {
      formHtml += `
        <div class="form-group">
          <label>${cfg.label}</label>
          <div class="nes-select is-dark">
            <select id="cfg-${cfg.key}">
              ${cfg.options.map(opt => `<option value="${opt}" ${currentVal === opt ? 'selected' : ''}>${opt}</option>`).join('')}
            </select>
          </div>
        </div>
      `;
    }
  });

  formHtml += `
    </div>
    <div class="config-actions">
      <button class="nes-btn is-primary" onclick="saveSystemSettings('${system}')" style="width: 100%">Save Configuration</button>
    </div>`;

  detail.innerHTML = formHtml;
  await loadSystemSettings(system);
  
  document.querySelectorAll('.system-item').forEach(item => {
    item.classList.toggle('active', item.dataset.system === system);
  });
}

async function loadSystemSettings(system) {
  try {
    const data = await fetchJSON('/api/systems/' + (system === 'global' ? 'global' : system));
    if (data.batoceraSettings) {
      systemSettings = data.batoceraSettings;
      Object.entries(systemSettings).forEach(([key, val]) => {
        const el = document.getElementById('cfg-' + key);
        if (!el) return;
        if (el.type === 'checkbox') el.checked = (val === 'true' || val === true);
        else el.value = val;
      });
      toast(`[OK] Settings loaded for ${system.toUpperCase()}`);
    }
  } catch (e) { 
    toast(`[ERROR] Failed to fetch settings: ${e.message}`, true);
    console.warn('Load failed:', e.message); 
  }
}

async function saveSystemSettings(system) {
  const def = SYSTEM_DEFS[system] || {
    configs: [{ key: 'emulator', label: 'Emulator', type: 'select', options: ['default'], default: 'default' }],
  };
  const settings = {};
  def.configs.forEach(cfg => {
    const el = document.getElementById('cfg-' + cfg.key);
    if (!el) return;
    settings[cfg.key] = cfg.type === 'bool' ? (el.checked ? 'true' : 'false') : el.value;
  });

  try {
    await postJSON('/api/systems/' + (system === 'global' ? 'global' : system), { settings });
    toast(`[SUCCESS] Configuration saved for ${system.toUpperCase()}`);
  } catch (e) { 
    toast(`[ERROR] Save failed: ${e.message}`, true); 
  }
}
