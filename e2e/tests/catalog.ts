import { expect, type Page } from '@playwright/test';
import { itemRow } from './helpers';

/** The list's group headings, top to bottom (the app bar title excluded). */
export async function groupHeadings(page: Page): Promise<string[]> {
  const headings = await page.getByRole('heading', { level: 2 }).allTextContents();
  return headings.slice(1);
}

/** The heading of the group an item row sits in: the nearest heading above it. */
export async function groupOf(page: Page, item: string): Promise<string | undefined> {
  const row = await itemRow(page, item).boundingBox();
  if (!row) return undefined;
  let found: string | undefined;
  let foundY = -Infinity;
  for (const heading of await page.getByRole('heading', { level: 2 }).all()) {
    const box = await heading.boundingBox();
    if (box && box.y < row.y && box.y > foundY) {
      foundY = box.y;
      found = (await heading.textContent()) ?? undefined;
    }
  }
  return found;
}

export async function expectGroup(page: Page, item: string, group: string): Promise<void> {
  await expect(itemRow(page, item)).toBeVisible();
  await expect.poll(() => groupOf(page, item), { message: `${item} is under ${group}` }).toBe(group);
}

/** Long-press drag of an item row onto a group heading. */
export async function dragItemTo(page: Page, item: string, group: string): Promise<void> {
  const from = (await itemRow(page, item).boundingBox())!;
  await page.mouse.move(from.x + from.width / 2, from.y + from.height / 2);
  await page.mouse.down();
  await page.waitForTimeout(800);
  await page.mouse.move(from.x + from.width / 2, from.y + from.height / 2 + 12, { steps: 4 });
  const target = page.getByRole('heading', { level: 2, name: group, exact: true });
  await expect(target).toBeVisible();
  const to = (await target.boundingBox())!;
  await page.mouse.move(to.x + to.width / 2, to.y + to.height / 2, { steps: 15 });
  await page.waitForTimeout(150);
  await page.mouse.up();
}

/** Drags a row of a reorderable list by its handle to the position of another row. */
export async function dragHandle(page: Page, handleName: string, ontoHandleName: string): Promise<void> {
  const from = (await page.getByText(handleName, { exact: true }).boundingBox())!;
  const to = (await page.getByText(ontoHandleName, { exact: true }).boundingBox())!;
  await page.mouse.move(from.x + from.width / 2, from.y + from.height / 2);
  await page.mouse.down();
  await page.mouse.move(from.x + from.width / 2, from.y + from.height / 2 + 5, { steps: 3 });
  await page.mouse.move(to.x + to.width / 2, to.y + to.height / 2 - 4, { steps: 20 });
  await page.waitForTimeout(300);
  await page.mouse.up();
}

export async function selectStore(page: Page, store: string): Promise<void> {
  await page.getByRole('checkbox', { name: store, exact: true }).click();
}

export async function deleteItem(page: Page, item: string): Promise<void> {
  await itemRow(page, item).click();
  await page.getByRole('button', { name: 'Löschen' }).click();
  await expect(itemRow(page, item)).toHaveCount(0);
}
