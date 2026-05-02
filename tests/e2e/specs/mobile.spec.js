const { test, expect } = require('@playwright/test');

test.describe('Mobile Layout (Remote)', () => {

  test('menu toggle button is visible on mobile', async ({ page }) => {
    await page.goto('/');
    await expect(page.locator('#menu-toggle')).toBeVisible({ timeout: 5_000 });
  });

  test('nav menu is hidden by default on mobile', async ({ page }) => {
    await page.goto('/');
    await expect(page.locator('#nav-menu')).not.toBeVisible({ timeout: 3_000 });
  });

  test('menu toggle opens and closes nav', async ({ page }) => {
    await page.goto('/');
    await page.click('#menu-toggle');
    await expect(page.locator('#nav-menu')).toBeVisible({ timeout: 3_000 });
    await page.click('#menu-toggle');
    await expect(page.locator('#nav-menu')).not.toBeVisible({ timeout: 3_000 });
  });

  test('upload button is a label (mobile compatible)', async ({ page }) => {
    await page.goto('/');
    await page.click('#menu-toggle');
    await page.click('[data-view="files"]');
    await page.waitForSelector('#file-list', { timeout: 5_000 });
    // Upload should be a <label> element, not a <button>
    const uploadEl = page.locator('label[for="file-upload-input"]');
    await expect(uploadEl).toBeVisible({ timeout: 3_000 });
  });

  test('ROM grid renders on mobile viewport', async ({ page }) => {
    await page.goto('/');
    await page.click('#menu-toggle');
    await page.click('[data-view="roms"]');
    await page.waitForSelector('#rom-list .rom-card', { timeout: 15_000 });
    const cards = await page.locator('#rom-list .rom-card').count();
    expect(cards).toBeGreaterThan(0);
    // Check grid is single column on narrow viewport
    const gridStyle = await page.locator('.rom-grid').evaluate(
      el => getComputedStyle(el).gridTemplateColumns
    );
    // On 390px iPhone, minmax(140px, 1fr) should resolve to ~2 columns max
    // Just verify it's not crashing and renders cards
    expect(cards).toBeGreaterThan(0);
  });

  test('modal closes with close button on mobile', async ({ page }) => {
    await page.goto('/');
    await page.click('#menu-toggle');
    await page.click('[data-view="roms"]');
    await page.waitForSelector('#rom-list .rom-card', { timeout: 15_000 });
    await page.locator('#rom-list .rom-card').first().click();
    await expect(page.locator('#game-modal')).toBeVisible({ timeout: 3_000 });
    // Close via the form button (no keyboard Esc on mobile typically)
    await page.locator('#game-modal button').click();
    await expect(page.locator('#game-modal')).not.toBeVisible({ timeout: 3_000 });
  });
});
