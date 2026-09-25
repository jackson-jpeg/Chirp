# Sky classic retheme: handoff

**Branch:** `claude/eager-einstein-bttn4d`
**Source design:** the ChirpChirps Icon canvas in Claude Design, board **G · Sky classic**
(https://claude.ai/artifact/DC1iUgCWZ3676ySxeTadJ2)

The app, its icon, and chirpchirps.com moved from dark-only slate + amber to
the Sky classic look, with a **Day** mode (the bright sky) and a **Night**
mode (navy dusk). The app follows the iPhone's setting by default, and
Settings has a new Appearance control: System / Day / Night.

This was done in a cloud session **with no Xcode**. Every Swift file parses
under Swift 6.3.1 (`swift-frontend -parse`), and every `Constants.Colors.*`
reference resolves. **Nothing has been type-checked or run.** Your job on
the Mac is to build it, fix anything the compiler finds, and look at every
screen in both modes.

---

## 1. Build first

```sh
cd ~/Chirp            # or: ssh to the VPS, cd /root/Chirp, and use `ios build`
ios build             # xcodegen picks up the new files automatically
```

These new APIs and files are the most likely places for a compiler complaint:

| Where | What to check |
|---|---|
| `Models/Constants.swift`: `Color(day:night:dayOpacity:nightOpacity:)` | Wraps `UIColor { traits in … }` (the dynamic provider) in `Color(uiColor:)`. The closure only captures `UInt`/`Double`, so it should satisfy Swift 6 `@Sendable`. |
| `Models/Constants.swift`: `private extension UIColor { init(hex:alpha:) }` | A file-private helper. It would clash if another `UIColor(hex:alpha:)` is ever added. |
| `Models/AppAppearance.swift` (new) | A `String` enum stored with `@AppStorage` in `ChirpApp` and `SettingsView`. |
| `Views/Components/SkyBackdrop.swift` (new) | Canvas-drawn clouds and stars; uses static tuple arrays. |
| `Views/Components/PerchBirdsView.swift` | Rewritten to draw the icon's bird paths through a `CGAffineTransform`. |
| `PTTButtonView.iconColor`, `ToastType.iconColor` | New computed properties that compare `== .idle` and `== .warning`. |

## 2. Then look at every screen, in both modes

Set the mode in **Settings → Appearance**. Screens to walk, with the spots
flagged during the sweep:

- **Onboarding.** Sky backdrop plus the mesh glows (sky tones by day, the
  original indigo by night). Check the glows don't wash out the clouds by day.
- **Home / Talk.** The PTT button face is now a white disc by day and the
  idle mic uses `amberInk`. Also check the signal ring (a 2 pt `amberInk`
  stroke) and the ambient mesh lines and dots, which are now dark orange by
  day. If that looks heavy, revert them to `amber`.
- **Map tab.** The map stays on its **dark** style in both modes (see §4).
  The panels over it (`slate900.opacity(0.9)`) turn pale by day. Check them
  against the dark map.
- **Channel view.** The drifting mesh blobs are now sky, sun and leaf tints
  by day. There's also a vignette (`backgroundDeep.opacity(0.5)`) and a LIVE
  badge that now uses `.white` on red.
- **Chat.** Own bubbles vs. others, the reply-quote chip (`surfaceHover`),
  the reaction chips (`surfaceGlass`, white by day), and the location and
  image attachment chips.
- **Friends / Add Friend / Channel Creation.** Avatar rings are now
  `amberInk`, and the FriendsView online-dot cutout ring is now
  `backgroundPrimary` (it may not match the material card exactly).
- **Voice messages, Settings, Diagnostics, Location consent, Offline map
  download.** All now sit on `SkyBackdrop`; their forced
  `.toolbarColorScheme(.dark)` modifiers were removed.
- **Photo viewer.** Pinned to dark with `.environment(\.colorScheme, .dark)`.
- **Debug overlay.** Now an adaptive panel. Check it over the dark map.
- **Toasts.** The warning triangle uses `amberInk`.
- **Demo mode banner.** Text on the amber banner is `onAmber` (navy).
- **Home screen icon.** Light and Dark home screens show different icons (§3).

## 3. What changed

### Icon
- `icon.svg` is now Sky classic, full-bleed square (iOS applies the mask).
- `icon-night.svg` (new) is the same scene after dark (navy sky, dim clouds,
  stars, a pale wire), shipped as the **dark-appearance** app icon.
- `scripts/brand/render-icons.mjs` renders both into
  `AppIcon.appiconset/icon_1024.png` and `icon_1024_dark.png` (RGB, no
  alpha), plus the website favicons, apple-touch icon, and `img/icon-512.png`.
  **The SVGs are the source; re-run the script, never hand-edit a PNG.**

### Palette (`Constants.Colors`)
Every token is now adaptive. The old names are kept as **roles** so the ~600
call sites didn't have to move. The table is in the doc comment on
`enum Colors`. New tokens:

- `amberInk`: amber for text, icons and thin strokes (#A85800 by day, which passes AA).
- `onAmber`: navy, for text on an amber fill.
- `ink`: navy by day, white by night. It replaces `Color.white.opacity(x)` hairlines.
- Brand constants: `sky`, `skyLight`, `cloud`, `navy`, `sun`, `wing`, `beak`.

Every text pairing was contrast-checked (WCAG AA) in both modes. The
`LaunchBackground` and `AccentColor` colorsets now have light and dark variants.

### Views
Five agents swept all ~14k lines of `Views/`: literal `.white`/`.black` on
the page → tokens, amber-as-text → `amberInk`, root page backgrounds →
`SkyBackdrop()`. The literal `.white` references left (35) all sit on
saturated fills, photos, the map, or scrims. `PerchBirdsView` now draws the
icon's birds, with the chirp pulsing along the wire.

### Website (`website/`, new in this repo)
chirpchirps.com had no source in git; it was served straight off the VPS.
`website/` is a copy of the live site, rethemed:
- `brand.css` is token-driven, with day as the default and night under
  `prefers-color-scheme: dark`.
- The hero has clouds and the icon's birds perched on a full-width wire. By
  day "Still works." becomes a sunny highlighter stroke, because yellow text
  on sky can't be read.
- `mesh.js` reads its colors from CSS and re-reads them when the scheme flips.
- New favicons, apple-touch icon, a nav icon mark, and a new `img/og.png`
  (`scripts/brand/render-og.mjs`).
- Cache-busted: `brand.css?v=5`, `mesh.js?v=3`.

### App Store art
`appstore_compose.py` is repaletted to the sky (navy headlines, sun needle,
white glow). It was test-rendered against the current raw captures and works.

## 4. Follow-ups (not done)

1. **Deploy the website.** Find the webroot on the VPS
   (`grep -rn chirpchirps /etc/nginx/`), back it up, then
   `rsync -av website/ <webroot>/`. The old site's files are a subset of
   `website/`, so nothing is removed. Social previews cache `og.png`; use a
   debugger (e.g. the Facebook sharing debugger) to refresh them.
2. **Recapture the App Store screenshots in Day mode** (`screenshots/raw/`),
   then run `python3 appstore_compose.py` and upload. The current raw
   captures show the old dark UI.
3. **The website's screenshot images** (`website/img/talk.webp`,
   `messages.webp`, `map.webp`) also show the old dark UI. Replace them from
   the new captures.
4. **Light map style.** The map stays on OpenFreeMap `dark` because offline
   packs cache that exact style's JSON, sprites and glyphs. A light style by
   day would need packs downloaded for both styles, plus a migration for
   existing packs. That's worth doing, but not blind.
5. **Optional: Icon Composer.** iOS 26 can take a layered `.icon` file for
   Liquid Glass, tinted, and clear variants. The asset-catalog light/dark
   pair works today.
6. `ChannelTheme.squad` is still `0xFFB800`. It's persisted in saved
   channels, so it was left alone.
