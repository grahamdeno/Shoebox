# Video 5: App Store previews (not ready to make)

Follow `docs/video/style.md` for everything not said here.

**Do not start this one yet.** Apple's rules for app previews are stricter than for any other video:
- They must show footage captured from the app itself. Pans and zooms over still screenshots may be rejected.
- They have set lengths (15 to 30 seconds), set sizes for each iPhone display, and a maximum number per listing.
- No hands, no device frames, no people, and nothing the app doesn't do.

**What has to happen first:**
1. Opus checks this plan against Apple's current App Store Connect rules for app previews, sizes and lengths.
2. CI records real simulator footage with sample data: Today, flicking up, pulling down into the box, opening a post, the Shoebox list. This is an addition to `Scripts/screens.sh`, made in Sonnet.
3. Graham approves the footage.

**Then, a plan for up to three previews, 15 to 30 seconds each, at the 6.9-inch iPhone size:**
1. **Three moves:** Today, flick up, pull down, tap open. Captions only, no voice.
2. **It reads the date:** the dated post and Coming up.
3. **Keep from anywhere:** Keep something, and a post appearing on Today.

The previews follow this guide's look and captions. Voice is optional on the App Store: if it's used, it's the same voice.
