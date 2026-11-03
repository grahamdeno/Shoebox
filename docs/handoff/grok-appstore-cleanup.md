# App Store and website cleanup (prompt for Grok)

**Who runs this:** Graham gives the prompt below to Grok. Claude can't reach App Store Connect or the website host.
**Source of truth:** `docs/appstore/1.0-text.md`, `docs/testflight/what-to-test.md`, `docs/legal/privacy.md`, `docs/legal/terms.md` and `docs/audit/05-release-checklist.md` on `main` of `grahamdeno/Shoebox`.

## The prompt

> You are cleaning up the App Store listing and website for Graham's iPhone app Shoebox. Work in App Store Connect (app "Shoebox: Your Own Feed", bundle id `com.grahamdeno.shoebox`) and on the website `inmyshoebox.com`. The text to use is in the GitHub repo `grahamdeno/Shoebox`, branch `main`; open each file raw.
>
> **Never do these. Stop and ask Graham instead:**
> - **Press Submit for Review, Add for Review, or submit anything to Apple, including Beta App Review.** Graham does that himself.
> - **Create, rename or delete the in-app purchase**, the app record, the bundle id, any build or any version. Product ids can never be reused.
> - **Publish the privacy policy or the terms.** Both are drafts Graham must read first (they start with a "Draft for Graham's review" box and have bracketed blanks). Prepare them, show him, and publish only after his yes in this chat.
> - Change price, availability, the Small Business Program, tax, banking or agreements.
>
> **1. Look first and report (changes nothing).** Write down, exactly as they appear now:
> - App Store tab, version being prepared: version number, promotional text, description, keywords, support URL, marketing URL, What's New, copyright, review notes, review contact, sign-in required setting.
> - App Information: name, subtitle, category, privacy policy URL, age rating, content rights.
> - App Privacy: every data type declared.
> - TestFlight > Test Information: Beta App Description, feedback email, marketing URL, privacy policy URL, and What to Test on the latest build. Also the version and build number of the newest build.
> - Website: what is at `https://inmyshoebox.com/`, `/privacy`, `/terms`, `/support` (status code and a one-line summary of each), and where the site is hosted.
>
> **2. Fix the App Store text.** Replace with the text in `docs/appstore/1.0-text.md`: promotional text, description, keywords, What's New, review notes. Shoebox no longer has weather or the calendar, so no field may mention weather, calendar, "hands a few back", "calm daily feed" or "no endless scrolling" unless that file says it. The version being prepared must be **1.0** (the record's only version; nothing was ever released). If it says 2.0, report it and ask before changing. Leave the name and subtitle as they are unless they differ from the file.
>
> **3. Fix TestFlight Test Information.** Beta App Description: use the first paragraph of the description in `docs/appstore/1.0-text.md`. What to Test: the text of `docs/testflight/what-to-test.md`. Feedback email: `support@inmyshoebox.com`.
>
> **4. URLs.** Privacy policy URL `https://inmyshoebox.com/privacy`, support URL `https://inmyshoebox.com/support`. Marketing URL `https://inmyshoebox.com/` if the home page works, otherwise blank. Each must answer 200 before you set it; if one does not, leave it, and report.
>
> **5. App Privacy label.** Compare with the "Privacy nutrition label" section of `docs/audit/05-release-checklist.md` and report every difference. Do not change the label yet; list the changes for Graham.
>
> **6. Website.** Compare each page with the repo: `/privacy` with `docs/legal/privacy.md`, `/terms` with `docs/legal/terms.md`. List every place the live page says something the draft does not (weather, calendar, accounts, AI on a server, a backup that holds the mailbox key, retention times). Check that `/support` gives `support@inmyshoebox.com` and says nothing about weather or calendar. Prepare the new privacy and terms pages, but do not publish (see the rules above).
>
> **Report back** in this order: anything that needs Graham's yes, with exactly what would change; then each step as done, skipped or failed, with the before and after text of every field you changed; then anything that did not match what this prompt expected.
