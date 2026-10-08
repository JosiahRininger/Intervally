"""Intervally icon: a stopwatch whose dial is the app's interval ring.

Two arcs — rest green flowing into work blue, one repeating round — with round caps like the
app's own run ring, a slim white stopwatch hand on a 40-degree diagonal with a navy pivot pin,
and a crown at twelve, on a navy gradient. Geometry is in 1024 units; lib draws at 4096 and
downsamples. Outputs 1024x1024 RGB PNGs (no alpha) + 300/60/44/24 strips.

History: v1 used a heavier hand (blade 136 -> 96 wide) and navy disc "bites" at the split
points carried over from the dumbbell version; with a lighter hand those bites read as
chunks missing, so the arcs now end in round caps with clean gaps.
"""
import th
from th import *

HAND = dict(hub_r=96, w_base=84, w_tip=52, tip_u=394, tail_u=-170, tail_w=54)
PIN_R = 31
HALO_W = 20                      # navy keyline around the hand
GAP_DEG = 16.5                   # arc end angle back from each split point (cap radius ~11.4 deg)
CROWN = dict(gap=24, stem=(48, 30), cap=(128, 52), cap_r=20)


def stopwatch_crown(path):
    th.HALO = HALO_W
    cy = C + 34                                    # crown adds top weight; drop the mark so it sits centred
    hand = clock_hand_at(cy, **HAND)
    img = canvas_gradient(*NAVY)
    paint(img, arc_mask(C, cy, RING_R, RING_W, A_TR + GAP_DEG, A_TR + 180 - GAP_DEG, round_caps=True), BLUE)
    paint(img, arc_mask(C, cy, RING_R, RING_W, A_TR + 180 + GAP_DEG, A_TR + 360 - GAP_DEG, round_caps=True), GREEN)
    bg = canvas_gradient(*NAVY)
    img = Image.composite(bg, img, subtract(dilate(hand, HALO_W), hand))
    paint(img, hand, WHITE)
    img = Image.composite(bg, img, disc_mask(C, cy, PIN_R))
    paint(img, crown_mask(cy, **CROWN), WHITE)
    finish(img, path)


def extent(path):
    """Max distance from centre of any pixel that differs from the plain background (mark extent)."""
    im = Image.open(path).convert('RGB')
    bg = canvas_gradient(*NAVY).convert('RGB').resize((1024, 1024), Image.LANCZOS)
    diff = ImageChops.difference(im, bg).convert('L').point(lambda v: 255 if v > 24 else 0)
    px = diff.load()
    best = 0
    for y in range(0, 1024, 2):
        for x in range(0, 1024, 2):
            if px[x, y]:
                best = max(best, math.hypot(x - 511.5, y - 511.5))
    return best


if __name__ == '__main__':
    for fn, name in ((stopwatch_crown, 'stopwatch-crown'),):
        fn(f'{name}.png')
        strip(f'{name}.png', f'{name}-strip.png')
        print(verify(f'{name}.png'), '| mark extent radius', round(extent(f'{name}.png')), '(limit 410)')
