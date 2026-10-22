import { assertEquals } from '@std/assert';
import { handle } from './handler.ts';

Deno.test('health answers ok with JSON and CORS headers', async () => {
  const res = handle(new Request('http://local/health'));
  assertEquals(res.status, 200);
  assertEquals(res.headers.get('access-control-allow-origin'), '*');
  assertEquals(await res.json(), { ok: true, service: 'family-groceries' });
});

Deno.test('health answers CORS preflight without a body', async () => {
  const res = handle(new Request('http://local/health', { method: 'OPTIONS' }));
  assertEquals(res.status, 204);
  assertEquals(await res.text(), '');
});
