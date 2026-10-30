# Shoebox 2.0: the spec

Written October 30, 2026, in phase 0, from the old code in `grahamdeno/edition` (read only). `docs/PLAN.md` holds the rules and decisions; this file holds the detailed behavior any client (iPhone now, web or Android later) must follow.

**How to read the markers**

- **[Old]** comes straight from the old code, with the file named.
- **[Check]** is something the old code didn't settle, so Claude decided it here. Graham should confirm or change each one. They are collected in section 14.
- **(Storyboard)** points to the new design reference, `docs/design/storyboard.html`, not the old code.
- Plain text with neither marker follows directly from `docs/PLAN.md`.

---

## 1. The data model

Everything is stored on the phone in SwiftData, in the App Group container (`group.com.grahamdeno.shoebox`), so the app, the share extension, the widgets and the notification extension read one store. Files are kept as files beside it.

### 1.1 Sync rules for every record

Every record type below carries these four fields, so sync can come later without a migration:

| Field | Type | Rule |
|---|---|---|
| `id` | UUID (v4), string form lowercased | Made on the device that creates the record. Never reused, never changed. |
| `createdAt` | timestamp, UTC, millisecond precision | Set once. |
| `updatedAt` | timestamp, UTC, millisecond precision | Set on every change to any field. |
| `deletedAt` | timestamp or null | Soft delete. A deleted record stays as a tombstone (fields cleared except these four) so a future sync can pass the delete on. File bytes are removed at once. |

Merge rule for later sync **[Check]**: last writer wins per record, by `updatedAt`; a tombstone always wins over an older edit. `MomentEvent` records are append-only, so they never conflict.

### 1.2 Save

One thing kept: a link, a note, a photo, a file.

| Field | Type | Notes |
|---|---|---|
| `kind` | enum: `link`, `note`, `quote`, `photo`, `pdf`, `file`, `video` | Section 2. Old `text` and `audio` kinds become `file` **[Check]**. |
| `reason` | string, max 140 chars, may be empty | Your words: why you kept it. Always the largest text. **[Old]** `why`, 140 chars (`model.js` `createItem`, `app.js` `maxlength="140"`). |
| `reasonSource` | enum: `typed`, `spoken`, `shareComment`, `email`, `imported`, `none` | So the planner and review know how much to trust it. |
| `title` | string, max 140 | **[Old]** `createItem` clips to 140. |
| `text` | string or null | Note body, quote text, page text you pasted. |
| `url` | string or null | Unwrapped (Outlook Safe Links, Google redirects, urldefense) **[Old]** `ai.js` `unwrapLink`. |
| `author` | string or null | Quote attribution, YouTube channel, book author. |
| `videoId` | string or null | YouTube id, 11 chars. |
| `imageURL` | string or null | Remote picture for a link or video. |
| `attachmentIds` | [UUID] | Original file, thumbnail, chosen page picture. |
| `summary` | string, max 200 | One line on why it might be worth the time **[Old]** `enrich`. |
| `hook` | string, asked for at 50 chars, stored up to 70 | The short face-of-card line, 5 to 8 words **[Old]** `HOOK_RULE` (50), `cleanHook` (70), `HOOK_VERSION` 2. |
| `points` | [string], max 3 | Key points **[Old]**. |
| `extended` | string, max 1800 | Fuller summary of a page or document **[Old]**. |
| `transcript` | string, max 1500 | Text read from a photo or screenshot **[Old]**. |
| `tags` | [string], max 6, lowercase, max 32 chars each | **[Old]** `MAX_TAGS`, `normTag`. |
| `minutes` | int or null | Time to read or watch; estimated when unknown (section 2.4). |
| `intent` | enum: `read`, `watch`, `listen`, `reference`, `idea`, `task` or null | **[Old]** `INTENTS`. Picks the Done word (section 3). |
| `book` | `{title, author}` or null | A photo of a book **[Old]** `asBook`; costs 30 minutes (`BOOK_SITTING_MINUTES`). |
| `pictureFocus` | `{x, y}` 0 to 100, or null | Point a crop keeps in view **[Old]** `cleanFocus`. |
| `alt` | string, max 160 | Picture description for VoiceOver **[Old]**. |
| `source` | enum: `share`, `actionButton`, `siri`, `paste`, `email`, `screenshot`, `school`, `import` | Where it came in. |
| `status` | enum (below) | |
| `passes` | int, starts 0 | Ignored moments (section 5). |
| `laters` | int, starts 0 | Times you chose Later. |
| `nextMomentId` | UUID or null | The one planned moment. Null when quiet, done or dropped. |
| `doneAt`, `droppedAt`, `quietAt` | timestamp or null | |
| `loved` | bool | **[Old]** `loved`. Kept; not shown in v1 **[Check]**. |
| `thoughts` | [`{at, text}`] | Your later notes on it **[Old]** `replies`. |
| `edited` | set of `title`, `tags`, `reason` | Fields you changed by hand, which AI never overwrites **[Old]** `titleMine`, `tagsMine`; old `editedAt` marked any hand edit. `reason` is new. |
| `school` | `SchoolPost` or null | Section 7. |
| `email` | `{from, fromName, subject, receivedAt}` or null | For saves that came by email. |
| `enrichedAt`, `enrichTries` | timestamp, int | AI filing state; at most 3 tries **[Check]**. |
| `oldId` | string or null | The id from the old app, for safe re-import (section 11). |

**Status values**

| Status | Meaning | Old equivalent |
|---|---|---|
| `planned` | Has a moment coming. | `aside` |
| `unplanned` | The planner hasn't placed it yet (just saved, imported, or waiting for the model). It becomes `planned` as soon as it has a moment. | `inbox`, `queued` (not faded) |
| `quiet` | Passed twice. Kept, never offered, back only if you ask. | faded (`fadedAt`, or 21 days untouched), `washedOut` |
| `done` | You did it. | `done` |
| `dropped` | You let it go. Kept in Everything kept under "Let go"; never deleted on its own. | `archived` |

Delete is separate from Drop: it sets `deletedAt` and removes the bytes. Only you can delete, one save or everything.

### 1.3 Attachment

| Field | Type | Notes |
|---|---|---|
| `saveId` | UUID | |
| `role` | enum: `original`, `thumbnail`, `picture` | `picture` is the chosen page picture for a link. |
| `fileName` | string | Stored at `Files/<id>.<ext>` in the App Group container. |
| `mime` | string | |
| `size` | int, bytes | |
| `sha256` | string | Detects duplicates and damaged files on import. |

Thumbnails: longest edge 1200 px, JPEG quality 0.82, only when the original is larger or over 400 KB **[Old]** `capture.js` `thumbnail`.

### 1.4 Moment

The one time a save comes back. A save has at most one moment that isn't finished.

| Field | Type | Notes |
|---|---|---|
| `saveId` | UUID | |
| `start`, `end` | timestamp | The window. Ignoring it until `end` is a pass. |
| `surface` | enum: `issue`, `notification`, `liveActivity` | Watch mirrors notifications on its own; no Watch app in v1. |
| `place` | enum: `any`, `homeEvening`, `work`, `weekend` | Condition that must hold; see section 4.5. |
| `anchorEventId` | string or null | EventKit identifier when tied to a calendar event. Stays on the phone. |
| `ruleId` | string | Which rule placed it (section 4.3), or `model`, `relay`, `you`. |
| `confidence` | enum: `sure`, `likely`, `guess` | `guess` shows "Change?" more plainly on the capture line. |
| `explanation` | string, max 60 | The capture line: "Comes back Saturday morning". |
| `laterLabel` | string, max 18 | The concrete Later button: "After planning", "Tomorrow". |
| `state` | enum: `scheduled`, `delivered`, `answered`, `passed`, `cancelled` | |
| `deliveredAt`, `answeredAt` | timestamp or null | |

### 1.5 MomentEvent (append-only)

Everything that happens to a save, in order. This is the learning signal and the audit trail.

| Field | Type |
|---|---|
| `saveId`, `momentId` | UUID, UUID or null |
| `type` | enum: `saved`, `planned`, `delivered`, `opened`, `done`, `later`, `dropped`, `passed`, `quiet`, `broughtBack`, `restored`, `edited` |
| `at` | timestamp |
| `surface` | enum or null: where it happened (lockScreen, notificationExpanded, issue, app, liveActivity, watch, siri) |
| `detail` | small JSON: Later target, old status on restore, and so on |

### 1.6 Settings (one record)

| Field | Default | Notes |
|---|---|---|
| `issueTime` weekdays / weekends | 7:00 AM / 8:00 AM | Weekend time is new **[Check]**. |
| `homeEvening` | 6:00 to 8:30 PM | Set in onboarding; moves with your answers (section 4.5). |
| `workHours` | Mon to Fri, 9:00 AM to 5:00 PM | Read from Focus if a Work Focus exists **[Check]**. |
| `weekendMorning` | Saturday 9:00 AM | |
| `dailyBudget` | 4 notifications a day, the Issue included | Section 4.6 **[Check]**. |
| `school` | `{on, child, school, about, words[], days[]}` | **[Old]** `edition.school`. `child` is one string; names are split on commas or "and" (`childNames`). Days default Mon and Fri. |
| `inbox` | `{key, address}` | The email-in key and address, carried over on import. |
| `ai` | `{consent, device, token, attested}` | Carried over on import, so 1.0 users keep their AI sign-up. |
| `statsOff` | false | **[Old]** `edition.statsOff`. |

### 1.7 Export format

JSON: `{ "app": "shoebox", "format": 3, "exported": ISO8601, "saves": [...], "moments": [...], "events": [...], "settings": {...} }` with files in a folder beside it (`files/<attachment id>.<ext>`), packed as one `.shoebox` zip **[Check]**. Format 3 so it never collides with the old app's version 1 and 2. Settings in the export leave out the inbox key and AI token unless you choose "Include my email address and AI sign-up" (for moving to a new phone).

---

## 2. Save kinds, and how each is detected and captured

You never pick a kind. Shoebox decides from what arrives.

### 2.1 Detection from text **[Old]** `model.js` `detectText`, `draftFromUrl`, `parseQuote`

In this order:

1. **Several links and nothing else** (only spaces, commas, dashes, bullets between them): one save per link.
2. **One link and fewer than 40 other characters**: a link save; the other words become the title.
3. **A link with its page title on one line**, at the start or end, up to 200 other characters and at most two lines (how Safari shares): a link save.
4. **A quote** (no link, up to 600 characters):
   - wrapped in quote marks (straight, curly or « »), optionally followed by a dash or line break and an author; or
   - a passage of 12 or more characters ending in an attribution. An em dash, en dash or line break before the name is enough; a plain hyphen needs a finished sentence of four or more words before it, so "call Sam - Tuesday" stays a note.
   - The attribution must start with a capital, be seven words or fewer, and not be a weekday, month, "today", "tomorrow", "tonight", "asap", "eod" or "tbd".
5. **Anything else**: a note. Its first line (90 characters max) is the title.

A single link becomes:
- **video** when it's YouTube (`watch?v=`, `youtu.be/`, `shorts/`, `embed/`, `live/`), with the thumbnail `https://i.ytimg.com/vi/<id>/hqdefault.jpg` and the real title and channel looked up (3.5 s limit, best effort), or when it ends in `.mp4 .mov .m4v .webm`;
- **photo** when it ends in `.jpg .jpeg .png .gif .webp .avif .heic`;
- **link** otherwise. Title from the page (relay `/preview`), falling back to the last part of the path, cleaned, or the host.

### 2.2 Detection from files **[Old]** `kindOfFile`

| Kind | Rule |
|---|---|
| photo | `image/*`, or `.heic .heif .jpg .jpeg .png .gif .webp` |
| pdf | `application/pdf` or `.pdf` |
| video | `video/*` |
| file | everything else, including text, audio, Word, Pages, Keynote, zip. Text files keep their text for AI. |

A photo whose main subject is a book becomes a book save (title and author read from the cover) **[Old]** `enrich` `book`.

### 2.3 Ways in

| Way in | What happens | Reason |
|---|---|---|
| **Share sheet** (any app) | A small sheet: what Shoebox found ("Link · nytimes.com"), a reason field with a microphone, and Save. Saving shows the capture line ("Comes back Saturday morning", tap to change), then closes. | Typed or spoken. If the sharing app passes a comment, it fills the reason field **[Check]** (the old extension used it as the title). |
| **Action Button / Siri** ("Save this to Shoebox") | Captures what's on screen (the page in Safari, the current item in apps that expose it, otherwise a screenshot), then asks out loud "Why are you keeping it?" and listens. | Spoken. |
| **Paste in the app** | Paste anywhere on the Coming back screen; same detection. | Typed. |
| **Email in** | Mail to your Shoebox address waits on the relay up to 30 days until the app collects it **[Old]**. Each email becomes one save (section 7 for school mail). | Your own note above a forward becomes the reason **[Old]** `emailPost` `why`. |
| **New screenshots** | With Photos access limited to screenshots, each new screenshot is read on the phone (text recognition). If it holds a date, a form, an address or a list, it is offered as a save. Otherwise it's left alone. | None; the planner reads the text. |
| **Import** | Section 11. | `imported` |

**Spoken reasons.** Recognized on the phone (iOS 26 speech recognition, on-device only; nothing is sent). Hold the microphone to talk, release to stop, 15 seconds max. Filler words ("um", "uh", "like," at the start) are removed, the first letter is capitalized, and it is cut at 140 characters on a word boundary. The words appear as you speak so you can see what was heard **[Check]**.

**No reason given.** The save is kept anyway. Shoebox never blocks a save to ask for a reason. The capture line shows the planner's guess with "Change?" (section 4.7).

### 2.4 Time to read or watch, when AI hasn't said **[Old]** `estimateMinutes`

note: words ÷ 220, at least 1 · quote 1 · photo 1 · link 6 · pdf 15 · video 10 · file 5. A book costs 30 **[Old]** `asBook`, `BOOK_SITTING_MINUTES` (not in `estimateMinutes`).

---

## 3. Verdicts

Every moment carries three actions, usable from the Lock Screen without unlocking (rule 4).

| Verdict | Button label | What it does |
|---|---|---|
| **Done** (the main action, in the act color) | The kind's own word: Read (read), Watched (watch), Listened (listen), Done (task; or the reason's verb when it starts with one: Booked, Ordered, Signed, Called), Tried it (idea), Kept (reference, photo, quote), I've read it (book). School posts: Done (action), Decided (decision), Got it (info) **[Old]** for school and book; the rest **[Check]**. | `status = done`, `doneAt` set, moment `answered`. Nothing else comes back for it. On the Lock Screen the main action may instead be the doing word ("Read now", "Show it", "Book it"), which opens the thing and marks it done after you return **[Check]**. |
| **Later** | A concrete time from the planner: "Tomorrow", "Saturday", "After planning", "Tonight". Expanded, it offers: Tonight, Tomorrow morning, This weekend, Next week, Pick a time, and "You choose" (Shoebox picks). | Plans one new moment. Doesn't count as a pass. The third Later asks instead: "Keep it, or let it go quiet?" **[Check]**. |
| **Drop** | Drop (Not for me on anything Shoebox suggested) **[Old]** "Let go". | `status = dropped`. Kept under Let go in Everything kept; restorable; never deleted on its own **[Old]** `model.js`: "Nothing is let go automatically". |

**Restore** puts a dropped, done or quiet save back to `unplanned` with `passes = 0`, `laters = 0`, and the planner places it **[Old]** `restore`.

**Undo** for 8 seconds after any verdict in the app, via the toast **[Check]**.

---

## 4. The return planner: how a reason becomes a moment

### 4.1 The pipeline

1. **Rules on the phone** (no AI): date words, weekdays, parts of the day, "this weekend", seasons, holidays, "before [event]" with a calendar match. Most reasons stop here. Runs in the share extension too, so the capture line appears at once.
2. **On-device model** (Foundation Models, structured output) when the rules find no time words but the reason isn't empty, or when the rules found two conflicting answers. It returns the same structure the rules do: `{when: date words, partOfDay, anchorQuery, lead, place, confidence}`. The rules engine then computes the actual times, so the model never does date arithmetic.
3. **Relay AI** only when the phone has no Apple Intelligence, and only with the reason text and today's date. Never calendar data (section 9).
4. **Content fallback** when there's no usable reason: kind, length and intent decide (rule R20).

The planner reruns for a save when its moment passes, when you choose Later, when the calendar changes an anchor event, and at each app launch for saves still `unplanned`.

### 4.2 Defaults the rules use

| Name | Default |
|---|---|
| Issue | 7:00 AM weekdays, 8:00 AM weekends |
| Morning (when a part of day is asked for) | the Issue |
| Lunch | 12:15 PM |
| Afternoon | 3:30 PM |
| Home evening | 6:00 to 8:30 PM; "at dinner" lands 10 minutes in (6:10 PM) (Storyboard) 6:10 |
| Tonight | 7:30 PM |
| After bed / late | 8:30 PM, the end of home evening |
| Weekend morning | Saturday 9:00 AM |
| Weekend evening | Saturday 7:30 PM |
| Workday start / end | 9:00 AM / 5:00 PM |
| Quiet hours | 9:00 PM to the Issue. Nothing arrives in them, except a moment you set to a time yourself. |

### 4.3 The rules, in priority order

The first rule that matches wins. "Lead" is how far ahead of the target the moment lands.

| Id | Matches | Moment |
|---|---|---|
| R1 | An explicit clock time ("7pm", "at 3") | That time, today if still ahead, else tomorrow. Notification. |
| R2 | Relative time ("in an hour", "in 2 weeks", "in 3 days") | That time; days round to the Issue of that day. |
| R3 | "before / ahead of / for / at / when it comes up at [something]" where [something] matches a calendar event in the next 60 days (on-device matching of words, then the model if unsure) | **Short event:** start at event start − (minutes + 1); window until the event starts; Live Activity on the Lock Screen with a countdown (Storyboard) 9:48 for an 11-minute read before 10:00. If that time isn't free, the latest free gap that day long enough; if none, that day's Issue. **Multi-day event or trip:** Issue 7 days before for trips, 2 days for anything else **[Check]**. |
| R4 | "on the plane / flight" with a flight on the calendar | The evening before departure at home, 7:30 PM, so it's downloaded **[Check]**. |
| R5 | Gift words ("gift", "present", "for X's birthday") with a dated target | Issue 10 days before the date **[Check]**. |
| R6 | A date ("Nov 20", "the 20th", "12/3") | That day's Issue. With deadline words ("by", "due", "register", "sign up", "before"): Issue 2 days before, or the day before if that's sooner than 2 days away. |
| R7 | A weekday ("Tuesday", "next Tuesday") | The next one that isn't today (on a Wednesday, "next Tuesday" and "Tuesday" are both 6 days out) **[Check]**, at its Issue, or at the part of day named. |
| R8 | "today", "this morning/afternoon", "tonight", "at lunch", "after the kids are in bed" | Today at that part of day if it's still ahead; otherwise the same part of day tomorrow. |
| R9 | "tomorrow", "tomorrow night" | Tomorrow at the Issue, or at the part of day named. |
| R10 | "at dinner", "at home", "with the kids", "show [family]" | Home evening, today if before 5:30 PM, else tomorrow. Place `homeEvening`. |
| R11 | "this weekend" | Saturday weekend morning. If it's already Saturday before noon: today 2:00 PM; Saturday afternoon or Sunday: Sunday 9:00 AM; Sunday after noon: next weekend. If the content needs a day ahead (a recipe with an overnight step, a delivery), the model may move it earlier, to Saturday 8:05 AM or Friday evening (Storyboard) 8:05 AM sourdough. Watch kinds go to weekend evening. |
| R12 | "next weekend" | The Saturday after the coming one. If that weekend is blocked by an all-day or away event on the calendar, the Friday 7:30 PM before it **[Check]**. |
| R13 | "next week" | Monday's Issue. |
| R14 | "this month", "next month", "end of the month", "in March" | Month start: the first weekday's Issue. "End of the month": the last weekday's Issue. |
| R15 | Seasons ("this fall", "next spring", "this summer") | Season in progress: this weekend (R11). Season ahead: the first Saturday on or after the season's start, weekend morning. If the save is about a place or event with a known best time (peak leaf color, a festival), the relay may look that up and use it instead (Storyboard) "first weekend of peak color". |
| R16 | Holidays ("Christmas", "Thanksgiving", "spring break") | The holiday is the target; with "before": Issue 14 days before for gifts and travel, 2 days otherwise. "Spring break" and other school dates come from school posts if one names it; otherwise Shoebox asks once at capture **[Check]**. |
| R17 | "next quarter", "next year" | The first workday of the next quarter or year, at its Issue. |
| R18 | Work words ("at work", "Monday at work", "for the team") | Workday start + 30 minutes on the next workday (or the day named). Place `work`. |
| R19 | Place words Shoebox can't know without location ("at Costco", "at the store", "when I'm downtown") | The next errand time: Saturday 10:30 AM. The capture line says "Comes back Saturday morning (I don't use your location)" **[Check]**. |
| R20 | No time words at all, or no reason | The content decides: under 15 minutes, an Issue 2 to 5 days out with room; 15 to 45 minutes or a watch, weekend morning or evening; over 45 minutes, a weekend morning; "someday", "eventually", "one day": an Issue about 4 weeks out on a Saturday. Picks the day with the fewest moments already planned **[Check]**. |
| R21 | A reason that names a time Shoebox can't place ("when Sam visits", "when it gets cold") | Asks once at capture with three choices drawn from the words ("This weekend", "Next month", "Pick a date"). Unanswered, it falls back to R20 (or to R14 when the model can read a month from the words, such as "cold" meaning December) and marks the moment `guess` **[Check]**. |
| R22 | Recurring words ("every Monday", "daily") | Not a save moment. The capture line offers "Make this a reminder instead?" and prepares a Reminders entry for you to confirm (rule 5). If you keep it as a save, it gets one moment on the first occurrence **[Check]**. |

A moment is never placed in the past, never in quiet hours (except R1 with your own time), and never more than 18 months out.

### 4.4 Examples

All examples are saved on **Wednesday, November 4, 2026, at 2:00 PM**, with default settings and this calendar:

- Thu Nov 5, 10:00 to 11:00 AM: Quarterly planning (9:00 to 10:00 is free)
- Fri Nov 6, 7:00 PM: Band concert
- Tue Nov 10, 2:00 PM: Sprint review
- Sat Nov 14 to Sun Nov 15, all day: Camping, Carolina Beach
- Sat Nov 21, all day: Sam's birthday
- Mon Nov 23, 8:15 AM: Flight to Denver (trip through Fri Nov 27)

Each example is planned on its own, as if it were the only save. When several land close together, section 4.6 spaces them out.

| # | Reason, as typed or said | What it is | Comes back | Surface | Rule, and why |
|---|---|---|---|---|---|
| 1 | Read before we plan next quarter | Link, 11 min | Thu Nov 5, 9:48 AM, until 10:00 | Live Activity | R3. Matches Quarterly planning; 10:00 − 12 min, inside the free hour. |
| 2 | For Thursday's meeting | Link, 6 min | Thu Nov 5, 9:53 AM | Live Activity | R3. "Thursday's meeting" picks the only Thursday event. |
| 3 | Bring this up when tech debt comes up at sprint review | Link, 4 min | Tue Nov 10, 1:55 PM | Live Activity | R3. Sprint review match; 2:00 − 5 min. |
| 4 | Show the kids at dinner | Photo | Today, 6:10 PM | Notification, home evening | R10. Before 5:30 PM, so today. |
| 5 | At dinner (saved instead at 6:45 PM) | Link | Tomorrow, Thu Nov 5, 6:10 PM | Notification | R10. Past 5:30 PM, so the next evening. |
| 6 | Tonight | Video, 12 min | Today, 7:30 PM | Notification | R8. |
| 7 | After the kids are in bed | Video, 40 min | Today, 8:30 PM | Notification | R8. End of home evening. |
| 8 | At lunch | Link, 6 min | Thu Nov 5, 12:15 PM | Notification | R8. Lunch has passed today, so tomorrow. |
| 9 | Tomorrow | Note | Thu Nov 5, 7:00 AM | Issue | R9. |
| 10 | Tomorrow night | Link | Thu Nov 5, 7:30 PM | Notification | R9 with part of day. |
| 11 | Friday | Link | Fri Nov 6, 7:00 AM | Issue | R7. |
| 12 | Tuesday | Link | Tue Nov 10, 7:00 AM | Issue | R7. Next Tuesday that isn't today. |
| 13 | Next Tuesday | Link | Tue Nov 10, 7:00 AM | Issue | R7. On a Wednesday, read as the coming Tuesday **[Check]**. |
| 14 | This weekend | Link, 20 min | Sat Nov 7, 9:00 AM | Notification (mirrors to Watch) | R11. |
| 15 | Try the long cold ferment this weekend | Link (recipe) | Sat Nov 7, 8:05 AM | Notification | R11. The model sees an overnight step and moves it earlier so the bread is ready Sunday. |
| 16 | Watch with Kate this weekend | Video, 95 min | Sat Nov 7, 7:30 PM | Notification | R11. A long watch goes to weekend evening. |
| 17 | Next weekend | Link | Fri Nov 13, 7:30 PM | Notification | R12. That weekend is all camping, so the Friday evening before. |
| 18 | Next week | Link | Mon Nov 9, 7:00 AM | Issue | R13. |
| 19 | In two weeks | Note | Wed Nov 18, 7:00 AM | Issue | R2. |
| 20 | In an hour | Note | Today, 3:00 PM | Notification | R2. |
| 21 | 7pm | Note | Today, 7:00 PM | Notification | R1. |
| 22 | Call about Nov 20 | Note | Fri Nov 20, 7:00 AM | Issue | R6. A plain date. |
| 23 | Register by Nov 20 | Link | Wed Nov 18, 7:00 AM | Issue | R6. Deadline word: 2 days before. |
| 24 | Gift idea for Sam's birthday | Link | Wed Nov 11, 7:00 AM | Issue | R5. Calendar has the birthday; 10 days before. |
| 25 | Read on the plane | PDF, 40 min | Sun Nov 22, 7:30 PM | Notification | R4. Evening before the flight, so it's downloaded. |
| 26 | For the Denver trip | Link | Mon Nov 16, 7:00 AM | Issue | R3, multi-day: 7 days before the trip. |
| 27 | Make this for Thanksgiving | Link (recipe) | Sat Nov 21, 9:00 AM | Notification | R16 with judgment: Thanksgiving falls inside the Denver trip, so the model places it on the last weekend morning before leaving **[Check]**. |
| 28 | Before Christmas | Link (a gift) | Fri Dec 11, 7:00 AM | Issue | R16. Gift: 14 days before Dec 25. |
| 29 | End of the month | Note | Mon Nov 30, 7:00 AM | Issue | R14. Last weekday. |
| 30 | Next month | Link | Tue Dec 1, 7:00 AM | Issue | R14. First weekday. |
| 31 | In March | Link | Mon Mar 1, 2027, 7:00 AM | Issue | R14. |
| 32 | Next quarter | Link | Mon Jan 4, 2027, 7:00 AM | Issue | R17. Jan 1 is a holiday and a Friday; first workday. |
| 33 | Drive it next fall | Link (Blue Ridge Parkway) | Sat Oct 16, 2027, 9:00 AM | Notification | R15. Relay looks up typical peak color for that stretch (mid-October); without it, Sat Sep 25, 2027, the first Saturday of fall. |
| 34 | Next spring | Link (a garden plan) | Sat Mar 20, 2027, 9:00 AM | Notification | R15. Spring starts Mar 20, a Saturday. |
| 35 | This summer | Link | Sat Jun 26, 2027, 9:00 AM | Notification | R15. Said in November, so next summer; first Saturday on or after Jun 21. |
| 36 | Monday at work | Link | Mon Nov 9, 9:30 AM | Notification | R18. |
| 37 | Pick up at Costco | Note | Sat Nov 7, 10:30 AM | Notification | R19. No location; the errand time. |
| 38 | Someday | Link | Sat Dec 5, 8:00 AM | Issue | R20. About 4 weeks out, on a Saturday. |
| 39 | (no reason) | Link, 6 min | Fri Nov 6, 7:00 AM | Issue | R20. Short read; 2 to 5 days out, the lightest Issue. |
| 40 | (no reason) | Link, 35 min, and AI calls it a weekend project | Sat Nov 7, 9:00 AM | Notification | R20 (Storyboard) "It sounds like a weekend project". |
| 41 | Interesting | Link, 6 min | Fri Nov 6, 7:00 AM | Issue | R20. No time in it, so treated like no reason. |
| 42 | For the house | Link, 25 min | Sat Nov 7, 9:00 AM | Notification | R20. Topic only, no time; medium length goes to the weekend. |
| 43 | When Sam visits | Note | Asks at capture: "This weekend · Next month · Pick a date". Unanswered: Fri Nov 6, 7:00 AM, marked `guess` | Issue | R21. No calendar match. |
| 44 | When it gets cold | Link (chili recipe) | Asks at capture; unanswered: Tue Dec 1, 7:00 AM **[Check]** | Issue | R21, then R14: the model reads "cold" as December, so the first weekday of it. Weather isn't used. |
| 45 | Every Monday | Note | Offers a Reminders entry; kept as a save: Mon Nov 9, 7:00 AM | Issue | R22. |

### 4.5 Place and "at home" (decision 3)

There is no location in v1. `homeEvening` holds when the time is inside home evening and, if you have a Home Focus, that Focus is on. If a Home Focus exists and isn't on at the planned time, the moment waits up to 90 minutes for it, then arrives anyway **[Check]**.

Home evening moves with you: after 10 answered home-evening moments, if the middle of your answer times is more than 30 minutes from where the window starts, the window shifts by that much, never earlier than 4:30 PM or later than 9:00 PM. Settings shows the current window and lets you set it back **[Check]**.

`work` holds inside work hours (or while a Work Focus is on, if you have one). A work moment never lands on a weekend or a day the calendar shows as away.

### 4.6 Collisions and the daily budget **[Check]**

- At most 4 Shoebox notifications a day, the Issue included. Live Activities count as one each.
- Timed notifications at least 2 hours apart, unless tied to a calendar event.
- A moment that would break either rule joins that day's Issue if it can still make it (before the Issue time), or moves to the next free slot of the same kind, at most 2 days later. Past that, it goes to the next Issue.
- Calendar-anchored moments (R3, R4) win over everything else.

### 4.7 The capture line

Right after saving, the sheet shows one line in plain words: "Comes back Saturday morning", "Back at 9:48, before Quarterly planning", "Back at dinner tonight". Tapping it offers the Later choices plus Pick a time. The line comes from the rules at once; if the model refines it later, the change shows in Coming back, never as a new notification (Storyboard) "Comes back Saturday morning, at home".

---

## 5. The quiet rule

Rule 3: ignored twice, it goes quiet.

**What counts as a pass.** A moment ends as a pass when its window closes with no verdict and the save wasn't opened. Specifically:

| Surface | Window closes | Also a pass |
|---|---|---|
| Notification | 3 hours after delivery, or at quiet hours, whichever is sooner | Swiping the notification away (the dismiss action) |
| Issue line | 11:59 PM that day | |
| Live Activity | When the anchor event starts | Dismissing the Live Activity |

**What is not a pass.** Later (any kind). Opening the save without a verdict: that's an `opened` event; the save is re-planned like "You choose" and shows a quiet "Done?" on its row **[Check]**. A moment that never reached you (notifications off, phone off the whole window) is cancelled, not passed, and re-planned **[Check]**.

**Two passes, then quiet.** On the second pass `status = quiet`, `quietAt` set, no moment. There is no third offer, no fading list and no countdown. The old fading rules (21 days untouched, or 8 deferrals) are gone **[Old]** `FADE_DAYS`, `MAX_SKIPS`.

**Quiet is not gone.** Quiet saves stay in Everything kept with a small "Quiet" label, turn up in search and Siri answers, and are never deleted on their own.

**How it comes back if you ask.**
- Find it (search, Siri, Everything kept) and tap **Bring it back**: the Later choices, plus "You choose". `passes` resets to 0.
- Ask Siri "bring back the campsite thing": same, by voice.
- Nothing else brings a quiet save back. Shoebox doesn't nudge about quiet saves **[Check]**.

---

## 6. The Daily Issue

One rich notification each morning: a small cover with today's few, as your reasons.

- **When:** 7:00 AM weekdays, 8:00 AM weekends (both settable). It's the only scheduled moment; everything else is timed to a reason.
- **What goes in, in order:**
  1. Saves whose moment is today's Issue (rules R2, R5, R6, R7, R9, R13, R14, R17, R20, and overflow from 4.6).
  2. School posts that need something within 2 days (action or decision) and any dated today (section 7).
- **How many:** up to 3 saves and up to 2 school posts, so at most 5 lines **[Check]**. Extra saves move to the next Issue with room. It is never padded: a quiet morning has one line, or no Issue at all.
- **The cover:** the first reason, large, in the serif; under it "and 2 more" in Archivo. Expanded (long press), each line has its own Done, Later and Drop. This needs a Notification Content extension target, which `docs/PLAN.md` section 6 doesn't list yet **[Check]**.
- **Composing it:** local notifications are fixed when scheduled, so the Issue is recomposed and rescheduled each time the planner runs (app open, background refresh, share extension save, any verdict). The last composition before 7:00 AM is what arrives.
- **Answering:** each line's window is the day (section 5).

---

## 7. School newsletters by email

### 7.1 Settings **[Old]** `app.js` `SCHOOL_PUBLIC`

`on` (off by default), `child` (one string; several names split on commas or "and"), `school` (short name), `about` (what the parent cares about: grade, teams, activities), `words` (other words that mark school mail, such as the mascot), `days` (Mon and Fri, when the app asks for a pasted newsletter).

### 7.2 Which mail is school mail **[Old]** `isSchoolMail`

A mail is school mail when the school's name or any of the words (3+ characters) appears in its sender, sender name or subject, or in the first 4,000 characters of its text. A PDF you send yourself (a district calendar) is also read as possible school mail when school posts are on and an `about` or child name is set; if nothing in it is for your child, it's kept as an ordinary file save.

An email with no attachments, a body under 400 characters and at least one link: the relay reads the first link's page (`/preview?text=1`) and that text is used. Up to 3 linked PDFs and 6 attachments are read with it **[Old]** `mailFiles`.

### 7.3 Masking the child's name **[Old]** `maskNames`, `nameIn`, `unmaskName`, `CHILD_TOKEN`

1. Before anything is sent, each name in `child` (2+ characters, whole word, any case) is replaced with `{child}` in the newsletter text and in `about`. With no name set, "your child" is used.
2. The AI is told to write `{child}` exactly, braces included, never "your child" and never an invented name.
3. On the phone, `{child}` is replaced with the first name (or "your child"; the old code capitalized it only at the very start of the text, 2.0 capitalizes it at the start of any sentence **[Check]**).

**Gap in the old app, and the fix [Check]:** attachments (flyers, PDFs) went to AI as they were, names and all; the privacy page said so. In 2.0, attachments are read on the phone first (text recognition for pictures, PDF text extraction), masked, and sent as text. A picture is sent as a picture only when no text could be read from it, and the privacy page keeps saying that.

Also masked **[Check]**: the child's name in the sender line and subject.

### 7.4 The AI's job **[Old]** `ai.js` `schoolPosts`, kept word for word in phase 5

Not a summary: each piece that matters for that child becomes its own short post, with its specifics. Keep: the child's grade, activities and teams, and whole-school dates, deadlines, closings and requests. Leave out other grades, other sports and clubs, staff news, fundraising pitches, filler, and anything already past. A calendar covering many weeks: each date in the next 8 weeks that affects the child, then only breaks, holidays and the last day. Up to 16 posts, each:

`type` (`action`, `decision`, `info`) · `headline` (max 70) · `body` (1 to 3 sentences, max 300, at most one exclamation mark, no emoji) · `date` (YYYY-MM-DD or null) · `tags` (1 to 2) · `photo_query` · `source` (attachment name or "email").

Model: Haiku, through the relay, max 3,500 tokens out, up to 30,000 characters of newsletter text.

### 7.5 What each post becomes

Each post is a save: `kind = note`, `source = school`, `reason` = the headline (with the name put back), `text` = the body, `school = {name, type, date, body, sourceFile, fromURL}`.

Its moment **[Check]**:
- **action or decision with a date:** the Issue 2 days before (or the day before, if sooner). Due today or tomorrow when it arrives: the next Issue.
- **info with a date:** that day's Issue.
- **info without a date:** the next Issue only. One pass and it goes quiet, since it's news.
- A post whose date passes without a verdict goes quiet, not done.

Done words: Done, Decided, Got it (section 3). The old "Not needed" / "Not for us" become Drop.

Pictures for school posts (Openverse photos plus an overlay line about the child) are left out of v1 **[Check]**.

---

## 8. Other email (not school) **[Old]** `emailPost`

One email becomes one save: a plain headline (max 70), a body (1 to 3 sentences, max 280), up to 4 dated items, the one link worth opening, and your own note above a forward as the reason. Never the whole email. The cleaned text (no forward headers, quoted replies, signatures, footers, tracking links) is kept as "The whole email" **[Old]** `cleanEmail`. Without AI, the body is the cleaned text cut to 280 characters, ending at the last sentence end past the halfway point, else at a word boundary with "…" **[Old]** `emailPreview`.

---

## 9. AI

### 9.1 Where each job runs

| Job | Runs on | Sends off the phone |
|---|---|---|
| Return planner: rules | Phone | Nothing |
| Return planner: model | Phone (Foundation Models) | Nothing |
| Return planner: fallback (no Apple Intelligence) | Relay, Haiku | The reason text and today's date only. Never calendar data. Matching to calendar events is always done on the phone. |
| Reading screenshots and photos for text | Phone (Vision) | Nothing |
| Filing a save (title, summary, tags, minutes, intent, hook) for notes, quotes and short text | Phone | Nothing |
| Filing a link (needs the page's text), PDFs, long documents, book covers, picture choice | Relay, Haiku | The page text or file, your reason, your tags in use **[Old]** `enrich`, `pickPicture` |
| School posts, email posts | Relay, Haiku | Masked text (section 7.3) |
| Task lookups ("Book the campsite": open dates, a prefilled link) | Relay, Haiku with web search | The task words and place; facts come back with sources. The relay never books, pays or sends (rule 5). |
| Seasonal "best time" lookups (R15) | Relay, web search | The place or event name only |

AI consent is asked once, the first time a save would need the relay, with the plain promise from section 10. Saying no keeps everything on the phone; relay-only jobs are skipped and the save is filed with what the phone could do **[Check]**.

### 9.2 App Attest **[Old]** `ai.js` `attest`, relay `/ai/challenge`, `/ai/attest`

1. The app asks the relay for a one-time challenge (`POST /ai/challenge`; kept 5 minutes; up to 30 per network per day).
2. The app attests a new App Attest key with that challenge.
3. `POST /ai/attest` with the challenge, key id and attestation. The relay checks it against Apple's App Attest root and returns a device id and token. Only a hash of the token is kept.
4. Every AI call carries `x-shoebox-device` and `x-shoebox-token`. A 401 with code `register` means start over; a 403 with code `attest` means attest again (once).
5. An install that already has a device id keeps it when it attests again (so 1.0 sign-ups carry over).
6. Owner phones (`AI_OWNER_DEVICES`) have no per-device limit.

### 9.3 Cost limits **[Old]** relay settings

| Limit | Default | Message |
|---|---|---|
| Per device, per calendar month | $1.00 (`AI_DEVICE_MONTHLY_CENTS` 100) | "You've used this month's AI allowance. It resets on the 1st." |
| Whole relay, per day | $20.00 (`AI_DAILY_CENTS` 2000) | "Shoebox's AI is resting for today. It's back tomorrow." |
| Per network address, per day | $0.75 (`AI_NETWORK_DAILY_CENTS` 75) | "This network has used today's AI allowance. It resets tomorrow." |

The relay also refuses: any model other than the allowed list (Haiku, Sonnet), `max_tokens` over 4,000, more than 4 messages, bodies over 12 MB, streaming, unexpected fields, and any tool other than web search. Web search is charged at $10 per 1,000 searches. Cost is computed from token usage at the model's price.

When a limit is hit, the save is filed with what the phone could do, and the relay job is retried after the reset **[Check]**.

---

## 10. Privacy, as plain promises

These replace `edition/privacy.html` for 2.0. Each is a promise the code must keep.

1. **No account, no ads, no tracking, nothing sold.**
2. **Your saves live on your phone.** Links, notes, photos, files, reasons, tags and history are stored on this iPhone. Deleting the app deletes them. Backups you export are files you control.
3. **Your calendar never leaves your phone.** Shoebox reads it on the phone to find the right time. Event titles, times and people are never sent anywhere.
4. **When a save comes back is decided on your phone.** If your iPhone can't run Apple's on-device AI, only the reason you typed and today's date are sent to work out the time.
5. **Shoebox doesn't use your location.**
6. **Photos: only screenshots, and only if you allow it.** They're read on your phone. A screenshot leaves the phone only if you keep it and turn AI on, in the same way as any other save.
7. **AI is your choice.** With AI on, the text of a link's page, a document or a newsletter, and your reason, go through Shoebox's server to Anthropic's Claude. The server passes it through and doesn't keep it. Anthropic doesn't train on it.
8. **Your child's name stays on your phone.** Newsletters and their flyers are read on your phone first; the AI sees "{child}" and the name goes back in on your phone.
9. **Link previews.** To show a link's title and picture, Shoebox's server fetches that page. The address isn't kept.
10. **Email in.** Mail sent to your Shoebox address waits on Shoebox's server for up to 30 days, until the app collects it, then it's deleted.
11. **What the server keeps about you:** a random install number, a fingerprint of its access code, Apple's confirmation that it's the real Shoebox app (which identifies no person), and a count of AI use, to keep costs in check.
12. **Anonymous counts, and you can turn them off.** Once a day: how many things were saved and came back, with a random number used only for this. Never what you saved.
13. **One button deletes everything,** on the phone and on the server (your email address, waiting mail, AI sign-up). Backups you exported stay where you put them.
14. **Shoebox never acts for you.** It can look things up and prepare a reminder or a link. It never books, pays, sends or deletes on its own.

Reminders no longer go through the server (they're local notifications), so the old "Reminders" paragraph and the calendar-address paragraph are gone from 2.0's page. They stay true for 1.0 while it's in use **[Check]**.

---

## 11. Importing the old app's saves

### 11.1 Where the old saves are

1.0 is a web app in an iPhone wrapper (`edition/ios/App/WebViewController.swift` loads `https://inmyshoebox.com/?native=1`). Its saves live in that page's IndexedDB (`edition` database, stores `items`, `blobs`, `meta`, `shares`) and its settings in localStorage (`edition.*` keys) **[Old]** `db.js`. Every day it also writes a backup:

- `Documents/Backups/shoebox-backup-YYYY-MM-DD.json` in the app's own container (Files › On My iPhone › Shoebox › Backups), last 7 kept;
- a copy in iCloud Drive › Shoebox › Backups when iCloud Drive is on.

### 11.2 Automatic import on 2.0's first launch

2.0 is an update to the same app (same bundle id), so it can read the same container.

1. On first launch, before onboarding, look for the newest `shoebox-backup-*.json` in `Documents/Backups`, then in the iCloud copy. Use the newest by date in the file name, then by `exported` inside it.
2. If found, show "Bringing your saves over…" and import it (11.4). Then show a one-screen report: "214 saves, 37 photos and files, your email address and settings came over."
3. **Fallback if no backup is found [Check]:** load a hidden web view with the base address `https://inmyshoebox.com`, read the `edition` IndexedDB and `edition.*` localStorage with a script, and import that. Must be tested in phase 2 on a real 1.0 install: whether the old web storage can be read this way, and offline.
4. If both fail, onboarding says plainly: "Your saves from Shoebox 1 are in Files › Shoebox › Backups. Tap here to import them." It never says they're lost.
5. The old backup files and web storage are never deleted by 2.0.

### 11.3 Manual import

Settings › Import a backup accepts a version 1 or 2 old backup (`"app": "edition"`, `items` array required) **[Old]** `unpackBackup`, or a 2.0 export (format 3). Anything else: "That file isn't a Shoebox backup."

### 11.4 How a backup maps **[Old]** `packBackup`: `{app: "edition", version: 2, exported, items, meta, files: [{id, type, data (base64)}], settings}`

| Old | New |
|---|---|
| `id` | `oldId`. A new UUID is made for `id`. |
| `kind` | Same, except `text` and `audio` become `file` **[Check]**. |
| `why` | `reason`, `reasonSource = imported`. Empty stays empty. |
| `title`, `text`, `url`, `author`, `videoId`, `imageUrl`, `summary`, `hook`, `points`, `extended`, `transcript`, `tags`, `minutes`, `intent`, `book`, `focus`, `imageAlt`, `loved`, `replies` | Same meaning (`imageAlt` → `alt`, `focus` → `pictureFocus`, `replies` → `thoughts`). |
| `titleMine`, `tagsMine`, `editedAt` | `edited` set. |
| `blobId`, `thumbId` | Attachments, from `files` matched by id; bytes decoded from base64, `sha256` computed. A missing file keeps the save without it and is counted in the report. |
| `created` | `createdAt`. `updatedAt` = import time. |
| `status: inbox` | `unplanned` |
| `status: queued`, not faded | `unplanned`; the planner places it, from its reason |
| `status: queued`, faded (`fadedAt`, or 21+ days since last touched) | `quiet` |
| `status: aside` with `until` | `planned`, with an Issue moment on the `until` day (or the next Issue, if that's past) |
| `status: done` | `done`, `doneAt` kept |
| `status: archived`, `washedOut` | `quiet` |
| `status: archived` | `dropped`, `droppedAt` = `archivedAt` |
| `school` | `school` (section 7.5); a date already past: `quiet` |
| `email` | `email` |
| `suggested: true` (old top stories and suggestions) | Imported as `dropped` unless done **[Check]** (suggestions aren't in v1). |
| `sample` | Skipped. |
| `history` | One `MomentEvent` per entry, type from `v` (`let-go` → `dropped`, `later`, `done`, `read-now` → `done`, `aside` → `later`). |
| `skips`, `deferredAt`, `queuedAt`, `backAt`, `ai`, `cover`, `tint`, `imageCands`, `postTries`, `pageTries`, `enrichTries`, `picSettled`, `coverOff`, `photoQuery`, `jung`, `suggestReason`, `site`, `blocked` | Not carried over **[Check]**. |

**Settings carried over:** `edition.inboxKey` and `edition.inboxAddress` (your email address keeps working), `edition.aiDevice`, `edition.aiToken`, `edition.aiConsent` (your AI sign-up keeps working), `edition.school`, `edition.statsOff`, `edition.remindTime` (becomes the weekday Issue time only if it isn't the default 9:00 **[Check]**). Everything else is dropped: songs, quotes, stories, weather, calendar caches, theme, palette, Perplexity and API keys.

**Safe to run twice.** A save whose `oldId` already exists is skipped (or updated if the backup's copy is newer). Import writes everything in one transaction; if it fails partway, nothing is kept and the report says so.

**Large backups.** Photos ride inside the JSON as base64, so a backup can be hundreds of MB. Phase 2 reads it in a streaming way, one item and one file at a time, not as one string in memory **[Check]**.

---

## 12. Coming back and Everything kept (the app)

Short here; phase 1 designs it.

- **Coming back:** planned saves by moment, grouped by day ("Sun", "Tue", "Nov", "Sep '27"), each with its reason and the source in small type (Storyboard) "Sunday · The app".
- **Everything kept:** one question away. Search by asking ("the campsite thing") across reasons, titles, text and transcripts; filters for Quiet, Done, Let go.
- No inbox to clear, no counts of what's waiting.

---

## 13. Proposals for a stickier, more distinctive app

Graham asked for pushback and ideas. None of these are decided; each needs a yes or no.

1. **The capture line is the hook, not the Issue.** The moment someone sees "Back at 9:48, before Quarterly planning" right after saving, they trust the app; that trust is what brings the next save. Make the capture line the most polished thing in phase 1, and measure "saves with a reason" as the first number we watch.
2. **A record of what came of it.** When you mark something done, an optional one-line "What came of it?" ("We booked the Nov 14 site", "Used it in the retro"). Over months, Everything kept becomes your own feed of intentions kept: the personal media feed, made of your reasons and outcomes rather than other people's posts. Once a year, "Your year in Shoebox": the things you meant to do and did.
3. **No guilt mechanics.** No streaks, no unread counts, no "you have 40 waiting". The quiet rule already does the forgiving; the app should feel lighter the more you use it. This is the main way Shoebox differs from read-later apps, and it should be visible in the App Store text.
4. **Pushback: 4 notifications a day may still be too many** for a first week. Proposal: the first 7 days cap at 2 a day (Issue plus one timed moment), then open up. The worst outcome is someone turning notifications off in week one, since then nothing comes back.
5. **Pushback: the Issue at 7:00 AM is a guess.** iOS can't send a local notification "at first unlock", so ask the Issue time in onboarding (7:00 as the default), then move it the way home evening moves: toward when you actually open the Issue, after two weeks of answers.
6. **A shared shoebox for the household, later.** "Show the kids at dinner" and school posts are family things. A second phone (a spouse) could share one household shoebox for the reasons that say so. Not v1; the sync-ready data model keeps it cheap.
7. **Siri as the second front door.** "What's coming back this week?" and "What did I save about tech debt?" answered in your own words. Already moment 7; proposal is to put it in onboarding as the second thing taught, after the share sheet.

---

## 14. For Graham to check

Every **[Check]** above, in one list. A "yes to all" is fine; otherwise name the numbers.

| # | Section | Decided here |
|---|---|---|
| 1 | 1.1 | Sync merge: last writer wins per record; tombstones win; events append-only. |
| 2 | 1.2 / 11.4 | Old `text` and `audio` kinds become `file`. |
| 3 | 1.2 | `loved` kept but not shown in v1. AI filing gives up after 3 tries. |
| 4 | 1.6 | Weekend Issue at 8:00 AM; Work hours from a Work Focus when one exists; daily budget of 4. |
| 5 | 1.7 | Export as a `.shoebox` zip, format 3; email key and AI token left out unless you choose. |
| 6 | 2.3 | A share-sheet comment fills the reason (old app used it as the title). |
| 7 | 2.3 | Spoken reasons: hold to talk, 15 s max, filler removed, words shown live. |
| 8 | 3 | Done words for non-school, non-book saves (Read, Watched, Listened, Done or the reason's verb, Tried it, Kept); a "Read now" style main action that opens then marks done. |
| 9 | 3 | The third Later asks "Keep it, or let it go quiet?". Undo for 8 seconds. |
| 10 | 4.3 R3 | Trips: 7 days ahead; other multi-day events: 2 days. |
| 11 | 4.3 R4 | "On the plane": the evening before, so it's downloaded. |
| 12 | 4.3 R5, R16 | Gifts 10 days before a birthday, 14 before a holiday. |
| 13 | 4.3 R7 | "Next Tuesday" said midweek means the coming Tuesday. |
| 14 | 4.3 R12 | A blocked "next weekend" moves to the Friday evening before. |
| 15 | 4.3 R16 | "Spring break" from school posts, else asked once. |
| 16 | 4.3 R19 | Place words without location go to Saturday 10:30 AM and say why. |
| 17 | 4.3 R20 | No-reason timing by length; "someday" about 4 weeks out. |
| 18 | 4.3 R21 | Unplaceable times ask once at capture with three choices. |
| 19 | 4.3 R22 | Recurring reasons offer a Reminders entry instead. |
| 20 | 4.4 #27, #44 | Thanksgiving moved before the trip; "when it gets cold" falls to December 1. |
| 21 | 4.5 | Home Focus wait of 90 minutes; home evening learns after 10 answers, bounded 4:30 to 9:00 PM. |
| 22 | 4.6 | Collision rules and the 2-hour spacing. |
| 23 | 5 | Opening without a verdict isn't a pass; undelivered moments aren't passes; no nudges about quiet saves. |
| 24 | 6 | Issue holds up to 3 saves and 2 school posts; needs a Notification Content extension target (add to PLAN section 6). |
| 25 | 7.3 | Flyers and PDFs read on the phone and masked before sending (fixes an old gap); sender and subject masked too; "Your child" capitalized at any sentence start. |
| 26 | 7.5 | School post moments; undated info goes quiet after one pass; school photos and overlays left out of v1. |
| 27 | 9.1 | No AI consent means relay jobs are skipped; over-limit jobs retry after the reset. |
| 28 | 10 | 1.0's privacy page stays as is while 1.0 is in use. |
| 29 | 11.2 | Fallback that reads the old web storage directly (to be proven in phase 2). |
| 30 | 11.4 | Old suggestions import as dropped; the listed old fields aren't carried; old reminder time only carried if changed. |
| 31 | 11.4 | Streaming import for large backups. |
| 32 | 13 | The seven proposals. |
