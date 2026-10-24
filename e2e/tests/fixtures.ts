import { test as base } from '@playwright/test';

export * from '@playwright/test';

/**
 * Playwright's `test`, plus closing every browser context a test opened. Specs open their own
 * contexts (one per user), and the browser outlives the test, so without this each test leaves
 * its Flutter apps running and later tests boot into a crowded browser.
 */
export const test = base.extend<{ closeContexts: void }>({
  closeContexts: [
    async ({ browser }, use) => {
      const before = new Set(browser.contexts());
      await use();
      await Promise.all(browser.contexts().filter((c) => !before.has(c)).map((c) => c.close()));
    },
    { auto: true },
  ],
});
