"""Shared drawing helpers for the dumbbell icon options.

All geometry is expressed in 1024-space units and drawn at 4096 (K=4),
then LANCZOS-downsampled to 1024.
"""
import math
from PIL import Image, ImageDraw, ImageChops, ImageFilter

S = 4096
K = S / 1024.0
C = 512.0  # centre in 1024 space


def hexc(h, a=255):
    h = h.lstrip('#')
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), a)


def canvas_gradient(c1, c2, angle_deg=135, radial=None):
    """Linear gradient background (RGB). angle 135 = top-left -> bottom-right."""
    c1 = hexc(c1)[:3]
    c2 = hexc(c2)[:3]
    small = 256
    img = Image.new('RGB', (small, small))
    px = img.load()
    a = math.radians(angle_deg)
    dx, dy = math.cos(a - math.pi / 2) * -1, math.sin(a - math.pi / 2) * -1
    # project onto diagonal
    for y in range(small):
        for x in range(small):
            u = (x / (small - 1) - 0.5)
            v = (y / (small - 1) - 0.5)
            t = (u + v) / 2 + 0.5 if angle_deg == 135 else (v + 0.5)
            t = max(0, min(1, t))
            px[x, y] = tuple(int(c1[i] + (c2[i] - c1[i]) * t) for i in range(3))
    img = img.resize((S, S), Image.BICUBIC)
    if radial:
        # soft centre glow: radial = (hex, strength 0..1, radius 1024-units)
        col, strength, rad = radial
        glow = Image.new('L', (small, small), 0)
        gp = glow.load()
        for y in range(small):
            for x in range(small):
                d = math.hypot((x / (small - 1) - 0.5) * 1024, (y / (small - 1) - 0.5) * 1024)
                t = max(0.0, 1 - d / rad)
                gp[x, y] = int(255 * strength * (t ** 1.6))
        glow = glow.resize((S, S), Image.BICUBIC)
        layer = Image.new('RGB', (S, S), hexc(col)[:3])
        img = Image.composite(layer, img, glow)
    return img.convert('RGBA')


def layer():
    return Image.new('RGBA', (S, S), (0, 0, 0, 0))


def mask():
    return Image.new('L', (S, S), 0)


def p(v):
    return v * K


def rrect(draw, cx, cy, w, h, r, fill):
    draw.rounded_rectangle([p(cx - w / 2), p(cy - h / 2), p(cx + w / 2), p(cy + h / 2)],
                           radius=p(min(r, w / 2, h / 2)), fill=fill)


def circle(draw, cx, cy, r, fill):
    draw.ellipse([p(cx - r), p(cy - r), p(cx + r), p(cy + r)], fill=fill)


def ring(draw, cx, cy, r, w, fill):
    """Full ring centred on radius r with stroke width w."""
    draw.ellipse([p(cx - r - w / 2), p(cy - r - w / 2), p(cx + r + w / 2), p(cy + r + w / 2)], fill=fill)
    draw.ellipse([p(cx - r + w / 2), p(cy - r + w / 2), p(cx + r - w / 2), p(cy + r - w / 2)], fill=0 if isinstance(fill, int) else (0, 0, 0, 0))


def ring_mask(cx, cy, r, w):
    m = mask()
    d = ImageDraw.Draw(m)
    d.ellipse([p(cx - r - w / 2), p(cy - r - w / 2), p(cx + r + w / 2), p(cy + r + w / 2)], fill=255)
    d.ellipse([p(cx - r + w / 2), p(cy - r + w / 2), p(cx + r - w / 2), p(cy + r - w / 2)], fill=0)
    return m


def arc_mask(cx, cy, r, w, start_deg, end_deg, round_caps=True):
    """Arc mask. Angles: 0 = 12 o'clock, clockwise positive."""
    m = mask()
    d = ImageDraw.Draw(m)
    # PIL: 0 = 3 o'clock, clockwise. convert.
    s = start_deg - 90
    e = end_deg - 90
    box = [p(cx - r - w / 2), p(cy - r - w / 2), p(cx + r + w / 2), p(cy + r + w / 2)]
    d.pieslice(box, s, e, fill=255)
    d.ellipse([p(cx - r + w / 2), p(cy - r + w / 2), p(cx + r - w / 2), p(cy + r - w / 2)], fill=0)
    if round_caps:
        for a in (start_deg, end_deg):
            ar = math.radians(a)
            x = cx + r * math.sin(ar)
            y = cy - r * math.cos(ar)
            d.ellipse([p(x - w / 2), p(y - w / 2), p(x + w / 2), p(y + w / 2)], fill=255)
    return m


def dumbbell_mask(cx, cy, angle_deg=0, grip=150, bar=64, plates=((90, 300), (60, 210)), cap=(40, 90),
                  r=26, bar_r=None, cap_r=None):
    """Horizontal dumbbell centred at (cx,cy) then rotated by angle_deg (CCW positive, PIL style).

    grip: visible grip length between inner plates.
    plates: list of (width, height) from inside out, butted together (clean stepped silhouette).
    cap: (width, height) end stub, or None.
    Returns (mask, half_length).
    """
    m = mask()
    d = ImageDraw.Draw(m)
    x = grip / 2
    segs = []
    for (w, h) in plates:
        segs.append((x + w / 2, w, h, r))
        x += w
    if cap:
        segs.append((x + cap[0] / 2, cap[0], cap[1], cap[1] / 2 if cap_r is None else cap_r))
        x += cap[0]
    half = x
    br = bar / 2 if bar_r is None else bar_r
    # bar spans to first plate centre
    for sgn in (-1, 1):
        d.rectangle([p(cx - 2), p(cy - bar / 2), p(cx + sgn * segs[0][0]), p(cy + bar / 2)] if sgn > 0 else
                    [p(cx + sgn * segs[0][0]), p(cy - bar / 2), p(cx + 2), p(cy + bar / 2)], fill=255)
    for i, (sx, w, h, rr) in enumerate(segs):
        for sgn in (-1, 1):
            rrect(d, cx + sgn * sx, cy, w, h, rr, 255)
            if i > 0:
                # fill junction notch between this segment and the previous (taller) one
                px0 = segs[i - 1][0]
                hh = min(h, segs[i - 1][2])
                a, b = sorted([cx + sgn * px0, cx + sgn * sx])
                d.rectangle([p(a), p(cy - hh / 2), p(b), p(cy + hh / 2)], fill=255)
    if angle_deg:
        m = m.rotate(angle_deg, resample=Image.BICUBIC, center=(p(cx), p(cy)))
    return m, half


def paint(img, m, color):
    col = Image.new('RGBA', (S, S), hexc(color) if isinstance(color, str) else color)
    img.alpha_composite(Image.composite(col, Image.new('RGBA', (S, S), (0, 0, 0, 0)), m))
    return img


def grow(m, px1024):
    """Dilate mask by px (1024-units)."""
    size = int(p(px1024) * 2) | 1
    # MaxFilter limited sizes; use blur+threshold for big radii
    b = m.filter(ImageFilter.GaussianBlur(p(px1024) * 0.6))
    return b.point(lambda v: 255 if v > 8 else int(v * 30) if v > 0 else 0)


def dilate(m, px1024):
    """Accurate-ish dilation: blur then threshold at low value."""
    rad = p(px1024)
    b = m.filter(ImageFilter.GaussianBlur(rad / 2.2))
    return b.point(lambda v: 255 if v >= 6 else 0).filter(ImageFilter.GaussianBlur(1.5))


def subtract(a, b):
    return ImageChops.subtract(a, b)


def finish(img, path):
    out = img.convert('RGB').resize((1024, 1024), Image.LANCZOS)
    out.save(path, 'PNG', optimize=True)
    return out


def strip(src_path, out_path):
    """Circle-masked previews at 300, 60, 44, 24 on black, plus 2x zoom of 44/24."""
    im = Image.open(src_path).convert('RGB')
    sizes = [300, 60, 44, 24]
    W = 300 + 60 + 44 + 24 + 5 * 20 + 88 + 48 + 40
    H = 340
    sheet = Image.new('RGB', (W, H), (0, 0, 0))
    x = 20
    small_imgs = {}
    for s in sizes:
        t = im.resize((s, s), Image.LANCZOS)
        mm = Image.new('L', (s * 4, s * 4), 0)
        ImageDraw.Draw(mm).ellipse([0, 0, s * 4 - 1, s * 4 - 1], fill=255)
        mm = mm.resize((s, s), Image.LANCZOS)
        bg = Image.new('RGB', (s, s), (0, 0, 0))
        t = Image.composite(t, bg, mm)
        small_imgs[s] = t
        sheet.paste(t, (x, 20 + (300 - s) // 2))
        x += s + 20
    # nearest-neighbour 2x zooms of 44 and 24 to inspect pixels
    for s in (44, 24):
        z = small_imgs[s].resize((s * 2, s * 2), Image.NEAREST)
        sheet.paste(z, (x, 20 + (300 - s * 2) // 2))
        x += s * 2 + 20
    sheet.save(out_path)
    return sheet


def tick_mask(R_outer, length, width, angle_cw_deg, cx=C, cy=C):
    """Rounded radial tick whose outer end sits at R_outer. angle 0 = 12 o'clock, clockwise."""
    m = mask()
    d = ImageDraw.Draw(m)
    rrect(d, cx, cy - R_outer + length / 2, width, length, width / 2, 255)
    if angle_cw_deg:
        m = m.rotate(-angle_cw_deg, resample=Image.BICUBIC, center=(p(cx), p(cy)))
    return m


def rot_pt(x, y, ang):
    """Rotate offset (x,y) about centre by ang degrees CCW (screen space)."""
    a = math.radians(ang)
    return (C + x * math.cos(a) + y * math.sin(a), C - x * math.sin(a) + y * math.cos(a))
