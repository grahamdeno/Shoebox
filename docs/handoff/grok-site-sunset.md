# Retire the web app, add the Android request form, take down the old relay (prompt for Grok)

**Who runs this:** Graham gives the prompt below to Grok. **Decided by Graham, November 4:** the landing page becomes the home page, the old web app goes today (nobody uses it), the old relay goes today, and there is an Android request form.
**Start only after Claude says PR #49 (website requests on the new relay) is merged.**

## Irreversible or public. Read these first.

1. **Deploy the new relay** with the request routes (step 1). **ASK.** Rollback: `npx wrangler rollback 99987eae-fd0b-4728-85b5-270a1d67e44e --name shoebox-app-relay`.
2. **Publish the website changes** (steps 2 to 4): the home page, the beta form's new address, the Android page and the privacy policy's new section. **ASK** once for all of them, showing the diff.
3. **Take down the old relay** `shoebox-relay` at `shoebox-api.tangomike.app` (step 6). **ASK.** Today: remove its domain and route only, so it can be brought back. Do not delete the Worker or its KV namespace `SHOEBOX`. Deleting them is a separate yes, in 30 days.

Never touch `shoebox-app-relay`'s settings other than the deploy, Email Routing, `support@inmyshoebox.com`, billing, or any other site.

## The prompt

> You are retiring the old Shoebox web app and its old server, and adding an Android request form. Work in Graham's Cloudflare account and in the GitHub repo `grahamdeno/edition` (GitHub Pages for inmyshoebox.com). Source files are in `grahamdeno/Shoebox` on `main`. Where it says ASK, stop and wait for Graham's yes in this chat. If anything does not match what this prompt expects, stop and describe what you see. At the end, report each step as done, skipped or failed, with commit ids, version ids and the exact results of the checks.
>
> **1. Deploy the new relay (ASK).** In `grahamdeno/Shoebox` `relay/app`: `npm ci`, then `node --test test/*.test.mjs` (every test must pass). Deploy `shoebox-app-relay` exactly as last time, keeping its variables (`PLUS_OWNER_ADDRESS` stays). Check: `POST https://api.inmyshoebox.com/request/android` with header `Origin: https://inmyshoebox.com` and body `{"email":"graham.denoyer@gmail.com","name":"Graham test"}` answers 200 `{"ok":true}`. The same without the Origin header answers 403.
>
> **2. Home page.** In `grahamdeno/edition`:
> - Make `index.html` the landing page: copy the current `welcome.html` into `index.html`. Fix its links: the home link and canonical URL become `https://inmyshoebox.com/`. Keep `welcome.html` as a tiny page that redirects to `/` (`<meta http-equiv="refresh" content="0; url=/">` and a link), so old links keep working.
> - Replace `sw.js` with this exact file, so phones that installed the old web app clear it the next time they visit:
>   ```js
>   // The old web app is retired. This removes it from any browser that installed it.
>   self.addEventListener("install", () => self.skipWaiting());
>   self.addEventListener("activate", (e) => e.waitUntil((async () => {
>     for (const k of await caches.keys()) await caches.delete(k);
>     await self.registration.unregister();
>     for (const c of await self.clients.matchAll({ type: "window" })) c.navigate(c.url);
>   })()));
>   ```
> - Delete `manifest.webmanifest`, the `src/` folder and `styles.css` if no remaining page uses it (check first: `grep -l styles.css *.html`). Leave `site/`, `icons/` and every other page.
> - On the home page, under the "Ask for the iPhone beta" button, add one line: `On Android? <a href="android">Tell me when it's ready</a>.` Add an `Android` link to the footer of every page, after Terms.
>
> **3. Forms.**
> - In `beta.html`: change `var RELAY = "https://shoebox-api.tangomike.app";` to `var RELAY = "https://api.inmyshoebox.com";`, change `fetch(RELAY + "/beta"` to `fetch(RELAY + "/request/beta"`, and change "Your answers are kept for 90 days" to "Your answers are kept for up to 180 days". Nothing else.
> - Add `android.html`: copy `docs/site/android.html` from `grahamdeno/Shoebox` exactly. If its footer differs from the other pages after step 2, make it match.
>
> **4. Privacy policy.** In `privacy.html`, add the new section "4. A request from our website" after the paragraph that starts "Newsletters and school notices", and the new table row "A beta or Android request from our website", both word for word from `docs/legal/privacy.md` in `grahamdeno/Shoebox`. Keep the effective date as it is and add "Updated November 4, 2026." under it.
>
> **ASK** with the full diff of steps 2 to 4, then commit to `edition` `main` in one commit.
>
> **5. Check the website** (2 minutes after the push): `/`, `/welcome`, `/beta`, `/android`, `/privacy`, `/support`, `/terms` each answer 200. `/` shows the landing page, not "Shoebox needs JavaScript". `/sw.js` is the new file. `/manifest.webmanifest` answers 404. Submit the Android form once in a browser with Graham's email and confirm it shows "You're on the list." Do not submit the beta form.
>
> **6. Take down the old relay (ASK).** In Cloudflare, Workers & Pages, `shoebox-relay`: write down its routes, custom domains and Cron Triggers, then remove the custom domain `shoebox-api.tangomike.app` and any route and Cron Trigger. Do not delete the Worker or the KV namespace `SHOEBOX`. Check: `https://shoebox-api.tangomike.app/photo?q=garden` no longer answers from the Worker, and `https://api.inmyshoebox.com/stock?q=garden` with the Shoebox origin still answers 200.
>
> **Report back** in this order: anything that needs Graham's yes; then steps 1 to 6 with commit and version ids, the before and after of every changed line, and each check's result; then what you wrote down in step 6, so the old relay can be brought back.
