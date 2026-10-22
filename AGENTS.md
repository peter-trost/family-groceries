# family-groceries

Shared shopping list for one household (Peter and Lea). Flutter app (iOS,
Android, web) on Supabase (Postgres + RLS, Auth, Realtime, Edge Functions).
The product spec is [`docs/SPEC.md`](docs/SPEC.md); decisions and their
reasons are in [`docs/DECISIONS.md`](docs/DECISIONS.md).

## Layout

- `app/`: the Flutter app. `lib/list/` is the list feature (model, cubit,
  repository, screen), `lib/session/` auth and household state,
  `lib/household/` onboarding and invites, `lib/app/` router, environment
  and app shell. UI strings live in `app/l10n/app_de.arb` (German template).
- `supabase/`: `config.toml` for the local stack, `migrations/`, pgTAP tests
  in `tests/`, Deno edge functions in `functions/` (`_shared/` for helpers).
- `e2e/`: Playwright tests that drive the Flutter web build against the local
  stack.
- `scripts/`: `bootstrap.sh` (toolchain), `dev.sh` (local stack + web dev
  server), `verify.sh` (every CI gate, locally).

## Conventions

- Run `scripts/verify.sh` before pushing. It runs what CI runs: gitleaks,
  pgTAP and `db lint`, Deno fmt/lint/test, Flutter l10n/format/analyze/test,
  the web build and Playwright.
- Public repo: never commit secrets. Only the project URL and the publishable
  key may appear in code. gitleaks runs as a pre-commit hook
  (`.githooks/pre-commit`) and as a required CI job.
- Lints follow emotely: `flutter_agent_lints` (experimental set), every rule
  an error. Fix the code, not the rule; `dart fix --apply` handles most
  primary-constructor and style findings.
- Build-time defines are read only in `app/lib/app/environment.dart`.
- Auth gating happens only in `authRedirect` (`app/lib/app/router.dart`).
- Every household-owned table carries `household_id` and the RLS policy
  `is_household_member(household_id)`. A new table gets the same policy and a
  cross-household case in `supabase/tests/rls.test.sql`.
- Item writes from the app are idempotent ops (`ItemOp` in
  `app/lib/list/model.dart`) applied optimistically and retried until the
  server acknowledges them; the screen shows server rows with pending ops
  folded on top. Add new mutations as new `ItemOp` variants.
- Categorization runs server-side in `public.classify_item(household, name)`
  (called by the items insert trigger). The app, MCP and Siri all go through
  it; change the function, not the callers.
- Flutter web e2e: semantics are enabled on web, so Playwright finds widgets
  by role and label. Type with `typeInto` (`e2e/tests/helpers.ts`); synthetic
  key events drop umlauts.
- `main` takes squash-merged PRs with `ci-ok` green.
