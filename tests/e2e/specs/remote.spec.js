const { test, expect } = require('@playwright/test');

test.describe('Remote Dashboard', () => {

  test('loads and shows SSH connected status', async ({ page }) => {
    await page.goto('/');
    await expect(page).toHaveTitle(/Batocera/i);
    // Wait for init to complete
    await page.waitForSelector('#ssh-status', { timeout: 10_000 });
    const status = await page.locator('#ssh-status').textContent();
    expect(status).toContain('Connected');
  });

  test('dashboard shows system stats', async ({ page }) => {
    await page.goto('/');
    await page.waitForSelector('#stat-cpu', { timeout: 10_000 });
    // Stats update via SSE — wait for a real value
    await expect(page.locator('#stat-cpu')).not.toHaveText('—', { timeout: 8_000 });
    await expect(page.locator('#stat-mem')).not.toHaveText('—', { timeout: 8_000 });
  });

  test('system info block loads Batocera version', async ({ page }) => {
    await page.goto('/');
    await page.waitForSelector('#sysinfo', { timeout: 10_000 });
    await expect(page.locator('#sysinfo')).toContainText('batocera', { timeout: 8_000 });
  });

  test('library tab loads ROM list', async ({ page }) => {
    await page.goto('/');
    await page.click('[data-view="roms"]');
    await page.waitForSelector('#rom-list .rom-card', { timeout: 15_000 });
    const cards = await page.locator('#rom-list .rom-card').count();
    expect(cards).toBeGreaterThan(0);
  });

  test('ROM system dropdown filters correctly', async ({ page }) => {
    await page.goto('/');
    await page.click('[data-view="roms"]');
    await page.waitForSelector('#rom-list .rom-card', { timeout: 15_000 });

    // Switch to snes only
    await page.selectOption('#rom-system', 'snes');
    await page.waitForTimeout(1000);
    const badges = await page.locator('.rom-system-badge').allTextContents();
    expect(badges.every(b => b.toLowerCase() === 'snes')).toBe(true);
  });

  test('search filters ROM list', async ({ page }) => {
    await page.goto('/');
    await page.click('[data-view="roms"]');
    await page.waitForSelector('#rom-list .rom-card', { timeout: 15_000 });

    const totalBefore = await page.locator('#rom-list .rom-card').count();
    await page.fill('#rom-search', 'mario');
    await page.waitForTimeout(400); // debounce
    const afterFilter = await page.locator('#rom-list .rom-card').count();
    expect(afterFilter).toBeGreaterThan(0);
    expect(afterFilter).toBeLessThanOrEqual(totalBefore);

    // Names should contain mario
    const names = await page.locator('.rom-name').allTextContents();
    expect(names.every(n => n.toLowerCase().includes('mario'))).toBe(true);
  });

  test('ROM card opens detail modal', async ({ page }) => {
    await page.goto('/');
    await page.click('[data-view="roms"]');
    await page.waitForSelector('#rom-list .rom-card', { timeout: 15_000 });
    await page.locator('#rom-list .rom-card').first().click();
    await expect(page.locator('#game-modal')).toBeVisible({ timeout: 3_000 });
    // Modal shows game name (not empty)
    const name = await page.locator('#modal-game-name').textContent();
    expect(name?.trim().length).toBeGreaterThan(0);
  });

  test('Esc closes game modal', async ({ page }) => {
    await page.goto('/');
    await page.click('[data-view="roms"]');
    await page.waitForSelector('#rom-list .rom-card', { timeout: 15_000 });
    await page.locator('#rom-list .rom-card').first().click();
    await expect(page.locator('#game-modal')).toBeVisible({ timeout: 3_000 });
    await page.keyboard.press('Escape');
    await expect(page.locator('#game-modal')).not.toBeVisible({ timeout: 3_000 });
  });

  test('file browser lists /userdata', async ({ page }) => {
    await page.goto('/');
    await page.click('[data-view="files"]');
    await page.waitForSelector('#file-list .file-item', { timeout: 10_000 });
    const items = await page.locator('#file-list .file-item').count();
    expect(items).toBeGreaterThan(0);
    // Should show roms and system dirs
    const names = await page.locator('.file-name').allTextContents();
    expect(names.some(n => n.includes('roms'))).toBe(true);
  });

  test('terminal input accepts and runs command', async ({ page }) => {
    await page.goto('/');
    await page.click('[data-view="terminal"]');
    await page.waitForSelector('#terminal-input', { timeout: 5_000 });
    await page.fill('#terminal-input', 'echo hello_test');
    await page.keyboard.press('Enter');
    await expect(page.locator('#terminal-output')).toContainText('hello_test', { timeout: 5_000 });
  });

  test('logs tab loads ES log content', async ({ page }) => {
    await page.goto('/');
    await page.click('[data-view="logs"]');
    await expect(page.locator('#log-output')).not.toHaveText('...', { timeout: 8_000 });
    const content = await page.locator('#log-output').textContent();
    expect(content?.length).toBeGreaterThan(10);
  });

  test('nav saves active view in localStorage', async ({ page }) => {
    await page.goto('/');
    // Wait for full init before navigating
    await page.waitForSelector('#ssh-status', { timeout: 10_000 });
    await page.click('[data-view="roms"]');
    await page.waitForSelector('#rom-list', { timeout: 10_000 });
    await page.reload();
    // After reload, init() restores saved view — wait for rom-list to be visible
    await expect(page.locator('#view-roms')).toHaveClass(/active/, { timeout: 10_000 });
  });
});
