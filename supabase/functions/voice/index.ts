import { authenticate } from '../_shared/auth.ts';
import { asUser } from '../_shared/db.ts';
import { createHandler } from './handler.ts';
import { addItems } from './items.ts';

Deno.serve(createHandler({
  authenticate: (req) => authenticate(req),
  addItems: (auth, items) => asUser(auth.userId, (tx) => addItems(tx, auth.householdId, items)),
}));
