"""Blush with a white dumbbell: plain, with a soft shadow, and on a deeper blush."""
import sys
sys.path.insert(0, sys.argv[1])
from lib import *
from PIL import ImageFilter, ImageChops

PINK, MINT = '#FF6FAE', '#7FDDB8'

def icon(path, bg, bell='#FFFFFF', shadow=None):
    img = canvas_gradient(*bg); bgimg = canvas_gradient(*bg)
    a = 90 - 40
    paint(img, arc_mask(C, C, 262, 104, a, a + 180, round_caps=False), PINK)
    paint(img, arc_mask(C, C, 262, 104, a + 180, a + 360, round_caps=False), MINT)
    dm, _ = dumbbell_mask(C, C, 40, grip=420, bar=86, plates=((104, 340), (62, 230)), cap=None, r=30)
    img = Image.composite(bgimg, img, subtract(dilate(dm, 26), dm))
    if shadow:
        # A soft drop shadow in a deeper rose, so white reads on a light ground.
        sm = dm.filter(ImageFilter.GaussianBlur(18))
        sm = ImageChops.offset(sm, 0, 14).point(lambda v: int(v * shadow[1]))
        tint = Image.new('RGB', img.size, shadow[0])
        img = Image.composite(tint, img, sm)
    paint(img, dm, bell)
    finish(img, path)

out = sys.argv[2]
icon(f'{out}/b1-blush-white.png', ('#FFE6F0', '#FFC9DE'))
icon(f'{out}/b2-blush-white-shadow.png', ('#FFE6F0', '#FFC9DE'), shadow=('#D9467F', 0.45))
icon(f'{out}/b3-deeper-blush-white.png', ('#FFC2DA', '#FF9DC4'), shadow=('#C73574', 0.35))
print('ok')
