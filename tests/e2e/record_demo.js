/**
 * Records a demo walkthrough of the dashboard as a video,
 * for conversion to GIF via ffmpeg.
 *
 * Run with: node record_demo.js
 * Output:   tests/e2e/demo-recording/<id>.webm
 */
const { chromium } = require('@playwright/test');
const path = require('path');
const fs = require('fs');

const OUT_DIR = path.resolve(__dirname, 'demo-recording');
fs.rmSync(OUT_DIR, { recursive: true, force: true });
fs.mkdirSync(OUT_DIR, { recursive: true });

const sleep = ms => new Promise(r => setTimeout(r, ms));

async function moveTo(page, sel, steps = 20) {
  const el = await page.locator(sel).first();
  const box = await el.boundingBox();
  if (!box) return;
  const x = box.x + box.width / 2;
  const y = box.y + box.height / 2;
  await page.mouse.move(x, y, { steps });
}

(async () => {
  const browser = await chromium.launch();
  const ctx = await browser.newContext({
    viewport: { width: 1280, height: 720 },
    recordVideo: { dir: OUT_DIR, size: { width: 1280, height: 720 } },
  });
  const page = await ctx.newPage();

  console.log('Recording demo...');

  // 1. Dashboard
  await page.goto('http://localhost:8091/');
  await page.waitForSelector('#stat-cpu', { timeout: 10_000 });
  await page.waitForSelector('#sysinfo', { timeout: 8_000 });
  await sleep(2500);

  // 2. ROM Library
  await moveTo(page, '[data-view="roms"]');
  await sleep(300);
  await page.click('[data-view="roms"]');
  await page.waitForSelector('#rom-list .rom-card', { timeout: 15_000 });
  await sleep(1800);

  // 3. Search
  await moveTo(page, '#rom-search');
  await page.click('#rom-search');
  await page.type('#rom-search', 'mario', { delay: 130 });
  await sleep(1800);
  await page.fill('#rom-search', '');
  await sleep(700);

  // 4. Open game modal
  await moveTo(page, '#rom-list .rom-card');
  await page.locator('#rom-list .rom-card').first().click();
  await page.waitForSelector('#game-modal[open]', { timeout: 3_000 });
  await sleep(2500);
  await page.keyboard.press('Escape');
  await sleep(700);

  // 5. File browser
  await moveTo(page, '[data-view="files"]');
  await page.click('[data-view="files"]');
  await page.waitForSelector('#file-list .file-item', { timeout: 8_000 });
  await sleep(1800);

  // 6. Terminal
  await moveTo(page, '[data-view="terminal"]');
  await page.click('[data-view="terminal"]');
  await page.waitForSelector('#terminal-input', { timeout: 3_000 });
  await page.click('#terminal-input');
  await page.type('#terminal-input', 'batocera-version', { delay: 80 });
  await sleep(500);
  await page.keyboard.press('Enter');
  await sleep(2000);

  // 7. Back to dashboard
  await moveTo(page, '[data-view="dashboard"]');
  await page.click('[data-view="dashboard"]');
  await sleep(2000);

  await ctx.close();
  await browser.close();

  // Find the produced video
  const files = fs.readdirSync(OUT_DIR).filter(f => f.endsWith('.webm'));
  if (files.length) {
    console.log(`✓ Video saved: ${path.join(OUT_DIR, files[0])}`);
  } else {
    console.error('✗ No video produced');
    process.exit(1);
  }
})();
