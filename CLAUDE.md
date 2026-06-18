# Claude Code Instructions — MontaniHire

## 1. Git: No Commit or Push Without Explicit Approval

Never commit or push to git without:
1. Showing the full `git diff` (staged and unstaged) first
2. Receiving explicit confirmation — "approved, push it" or equivalent

After approval, audit the diff against POODR/Sandi Metz principles before considering the change final:
- **SRP**: each class/method does one thing
- **Dependency injection**: collaborators passed in, not hardcoded
- **Duck typing**: depend on messages (method names), not types
- **Law of Demeter**: no chaining through unrelated objects (`a.b.c.d`)

If the diff violates any of these without a clear reason, flag it before pushing.

## 2. Phased Migration Rule

Never write a migration file with real destructive logic (`remove_column`, `drop_table`, `delete_all`, `execute "DELETE"`, etc.) in the same commit or batch as a migration being held.

If a destructive migration is requested but not yet approved to run in production:
- Either do not create the file at all until explicitly approved
- Or create it with an empty/no-op `change` method and a comment: `# DO NOT RUN — pending approval`

Never assume a destructive migration is safe to run just because it exists on disk. `db:migrate` runs all pending files unconditionally — a file on disk is a file that will run on the next deploy.

## 3. Railway Deployment

**Web service** — governed by `railway.toml`:
```toml
[deploy]
healthcheckPath = "/up"

[[deploy.preDeployCommands]]
command = "bundle exec rails assets:precompile"

[[deploy.preDeployCommands]]
command = "bundle exec rails db:migrate"
```

**Worker service (Sidekiq)** — governed by `railway.worker.toml`:
```toml
[deploy]
startCommand = "bundle exec sidekiq -c 3"
```
No `healthcheckPath` (Sidekiq serves no HTTP). No `db:migrate` (runs once on web only). Set via **worker service → Settings → Config File Path → `railway.worker.toml`**.

**Service-to-service variable references** must use Railway's reference syntax:
```
${{Postgres.DATABASE_URL}}
${{Redis.REDIS_URL}}
```
Never hardcode placeholder strings like `${PGUSER}` or `postgresql://${PGHOST}/...` — Railway does not evaluate shell-style variable interpolation in variable values.

**Variable sharing is NOT automatic.** Railway only auto-injects plugin-provided variables (Postgres, Redis) into services in the same project. Manually-set variables (AWS keys, Google OAuth credentials, `SECRET_KEY_BASE`, etc.) are NOT shared — they must be explicitly copied to each service that needs them. There is no "inherit from web service" mechanism for manual variables.

**Worker requires these env vars** (must be set explicitly on the worker service — they are not inherited from the web service):
`DATABASE_URL`, `REDIS_URL`, `ANTHROPIC_API_KEY`, `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET`, `SECRET_KEY_BASE`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_REGION`, `S3_BUCKET`

`SECRET_KEY_BASE` must be identical on web and worker — ActiveStorage signed blob keys and Active Job serialization both depend on it.

**Config File Path must be set manually.** Railway does not infer which config file a service should use from the filename. To make the worker use `railway.worker.toml`, go to: worker service → **Settings → Config File Path** → enter `railway.worker.toml`. Without this, Railway falls back to `railway.toml` for all services and the worker will inherit the web service's healthcheck and migration commands.

## 4. Google OAuth

Production uses a **Web application** OAuth client type (not Desktop) registered in Google Cloud Console.

Both callback URLs must be registered under Authorized redirect URIs:
- `http://localhost:3000/auth/google/callback` (development)
- `https://montanihire-production.up.railway.app/auth/google/callback` (production)

ENV vars required on both web and worker:
- `GOOGLE_CLIENT_ID` — `ENV.fetch`, raises `KeyError` if missing
- `GOOGLE_CLIENT_SECRET` — `ENV.fetch`, raises `KeyError` if missing
- `GOOGLE_BROWSER_API_KEY` — web only, used for Drive Picker, has empty-string fallback
- `GOOGLE_SERVICE_ACCOUNT_JSON` — not required in normal flow; only hit if user has no OAuth token

`UserRegistrationService` skips org creation for users with a pending invite — the `InvitesController#accept` flow assigns the correct org. If a user's auto-created org has only themselves as a member, `accept` treats it as a first-login placeholder and replaces it.

## 5. Episode/CV Scoring Prompt Versioning

**Versioning pattern**: prompt versions follow `YYYY-MM-DD-vN` (e.g. `2026-06-17-v9`). Stored in `PROMPT_VERSION` constant in each service.

**v9 episode prompt shape** — each dimension is a CoT object:
```json
{
  "literal_quote": "exact phrase from transcript or NONE",
  "tier_check": "which tier definition matches and why",
  "rating": "meets | partially_meets | vague | does_not_meet"
}
```

`red_flags` are objects (not strings):
```json
{ "flag": "...", "literal_quote": "...", "rationale": "..." }
```

`recommendation_basis` is a non-empty array of 2–3 decisive signal names.

**Rules before shipping a prompt change that alters JSON shape**:
1. Update views to handle both legacy and new shape before the prompt ships (use `is_a?(Hash)` guards)
2. Run the new prompt against 5–10 real `VideoAnalysis` records and inspect output
3. Confirm `max_tokens` budget has real headroom (not just theoretical max)
4. `EpisodeScoreCalculator` already handles both flat string and Hash dims — verify it still does

**Periodic audit**: run `bin/rails runner scripts/episode_v9_audit.rb` every 5–10 new v9+ completed analyses. Checks red flag literal_quote grounding, tier_check/rating consistency, and recommendation_basis populated.

## 6. Pre-Change Cleanliness Check

Before any infrastructure, schema, or multi-file change:
1. Run `git status` — confirm working tree is clean (nothing uncommitted, nothing untracked that shouldn't be)
2. If untracked files exist, classify each as WIP-to-commit, noise-to-gitignore, or file-to-delete before proceeding
3. Never stash with `--include-untracked` during a pull/rebase — it caused a prior incident where all local WIP was swept into an unrelated commit

## 7. Asset Pipeline

This app uses **Propshaft** (`Gemfile:36: gem "propshaft"`, not Sprockets). Key verified facts:

- `vendor/javascript/` is confirmed in Propshaft's asset paths — use `./bin/importmap pin <pkg>` to vendor ESM packages there
- `pin "pkg"` with no `to:` resolves to a CDN (jspm.io) at runtime — always vendor or specify `to:` explicitly; CDN pins silently fail if the CDN is unreachable or blocked
- `vendor/javascript/trix.js` is the ESM build from jspm.io — the `action_text-trix` gem provides only a UMD build (`(function(global, factory)`), which is not importmap-compatible; do not use `to: "trix.js"` pointing at the gem asset
- The Dockerfile does `COPY vendor/* ./vendor/` so vendored JS is included in the built image
- `assets:precompile` must run during the **Docker image build** (Dockerfile build stage), NOT in Railway's `preDeployCommands`. preDeployCommands run in a temporary container that exits before the service container starts — any files written there (like `public/assets/`) are discarded. The Dockerfile build stage runs `SECRET_KEY_BASE=dummy bundle exec rails assets:precompile` to bake digested assets into the image
- Propshaft in production generates digested URLs (e.g. `/assets/actiontext-3720ab2a.css`). If those files aren't in `public/assets/` (because precompile didn't run at build time), every asset request returns 404 and Trix/ActionText will not load

## 8. Testing Expectations

- Every new service, job, or significant model change ships with tests covering its public interface — not just the happy path, but error/failure isolation. Reference pattern: `SegmentHighlightService` rescues its own errors and logs a warning rather than crashing `VideoProcessingJob`. Tests should verify this boundary holds.
- Run the full suite (`bin/rails test`) before considering any change complete. "Tests pass locally" is part of the definition of done, not a separate optional step.
- For destructive or risky changes (migrations, prompt versioning, scoring logic changes), write characterization tests capturing current behavior before refactoring. The diff between old and new test output should be explainable as either behavior-preserving or intentionally changed — not a surprise.
- **Current suite size as of 2026-06-18: 291 runs, 627 assertions.** If a future session shows materially fewer runs (e.g. 250), investigate before assuming tests pass — files may have been moved, renamed, or silently excluded from discovery.
