"""Composes the iPhone and iPad App Store screenshots from raw simulator captures.

    python3 compose.py <captures folder> <output folder>

The captures are full-screen PNGs named as in SHOTS, taken at the size App Store Connect
wants for one display (1206x2622 on an iPhone 17 Pro, 2064x2752 on a 13-inch iPad Pro).
A capture as wide as an iPad's gets the iPad's proportions and captions.
Each comes out at that same size: a caption on the app icon's navy, over the capture with
its screen corners, flattened to RGB because App Store Connect rejects an alpha channel.

The captures are the real app, unedited. Only the caption is added, and every shot that
shows a Pro feature says so in it (Guideline 2.3.2). No shot shows a price (2.3.7).
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFont

ROUNDED = '/System/Library/Fonts/SFNSRounded.ttf'
NAVY = ((0x18, 0x29, 0x4F), (0x0B, 0x16, 0x31))     # Design/AppIcon/th.py
BLUE = (0x27, 0xBF, 0xFF)                            # Theme.work
WHITE = (0xFF, 0xFF, 0xFF)

# (capture name, eyebrow, headline lines, eyebrow drawn as a capsule)
SHOTS = [
    ('1-run', 'TRAIN ON IPHONE', ['Press Start.', 'Hear every interval.'], False),
    ('2-lock', 'LOCK SCREEN', ['Your countdown,', 'phone locked'], False),
    ('3-workouts', 'WORKOUTS', ['Every workout,', 'one tap from Start'], False),
    ('4-editor', 'EDITOR', ['Build it here.', 'Start it anywhere.'], False),
    ('5-history', 'HISTORY', ['Every session,', 'interval by interval'], False),
    ('6-session', 'SESSION', ['Your calories,', 'every interval'], False),
    ('7-pro-editor', 'INTERVALLY PRO', ['Add a warmup', 'and a cooldown'], True),
    ('8-pastel', 'INTERVALLY PRO', ['Make it yours', 'with Pastel'], True),
]

# On iPad, where a run has no watch to start it on: the same shots, worded for it.
IPAD_CAPTIONS = {
    '1-run': ('TRAIN ON IPAD', ['Press Start.', 'Hear every interval.']),
    '4-editor': ('EDITOR', ['Build a workout', 'in seconds']),
}


class Layout:
    """Fractions of the canvas width, so every display of one kind shares one layout."""

    def __init__(self, top, eyebrow, headline, line_gap, headline_gap, screen_top, bottom, corner):
        self.top = top                  # the eyebrow's cap height starts here
        self.eyebrow = eyebrow
        self.headline = headline
        self.line_gap = line_gap
        self.headline_gap = headline_gap  # from the eyebrow's baseline to the headline's top
        self.screen_top = screen_top    # below the caption
        self.bottom = bottom            # margin under the screen
        self.corner = corner            # the display's corner radius, as a fraction of its width


IPHONE = Layout(0.095, 0.034, 0.080, 0.012, 0.045, 0.395, 0.066, 0.105)
# A 3:4 canvas: the screen takes more of it, and the words less of its width.
IPAD = Layout(0.062, 0.022, 0.052, 0.008, 0.028, 0.262, 0.05, 0.035)


def layout_for(size):
    width, height = size
    return IPAD if width / height > 0.6 else IPHONE


def font(size, weight):
    face = ImageFont.truetype(ROUNDED, size)
    face.set_variation_by_name(weight)
    return face


def gradient(width, height):
    top, bottom = NAVY
    column = Image.new('RGB', (1, height))
    for y in range(height):
        t = y / (height - 1)
        column.putpixel((0, y), tuple(round(a + (b - a) * t) for a, b in zip(top, bottom)))
    return column.resize((width, height))


def rounded_mask(size, radius, scale=4):
    """An anti-aliased rounded rectangle, drawn large and scaled down."""
    big = Image.new('L', (size[0] * scale, size[1] * scale), 0)
    ImageDraw.Draw(big).rounded_rectangle((0, 0, big.width - 1, big.height - 1), radius * scale, fill=255)
    return big.resize(size, Image.LANCZOS)


def tracked_width(draw, text, face, tracking):
    return sum(draw.textlength(ch, font=face) for ch in text) + tracking * (len(text) - 1)


def draw_tracked(draw, baseline, text, face, fill, width, tracking):
    """One line of letter-spaced capitals, centred, sitting on `baseline`."""
    x = (width - tracked_width(draw, text, face, tracking)) / 2
    for ch in text:
        draw.text((x, baseline), ch, font=face, fill=fill, anchor='ls')
        x += draw.textlength(ch, font=face) + tracking


def compose(capture, eyebrow, lines, capsule):
    width, height = capture.size
    lay = layout_for(capture.size)
    canvas = gradient(width, height)
    draw = ImageDraw.Draw(canvas)

    eyebrow_face = font(round(width * lay.eyebrow), 'Bold')
    tracking = round(width * lay.eyebrow * 0.12)
    cap_height = eyebrow_face.getbbox('H', anchor='ls')
    cap_height = cap_height[3] - cap_height[1]
    baseline = round(width * lay.top) + cap_height
    if capsule:
        # The Pro shot's marker: the brand blue capsule with dark text, drawn as the app
        # draws its one tinted control.
        pad_x, pad_y = width * lay.eyebrow * 1.03, width * lay.eyebrow * 0.65
        half = tracked_width(draw, eyebrow, eyebrow_face, tracking) / 2 + pad_x
        top, bottom = baseline - cap_height - pad_y, baseline + pad_y
        draw.rounded_rectangle((width / 2 - half, top, width / 2 + half, bottom), (bottom - top) / 2, fill=BLUE)
        draw_tracked(draw, baseline, eyebrow, eyebrow_face, (0, 0, 0), width, tracking)
    else:
        draw_tracked(draw, baseline, eyebrow, eyebrow_face, BLUE, width, tracking)

    headline_face = font(round(width * lay.headline), 'Bold')
    line_height = headline_face.size + round(width * lay.line_gap)
    baseline += round(width * lay.headline_gap) + headline_face.size
    for line in lines:
        draw.text((width / 2, baseline), line, font=headline_face, fill=WHITE, anchor='ms')
        baseline += line_height

    top = round(width * lay.screen_top)
    screen_h = height - top - round(width * lay.bottom)
    screen_w = round(screen_h * width / height)
    screen = capture.convert('RGB').resize((screen_w, screen_h), Image.LANCZOS)
    radius = round(screen_w * lay.corner)
    x = (width - screen_w) // 2

    # A hairline keyline, so the black screen's edge holds against the navy.
    edge = 3
    rim = Image.new('RGB', (screen_w + 2 * edge, screen_h + 2 * edge), (0x3A, 0x48, 0x6B))
    canvas.paste(rim, (x - edge, top - edge), rounded_mask(rim.size, radius + edge))
    canvas.paste(screen, (x, top), rounded_mask(screen.size, radius))
    return canvas.convert('RGB')


def main(source, destination):
    os.makedirs(destination, exist_ok=True)
    for name, eyebrow, lines, capsule in SHOTS:
        capture = Image.open(os.path.join(source, f'{name}.png'))
        if layout_for(capture.size) is IPAD and name in IPAD_CAPTIONS:
            eyebrow, lines = IPAD_CAPTIONS[name]
        out = compose(capture, eyebrow, lines, capsule)
        assert out.size == capture.size and out.mode == 'RGB'
        out.save(os.path.join(destination, f'{name}.png'), optimize=True)
        print(name, out.size)


if __name__ == '__main__':
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2])
