# Deploy the Shoebox app relay (prompt for Grok)

**Who runs this:** Graham gives the prompt below to Grok. Claude does not deploy.
**What it deploys:** the new Worker in `relay/app/worker.js`, seven routes, at `https://api.inmyshoebox.com`.
**Do this only after:** the beta PR is merged and Graham has said "ship" (the new app build points at this address, and the old Worker must keep serving Shoebox 1 and build 36 until then).

## Irreversible steps. Read these first.

These can't be undone cleanly, so Grok stops and asks Graham before each one marked **ASK**.

1. **Deploy the new Worker** `shoebox-app-relay` (step 3). Rollback: delete the Worker. Nothing else depends on it until step 5.
2. **Attach the custom domain** `api.inmyshoebox.com` to it (step 5). Rollback: remove the domain from the Worker.
3. **Move the Email Routing catch-all for `inmyshoebox.com`** from the old Worker `shoebox-relay` to the new one (step 6). **ASK.** From that moment mail to every address is delivered by the new Worker. Addresses made by Shoebox 1 or by build 36 stop working until their phones get new ones. Graham is the only user. Rollback: point the catch-all back at `shoebox-relay`.
4. **Set the secret** `PIXABAY_API_KEY` (step 4). Secret values can't be read back from the old Worker, so Graham types or pastes it. Never put it in a chat log, a file or a screenshot.
5. **Upgrade the Cloudflare plan to Workers Paid** ($5 a month). **ASK.** Do it on the day a public TestFlight link goes out (the free plan allows only 1,000 KV writes a day). Rollback: downgrade next billing cycle.

Do not touch the old Worker `shoebox-relay`, its KV namespace `SHOEBOX`, its domain `shoebox-api.tangomike.app`, or any other site. Do not delete anything that is not named here.

## The prompt

> You are deploying a small Cloudflare Worker for Graham's app Shoebox. Work only in his Cloudflare account. Follow the steps in order. Where it says ASK, stop and wait for Graham's yes in this chat. Never paste a secret value into chat, a file or a screenshot. If a step does not match what you see, stop and describe what you see instead of guessing. At the end, report each step as done, skipped or failed, with the exact output of the checks. If you cannot run a check, say which, so Graham can run it.
>
> The code to deploy is the file `relay/app/worker.js` in the GitHub repo `grahamdeno/Shoebox`, on the `main` branch (Graham will tell you if it is on another branch). Open the file raw on GitHub and copy all of it. It has no imports, so it can be pasted into the Cloudflare code editor as is. If you have a shell with Node, you may instead run `npx wrangler deploy -c relay/app/wrangler.jsonc` after replacing the KV id placeholder (do not commit the id).
>
> **1. Look first (changes nothing).** In the Cloudflare dashboard open Workers & Pages. Confirm that the Worker `shoebox-relay` exists and do not change it. Confirm that no Worker named `shoebox-app-relay` exists yet. Open Email Routing for `inmyshoebox.com` and write down where the catch-all goes now (it should be the Worker `shoebox-relay`).
>
> **2. Make the storage.** Storage & Databases, KV, Create a namespace named `SHOEBOX_APP`. Do not reuse `SHOEBOX`.
>
> **3. Deploy the Worker.** Workers & Pages, Create, Worker, name it exactly `shoebox-app-relay`, deploy the starter, then Edit code, replace everything with the contents of `worker.js`, and Deploy. Then Settings, Bindings, add a KV namespace binding: variable name `SHOEBOX` (capitals), namespace `SHOEBOX_APP`. Save and deploy again if asked.
>
> **4. Settings.** Settings, Variables and Secrets:
> - Secret `PIXABAY_API_KEY`: ask Graham to enter it himself, or to tell you he has.
> - Do not set `OWNER_INBOX_KEY`, `EMAIL_ADDRESS`, `MINT_DAILY_CAP` or `MAILBOX_DAILY_CAP`. The defaults are right.
> - Settings, Domains & Routes: turn OFF the `workers.dev` route and OFF Preview URLs. The Worker must be reachable only at its own domain.
>
> **5. Attach the domain.** Settings, Domains & Routes, Add, Custom domain, `api.inmyshoebox.com`. Wait until its status is Active. This makes the DNS record by itself.
>
> **6. ASK: move the email.** Tell Graham what the catch-all points to now, and that moving it means every address is delivered by the new Worker. After his yes: Email Routing, Routing rules, Catch-all address, Edit, Action: Send to a Worker, Destination `shoebox-app-relay`, Save, and make sure it is Active. Do not change any other rule. In particular leave `support@inmyshoebox.com` forwarding to Graham's Gmail exactly as it is.
>
> **7. ASK: the plan.** Only if Graham says a public TestFlight link is going out today: Billing, upgrade the account to Workers Paid. Otherwise skip and say so.
>
> **8. Checks.** Run each and report the exact status and body. `O` means the header `Origin: https://inmyshoebox.com`.
>
> | # | Command | Expect |
> |---|---|---|
> | a | `curl -s -o /dev/null -w '%{http_code}' https://api.inmyshoebox.com/stock?q=garden` | `403` (no Origin) |
> | b | `curl -s -H 'Origin: https://inmyshoebox.com' 'https://api.inmyshoebox.com/stock?q=garden&n=3'` | `200`, JSON `{"photos":[...]}` with 1 to 3 photos, each with `url`, `by`, `page` |
> | c | `curl -s -X POST -H 'Origin: https://inmyshoebox.com' -H 'x-inbox-key: sb-checkcheckcheckcheckcheckcheckcheck01' https://api.inmyshoebox.com/me/delete` | `200`, `{"ok":true,"mail":0}` |
> | d | same as c without the `x-inbox-key` header | `401`, `{"error":{"message":"No inbox key."}}` |
> | e | `curl -s -o /dev/null -w '%{http_code}' -H 'Origin: https://inmyshoebox.com' https://api.inmyshoebox.com/version` and the same for `/v1/agent`, `/apple/token`, `/photo?q=cat` | `404` each (the old routes are not here) |
> | f | `curl -s -H 'Origin: https://inmyshoebox.com' 'https://api.inmyshoebox.com/preview?url=https://example.com&text=1'` | `200`, JSON with a `title` |
> | g | `curl -s -H 'Origin: https://inmyshoebox.com' 'https://api.inmyshoebox.com/preview?url=http://127.0.0.1/'` | `400` |
> | h | `curl -s -m 10 -o /dev/null -w '%{http_code}' https://shoebox-app-relay.<account subdomain>.workers.dev/` | no answer or `404` from Cloudflare, never our JSON (workers.dev is off) |
> | i | Make an address: `curl -s -X POST -H 'Origin: https://inmyshoebox.com' -H 'Content-Type: application/json' -H 'x-inbox-key: sb-checkcheckcheckcheckcheckcheckcheck02' -d '{"name":"check"}' https://api.inmyshoebox.com/inbox/address` | `200`, `{"address":"check-xxxxxxxx@inmyshoebox.com"}` with exactly 8 characters after the dash |
> | j | Ask Graham to send a short email to that address from his Gmail, wait one minute, then `curl -s -H 'Origin: https://inmyshoebox.com' -H 'x-inbox-key: sb-checkcheckcheckcheckcheckcheckcheck02' https://api.inmyshoebox.com/inbox` | `200`, one mail in `mails`, the same address in `address` |
> | k | Ask Graham to send an email to `nobody-abcd2345@inmyshoebox.com` | no bounce message comes back (an unknown address is dropped without a reply) |
> | l | Delete the check data: `curl -s -X POST -H 'Origin: https://inmyshoebox.com' -H 'x-inbox-key: sb-checkcheckcheckcheckcheckcheckcheck02' https://api.inmyshoebox.com/me/delete`, then repeat j | `200` with `"mail":1`, then an empty `mails` and `"address":null` |
> | m | Ask Graham to send a test email to `support@inmyshoebox.com` | it still arrives in his Gmail under Support/Shoebox |
>
> Checks i and l use one of the five new addresses a network may make per day. That is expected.
>
> **9. Report.** For each step: done, skipped or failed, and the exact outputs of checks a to m. List anything you did that is not in this prompt (there should be nothing). Do not do anything else.

## After Grok reports

Claude (or Graham) checks the table. If check b fails with a 502 and `{"photos":[]}`, the Pixabay key is missing or wrong (step 4). If check j never shows the mail, look at the catch-all (step 6).

## Roll back everything

1. Email Routing catch-all back to `shoebox-relay`.
2. Remove `api.inmyshoebox.com` from `shoebox-app-relay`.
3. Delete the Worker `shoebox-app-relay` and the KV namespace `SHOEBOX_APP`.
4. If the plan was upgraded and is no longer wanted, downgrade it.

The old Worker was never changed, so Shoebox 1 and build 36 keep working throughout, except for mail delivery between steps 6 and the rollback.
