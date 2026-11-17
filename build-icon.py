#!/usr/bin/env python3
"""Generate XBiGOD's layered app icon per the HarmonyOS application-icon spec.

Scene: a 2.5D-rendered Xbox 360-style controller below an optical disc.
The pad is a thick slab with a lit front face, a darker extruded wall, recessed
sockets, raised sticks / D-pad / buttons and a soft cast shadow. Above it a
conversion mark — two extruded arrowed arcs — cradles a silver game disc with an
iridescent data zone, a moulded hub and a punched centre hole. The 360 outline
is traced from a front-view product photo; the logo is intentionally absent.

Spec musts encoded here: 1024x1024 PNG, two layers (foreground + background),
square with no baked rounded corners, background with zero transparent pixels,
vertical top-light gradient, subject centred and clear of the corners.
"""
import math
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

S = 1024
K = 4  # supersample, then LANCZOS down to S for antialiased curves
N = S * K
CX = CY = S / 2.0

ROOT = os.path.dirname(os.path.abspath(__file__))
MEDIA = os.path.join(ROOT, 'entry/src/main/resources/base/media')
APPSCOPE = os.path.join(ROOT, 'AppScope/resources/base/media')
STORE = os.path.join(ROOT, 'store/icon')

BG_TOP = np.array([64, 202, 121], np.float64)   # top is the lighter end
BG_BOT = np.array([9, 104, 55], np.float64)

SHELL_TOP = np.array([46, 51, 62], np.float64)   # controller front face
SHELL_BOT = np.array([18, 21, 27], np.float64)
SIDE_TOP = np.array([22, 25, 32], np.float64)    # extruded wall below the face
SIDE_BOT = np.array([5, 6, 9], np.float64)
SOCKET = np.array([5, 7, 10], np.float64)        # recessed detail wells
LT_TOP = np.array([252, 253, 255], np.float64)   # sticks, D-pad, guide
LT_BOT = np.array([188, 199, 214], np.float64)
LT_WALL_TOP = np.array([168, 178, 192], np.float64)
LT_WALL_BOT = np.array([104, 114, 128], np.float64)
LT_CONCAVE = np.array([196, 206, 219], np.float64)
SHADOW = np.array([2, 30, 17], np.float64)

BTN_Y = np.array([244, 186, 66], np.float64)     # ABXY face buttons
BTN_X = np.array([58, 130, 214], np.float64)
BTN_B = np.array([224, 72, 64], np.float64)
BTN_A = np.array([96, 190, 88], np.float64)

# Composition: the pad sets the width, the disc group its own size; the two
# are stacked, centred vertically. Give the disc group more height and the
# top/bottom padding necessarily drops below the side padding.
PAD_W = 660.0            # pad silhouette width
PAD_PS = PAD_W / 660.0   # traced points live in a 660-wide space
PAD_TILT = 1.0           # frontal view; depth comes from the extrusion

EXT = 30.0               # extruded wall depth, px at 1024
SHADOW_B = 20.0          # bbox extent of the pad shadow below its wall

DISC_EXT = 8.0           # disc thickness, px at 1024
DISC_HUB = 0.375         # hub shoulder, fraction of the radius
DISC_HOLE = 0.15         # centre hole, fraction of the radius
DISC_FACE = np.array([235, 240, 246], np.float64)
DISC_EDGE = np.array([160, 169, 183], np.float64)
DISC_WALL = np.array([126, 134, 148], np.float64)
DISC_WALL_DEEP = np.array([68, 74, 86], np.float64)

# Conversion mark: two thick arcs with arrowheads wrapping the disc.
RING_R = 143.0           # arc centreline radius
RING_W = 24.0            # arc stroke
RING_EXT = 8.0           # mark thickness, px at 1024
RING_HEAD_LEN = 38.0
RING_HEAD_HALF = 20.0
UNIT_GAP = 13.0          # mark bottom to the pad's top dip
DISC_GAP = 16.0          # disc edge to the mark's inner edge
WALL_DY = 7.0            # pad-space drop of a raised detail's side wall
TOP_DY = -2.0            # pad-space lift of a raised detail's top face

# Traced from an Xbox 360 front-view product photo, normalised to 660 x 460.
PTS = [
    (239.9, -203.5), (189.7, -227.1), (138.1, -228.5), (126.2, -215.3),
    (114.4, -215.3), (79.0, -196.1), (45.0, -190.2), (-74.6, -191.7),
    (-126.2, -215.3), (-135.1, -215.3), (-148.4, -227.1), (-161.7, -228.5),
    (-200.1, -224.1), (-245.8, -202.0), (-270.9, -150.4), (-294.6, -87.0),
    (-321.1, 26.5), (-330.0, 101.7), (-330.0, 150.4), (-325.6, 179.9),
    (-310.8, 213.8), (-288.7, 228.5), (-266.5, 228.5), (-247.3, 222.6),
    (-208.9, 200.5), (-141.0, 137.1), (-102.6, 117.9), (-58.3, 109.1),
    (49.5, 109.1), (83.4, 115.0), (115.9, 126.8), (148.4, 148.9),
    (200.1, 196.1), (241.4, 221.2), (268.0, 228.5), (287.2, 228.5),
    (303.4, 221.2), (321.1, 193.1), (328.5, 159.2), (328.5, 104.7),
    (322.6, 56.0), (293.1, -69.3), (260.6, -157.8), (241.4, -191.7),
]

LEFT_STICK = (-209.0, -119.0, 58.0)
GUIDE = (-14.0, -115.0, 38.0)
ABXY = (182.0, -124.0, 52.0, 24.0)   # cx, cy, spread, dot radius
DPAD = (-103.0, -13.0, 74.0, 23.0)   # cx, cy, arm half-length, arm half-width
RIGHT_STICK = (79.0, -13.0, 59.0)

BTN_OFFSETS = ((0, -ABXY[2]), (-ABXY[2], 0), (ABXY[2], 0), (0, ABXY[2]))
BTN_COLORS = (BTN_Y, BTN_X, BTN_B, BTN_A)

PAD_HALF_H = max(abs(y) for _, y in PTS) * PAD_PS * PAD_TILT
PAD_HALF_W = max(abs(x) for x, _ in PTS) * PAD_PS

# Stack the disc group, the gap and the pad as one block and centre it.
UNIT_H = 2.0 * RING_R + RING_EXT
BLOCK_H = UNIT_H + UNIT_GAP + SHADOW_B + EXT + 420.2 * PAD_PS
MARGIN = (S - BLOCK_H) / 2.0
PAD_CY = S - MARGIN - SHADOW_B - EXT - PAD_HALF_H
PAD_TOP = PAD_CY - PAD_HALF_H
PAD_BOT = PAD_CY + PAD_HALF_H

DIP_Y = PAD_CY - 191.7 * PAD_PS
DISC_R = RING_R - RING_W / 2.0 - DISC_GAP
DISC_CY = MARGIN + RING_R + 2.0
DISC_TOP = DISC_CY - DISC_R
DISC_BOT = DISC_CY + DISC_R


def vertical_gradient(top, bot, n):
    t = np.linspace(0.0, 1.0, n)[:, None]
    g = top[None, :] * (1.0 - t) + bot[None, :] * t
    return np.repeat(g[:, None, :], n, axis=1)


def vgrad(top, bot, y0, y1):
    """Vertical gradient mapped onto the span [y0, y1] of the canvas."""
    t = np.clip((np.arange(S, dtype=np.float64) - y0) / max(y1 - y0, 1.0), 0.0, 1.0)
    g = top[None, :] * (1.0 - t[:, None]) + bot[None, :] * t[:, None]
    return np.repeat(g[:, None, :], S, axis=1)


def build_background():
    img = vertical_gradient(BG_TOP, BG_BOT, S).astype(np.float64)
    rows = np.arange(S) / (S - 1.0)
    img += (24.0 * np.exp(-rows / 0.035))[:, None, None]         # top rim light
    img -= (12.0 * np.exp(-(1.0 - rows) / 0.05))[:, None, None]  # bottom shade
    yy, xx = np.mgrid[0:S, 0:S].astype(np.float64)
    glow = np.exp(-(((xx - S / 2.0) ** 2 + (yy - 575.0) ** 2) / (470.0 ** 2)))
    img += (9.0 * glow)[:, :, None]                              # depth behind subject
    rgb = Image.fromarray(np.clip(img, 0, 255).astype(np.uint8), 'RGB')
    rgb.save(os.path.join(MEDIA, 'background.png'), optimize=True)
    return rgb


def chaikin(points, iterations=3):
    pts = list(points)
    for _ in range(iterations):
        out = []
        n = len(pts)
        for i in range(n):
            x0, y0 = pts[i]
            x1, y1 = pts[(i + 1) % n]
            out.append((0.75 * x0 + 0.25 * x1, 0.75 * y0 + 0.25 * y1))
            out.append((0.25 * x0 + 0.75 * x1, 0.25 * y0 + 0.75 * y1))
        pts = out
    return pts


def tp(x, y):
    """Map an unscaled pad coordinate into supersampled canvas pixels."""
    return (CX + x * PAD_PS) * K, (PAD_CY + y * PAD_PS * PAD_TILT) * K


def ts(v):
    return v * PAD_PS * K


def tsy(v):
    return v * PAD_PS * PAD_TILT * K


def draw_pad_body(mask):
    pts = [tp(x, y) for x, y in chaikin(PTS, 3)]
    ImageDraw.Draw(mask).polygon(pts, fill=255)


def ellipse(d, cx, cy, rx, scale=1.0, dy=0.0, ry=None):
    ry = rx if ry is None else ry
    px, py = tp(cx, cy + dy)
    a, b = ts(rx * scale), tsy(ry * scale)
    d.ellipse([px - a, py - b, px + a, py + b], fill=255)


def cross(d, cx, cy, arm, hw, scale=1.0, dy=0.0):
    px, py = tp(cx, cy + dy)
    a, w = ts(arm * scale), ts(hw * scale)
    ay, wy = tsy(arm * scale), tsy(hw * scale)
    rad = int(min(w, wy))
    d.rounded_rectangle([px - w, py - ay, px + w, py + ay], rad, fill=255)
    d.rounded_rectangle([px - a, py - wy, px + a, py + wy], rad, fill=255)


def draw_sockets(mask):
    d = ImageDraw.Draw(mask)
    for cx, cy, r in (LEFT_STICK, RIGHT_STICK):
        ellipse(d, cx, cy, r, 1.09, 2.5)
    ellipse(d, DPAD[0], DPAD[1], DPAD[2] * 1.06, 1.0, 2.5)
    ellipse(d, GUIDE[0], GUIDE[1], GUIDE[2], 1.12, 2.5)


def draw_button_sockets(mask):
    d = ImageDraw.Draw(mask)
    for ox, oy in BTN_OFFSETS:
        ellipse(d, ABXY[0] + ox, ABXY[1] + oy, ABXY[3], 1.05, 4.0)


def draw_detail_walls(mask):
    d = ImageDraw.Draw(mask)
    for cx, cy, r in (LEFT_STICK, RIGHT_STICK):
        ellipse(d, cx, cy, r, 1.0, WALL_DY)
    cross(d, DPAD[0], DPAD[1], DPAD[2], DPAD[3], 1.0, WALL_DY - 1.0)
    ellipse(d, GUIDE[0], GUIDE[1], GUIDE[2], 1.0, WALL_DY - 1.5)


def draw_light_tops(mask):
    d = ImageDraw.Draw(mask)
    for cx, cy, r in (LEFT_STICK, RIGHT_STICK):
        ellipse(d, cx, cy, r * 0.95, 1.0, TOP_DY)
    cross(d, DPAD[0], DPAD[1], DPAD[2], DPAD[3], 0.95, TOP_DY)
    ellipse(d, GUIDE[0], GUIDE[1], GUIDE[2] * 0.95, 1.0, TOP_DY)


def draw_stick_concave(mask):
    d = ImageDraw.Draw(mask)
    for cx, cy, r in (LEFT_STICK, RIGHT_STICK):
        ellipse(d, cx, cy, r * 0.62, 1.0, TOP_DY)


def draw_stick_spec(mask):
    d = ImageDraw.Draw(mask)
    for cx, cy, r in (LEFT_STICK, RIGHT_STICK):
        ellipse(d, cx, cy, r * 0.34, 1.0, TOP_DY - r * 0.30, ry=r * 0.20)


def draw_button_wall(mask, i):
    d = ImageDraw.Draw(mask)
    ox, oy = BTN_OFFSETS[i]
    ellipse(d, ABXY[0] + ox, ABXY[1] + oy, ABXY[3], 1.0, 3.5)


def draw_button_top(mask, i):
    d = ImageDraw.Draw(mask)
    ox, oy = BTN_OFFSETS[i]
    ellipse(d, ABXY[0] + ox, ABXY[1] + oy, ABXY[3] * 0.92, 1.0, -1.0)


def draw_button_spec(mask):
    d = ImageDraw.Draw(mask)
    r = ABXY[3]
    for ox, oy in BTN_OFFSETS:
        ellipse(d, ABXY[0] + ox, ABXY[1] + oy, r * 0.40, 1.0, -1.0 - r * 0.30, ry=r * 0.24)


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def draw_disc(mask):
    d = ImageDraw.Draw(mask)
    r = DISC_R * K
    d.ellipse([CX * K - r, DISC_CY * K - r, CX * K + r, DISC_CY * K + r], fill=255)
    hr = DISC_HOLE * DISC_R * K
    d.ellipse([CX * K - hr, DISC_CY * K - hr, CX * K + hr, DISC_CY * K + hr], fill=0)


def draw_ring(mask):
    d = ImageDraw.Draw(mask)
    cx, cy = CX * K, DISC_CY * K
    r = RING_R * K
    w = RING_W * K
    box = [cx - r, cy - r, cx + r, cy + r]
    for a0, a1 in ((200.0, 330.0), (20.0, 150.0)):
        d.arc(box, a0, a1, fill=255, width=int(round(w)))
    cap = w / 2.0
    for tail in (200.0, 20.0):
        a = math.radians(tail)
        tx, ty = cx + math.cos(a) * r, cy + math.sin(a) * r
        d.ellipse([tx - cap, ty - cap, tx + cap, ty + cap], fill=255)
    for head in (330.0, 150.0):
        a = math.radians(head)
        ca, sa = math.cos(a), math.sin(a)
        bx, by = cx + ca * r, cy + sa * r
        half = RING_HEAD_HALF * K
        length = RING_HEAD_LEN * K
        d.polygon([(bx - sa * length, by + ca * length),
                   (bx + ca * half, by + sa * half),
                   (bx - ca * half, by - sa * half)], fill=255)


def disc_face_color():
    yy, xx = np.mgrid[0:S, 0:S].astype(np.float64)
    dx = xx - CX
    dy = yy - DISC_CY
    rn = np.sqrt(dx * dx + dy * dy) / DISC_R
    ang = np.arctan2(dy, dx)

    t = np.clip((rn - 0.30) / 0.70, 0.0, 1.0)
    col = (DISC_FACE[None, None, :] * (1.0 - t[..., None])
           + DISC_EDGE[None, None, :] * t[..., None])

    # Iridescent data surface: two hue turns, kept faint so the greens dominate.
    zone = smoothstep(0.40, 0.55, rn) * (1.0 - smoothstep(0.84, 0.975, rn))
    hue = np.mod(ang / (2.0 * np.pi) * 2.0, 1.0)[..., None] + np.array([0.0, 1.0 / 3.0, 2.0 / 3.0])
    rainbow = (0.5 + 0.5 * np.cos(2.0 * np.pi * hue)) * 255.0
    col = col * (1.0 - 0.16 * zone[..., None]) + rainbow * (0.16 * zone[..., None])

    # Clear hub: a bevelled shoulder around it and a slightly brighter bore.
    bevel = np.exp(-((rn - DISC_HUB) / 0.035) ** 2)
    col = col * (1.0 - 0.26 * bevel[..., None])
    col += (10.0 * (1.0 - smoothstep(0.16, 0.32, rn)))[..., None]

    # Outer rim darkening and one soft sheen across the upper left.
    col = col * (1.0 - 0.20 * smoothstep(0.975, 1.0, rn)[..., None])
    sheen = (np.exp(-((ang + 2.1) / 0.55) ** 2) * smoothstep(0.45, 0.62, rn)
             * (1.0 - smoothstep(0.86, 0.97, rn)))
    col += (26.0 * sheen)[..., None]

    lift = 1.05 - 0.10 * np.clip((yy - DISC_TOP) / (2.0 * DISC_R), 0.0, 1.0)
    return col * lift[..., None]


def make_mask(draw_fn):
    img = Image.new('L', (N, N), 0)
    draw_fn(img)
    arr = np.asarray(img.resize((S, S), Image.LANCZOS), np.float64) / 255.0
    del img
    return arr


def shift(mask, dy, dx=0):
    if dx == 0 and dy == 0:
        return mask
    return np.roll(mask, (int(round(dy)), int(round(dx))), axis=(0, 1))


def blur(mask, radius):
    img = Image.fromarray(np.clip(mask * 255.0 + 0.5, 0, 255).astype(np.uint8), 'L')
    img = img.filter(ImageFilter.GaussianBlur(radius))
    return np.asarray(img, np.float64) / 255.0


def over(rgb, alpha, mask, color, opacity=1.0):
    """Straight-alpha 'source over' with a per-pixel or constant colour."""
    a = np.clip(mask * opacity, 0.0, 1.0)
    keep = alpha * (1.0 - a)
    na = a + keep
    safe = np.maximum(na, 1e-6)
    out = (color * a[..., None] + rgb * keep[..., None]) / safe[..., None]
    return out, na


def build_foreground():
    mb = make_mask(draw_pad_body)
    msock = make_mask(draw_sockets)
    msock_btn = make_mask(draw_button_sockets)
    mwall = make_mask(draw_detail_walls)
    mtop = make_mask(draw_light_tops)
    mconc = make_mask(draw_stick_concave)
    mspec = make_mask(draw_stick_spec)
    mbtn_wall = [make_mask(lambda img, i=i: draw_button_wall(img, i)) for i in range(4)]
    mbtn_top = [make_mask(lambda img, i=i: draw_button_top(img, i)) for i in range(4)]
    mbtn_spec = make_mask(draw_button_spec)
    md = make_mask(draw_disc)

    rgb = np.zeros((S, S, 3), np.float64)
    alpha = np.zeros((S, S), np.float64)

    # Ground shadow under the extruded slab.
    foot = np.clip(mb + shift(mb, EXT), 0.0, 1.0)
    rgb, alpha = over(rgb, alpha, shift(blur(foot, 9.0), 12), SHADOW, 0.26)

    # Extruded wall, then the lit front face on top of it. The face is shaded
    # across x as well, so the shell reads as a rounded solid.
    rgb, alpha = over(rgb, alpha, shift(mb, EXT),
                      vgrad(SIDE_TOP, SIDE_BOT, PAD_TOP, PAD_BOT + EXT))
    xs = np.abs(np.arange(S, dtype=np.float64) - CX) / PAD_HALF_W
    round_shade = (1.0 - 0.24 * np.clip(xs, 0.0, 1.0) ** 2.4)[None, :, None]
    rgb, alpha = over(rgb, alpha, mb,
                      vgrad(SHELL_TOP, SHELL_BOT, PAD_TOP, PAD_BOT) * round_shade)

    # Bevel: light along the top rim, occlusion toward the bottom edge.
    rgb, alpha = over(rgb, alpha, blur(np.clip(mb - shift(mb, 5), 0, 1), 1.0),
                      np.array([152, 163, 178], np.float64), 0.42)
    rgb, alpha = over(rgb, alpha, blur(np.clip(mb - shift(mb, -30), 0, 1), 8.0),
                      np.array([4, 6, 9], np.float64), 0.34)
    # Contact line where the face turns into the extruded wall.
    rgb, alpha = over(rgb, alpha, blur(np.clip(mb - shift(mb, -3), 0, 1), 0.8),
                      np.array([0, 0, 0], np.float64), 0.55)

    # Recessed wells under every raised part.
    rgb, alpha = over(rgb, alpha, blur(msock, 1.8), SOCKET, 0.58)
    rgb, alpha = over(rgb, alpha, blur(msock_btn, 1.4), SOCKET, 0.46)

    # Raised details: side wall, then top face, then rim light.
    rgb, alpha = over(rgb, alpha, mwall, vgrad(LT_WALL_TOP, LT_WALL_BOT, PAD_TOP, PAD_BOT))
    for i, col in enumerate(BTN_COLORS):
        rgb, alpha = over(rgb, alpha, mbtn_wall[i], col * 0.52)
    for i, col in enumerate(BTN_COLORS):
        rgb, alpha = over(rgb, alpha, mbtn_top[i],
                          vgrad(np.clip(col * 1.10, 0, 255), col * 0.78, PAD_TOP, PAD_BOT))
    rgb, alpha = over(rgb, alpha, mtop, vgrad(LT_TOP, LT_BOT, PAD_TOP, PAD_BOT))
    rgb, alpha = over(rgb, alpha, blur(mconc, 1.5), LT_CONCAVE, 0.26)

    rgb, alpha = over(rgb, alpha, blur(np.clip(mtop - shift(mtop, 5), 0, 1), 1.2),
                      np.array([255, 255, 255], np.float64), 0.60)
    for i in range(4):
        rim = blur(np.clip(mbtn_top[i] - shift(mbtn_top[i], 3.5), 0, 1), 1.0)
        rgb, alpha = over(rgb, alpha, rim, np.array([255, 255, 255], np.float64), 0.50)

    rgb, alpha = over(rgb, alpha, blur(mspec, 2.0), np.array([255, 255, 255], np.float64), 0.26)
    rgb, alpha = over(rgb, alpha, blur(mbtn_spec, 1.6),
                      np.array([255, 255, 255], np.float64), 0.50)

    # Conversion mark: extruded arrowed arcs cradling the game disc.
    mr = make_mask(draw_ring)
    munit = np.clip(mr + md, 0.0, 1.0)
    foot = np.clip(munit + shift(munit, RING_EXT), 0.0, 1.0)
    rgb, alpha = over(rgb, alpha, shift(blur(foot, 10.0), 12), SHADOW, 0.30)

    rgb, alpha = over(rgb, alpha, shift(mr, RING_EXT),
                      vgrad(SIDE_TOP, SIDE_BOT, DISC_CY - RING_R - RING_W / 2,
                            DISC_CY + RING_R + RING_W / 2 + RING_EXT))
    rgb, alpha = over(rgb, alpha, shift(md, DISC_EXT),
                      vgrad(DISC_WALL, DISC_WALL_DEEP, DISC_TOP, DISC_BOT + DISC_EXT))
    rgb, alpha = over(rgb, alpha, mr,
                      vgrad(SHELL_TOP, SHELL_BOT, DISC_CY - RING_R - RING_W / 2,
                            DISC_CY + RING_R + RING_W / 2))
    rgb, alpha = over(rgb, alpha, md, disc_face_color())

    rgb, alpha = over(rgb, alpha, blur(np.clip(mr - shift(mr, 4), 0, 1), 1.0),
                      np.array([255, 255, 255], np.float64), 0.45)
    rgb, alpha = over(rgb, alpha, blur(np.clip(mr - shift(mr, -3.5), 0, 1), 0.8),
                      np.array([0, 0, 0], np.float64), 0.45)
    rgb, alpha = over(rgb, alpha, blur(np.clip(md - shift(md, 4), 0, 1), 1.0),
                      np.array([255, 255, 255], np.float64), 0.55)

    rgba = Image.fromarray(np.clip(rgb, 0, 255).astype(np.uint8), 'RGB').convert('RGBA')
    rgba.putalpha(Image.fromarray(np.clip(alpha * 255.0, 0, 255).astype(np.uint8), 'L'))
    rgba.save(os.path.join(MEDIA, 'foreground.png'), optimize=True)
    return rgba


def build_start_icon(bg, fg):
    comp = bg.convert('RGBA').copy()
    comp.alpha_composite(fg)
    size = 144
    r = int(round(size * 0.24))
    m = Image.new('L', (size * 4, size * 4), 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, size * 4 - 1, size * 4 - 1], r * 4, fill=255)
    t = comp.resize((size, size), Image.LANCZOS)
    t.putalpha(m.resize((size, size), Image.LANCZOS))
    t.save(os.path.join(MEDIA, 'startIcon.png'), optimize=True)


def build_store_icons(bg, fg):
    comp = bg.convert('RGBA').copy()
    comp.alpha_composite(fg)
    comp = comp.convert('RGB')
    comp.save(os.path.join(STORE, 'xbigod_icon_1024.png'), optimize=True)
    comp.resize((216, 216), Image.LANCZOS).save(os.path.join(STORE, 'xbigod_icon_216.png'), optimize=True)


def mirror_to_appscope():
    if not os.path.isdir(APPSCOPE):
        return
    for name in ('background.png', 'foreground.png'):
        with open(os.path.join(MEDIA, name), 'rb') as fh:
            data = fh.read()
        with open(os.path.join(APPSCOPE, name), 'wb') as fh:
            fh.write(data)


def main():
    os.makedirs(STORE, exist_ok=True)
    bg = build_background()
    fg = build_foreground()
    build_start_icon(bg, fg)
    build_store_icons(bg, fg)
    mirror_to_appscope()
    alpha = np.asarray(fg.getchannel('A'))
    ys, xs = np.nonzero(alpha > 8)
    r = np.sqrt((xs - S / 2.0) ** 2 + (ys - S / 2.0) ** 2).max()
    print('wrote background.png, foreground.png, startIcon.png, store icons')
    print('opaque bbox x %d..%d  y %d..%d' % (xs.min(), xs.max(), ys.min(), ys.max()))
    print('foreground max radius (alpha>8) = %.1f/512' % (r / 2))


if __name__ == '__main__':
    main()
