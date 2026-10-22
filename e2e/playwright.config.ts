import { defineConfig, devices } from '@playwright/test';

const port = Number(process.env.WEB_PORT ?? 3100);

export default defineConfig({
  testDir: './tests',
  timeout: 60_000,
  expect: { timeout: 10_000 },
  fullyParallel: true,
  workers: process.env.CI ? 2 : 3,
  retries: 0,
  reporter: process.env.CI ? [['list'], ['html', { open: 'never' }]] : 'list',
  use: {
    baseURL: `http://127.0.0.1:${port}`,
    locale: 'de-DE',
    timezoneId: 'Europe/Berlin',
    trace: 'retain-on-failure',
    screenshot: 'only-on-failure',
    ...devices['Desktop Chrome'],
    viewport: { width: 480, height: 900 },
    // Supabase Auth sends the browser to the fake identity provider by the
    // name its container knows it under.
    launchOptions: { args: ['--host-resolver-rules=MAP host.docker.internal 127.0.0.1'] },
  },
  webServer: [
    {
      command: `node serve.mjs ../app/build/web ${port}`,
      url: `http://127.0.0.1:${port}`,
      reuseExistingServer: !process.env.CI,
    },
    {
      // Every copy signs with the same key, so one left running is reusable.
      command: 'node fake-oidc.mjs',
      url: 'http://127.0.0.1:54399/realms/test/.well-known/openid-configuration',
      reuseExistingServer: true,
    },
  ],
});
