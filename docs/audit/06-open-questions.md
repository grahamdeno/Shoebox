# Open questions for Graham

**Answered November 2.** Answers are in bold after each question and recorded in `docs/SPEC.md` section 8.

1. **Who is v1.0 for?** The brief's assumption is busy parents and working adults, 30 to 55. Confirm, because it decides whether school newsletters lead the App Store text and whether US-only is acceptable. **Yes, busy parents and working adults, about 28 to 50.**
2. **Price.** Recommendation: free download, Shoebox Plus one-time $9.99 unlocking the email address (decision C). Yes, or another model? **One-time $9.99, lifetime. Running cost per user is under a cent a year; fixed costs need about 23 new buyers a year.**
3. **First save timing.** SPEC rule 1 says saves made during the day join Today; rule 6 says a new save comes back tomorrow. The code does rule 6, so new users never see their first save the same day. Recommendation: rule 1 for saves made today, rule 6 after the first flick up. Which? **Saves show on Today the day they are kept; after a flick up, the reason or tomorrow.**
4. **US English only for v1.0?** Dates, grades and reason words assume US English. Yes keeps v1 small; no adds about 2 to 4 weeks of locale work (C-10). **Yes. Spanish, screens and reading, in v1.1.**
5. **Relay split.** OK to put the new app on its own Worker (or a `/v2` prefix) and leave Shoebox 1's routes on the old one until build 36 is retired? And is anyone besides you still on build 36? **Graham is the only user; split approved.**
6. **Empty state.** SPEC forbids a "Keep something" row on the empty Today. Is a single starter post that teaches the moves acceptable instead? **Yes, a welcome post.**
7. **Mail retention.** Shorten from 30 to 7 days (R-11)? Shorter is better for children's details; longer helps people who open the app rarely. **7 days, with background refresh to collect mail.**
8. **Privacy policy host and owner.** Publish on inmyshoebox.com under your name or a company (Team D503 or a separate entity)? The seller name on the App Store must match. **Graham as an individual, no LLC. Policy exists at inmyshoebox.com/privacy. EU storefronts left out of v1.0.**
9. **Daily limit default.** Change from All to 10 (decision F)? **10, with new and soon-dated posts always joining.**
10. **App Store name.** Keep "Shoebox: Your Own Feed" or something that says it comes back? **Keep "Shoebox: Your Own Feed".**
11. **Public repo.** Keep `grahamdeno/Shoebox` public? If yes, scrub family details (P-8); if no, make it private before the beta. **Stay public for now (free Mac CI minutes), scrub family names, go private later.**
12. **Notification actions in v1.0** or first post-launch release with the widget? **v1.0.**
