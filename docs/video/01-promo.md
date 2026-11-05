# Video 1: the promo (and 2: the home page loop)

Follow `docs/video/style.md` for everything not said here.

**Job:** explain the whole app to a stranger in a minute, and make the newsletter land: forward one school newsletter, get just your family's dates, each as its own post that comes back before the day. **Where:** LinkedIn, and linked from the home page. **Call to action:** Join the beta.

**Second edition.** This replaces the cut of November 4, 2026. Two things changed: shot 5 (the newsletter) is new and is the longest shot in the video, and the tagline is now spoken with its pause (style.md, Sound). Both cuts are re-rendered. The loop keeps its shots and need not change unless its screenshots did.

## The 60-second cut, 16:9

| # | Time | Picture | Voice | Caption | How |
|---|---|---|---|---|---|
| 1 | 0:00 to 0:04 | Abstract cards (a link, a flyer, an email) pile up and slide off a phone outline. | You saved it. Then it was gone. | You saved it. Then it was gone. | Cards in Bone and lighter Plum on Plum. Gentle drift, not chaos. |
| 2 | 0:04 to 0:08 | `light-welcome`: the logo and "Keep it. It comes back to you." | Shoebox. Keep it. *(0.5 s)* It comes back to you. | (none: the line is on screen) | Mask the logo tile in, then the words. Box tap as the logo settles. The pause is rendered as two clips (style.md). |
| 3 | 0:08 to 0:15 | `light-share`: Tap Share, Tap Shoebox, Say why. | Keep anything, from any app. Say why in a few words. | Keep it from anywhere. | Spotlight the three steps one at a time. |
| 4 | 0:15 to 0:23 | `light-today`: the Fall band concert post, its date line and the reason "Bring the good camera". Then a small timeline: 5 days before, 1 day before, the day, then Kept. | Shoebox reads the day it's about, and brings it back before then. | It reads the day it's about. | Spotlight the date line, then the reason. Timeline builds left to right in Sunflower dots. |
| 5 | 0:23 to 0:36 | A plain envelope shape slides in (a newsletter: a few abstract lines of Bone text with six short Sunflower marks where the dates are). It becomes `light-dates`: one date post on Today, "from Maple Grove newsletter" in the byline, the day and time on its first line. Then `light-box`, Coming up, the six dates soonest first. | Forward the school newsletter. Shoebox finds the dates that are about your family, and makes each one its own post. They come back before the day. | One newsletter. Just your dates. | The longest shot. Envelope 3 s, the post 5 s (spotlight the byline, then the first line), Coming up 5 s with the six rows revealed top to bottom. Small line under the caption for the whole shot: "Shoebox Plus. Sealed so only your phone can read it." |
| 6 | 0:36 to 0:46 | `light-up`, `light-away`, `light-opened`, one after another with the thumb dot. | Flick up for the next one. Pull down when you're done. Tap to open. | Up. Down. Tap. | Thumb dot up and the post lifts out; dot down and the post drops into the box with the box tap; a press on the dot with a 4% push-in. One caption for the three. |
| 7 | 0:46 to 0:51 | `light-box`, then `dark-box` | Everything you're not done with, in one calm place. | Everything you're not done with. | Cross-dissolve light to dark, push out 4%. |
| 8 | 0:51 to 0:57 | `dark-today` | It reads on your phone, with Apple Intelligence. Your mail is sealed, so only your phone can open it. No account. No ads. | On your phone. Sealed mail. No account. | A slow 2% push. The words are the fixed privacy line (style.md rule 6). If the voice has to rush, drop "No account. No ads." from the voice and keep it in the caption. |
| 9 | 0:57 to 1:00 | End card | Shoebox for iPhone. Join the beta. | Join the beta. | Hold 3 seconds. |

## The 30-second cut, 9:16

Shots 2, 4, 5, 6 and 9, with their voice lines, re-timed to fit. Shot 5 keeps at least 10 seconds. Captions larger: they must read in a phone feed.

## Video 2: the home page loop

16:9, 12 to 15 seconds, silent, no captions. Shots 4, 5 (the post and Coming up only, no envelope), 6 and 7, looping cleanly from the last frame to the first. No end card. Deliver `shoebox-loop.mp4` (at most 4 MB) and `shoebox-loop.webm` (VP9, at most 3 MB), and a poster from shot 4.

## Files

`shoebox-promo-60.mp4` (at most 15 MB), `shoebox-promo-30-vertical.mp4` (at most 10 MB), `shoebox-loop.mp4`, `shoebox-loop.webm`, `shoebox-promo.jpg`, `shoebox-promo-60.vtt`, `shoebox-promo-30-vertical.vtt`, `music-license.txt`, and `docs/video/voice.txt` (the voice settings and the line timings, updated for this edition).

## On the home page

Only after Graham's yes on the final cuts. The files replace the ones already in `site/` of `grahamdeno/edition`, same names, so the page needs no change. Under the hero text the page already has:

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
