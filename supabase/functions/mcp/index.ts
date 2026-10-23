// MCP server for the shopping list: POST /functions/v1/mcp (streamable HTTP, OAuth 2.1 or PAT).
import { handle } from './handler.ts';

Deno.serve((req) => handle(req));
