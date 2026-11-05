# Shoebox videos: the style every video follows

**For:** Grok, making any Shoebox video. **Approver:** Graham. Read this first, then the sheet for the video you are making (`docs/video/01-promo.md` and the rest).
**What the app does:** `docs/SPEC.md`. Show only what is built. If a sheet and SPEC disagree, SPEC wins.

## Rules that can't bend

1. **Sample data only.** Every app screen comes from the screenshots CI makes with sample data: branch `ci-screens` of `grahamdeno/Shoebox`, files `light-<screen>.png` and `dark-<screen>.png`. Footage comes from CI recordings when a sheet asks for them. Never use anything from Graham's own phone: it holds his family's school mail and names.
2. **Fresh screens only.** Use the screenshots only if the `ci-screens` commit is newer than the last change to `App/Shoebox/Model/SampleData.swift` or `Scripts/demo-photos/`. If not, stop and tell Graham they are stale.
3. **Show only what exists.** No Android, Apple Watch, widgets, Lock Screen, Siri or Mac. No prices. Name Shoebox Plus only where a sheet does.
4. **No one else's interface or marks.** Abstract shapes stand in for other apps (Safari, Messages, Mail). No Apple logos, no App Store badge until the app is in the store, no brand names on screen.
5. **No people.** No faces, hands or children, real or generated. The thumb dot stands in for a hand.
6. **Ask twice.** Send Graham the storyboard (one still per shot, with its caption and line of voice) and wait for his yes. Then send the finished cut and wait for his yes before it goes anywhere.

## Who we're talking to

Busy adults who save things to come back to and rarely do: a parent with school emails and permission slips, a professional with links and screenshots. Most watch on a phone with the sound off, arriving from Graham's LinkedIn or a friend's link.

**What they should feel:** relief. Calm, warm, tidy. Not a productivity hustle.
**The line they should remember:** *Keep it. It comes back to you.*

## Look

| | |
|---|---|
| Colors | Pistachio `#F6F3E8` (light ground), Plum `#3B2240` (dark ground), Plum Ink `#2A1E2E` (text on light), Bone `#F1E9D8` (text on dark), Sunflower `#F9C93A` (the lid, highlights), lip `#D4A21E`, shade `#1A1020` (shadows, never black), lighter Plum `#6A4F73` (the box in dark scenes). No pure black, no peach, no other colors. |
| Type | SF Pro Display, semibold for captions; Inter if SF Pro is not available. Sentence case, at most 7 words a caption. |
| Screens | Full bleed with rounded corners, no device frame, except a plain rounded phone outline in the shade color when a sheet asks for one. |
| Motion | Slow and calm. Push-ins of 3 to 6% over 700 to 900 ms, ease in-out. Cross-dissolves of 300 ms, or a rounded-card mask wipe. No whip pans, spins, 3D flips or bounces. |
| Gestures | A soft thumb dot (Bone at 85%, 26 pt), like the app's own How Shoebox works pictures: up for Next, down into the box for Put away, a press for Open. |
| Focus | To point at something, dim the rest with the shade color at 40% and leave one rounded spotlight. One at a time. |
| End card | The logo from `light-welcome` on Pistachio, "Shoebox for iPhone", `inmyshoebox.com`, and the sheet's call to action. 3 seconds. |

## Sound

- **Voice: the same in every video.** One calm adult voice: warm, mid-range, female, unhurried, plain American English, like a friend explaining something she uses. Not an announcer, not upbeat, not salesy. About 130 words a minute, with pauses where the screen does the work. It must not imitate any real person. Keep the voice settings (model, voice name, speed) in `docs/video/voice.txt` once Graham approves the first video, and use them every time after.
- **Captions always.** Every spoken line is also on screen. Captions are the script trimmed to 7 words or fewer; they need not match word for word.
- **Music:** warm, sparse piano or acoustic guitar, 90 to 100 BPM, under the voice, royalty-free with a license Graham can keep (write it in `music-license.txt` with each video). The same track family across videos.
- **One sound effect:** a soft wooden "box" tap when a post drops into the box or the lid settles.
- **Silent versions** (the home page loop) have no audio track at all.

## Files

H.264 MP4, 30 fps, AAC audio. 16:9 at 1920×1080, vertical at 1080×1920. A poster JPEG (at most 200 KB) and a `.vtt` caption file with each video. Name files `shoebox-<video>-<length>.mp4`, for example `shoebox-promo-60.mp4`.

## The screenshots

| File | Shows |
|---|---|
| `welcome` | The logo and "Keep it. It comes back to you." |
| `share` | "Save from anywhere": Tap Share, Tap Shoebox, Say why |
| `time` | Choosing when posts come out each day |
| `learn` | "Three moves. That's the whole app." |
| `add` | Keep something: write a note or paste a link, Photo or file |
| `today` | The Fall band concert post on Today, its date and reason |
| `up` | Flicking it up for the next one |
| `away` | Pulling it down: "Let go to put it away" |
| `opened` | The opened post, "via your Shoebox email" |
| `box` | The Shoebox list: Coming up, then everything else |
| `clear` | The day's end: "That's all for today" |
| `settings` | Settings |

Each comes in `light-` and `dark-`.
