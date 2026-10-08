"""Timer-hand variants of option #9 (split ring) for Intervally.

Reuses lib.py from icon3/dumbbell so navy, ring radius/width, colours and halo match #9 exactly.
Geometry is in 1024 units; lib draws at 4096 and downsamples.
"""
import math
from PIL import Image, ImageDraw, ImageChops
from lib import *

NAVY = ('#18294F', '#0B1631')
GREEN = '#4CD98A'
BLUE = '#27BFFF'
WHITE = '#FFFFFF'
ANGLE = 40                      # diagonal, CCW from horizontal (same as #9)
A_TR = 90 - ANGLE               # clock angle of the top-right split (50 deg)
RING_R, RING_W = 262, 104       # same as #9
HALO = 26                       # same navy keyline as #9

UX, UY = math.cos(math.radians(ANGLE)), -math.sin(math.radians(ANGLE))   # axis toward top-right
VX, VY = -UY, UX                                                          # perpendicular


def axis_pt(u, v=0.0, cx=C, cy=C):
    return (cx + u * UX + v * VX, cy + u * UY + v * VY)


def poly_mask(pts):
    m = mask()
    ImageDraw.Draw(m).polygon([(p(x), p(y)) for x, y in pts], fill=255)
    return m


def disc_mask(x, y, r):
    m = mask()
    circle(ImageDraw.Draw(m), x, y, r, 255)
    return m


def union(*ms):
    out = ms[0]
    for m in ms[1:]:
        out = ImageChops.lighter(out, m)
    return out


def taper_bar(u0, u1, w0, w1, round0=True, round1=True, n=48):
    """Bar along the diagonal from u0 (width w0) to u1 (width w1) with rounded ends."""
    # body
    pts = [axis_pt(u0, -w0 / 2), axis_pt(u1, -w1 / 2), axis_pt(u1, w1 / 2), axis_pt(u0, w0 / 2)]
    m = poly_mask(pts)
    if round1:
        m = union(m, disc_mask(*axis_pt(u1), w1 / 2))
    if round0:
        m = union(m, disc_mask(*axis_pt(u0), w0 / 2))
    return m


def hand_mask(length=360, tail=120, w_hub=112, w_tip=62, hub_r=92, tail_w=None):
    """Stopwatch hand: round hub at centre, long tapered blade to top-right, short tail to bottom-left."""
    tail_w = tail_w or w_hub
    blade = taper_bar(0, length - w_tip / 2, w_hub, w_tip)
    tailm = taper_bar(-(tail - tail_w / 2), 0, tail_w, w_hub)
    hub = disc_mask(C, C, hub_r)
    return union(blade, tailm, hub)


def band_cut(u_from, u_to, half_w):
    """Navy cutter band along the diagonal (used to open a split the white mark doesn't reach)."""
    return poly_mask([axis_pt(u_from, -half_w), axis_pt(u_to, -half_w), axis_pt(u_to, half_w), axis_pt(u_from, half_w)])


def base(img_cut=None, cy=C):
    img = canvas_gradient(*NAVY)
    paint(img, arc_mask(C, cy, RING_R, RING_W, A_TR, A_TR + 180, round_caps=False), BLUE)
    paint(img, arc_mask(C, cy, RING_R, RING_W, A_TR + 180, A_TR + 360, round_caps=False), GREEN)
    return img


def compose(white, cutters=(), cy=C, path=None):
    """Draw ring, punch navy halo around the white mark (and any extra cutters), then paint white."""
    img = base(cy=cy)
    bg = canvas_gradient(*NAVY)
    halo = dilate(white, HALO)
    for c in cutters:
        halo = union(halo, c)
    img = Image.composite(bg, img, subtract(halo, white))
    paint(img, white, WHITE)
    if path:
        finish(img, path)
    return img


def verify(path):
    im = Image.open(path)
    assert im.size == (1024, 1024), im.size
    assert im.mode == 'RGB', im.mode
    assert 'A' not in im.getbands()
    return f'{path}: {im.size} {im.mode} bands={im.getbands()}'


def hull2(c0, r0, c1, r1, n=96):
    """Convex hull of two circles given by axis positions (u) and radii -> mask (smooth tapered capsule)."""
    d = abs(c1 - c0)
    if c1 < c0:
        c0, r0, c1, r1 = c1, r1, c0, r0
    # outer tangent touches both circles at +-(90 - phi) from the +u axis, sin(phi) = (r0 - r1)/d
    phi = math.asin(max(-1, min(1, (r0 - r1) / d)))
    pts = []
    # arc around circle 1 (far end, u=c1) from +90+phi through 0 to -(90+phi)
    a0 = math.pi / 2 - phi
    for i in range(n + 1):
        a = a0 - (2 * a0) * i / n
        pts.append(axis_pt(c1 + r1 * math.cos(a), r1 * math.sin(a)))
    # arc around circle 0 from -(90+phi) going through 180 to +(90+phi)
    b0 = math.pi / 2 - phi
    for i in range(n + 1):
        a = -b0 - (2 * math.pi - 2 * b0) * i / n
        pts.append(axis_pt(c0 + r0 * math.cos(a), r0 * math.sin(a)))
    return poly_mask(pts)


def needle(hub_r=110, tip_u=350, tip_r=48, tail_u=-170, tail_r=40):
    m = hull2(0, hub_r, tip_u, tip_r)
    if tail_u is not None:
        m = union(m, hull2(tail_u, tail_r, 0, hub_r))
    return m


def clock_hand(hub_r=100, w_base=96, w_tip=70, tip_u=380, tail_u=-160, tail_w=None):
    """Distinct round hub + tapered blade (rounded tip) to top-right + short rounded tail."""
    tail_w = tail_w or w_base
    m = union(disc_mask(C, C, hub_r), hull2(0, w_base / 2, tip_u - w_tip / 2, w_tip / 2))
    if tail_u is not None:
        m = union(m, hull2(tail_u + tail_w / 2, tail_w / 2, 0, tail_w / 2))
    return m


def compose_pin(white, pin_r=0, cutters=(), cy=C, path=None, extra_white=None):
    img = compose(white, cutters, cy=cy)
    if pin_r:
        paint(img, disc_mask(C, cy, pin_r), NAVY[0])
    if path:
        finish(img, path)
    return img


def splits(r, cy=C):
    """Navy disc cutters centred on the ring at both diagonal split points -> concave swoosh ends like #9."""
    return [disc_mask(*axis_pt(RING_R, cy=cy), r), disc_mask(*axis_pt(-RING_R, cy=cy), r)]


def clock_hand_at(cy, hub_r, w_base, w_tip, tip_u, tail_u, tail_w):
    m = union(disc_mask(C, cy, hub_r), hull2c(cy, 0, w_base / 2, tip_u - w_tip / 2, w_tip / 2))
    if tail_u is not None:
        m = union(m, hull2c(cy, tail_u + tail_w / 2, tail_w / 2, 0, tail_w / 2))
    return m


def hull2c(cy, c0, r0, c1, r1, n=96):
    if c1 < c0:
        c0, r0, c1, r1 = c1, r1, c0, r0
    d = c1 - c0
    phi = math.asin(max(-1, min(1, (r0 - r1) / d)))
    a0 = math.pi / 2 - phi
    pts = []
    for i in range(n + 1):
        a = a0 - (2 * a0) * i / n
        pts.append(axis_pt(c1 + r1 * math.cos(a), r1 * math.sin(a), cy=cy))
    for i in range(n + 1):
        a = -a0 - (2 * math.pi - 2 * a0) * i / n
        pts.append(axis_pt(c0 + r0 * math.cos(a), r0 * math.sin(a), cy=cy))
    return poly_mask(pts)


def crown_mask(cy, ring_outer=RING_R + RING_W / 2, gap=30, stem=(60, 40), cap=(156, 62), cap_r=24):
    """Stopwatch crown at 12 o'clock: stem + rounded cap sitting above the ring."""
    m = mask()
    d = ImageDraw.Draw(m)
    y0 = cy - ring_outer - gap                     # bottom of stem
    sw, sh = stem
    cw, ch = cap
    rrect(d, C, y0 - sh / 2 - 4, sw, sh + 8, 6, 255)            # stem (overlaps cap a little)
    rrect(d, C, y0 - sh - ch / 2, cw, ch, cap_r, 255)           # cap
    return m


def play_mask(cx, cy, R, rc, rot_ccw_deg):
    """Rounded play triangle (points right before rotation), vertices on circle R (sharp), corner radius rc.
    Centred on its centroid at (cx, cy). Rotation is CCW in screen space."""
    pts = []
    for k in range(3):
        a = math.radians(rot_ccw_deg + k * 120)            # vertex 0 = tip
        pts.append((cx + R * math.cos(a), cy - R * math.sin(a)))
    # rounded triangle = inset triangle dilated by rc: build via polygon of offset arcs
    inset = []
    Ri = R - 2 * rc                                          # equilateral: inradius offset rc moves vertex by 2rc
    for k in range(3):
        a = math.radians(rot_ccw_deg + k * 120)
        inset.append((cx + Ri * math.cos(a), cy - Ri * math.sin(a)))
    outline = []
    n = 40
    for k in range(3):
        a_v = math.radians(rot_ccw_deg + k * 120)
        vx, vy = inset[k]
        # arc spans +-60 deg around the vertex direction
        for i in range(n + 1):
            t = a_v + math.radians(-60 + 120 * i / n)
            outline.append((vx + rc * math.cos(t), vy - rc * math.sin(t)))
    return poly_mask(outline)


def rounded_poly_pts(verts, rc, n=40):
    """Outline points of a convex polygon (screen coords, any winding) with corners rounded by rc."""
    k = len(verts)
    # ensure counter-clockwise in math sense (y up) -> in screen coords (y down) use signed area
    area = sum(verts[i][0] * verts[(i + 1) % k][1] - verts[(i + 1) % k][0] * verts[i][1] for i in range(k))
    if area < 0:
        verts = verts[::-1]
    out = []
    for i in range(k):
        p0, p1, p2 = verts[i - 1], verts[i], verts[(i + 1) % k]
        e1 = (p1[0] - p0[0], p1[1] - p0[1]); l1 = math.hypot(*e1); e1 = (e1[0] / l1, e1[1] / l1)
        e2 = (p2[0] - p1[0], p2[1] - p1[1]); l2 = math.hypot(*e2); e2 = (e2[0] / l2, e2[1] / l2)
        # outward normals for positive-area (screen) winding
        n1 = (e1[1], -e1[0]); n2 = (e2[1], -e2[0])
        bis = (n1[0] + n2[0], n1[1] + n2[1]); lb = math.hypot(*bis); bis = (bis[0] / lb, bis[1] / lb)
        cosh = n1[0] * bis[0] + n1[1] * bis[1]
        cx, cy = p1[0] - bis[0] * rc / cosh, p1[1] - bis[1] * rc / cosh
        a1 = math.atan2(n1[1], n1[0]); a2 = math.atan2(n2[1], n2[0])
        while a2 < a1:
            a2 += 2 * math.pi
        for j in range(n + 1):
            t = a1 + (a2 - a1) * j / n
            out.append((cx + rc * math.cos(t), cy + rc * math.sin(t)))
    return out


def play_iso(cx, cy, H, D, rc, rot_ccw_deg, fit=None):
    """Isosceles play triangle, back edge height H, depth D, centroid at (cx,cy), rotated CCW.
    If fit is given, scale so the rounded outline's farthest point is exactly `fit` from the centre."""
    def build(s):
        local = [(2 * D * s / 3, 0), (-D * s / 3, -H * s / 2), (-D * s / 3, H * s / 2)]
        a = math.radians(rot_ccw_deg)
        v = [(cx + x * math.cos(a) + y * math.sin(a), cy - x * math.sin(a) + y * math.cos(a)) for x, y in local]
        return rounded_poly_pts(v, rc)
    s = 1.0
    if fit:
        for _ in range(30):
            pts = build(s)
            m = max(math.hypot(x - cx, y - cy) for x, y in pts)
            s *= fit / m
    pts = build(s)
    return poly_mask(pts), pts


def pusher_mask(cy, clock_deg, ring_outer=RING_R + RING_W / 2, gap=28, w=70, h=50, r=18):
    """Small rounded pusher button outside the ring at a clock angle (0 = 12 o'clock, clockwise)."""
    m = mask()
    d = ImageDraw.Draw(m)
    rr = ring_outer + gap + h / 2
    rrect(d, C, cy - rr, w, h, r, 255)
    if clock_deg:
        m = m.rotate(-clock_deg, resample=Image.BICUBIC, center=(p(C), p(cy)))
    return m
