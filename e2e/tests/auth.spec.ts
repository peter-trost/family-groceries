import { expect, test } from './fixtures';
import { addField, latestLinkFor, newEmail, password, signUpWithHousehold, typeInto } from './helpers';

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
