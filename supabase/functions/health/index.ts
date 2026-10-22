// Liveness probe for deploy checks: GET /functions/v1/health -> {"ok": true}.
import { handle } from './handler.ts';

Deno.serve(handle);
