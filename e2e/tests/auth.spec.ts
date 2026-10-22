import { expect, test } from '@playwright/test';
import { addField, newEmail, password, signUpWithHousehold, typeInto } from './helpers';

const mailpit = process.env.MAILPIT_URL ?? 'http://127.0.0.1:54324';

async function latestLinkFor(email: string): Promise<string> {
  for (let attempt = 0; attempt < 20; attempt++) {
    const res = await fetch(`${mailpit}/api/v1/search?query=${encodeURIComponent(`to:"${email}"`)}`);
    const { messages } = await res.json() as { messages: { ID: string }[] };
    if (messages.length > 0) {
      const message = await (await fetch(`${mailpit}/api/v1/message/${messages[0].ID}`)).json() as { Text: string };
      const link = message.Text.match(/https?:\/\/\S+\/auth\/v1\/verify\S+/)?.[0];
      if (link) return link;
    }
    await new Promise((r) => setTimeout(r, 500));
  }
  throw new Error(`no magic link mail for ${email}`);
}

test('email and password: sign out and back in', async ({ page }) => {
  const email = newEmail('pw');
  await signUpWithHousehold(page, email);
  await page.getByRole('button', { name: 'Menü' }).click();
  await page.getByRole('menuitem', { name: 'Abmelden' }).click();
  await expect(page).toHaveURL(/\/login$/);

  await typeInto(page.getByRole('textbox', { name: 'E-Mail' }), email);
  await typeInto(page.getByRole('textbox', { name: 'Passwort' }), 'wrong-password');
  await page.getByRole('button', { name: 'Anmelden', exact: true }).click();
  await expect(page.getByText(/Anmeldung fehlgeschlagen/).first()).toBeVisible();

  await typeInto(page.getByRole('textbox', { name: 'Passwort' }), password);
  await page.getByRole('button', { name: 'Anmelden', exact: true }).click();
  await expect(addField(page)).toBeFocused();
});

test('magic link signs in on this device', async ({ page }) => {
  const email = newEmail('magic');
  await signUpWithHousehold(page, email);
  await page.getByRole('button', { name: 'Menü' }).click();
  await page.getByRole('menuitem', { name: 'Abmelden' }).click();

  await typeInto(page.getByRole('textbox', { name: 'E-Mail' }), email);
  await page.getByRole('button', { name: 'Anmeldelink per E-Mail senden' }).click();
  await expect(page.getByText(/Anmeldelink geschickt/).first()).toBeVisible();

  await page.goto(await latestLinkFor(email));
  await expect(addField(page)).toBeFocused();
  await expect(page).toHaveURL(/\/$/);
});
