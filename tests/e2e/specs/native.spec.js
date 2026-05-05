const { test, expect } = require('@playwright/test');

test.describe('Native Dashboard', () => {

  test('loads with ONLINE status (no SSH setup needed)', async ({ page }) => {
    await page.goto('/');
    await page.waitForSelector('#ssh-status', { timeout: 10_000 });
    const status = await page.locator('#ssh-status').textContent();
    expect(status).toContain('ONLINE');
  });

  test('settings tab is hidden in native mode', async ({ page }) => {
    await page.goto('/');
    const settingsBtn = page.locator('[data-view="settings"]');
    await expect(settingsBtn).not.toBeVisible({ timeout: 5_000 });
  });

  test('library shows ROMs with gamelist metadata', async ({ page }) => {
    await page.goto('/');
    await page.click('[data-view="roms"]');
    await page.waitForSelector('#rom-list .rom-card', { timeout: 15_000 });
    const cards = await page.locator('#rom-list .rom-card').count();
    expect(cards).toBeGreaterThan(0);
  });

  test('stats update via SSE stream', async ({ page }) => {
    await page.goto('/');
    await page.waitForSelector('#stat-cpu', { timeout: 10_000 });
    await expect(page.locator('#stat-cpu')).not.toHaveText('—', { timeout: 8_000 });
  });

  test('file upload controls are wired', async ({ page }) => {
    await page.goto('/');
    await page.click('[data-view="files"]');
    await page.waitForSelector('#file-upload-input', { state: 'attached', timeout: 10_000 });

    const uploadFunctions = await page.evaluate(() => ({
      uploadFile: typeof window.uploadFile,
      performUpload: typeof window.performUpload,
    }));

    expect(uploadFunctions.uploadFile).toBe('function');
    expect(uploadFunctions.performUpload).toBe('function');
  });
});
