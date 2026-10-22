import { json, preflight } from '../_shared/http.ts';

export function handle(req: Request): Response {
  return preflight(req) ?? json({ ok: true, service: 'family-groceries' });
}
