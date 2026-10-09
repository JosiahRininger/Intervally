# App icon

"Stopwatch with crown": two arcs — rest green flowing into work blue, a repeating round —
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
