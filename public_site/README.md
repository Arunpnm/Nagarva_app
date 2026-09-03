# link.nagarva.in — the customer-facing static site

**This is NOT the Flutter app.** It is a small hand-written static site,
deployed to the Netlify project `nagarva-link` (site id
`fa1c88c1-9d35-4bc7-b94e-1c962b6efdac`, primary URL
https://link.nagarva.in). The Flutter app in `lib/` has its own
`SurveyPage`/`SignPage`/`QuotePage`/`TrackPage` widgets which are DEAD
CODE with respect to this domain — they have never served live traffic
here. See CLAUDE.md, "Public web surface".

## Why this directory exists

The 17 Aug 2026 incident deleted the live `/survey` and `/sign` pages,
and they could not simply be restored **because their source had never
been in git** — the site had only ever been drag-dropped into Netlify.
That is the whole reason this directory is tracked: so the next mistake
costs a `git checkout`, not an archaeology session.

## What each path is

| Path | What it is |
|---|---|
| `survey/` | The real customer survey. Calls `public_get_survey` / `public_submit_survey`. |
| `sign/` | The real signature capture. Calls `public_get_signature_request` / `public_submit_signature`. |
| `privacy/` | Privacy policy. |
| `auth/` | Email-confirmation relay: forwards the URL fragment to `nagarva://auth-callback`, which triggers `lib/backend/auth_deep_link.dart`. Belongs to the Flutter app's auth flow, and is the one page here that is not customer-facing. |
| `quote/`, `track/` | Holding pages. **Neither has ever been built.** `/quote` has no page and no `public_*` RPC; `/track` has a working Flutter page that has never been deployed. |
| `index.html`, `404.html` | Root and fallback. |
| `nagarva.css`, `config.js` | Shared by `survey/` and `sign/`. **Both are required** — without `config.js` the pages have no Supabase URL or key and do not function at all. |
| `_redirects` | Read its comments before editing. It deliberately has no catch-all. |

`config.js` carries the Supabase URL and the **anon** key (verified:
`role: anon`). That is public by design, the same key already in
`lib/backend/supabase/supabase.dart`. A service-role key must never
appear here.

## The four RPCs these pages call

All four are `SECURITY DEFINER` and anon-executable, verified live
3 Sept 2026:

```
public_get_survey(p_token)                  public_submit_survey(p_token, p_rooms, p_instructions)
public_get_signature_request(p_token)       public_submit_signature(p_token, p_customer_name, p_signature_data)
```

Note these are a DIFFERENT family from the ones the Flutter pages call
(`get_survey_by_token` / `submit_survey` etc). Consolidating to one
family is a stated goal, not scheduled.

## Deploying

Drag this directory onto the `nagarva-link` project in Netlify, or
`netlify deploy --dir public_site --prod --site nagarva-link`.

**Deploying this replaces the "Link unavailable" holding pages currently
live at `/survey` and `/sign` with the real, working pages.** That is
the point — but verify by opening a real token link in a browser
afterwards, not by reading the deploy log.

`netlify.toml` (177 bytes) exists on the live site and could NOT be
recovered — Netlify does not serve it over HTTP and its API returns
metadata only. It is the one file here that is still unversioned.
