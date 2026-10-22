// Static server for the Flutter web build with SPA fallback for path URLs.
// Usage: node e2e/serve.mjs <dir> <port>
import { createReadStream, statSync } from 'node:fs';
import { createServer } from 'node:http';
import { extname, join, normalize } from 'node:path';

const [root, port = '3000'] = process.argv.slice(2);
const types = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript',
  '.mjs': 'text/javascript',
  '.json': 'application/json',
  '.wasm': 'application/wasm',
  '.png': 'image/png',
  '.otf': 'font/otf',
  '.ttf': 'font/ttf',
  '.css': 'text/css',
  '.ico': 'image/x-icon',
};

function resolve(urlPath) {
  const path = normalize(join(root, decodeURIComponent(urlPath.split('?')[0])));
  if (!path.startsWith(normalize(root))) return null;
  try {
    if (statSync(path).isFile()) return path;
  } catch {}
  return null;
}

createServer((req, res) => {
  const file = resolve(req.url) ?? join(root, 'index.html');
  res.writeHead(200, {
    'content-type': types[extname(file)] ?? 'application/octet-stream',
    'cache-control': 'no-store',
  });
  createReadStream(file).pipe(res);
}).listen(Number(port), '127.0.0.1', () => console.log(`serving ${root} on http://127.0.0.1:${port}`));
