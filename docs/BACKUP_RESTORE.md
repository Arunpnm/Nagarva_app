# Nagarva backups and restore

Written 11 Nov 2026. The job is `.github/workflows/db-backup.yml`.

## Why this exists

The Supabase project (`hqqcapifefsaqvotqvlt`) is on the **Free plan**, which
has **no automatic backups**. Supabase's own advice for Free projects is to
export the data regularly and keep it off-site. Upgrading to Pro (daily
backups for 7 days, no pausing) is still worth doing before paying vendors
are on the platform; this job stays useful after that as an off-site copy.

## What runs, every night at 02:11 IST

1. Row counts of every app table, before and after the dump.
2. Three database dumps: the app tables (`public.dump`), logins
   (`auth-data.dump`), storage records (`storage-data.dump`).
3. Every stored file (logos, documents, signatures, photos) into `files/`.
4. **Restore check**: `public.dump` is restored into a throwaway Postgres 17
   and every table's row count must lie between the before and after
   counts. If not, the run fails and GitHub emails the repo owner.
5. Everything is packed and encrypted with `BACKUP_PASSPHRASE` (AES-256),
   then kept as a GitHub artifact for 30 days.

A few queries every night also keep the Free project from being paused for
inactivity.

## One-time setup (repo Settings -> Secrets and variables -> Actions)

| Secret | Where to get it |
| --- | --- |
| `SUPABASE_DB_URL` | Supabase -> Connect -> **Session pooler** connection string, with the database password filled in. Not the direct `db.<ref>.supabase.co` string: GitHub cannot reach it. |
| `SUPABASE_URL` | `https://hqqcapifefsaqvotqvlt.supabase.co` |
| `SUPABASE_SERVICE_ROLE_KEY` | Supabase -> Project Settings -> API keys -> service_role (secret) |
| `BACKUP_PASSPHRASE` | Make one (long random text). **Keep a copy outside GitHub** (password manager). Without it no backup can be opened. |

The job runs only from `main`. After merging, run it once by hand:
Actions -> Nagarva daily backup -> Run workflow.

## Restoring

Only for a real loss. Practise once on a spare Supabase project first.

1. **Download**: Actions -> the run -> Artifacts -> `nagarva-backup-<date>`
   (a zip holding one `.tar.gz.gpg` file).
2. **Decrypt and unpack** (gpg comes with Git for Windows' bash, or install Gpg4win):
   ```
   gpg --decrypt nagarva-backup-<date>.tar.gz.gpg > backup.tar.gz
   tar -xzf backup.tar.gz
   ```
3. **Target**: a Supabase project on Postgres 17, empty, or the same project
   after the damage is understood. Copy its Session pooler string as `$DB`.
4. **Logins first** (the app tables point at `auth.users`):
   ```
   pg_restore --no-owner --data-only -d "$DB" auth-data.dump
   ```
   A new project already has rows in `auth.schema_migrations`, so
   "duplicate key" messages for that one table are expected.
5. **App tables, functions, rules and grants**:
   ```
   pg_restore --no-owner -d "$DB" public.dump
   ```
   Messages about objects that already exist (schema `public`, the
   realtime publication) are expected.
6. **Files**: create the same buckets (names and public/private as in the
   old project), then upload `files/<bucket>/...` with the same paths, e.g.
   `npx supabase storage cp -r files/org-logos ss:///org-logos --experimental`.
   Uploading creates the storage records, so `storage-data.dump` is only
   needed to check bucket settings.
7. **Check**: run `scripts/backup/counts.sql` on the restored project and
   compare with `counts-after.tsv` from the backup.
8. **Not in the backup, redo by hand**: Edge Functions (deploy from this
   repo) and their secrets (AI keys, Razorpay keys, webhook secret; names
   are in each function's header), Auth settings (email templates, redirect
   URLs), and the app's Supabase URL and anon key if the project changed.
