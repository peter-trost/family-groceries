# Needs Peter

Steps that cannot be done from the build box. Everything around them is
implemented.

## 1. Remote Supabase deploy (job 1)

No `SUPABASE_ACCESS_TOKEN` was available, so migrations are not yet on
`jdwqrallbpdbshrdhenk`. Pick one:

**A. GitHub Actions (recommended).** In the repo settings, add:

- Secret `SUPABASE_ACCESS_TOKEN`: a personal access token from
  https://supabase.com/dashboard/account/tokens
- Secret `SUPABASE_DB_PASSWORD`: the project's database password
- Variable `SUPABASE_PROJECT_REF`: `jdwqrallbpdbshrdhenk`

Then run the "Supabase deploy" workflow (Actions tab, Run workflow). It links
the project, runs `supabase db push` and deploys the edge functions. Without
the secrets the workflow skips and stays green.

**B. From the box.** Put the two values in `~/groceries-ops/env`, then:

```bash
set -a; source ~/groceries-ops/env; set +a
supabase link --project-ref jdwqrallbpdbshrdhenk
supabase db push
supabase functions deploy
```

## 2. Auth URLs on the hosted project

Dashboard, Authentication, URL Configuration:

- Site URL: the public web app URL once it is hosted (for example
  `https://peter-trost.github.io/family-groceries`).
- Redirect URLs: that URL with `/**`, plus `http://127.0.0.1:3000/**` and
  `http://localhost:3000/**` for local web testing against the hosted project.

Magic links and sign-up confirmation mails redirect there. Email
confirmation is on by default for hosted projects: new users confirm their
address before the first sign-in, and the app tells them so.

## 3. Web hosting (optional, free)

The web app has no public URL yet. GitHub Pages on this public repo is free;
say the word and a later job adds the Pages workflow (needs the SPA
fallback: a copy of `index.html` as `404.html`).
