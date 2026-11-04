# Shoebox promo video: director's sheet

**For:** Grok, building the promo video. **Approver:** Graham. **Written:** November 4, 2026.
**Source of truth for what the app does:** `docs/SPEC.md`. Show only what is built. If this sheet and SPEC disagree, SPEC wins.

## Read these first (rules that can't bend)

1. **Real screens only, sample data only.** Every app screen in the video comes from the screenshots CI makes with sample data (branch `ci-screens` of `grahamdeno/Shoebox`, files `light-<screen>.png` and `dark-<screen>.png`). Never use a recording or screenshot of Graham's own phone: it holds his family's school mail and names.
2. **Show only what exists.** No Android, Apple Watch, widgets, Lock Screen, Siri or Mac. No prices. Shoebox Plus is named only on the email beat.
3. **No other company's interface.** The "messy phone" opening uses abstract shapes, not real screenshots of Safari, Messages, Mail or anyone's app. No Apple logos or App Store badge until the app is live in the store.
4. **Approval before render.** Send Graham one still per beat (the storyboard) and wait for his yes before rendering. Then send the cuts for his yes before anything goes on the website.

## Who it's for

Busy adults who save things to come back to and rarely do: a parent with school emails and permission slips, a professional with links and screenshots, anyone with 40 open tabs. Most viewers arrive from Graham's LinkedIn or a friend's link, on a phone, with the sound off.

**What they should feel:** relief. "Oh, that's where those things should go." Calm, warm, tidy. Not a productivity hustle.

**The one line they should remember:** *Keep it. It comes back to you.*

## Look and sound

| | |
|---|---|
| Colors | Pistachio `#F6F3E8` (light ground), Plum `#3B2240` (dark ground), Plum Ink `#2A1E2E` (text on light), Bone `#F1E9D8` (text on dark), Sunflower `#F9C93A` (the lid, highlights), lip `#D4A21E`, shade `#1A1020` (shadows, never black). Lighter Plum `#6A4F73` for the box in dark scenes. No pure black, no peach, no gradients outside these. |
| Type | SF Pro Display, semibold for captions; Inter if SF Pro is not available. Captions sentence case, short, at most 7 words. |
| Device | A plain rounded phone outline in the shade color, no brand marks, slightly tilted (max 4°) only in the logo beat. Most shots are the screen alone, full bleed, rounded corners. |
| Motion | Slow and calm. Push-ins of 3 to 6%, 700 to 900 ms, ease in-out. Cross-dissolves of 300 ms or a rounded-card mask wipe. No whip pans, no spins, no 3D flips, no bouncing. |
| Gestures | Show each move with a soft thumb dot (Bone at 85%, 26 pt) like the app's own How Shoebox works pictures: up for Next, down into the box for Put away, a press for Open. |
| Focus | To point at a feature, dim the rest of the screen with the shade color at 40% and leave a rounded spotlight on the part that matters. One spotlight at a time. |
| Sound | Optional bed: warm, sparse piano or acoustic guitar, 90 to 100 BPM, royalty-free with a license Graham can keep. A soft wooden "box" tap when a post drops in. No voiceover in the website version. The video must make sense muted: captions carry it. |

## The shots, in order (60-second main cut, 16:9)

| # | Time | Picture | Caption | How |
|---|---|---|---|---|
| 1 | 0:00 to 0:04 | Abstract cards (links, a flyer, an email) pile up and slide off a phone outline. | You saved it. Then it was gone. | Cards in Bone and lighter Plum on Plum. Gentle drift, not chaos. |
| 2 | 0:04 to 0:08 | The Shoebox logo: the Sunflower lid settles onto the box. | Keep it. It comes back to you. | Lid drops 12 pt with a soft settle. The box tap sound lands here. |
| 3 | 0:08 to 0:15 | `light-share`: the share sheet keeping a link, with the reason line. | Keep it from anywhere. | Push in on the reason field, then spotlight it. |
| 4 | 0:15 to 0:20 | `light-add`: Keep something with a photo or note. | Say why in a few words. | Mask wipe from shot 3. |
| 5 | 0:20 to 0:28 | `light-today`: a dated post ("Saturday, Nov 14 · 5:00 PM"). Then a small timeline: 5 days before, 1 day before, the day, then Kept. | It reads the day it's about. | Spotlight the date line. Timeline builds left to right in Sunflower dots. |
| 6 | 0:28 to 0:33 | `light-up`: flick up for the next one. | Flick up: next. | Thumb dot moves up, post lifts out. |
| 7 | 0:33 to 0:38 | `light-away`: pull down, the lid opens, the post drops into the box. | Pull down: put it away. | Thumb dot down, post shrinks into the box, box tap sound. |
| 8 | 0:38 to 0:42 | `light-opened`: the opened post. | Tap: open it. | Press on the dot, gentle 4% push-in. |
| 9 | 0:42 to 0:48 | Email beat: a plain envelope shape becomes a short post (`light-today` or `light-opened` with an email post). | Forward an email. Keep what matters. | Small line under the caption: "Shoebox Plus. Sealed so only your phone can read it." |
| 10 | 0:48 to 0:53 | `light-box`, then `dark-box`: the Shoebox list, Coming up first. | Everything you're not done with. | Cross-dissolve light to dark, push out 4%. |
| 11 | 0:53 to 0:57 | `dark-settings` (or `dark-today`): the dark look. | On your phone. No account. No ads. | Hold, no motion but a slow 2% push. |
| 12 | 0:57 to 1:00 | End card: logo, "Shoebox for iPhone", `inmyshoebox.com`. | Join the beta. | Pistachio ground. Hold 3 seconds. |

## The other cuts

- **30 seconds, 9:16 (1080×1920), for LinkedIn and phones:** shots 2, 3, 5, 6, 7, 9, 12. Same captions, larger (they must read on a phone in a feed).
- **Homepage loop, 16:9, 12 to 15 seconds, silent:** shots 5, 6, 7, 8, 10 only, looping cleanly from the last frame to the first. No end card.

## Files to deliver

| File | Spec |
|---|---|
| `shoebox-promo-60.mp4` | 1920×1080, 30 fps, H.264, AAC, at most 15 MB |
| `shoebox-promo-30-vertical.mp4` | 1080×1920, 30 fps, H.264, AAC, at most 10 MB |
| `shoebox-loop.mp4` | 1920×1080, 30 fps, H.264, no audio track, at most 4 MB |
| `shoebox-loop.webm` | the same loop in VP9, at most 3 MB |
| `shoebox-promo.jpg` | poster frame from shot 5, 1920×1080, at most 200 KB |
| `shoebox-promo-60.vtt` | captions for the 60-second cut |
| `music-license.txt` | where the music came from and its license |

## On the homepage

Only after Graham's yes on the final cuts. Files go in `site/` of `grahamdeno/edition` (the website). Under the hero text on the home page:

```html
<figure class="promo">
  <video class="promo-loop" autoplay muted loop playsinline preload="metadata" poster="site/shoebox-promo.jpg"
         aria-label="Shoebox in use: a dated post, flicking up for the next, pulling one down into the box, opening one">
    <source src="site/shoebox-loop.webm" type="video/webm">
    <source src="site/shoebox-loop.mp4" type="video/mp4">
  </video>
  <figcaption><a href="site/shoebox-promo-60.mp4">Watch the one-minute video</a></figcaption>
</figure>
<style>
  .promo { margin: 32px auto 0; max-width: 960px; }
  .promo-loop { width: 100%; height: auto; border-radius: 20px; display: block; background: #3B2240; }
  @media (prefers-reduced-motion: reduce) { .promo-loop { display: none; } }
</style>
```

With Reduce Motion on, the loop is hidden and the link to the full video stays.
