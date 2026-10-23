import { defineConfig, devices } from '@playwright/test';
import { fakeOidcPort, webPort as port } from './stack';

export default defineConfig({
  testDir: './tests',
  timeout: 60_000,
  expect: { timeout: 10_000 },
  fullyParallel: true,
  // One locally: the box's RAM is shared by parallel jobs (COORDINATION.md, Memory).
  workers: process.env.CI ? 2 : 1,
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
      command: `node fake-oidc.mjs ${fakeOidcPort}`,
      url: `http://127.0.0.1:${fakeOidcPort}/realms/test/.well-known/openid-configuration`,
      reuseExistingServer: true,
    },
  ],
});
