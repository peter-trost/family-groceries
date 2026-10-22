# Einkauf (family-groceries)

A shared grocery list for one household. Open the app and the cursor is
already in the "Was fehlt?" field with the list beneath it. Items sort
themselves into store-route categories, ticking one off removes it on every
phone at once, and an undo is one tap away.

Flutter (iOS, Android, web) on Supabase. See [`docs/SPEC.md`](docs/SPEC.md)
for the full product spec.

## Quick start

```bash
scripts/bootstrap.sh          # Flutter, Docker, Supabase CLI, Deno, gitleaks, Playwright
scripts/dev.sh                # local Supabase + web app on http://127.0.0.1:3000
scripts/verify.sh             # everything CI runs, incl. Playwright e2e
```

Local mail (magic links) lands in Mailpit at http://127.0.0.1:54324.
`scripts/dev.sh --stop` stops the local stack.

## Repository

| Path | What |
| --- | --- |
| `app/` | Flutter app |
| `supabase/` | migrations, pgTAP tests, edge functions, local config |
| `e2e/` | Playwright tests against the web build |
| `scripts/` | bootstrap, dev, verify |
| `docs/` | spec, decisions, open items for Peter, emotely reuse notes |

## Configuration

The app defaults to the hosted project `jdwqrallbpdbshrdhenk` with its public
publishable key. Point it elsewhere with
`--dart-define=SUPABASE_URL=... --dart-define=SUPABASE_PUBLISHABLE_KEY=...`.
Admin credentials (`SUPABASE_ACCESS_TOKEN`, `SUPABASE_DB_PASSWORD`) never go
in the repo; see [`.env.example`](.env.example) and
[`docs/NEEDS_PETER.md`](docs/NEEDS_PETER.md).
