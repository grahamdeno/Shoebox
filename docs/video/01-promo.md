# Video 1: the promo (and 2: the home page loop)

Follow `docs/video/style.md` for everything not said here.

**Job:** explain the whole app to a stranger in a minute. **Where:** LinkedIn, and linked from the home page. **Call to action:** Join the beta.

## The 60-second cut, 16:9

| # | Time | Picture | Voice | Caption | How |
|---|---|---|---|---|---|
| 1 | 0:00 to 0:04 | Abstract cards (a link, a flyer, an email) pile up and slide off a phone outline. | You saved it. Then it was gone. | You saved it. Then it was gone. | Cards in Bone and lighter Plum on Plum. Gentle drift, not chaos. |
| 2 | 0:04 to 0:08 | `light-welcome`: the logo and "Keep it. It comes back to you." | Shoebox. Keep it, and it comes back to you. | (none: the line is on screen) | Mask the logo tile in, then the words. Box tap as the logo settles. |
| 3 | 0:08 to 0:15 | `light-share`: Tap Share, Tap Shoebox, Say why. | Keep anything, from any app. Say why in a few words. | Keep it from anywhere. | Spotlight the three steps one at a time. |
| 4 | 0:15 to 0:20 | `light-add`: Keep something. | Or keep it right here. | Or keep it here. | Mask wipe from shot 3. Spotlight the writing panel. |
| 5 | 0:20 to 0:28 | `light-today`: the Fall band concert post, full screen, its date line and the reason "Bring the good camera". Then a small timeline: 5 days before, 1 day before, the day, then Kept. | Shoebox reads the day it's about, and brings it back before that day. | It reads the day it's about. | Spotlight the date line, then the reason. Timeline builds left to right in Sunflower dots. |
| 6 | 0:28 to 0:33 | `light-up` | Flick up for the next one. | Flick up: next. | Thumb dot up, the post lifts out. |
| 7 | 0:33 to 0:38 | `light-away` | Pull down when you're done. | Pull down: put it away. | Thumb dot down, the post drops into the box, box tap. |
| 8 | 0:38 to 0:42 | `light-opened` | Tap to open it. | Tap: open it. | A press on the dot, 4% push-in. |
| 9 | 0:42 to 0:48 | A plain envelope shape slides in and becomes `light-opened`, showing "via your Shoebox email". | Forward an email, and keep just what matters. | Forward an email. Keep what matters. | Spotlight "via your Shoebox email". Small line: "Shoebox Plus. Sealed so only your phone can read it." |
| 10 | 0:48 to 0:53 | `light-box`, then `dark-box` | Everything you're not done with, in one calm place. | Everything you're not done with. | Cross-dissolve light to dark, push out 4%. |
| 11 | 0:53 to 0:57 | `dark-today` | On your phone. No account. No ads. | On your phone. No account. No ads. | A slow 2% push. |
| 12 | 0:57 to 1:00 | End card | Shoebox for iPhone. Join the beta. | Join the beta. | Hold 3 seconds. |

## The 30-second cut, 9:16

Shots 2, 5, 6, 7, 9 and 12, with their voice lines, re-timed to fit. Captions larger: they must read in a phone feed.

## Video 2: the home page loop

16:9, 12 to 15 seconds, silent, no captions. Shots 5, 6, 7, 8 and 10 only, looping cleanly from the last frame to the first. No end card. Deliver `shoebox-loop.mp4` (at most 4 MB) and `shoebox-loop.webm` (VP9, at most 3 MB), and a poster from shot 5.

## Files

`shoebox-promo-60.mp4` (at most 15 MB), `shoebox-promo-30-vertical.mp4` (at most 10 MB), `shoebox-loop.mp4`, `shoebox-loop.webm`, `shoebox-promo.jpg`, `shoebox-promo-60.vtt`, `shoebox-promo-30-vertical.vtt`, `music-license.txt`, and `docs/video/voice.txt` (the voice settings, once approved).

## On the home page

Only after Graham's yes on the final cuts. Files go in `site/` of `grahamdeno/edition`. Under the hero text:

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
