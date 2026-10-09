# App icon

**Shipping: the dumbbell ("split ring", option 9 of round 3), `AppIcon-dumbbell.png`.** A
white dumbbell on the diagonal across two arcs, rest green flowing into work blue, on deep
navy. Josiah's story poll (2026-10-09) leaned toward it over the stopwatch below. It is
used exactly as rendered in round 3, which has no script here; the PNG is the source. To
switch back, copy `AppIcon-stopwatch.png` over both `AppIcon.png` files named below.

**Pastel's alternate icon (iPhone only), `AppIcon-pastel.png`:** the same dumbbell and split
ring, white on a blush gradient, the arcs in pink and mint. Those were Pastel's first work and
rest colours; the theme has since moved rest to a sky blue, but the icon keeps mint, which
holds up on blush where sky blue washes out at home-screen size. The iPhone
switches to it while the theme is Pastel (`AppIconFollower`); watchOS has no alternate icons,
so the watch keeps the dumbbell. Regenerate it with `python3 dumbbell/render_pastel.py dumbbell
<outdir>` from this folder: of the three it writes, `b3-deeper-blush-white.png` is the icon
(byte-identical to `AppIcon-pastel.png`); copy it to
`Phone/Resources/Assets.xcassets/AppIcon-Pastel.appiconset/AppIcon-Pastel.png`.
`ShipAssetsTests` holds that copy to this one, 1024 square with no alpha.

The alternative, kept and regenerable: "Stopwatch with crown": two arcs — rest green flowing into work blue, a repeating round —
with round caps like the app's own run ring, a slim white stopwatch hand on the diagonal
and a crown at twelve, on deep navy. It says "interval timer" without naming a sport, so it
reads as Intervally's for yoga, running and HIIT alike.

- `render.py` + `th.py` + `lib.py` regenerate it with `python3 render.py` (writes into the
  current directory); copy `stopwatch-crown.png` to both
  `Sources/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png` (watch) and
  `Phone/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png` (iPhone). The two must
  stay byte-identical (Guideline 2.3.8); `ShipAssetsTests` checks.
- 1024×1024, RGB, no alpha — the watchOS and iOS asset slots and the App Store marketing
  icon. iOS masks it to its rounded square; the mark stays inside a 410-pixel radius.
- History: a square-wave mark (read as the letter M), a kettlebell timer (read as a
  padlock at wrist size), and a dumbbell version of this same composition (dropped
  because a weight signals strength training only, while broad interval timers almost
  all use a timer symbol).
