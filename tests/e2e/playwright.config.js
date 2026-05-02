const { defineConfig, devices } = require('@playwright/test');

module.exports = defineConfig({
  testDir: './specs',
  timeout: 30_000,
  retries: process.env.CI ? 2 : 0,
  workers: 1,
  reporter: [['list'], ['html', { open: 'never' }]],

  use: {
    trace: 'on-first-retry',
    screenshot: 'only-on-failure',
    video: 'off',
  },

  projects: [
    {
      name: 'Remote Mode',
      use: {
        ...devices['Desktop Chrome'],
        baseURL: 'http://localhost:8091',
      },
      testMatch: '**/remote*.spec.js',
    },
    {
      name: 'Native Mode',
      use: {
        ...devices['Desktop Chrome'],
        baseURL: 'http://localhost:8092',
      },
      testMatch: '**/native*.spec.js',
    },
    {
      name: 'Mobile (Remote)',
      use: {
        browserName: 'chromium',
        viewport: { width: 390, height: 844 },
        userAgent: 'Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Mobile/15E148 Safari/604.1',
        isMobile: true,
        hasTouch: true,
        baseURL: 'http://localhost:8091',
      },
      testMatch: '**/mobile*.spec.js',
    },
  ],
});
