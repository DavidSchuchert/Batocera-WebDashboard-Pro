const { chromium } = require('@playwright/test');
const path = require('path');

const OUT = path.resolve(__dirname, '../../screenshots');

async function shot(page, name) {
  await page.screenshot({ path: `${OUT}/${name}.png`, fullPage: false });
  console.log(`  ✓ ${name}.png`);
}

(async () => {
  const browser = await chromium.launch();
  const ctx = await browser.newContext({ viewport: { width: 1400, height: 860 } });
  const page = await ctx.newPage();

  console.log('Taking screenshots of Remote Dashboard (http://localhost:8091)...');

  // Dashboard
  await page.goto('http://localhost:8091/');
  await page.waitForSelector('#stat-cpu:not(:has-text("—"))', { timeout: 10000 }).catch(() => {});
  await page.waitForSelector('#sysinfo', { timeout: 8000 });
  await page.waitForTimeout(1500);
  await shot(page, 'dashboard');

  // Library
  await page.click('[data-view="roms"]');
  await page.waitForSelector('#rom-list .rom-card', { timeout: 15000 });
  await page.waitForTimeout(600);
  await shot(page, 'library');

  // ROM modal
  await page.locator('#rom-list .rom-card').first().click();
  await page.waitForSelector('#game-modal[open]', { timeout: 3000 });
  await shot(page, 'rom-modal');
  await page.keyboard.press('Escape');

  // File Manager
  await page.click('[data-view="files"]');
  await page.waitForSelector('#file-list .file-item', { timeout: 8000 });
  await page.waitForTimeout(400);
  await shot(page, 'files');

  // Terminal
  await page.click('[data-view="terminal"]');
  await page.waitForSelector('#terminal-input', { timeout: 3000 });
  await page.fill('#terminal-input', 'batocera-version');
  await page.keyboard.press('Enter');
  await page.waitForTimeout(1000);
  await shot(page, 'terminal');

  // Config
  await page.click('[data-view="systems"]');
  await page.waitForTimeout(800);
  await shot(page, 'config');

  // Mobile view
  const mobileCtx = await browser.newContext({
    viewport: { width: 390, height: 844 },
    userAgent: 'Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15',
    isMobile: true,
  });
  const mobile = await mobileCtx.newPage();
  await mobile.goto('http://localhost:8091/');
  await mobile.waitForSelector('#stat-cpu', { timeout: 10000 });
  await mobile.waitForTimeout(1500);
  await mobile.screenshot({ path: `${OUT}/mobile.png`, fullPage: false });
  console.log('  ✓ mobile.png');

  await browser.close();
  console.log('\nAll screenshots saved to screenshots/');
})();
