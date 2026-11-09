# inmyshoebox.com

The public website: the home page, privacy, terms, support, the beta and Android request forms. Moved here from
`grahamdeno/edition` (Nov 2026) so everything Shoebox uses lives in one repo.

## Hosting

Cloudflare Pages, project `inmyshoebox`, built from this repo's `main` branch with `web` as the output folder and no
build command. A change under `web/` on `main` goes live in about a minute; other branches get a preview address on
`pages.dev` (for example `site-move.inmyshoebox.pages.dev`). Only changes under `web/` start a build.

Addresses work without `.html` (`/privacy` serves `privacy.html`). The App Store listing and the app link to `/`,
`/privacy`, `/terms` and `/support`, so those four must never move or break.

## Files

| File | What it is |
|---|---|
| `index.html` | Home page |
| `privacy.html`, `terms.html` | The published privacy policy and terms. `docs/legal/*.md` are drafts, not what is live. |
| `support.html` | Support page, linked from Settings and the App Store |
| `beta.html`, `android.html` | Request forms; they post to `api.inmyshoebox.com` |
| `privacy-1.html` | Privacy policy of the retired Shoebox 1 web app |
| `welcome.html` | Old address; sends visitors to the home page |
| `sw.js` | Removes the retired web app from browsers that installed it. Keep it at the root. |
| `site/` | Pictures, videos and CSS the pages use |
| `icons/` | Old favicons, kept for browsers that saved them |

Never put anything private here: the whole folder is public on the web.

## Cutover record (Nov 9, 2026)

Moved from GitHub Pages (`grahamdeno/edition`, now off) to Cloudflare Pages. Only the apex and `www` records changed.

Now: `CNAME inmyshoebox.com -> inmyshoebox.pages.dev` and `CNAME www -> inmyshoebox.pages.dev`, both proxied.

To go back to GitHub Pages (also turn Pages back on in `edition` with the custom domain), the old records, none proxied:
- `A inmyshoebox.com` 185.199.108.153, 185.199.109.153, 185.199.110.153, 185.199.111.153
- `AAAA inmyshoebox.com` 2606:50c0:8000::153, 2606:50c0:8001::153, 2606:50c0:8002::153, 2606:50c0:8003::153
- `CNAME www -> grahamdeno.github.io`

Leave alone: the three MX records and Email Routing (support@ mail), the SPF, DKIM and DMARC records, the `api` record
(the relay), and the GitHub verification TXT record (it stops anyone else claiming the domain on GitHub Pages).
