"""Части зданий Коканда: стены с поясом и зубцами, глиняные блоки с плоской крышей и
выпусками балок, айваны с резными колоннами-устунами, двери, окна-панжара, купола,
дворовые стены, мелкие предметы (тандыр, мешки, стойки оружия, пушка, колесо мельницы).

Всё в метрах, Y вверх, фасад в +Z; функции возвращают Mesh в осях здания.
"""
from __future__ import annotations

import math

import numpy as np

import gen_kokand_kit as G
import gen_kokand_ruins as R
import meshkit as K
from gen_kokand_atlas import arch_curve
from meshkit import Mesh


def q(lod, hi, lo):
    return hi if lod == 0 else lo


# ================================================================ стены

def wall_run(x0, x1, t, h, region="brick", plinth=0.7, band=None, merlons=None, inner=True, top=True, lod=0,
             band_region="tileband", inner_region=None, top_region=None):
    """Стена вдоль X (x0..x1), толщина t (z ∈ [−t/2, t/2]), наружу +Z.
    band — (y0, y1) изразцовый пояс снаружи; merlons — (шаг, ширина, высота, глубина) по наружной кромке."""
    z0, z1 = -t / 2, t / 2
    parts = []
    if plinth:
        parts.append(G.box_face("front", x0, x1, z0, z1, 0, plinth, "plinth", tile=(3.2, None)))
    yb = plinth or 0.0
    if band:
        parts.append(G.box_face("front", x0, x1, z0, z1, yb, band[0], region))
        parts.append(G.box_face("front", x0, x1, z0, z1 + 0.03, band[0], band[1], band_region, tile=(3.2, None)))
        if band[1] < h - 1e-3:
            parts.append(G.box_face("front", x0, x1, z0, z1, band[1], h, region))
    else:
        parts.append(G.box_face("front", x0, x1, z0, z1, yb, h, region))
    if inner:
        parts.append(G.box_face("back", x0, x1, z0, z1, 0, h, inner_region or region))
    if top:
        parts.append(G.box_face("top", x0, x1, z0, z1 + (0.03 if band and band[1] >= h - 1e-3 else 0), 0, h,
                                top_region or region))
    if merlons:
        step, w, mh, d = merlons
        if lod:
            step, w = step * 2.0, w * 1.3      # издали — реже и шире
        n = max(1, int((x1 - x0 - w) / step) + 1)
        span = (n - 1) * step
        xs = [(x0 + x1) / 2 - span / 2 + i * step for i in range(n)]
        for i, x in enumerate(xs):
            m = G.merlon(w, mh, d, region, arc_seg=q(lod, 5, 2), back=lod == 0, seed=i * 7 + int(x * 3))
            parts.append(m.translate(x, h, z1 - d + (0.03 if band and band[1] >= h - 1e-3 else 0)))
    return Mesh.merge(parts)


def place_run(m: Mesh, a, b) -> Mesh:
    """Переносит стену, построенную вдоль X с центром в 0, на отрезок a→b в плане (наружу — справа)."""
    a, b = np.asarray(a, float), np.asarray(b, float)
    d = b - a
    yaw = math.degrees(math.atan2(-d[1], d[0]))
    c = (a + b) / 2
    return m.rotate_y(yaw).translate(c[0], 0, c[1])


def run_between(a, b, t, h, **kw) -> Mesh:
    a, b = np.asarray(a, float), np.asarray(b, float)
    L = float(np.linalg.norm(b - a))
    return place_run(wall_run(-L / 2, L / 2, t, h, **kw), a, b)


# ================================================================ глиняный блок с крышей

def ridge(a, b, y, w=0.32, h=0.12, region="roof") -> Mesh:
    """Глиняный валик по крыше вдоль a→b (в плане), основание на высоте y: два ската."""
    a, b = np.asarray(a, float), np.asarray(b, float)
    d = b - a
    L = float(np.linalg.norm(d))
    d /= max(L, 1e-9)
    n = np.array([d[1], -d[0]])
    parts = []
    u1 = min(L / 4.0, 1.0)
    for sg in (1, -1):
        e0, e1 = a + n * sg * w / 2, b + n * sg * w / 2
        quad = G.quad((e0[0], y, e0[1]), (e1[0], y, e1[1]), (b[0], y + h, b[1]), (a[0], y + h, a[1]), region,
                      uvs=((0, 0.9), (u1, 0.9), (u1, 0.82), (0, 0.82)))
        if np.dot(quad.N[0], [n[0] * sg, 1.0, n[1] * sg]) < 0:
            quad.flip()
        parts.append(quad)
    return Mesh.merge(parts)


def roof_slab(x0, x1, z0, z1, y, thick=0.26, fascia="wood", sides=("front", "back", "left", "right"),
              beam_side="front", beam_step=0.7, lod=0, under=True, region="roof", ceiling="planks", lip=True,
              chimney=None):
    """Плоская земляная крыша на балках: верх (roof), кромка (дерево), низ свеса и выпуски балок-васса,
    глиняный валик по краю (мягкий силуэт сверху), труба-мўркон (chimney=(x, z))."""
    parts = [G.box_face("top", x0, x1, z0, z1, 0, y + thick, region)]
    for s in sides:
        parts.append(G.box_face(s, x0, x1, z0, z1, y, y + thick, fascia, tile=(2.0, None), v_span=(y, y + 2.0)))
    if under:
        parts.append(G.face((0, y, 0), (1, 0, 0), (0, 0, 1), x0, x1, ceiling, (2.0, 2.0), z0, z1))
    if beam_side and lod == 0:
        n = max(2, int((x1 - x0) / beam_step))
        for i in range(n):
            x = x0 + (i + 0.5) * (x1 - x0) / n
            if beam_side == "front":
                p0, p1 = (x, y - 0.08, z1 - 0.3), (x, y - 0.08, z1 + 0.12)
            else:
                p0, p1 = (x, y - 0.08, z0 + 0.3), (x, y - 0.08, z0 - 0.12)
            parts.append(G.pole(p0, p1, 0.08, 0.08, 5, "pole", caps=True))
    m = Mesh.merge(parts)
    topm = (m.N[:, 1] > 0.9) & (m.P[:, 1] > y + thick - 0.01)
    m.C[:] = 1.0
    m.has_color = True
    m.C[topm, :3] = 0.66
    extra = []
    yt = y + thick
    if lip and lod == 0:
        e = 0.2
        corners = [(x0 + e, z1 - e), (x1 - e, z1 - e), (x1 - e, z0 + e), (x0 + e, z0 + e)]
        for i in range(4):
            extra.append(ridge(corners[i], corners[(i + 1) % 4], yt))
    if chimney:
        cx, cz = chimney
        ch = G.box(0.45, 0.55, 0.45, {"front": "clay", "back": "clay", "left": "clay", "right": "clay",
                                      "top": "embers"})
        ch.translate(cx, yt, cz)
        top = ch.N[:, 1] > 0.9
        ch = G.white(ch)
        ch.C[top, :3] = 0.18
        extra.append(ch)
    if extra:
        ex = G.shade(Mesh.merge(extra), 0.72)
        m = Mesh.merge([m, ex])
    return m


def clay_block(x0, x1, z0, z1, h, region="clay", footing=0.35, over=(0.35, 0.15, 0.2, 0.2), lod=0,
               sides=("front", "back", "left", "right"), roof=True, beam_side="front", taper=0.0, chimney=None):
    """Дом из глины/пахсы: бутовый фундамент, стены, плоская крыша со свесом over=(перед, зад, лево, право)."""
    parts = []
    for s in sides:
        if footing:
            parts.append(G.box_face(s, x0, x1, z0, z1, 0, footing, "plinth", tile=(3.2, None), v_span=(0, 0.7),
                                    inset=0.03))
        parts.append(G.box_face(s, x0, x1, z0, z1, footing * 0.5, h, region))
    walls = Mesh.merge(parts)
    if taper:
        G.taper(walls, (x0 + x1) / 2, (z0 + z1) / 2, taper, 0, h)
    G.wall_light(walls, h, base=0.72, top=1.04)
    out = [walls]
    if roof:
        f, b, l, r = over
        out.append(roof_slab(x0 - l, x1 + r, z0 - b, z1 + f, h, lod=lod, beam_side=beam_side, chimney=chimney))
    return Mesh.merge(out)


def brick_block(x0, x1, z0, z1, h, plinth=0.6, band=None, lod=0, sides=("front", "back", "left", "right"),
                top_region="roof", parapet=0.0, merlon_side=None):
    """Кирпичный блок (казённое здание): каменный цоколь, кирпич, изразцовый пояс, плоская крыша с парапетом."""
    parts = []
    for s in sides:
        parts.append(G.box_face(s, x0, x1, z0, z1, 0, plinth, "plinth", tile=(3.2, None), v_span=(0, 0.8), inset=0.04))
        if band:
            parts.append(G.box_face(s, x0, x1, z0, z1, plinth, band[0], "brick", off=(0, -plinth)))
            parts.append(G.box_face(s, x0, x1, z0, z1, band[0], band[1], "tileband", tile=(3.2, None), inset=0.03))
            parts.append(G.box_face(s, x0, x1, z0, z1, band[1], h + parapet, "brick", off=(0, -plinth)))
        else:
            parts.append(G.box_face(s, x0, x1, z0, z1, plinth, h + parapet, "brick", off=(0, -plinth)))
    walls = Mesh.merge(parts)
    G.wall_light(walls, h + parapet, base=0.72, top=1.05)
    G.grime(walls, 0.07, seed=int(abs(x0 * 3 + z0 * 7)))
    out = [walls]
    if parapet:
        t = 0.3
        for s, (a0, a1, b0, b1) in (("front", (x0, x1, z1 - t, z1)), ("back", (x0, x1, z0, z0 + t)),
                                     ("left", (x0, x0 + t, z0, z1)), ("right", (x1 - t, x1, z0, z1))):
            inner = {"front": "back", "back": "front", "left": "right", "right": "left"}[s]
            out.append(G.box_face(inner, a0, a1, b0, b1, h, h + parapet, "brick"))
            out.append(G.box_face("top", a0, a1, b0, b1, 0, h + parapet, "brick"))
        top = G.box_face("top", x0, x1, z0, z1, 0, h, top_region)
        G.shade(top, 0.78)
        out.append(top)
        if merlon_side == "front":
            n = max(1, int((x1 - x0) / 1.0))
            for i in range(n):
                x = x0 + (i + 0.5) * (x1 - x0) / n
                out.append(G.merlon(0.48, 0.55, 0.3, "brick", arc_seg=q(lod, 5, 2), back=lod == 0, seed=i)
                           .translate(x, h + parapet, z1 - 0.3))
    else:
        top = G.box_face("top", x0, x1, z0, z1, 0, h, top_region)
        G.shade(top, 0.78)
        out.append(top)
    return Mesh.merge(out)


# ================================================================ двери, окна, колонны

def frame_strips(w, h, t=0.12, d=0.06, region="walnut"):
    """Рама проёма (косяки и перемычка) у плоскости z=0, лицом в +Z."""
    parts = []
    for x in (-w / 2 - t / 2, w / 2 + t / 2):
        parts.append(G.box(t, h + t, d, {"front": region, "left": region, "right": region, "top": region})
                     .translate(x, 0, d / 2))
    parts.append(G.box(w + 2 * t, t, d, {"front": region, "top": region, "bottom": region}).translate(0, h, d / 2))
    return Mesh.merge(parts)


def door(w=1.2, h=2.1, region="door", frame=True, step=True):
    """Дверь у плоскости z=0 (лицо +Z): полотно чуть утоплено, рама, порог-ступень."""
    parts = [G.quad((-w / 2, 0.02, 0.01), (w / 2, 0.02, 0.01), (w / 2, h, 0.01), (-w / 2, h, 0.01), region)]
    if frame:
        parts.append(frame_strips(w, h))
    if step:
        parts.append(G.box(w + 0.5, 0.14, 0.4, {"front": "stones", "top": "stones", "left": "stones",
                                                "right": "stones"}).translate(0, 0, 0.2))
    m = Mesh.merge(parts)
    return G.shade(m, lambda P: 0.75 + 0.25 * np.clip(P[:, 1] / h, 0, 1))


def window(w=0.9, h=1.0, y=1.0, region="panjara", frame=True):
    """Окно-панжара (резная решётка) у плоскости z=0, низ на высоте y."""
    parts = [G.quad((-w / 2, y, 0.015), (w / 2, y, 0.015), (w / 2, y + h, 0.015), (-w / 2, y + h, 0.015), region)]
    if frame:
        parts.append(frame_strips(w, h, 0.09, 0.05).translate(0, y, 0))
        parts.append(G.box(w + 0.3, 0.07, 0.14, {"front": "walnut", "top": "walnut"}).translate(0, y - 0.07, 0.07))
    return Mesh.merge(parts)


def ustun(h=4.0, lod=0):
    """Резная ореховая колонна-устун: пузатая база (~23% высоты), тонкий ствол, капитель-сталактит
    (~15%), сверху брусок-подбалка. Рисунок области «column» по высоте."""
    b = 0.23 * h
    c = 0.15 * h
    prof = [(0.13, 0.0), (0.19, b * 0.12), (0.215, b * 0.35), (0.17, b * 0.62), (0.115, b * 0.86), (0.1, b),
            (0.09, h - c), (0.11, h - c * 0.7), (0.16, h - c * 0.35), (0.215, h - 0.04), (0.23, h)]
    if lod:
        prof = [prof[0], prof[2], prof[4], prof[6], prof[8], prof[10]]
    m = K.lathe(prof, q(lod, 7, 5), 1.0, v_mode="height", normals="smooth")
    m.UV[:, 1] = 1.0 - m.UV[:, 1]
    G.to_region(m, "column")
    cap = G.box(0.62, 0.14, 0.34, {"front": "walnut", "back": "walnut", "left": "walnut", "right": "walnut",
                                   "top": "walnut", "bottom": "walnut"}).translate(0, h, 0)
    m = Mesh.merge([m, cap])
    return G.shade(m, lambda P: 0.8 + 0.25 * np.clip(P[:, 1] / h, 0, 1))


def iwan(x0, x1, z_back, z_front, h, n_cols, lod=0, slab=0.4, floor=0.35, back_wall=False):
    """Айван: навес на резных колоннах (ряд у переднего края), резная балка-архитрав, расписной
    потолок, плоская крыша с выпусками балок, приподнятый пол-суфа."""
    parts = []
    zc = z_front - 0.35
    xs = np.linspace(x0 + 0.5, x1 - 0.5, n_cols)
    col_h = h - floor - 0.25
    for x in xs:
        parts.append(ustun(col_h, lod).translate(x, floor, zc))
    # архитрав (резной брус орехом) и балки поперёк
    parts.append(G.beam((x0, h - 0.13, zc), (x1, h - 0.13, zc), 0.3, 0.26, "walnut", ends=True))
    if lod == 0:
        for x in xs:
            parts.append(G.beam((x, h - 0.06, z_back), (x, h - 0.06, z_front + 0.15), 0.18, 0.12, "walnut", ends=True))
    # потолок: расписные доски между балками
    ceil = G.face((0, h, 0), (1, 0, 0), (0, 0, 1), x0, x1, "ceiling", (2.0, 2.0), z_back, z_front)
    G.shade(ceil, 0.8)
    parts.append(ceil)
    parts.append(roof_slab(x0 - 0.1, x1 + 0.1, z_back, z_front + 0.3, h, slab, under=False, sides=("front", "left", "right"),
                           lod=lod))
    # суфа: приподнятый пол
    if floor:
        fl = [G.box_face("top", x0, x1, z_back, z_front, 0, floor, "stones", tile=(1.6, 1.6)),
              G.box_face("front", x0, x1, z_back, z_front, 0, floor, "plinth", tile=(3.2, None), v_span=(0, 0.8))]
        for s in ("left", "right"):
            fl.append(G.box_face(s, x0, x1, z_back, z_front, 0, floor, "plinth", tile=(3.2, None), v_span=(0, 0.8)))
        flm = Mesh.merge(fl)
        G.shade(flm, 0.85)
        parts.append(flm)
    return Mesh.merge(parts)


def guldasta(x, z, h, r=0.38, lod=0):
    """Тонкая башенка-гульдаста на углу портала: ствол, изразцовые кольца, фонарик и купол."""
    seg = q(lod, 4, 3)
    parts = [G.lathe_bands([(r * 1.15, 0.0), (r, h * 0.12)], "plinth", 2, seg, v_span=(0, 0.8)),
             G.lathe_bands([(r, h * 0.12), (r * 0.9, h * 0.82)], "brick", 2, seg, tile_h=1.6),
             G.ring_band(r * 0.95, r * 0.95, h * 0.55, h * 0.55 + 0.35, "tileband", 2, seg),
             G.ring_band(r * 1.05, r * 1.05, h * 0.82, h * 0.82 + 0.4, "tileband", 2, seg)]
    # фонарик: кольцо-балкон и купол
    parts.append(G.disc_uv(r * 1.25, 8, "brick", y=h * 0.82 + 0.4))
    import gen_kokand_fort as FO
    parts.append(FO.cupola(0, 0, h * 0.82 + 0.4, r * 0.95, lod, drum_h=0.5))
    m = Mesh.merge(parts)
    return m.translate(x, 0, z)


def round_tower(r, h, plinth=0.8, band=None, merlons=7, cupola=True, lod=0, seed=0):
    """Круглая угловая башня: цоколь, кирпич, пояс, зубцы кольцом, купол на барабане."""
    import gen_kokand_fort as FO
    tiles = 3
    seg = q(lod, 4, 3)
    b0, b1 = band or (h - 0.4, h)
    parts = [G.lathe_bands([(r + 0.08, 0.0), (r + 0.06, plinth)], "plinth", tiles, seg, v_span=(0, plinth)),
             G.ring_flat(r - 0.02, r + 0.06, plinth, seg, "stones", tiles),
             G.lathe_bands([(r, plinth), (r * 0.95, b0)], "brick", tiles, seg, tile_h=1.6, off_y=-plinth),
             G.ring_band(r * 0.97, r * 0.97, b0, b1, "tileband", tiles, seg)]
    if b1 < h - 1e-3:
        parts.append(G.lathe_bands([(r * 0.95, b1), (r * 0.95, h)], "brick", tiles, seg, tile_h=1.6))
    parts.append(G.disc_uv(r * 0.97, tiles * seg, "brick", y=h))
    if merlons:
        parts.append(FO._merlon_ring(merlons, r * 0.97, h, 0.36, 0.5, 0.62, "brick", lod, seed=seed))
    m = Mesh.merge(parts)
    G.wall_light(m, h + 0.6, base=0.72, top=1.05)
    G.grime(m, 0.07, seed=seed)
    if cupola:
        m = Mesh.merge([m, FO.cupola(0, 0, h, r * 0.55, lod, drum_h=0.55)])
    return m


# ================================================================ двор

def yard_wall(a, b, h=1.9, t=0.32, region="pakhsa", lod=0, top_region="earth"):
    w = R.Wall(a, b, h, t, region)
    m = R.wall_piece(w, top_region=top_region, lod=lod)
    G.wall_light(m, h, base=0.72, top=1.02)
    return m


def gate_canopy(x, z, w=1.5, h=2.3, lod=0, leaves=True):
    """Ворота двора (дарвозахона): два столба, перемычка, маленькая крыша, две створки."""
    parts = []
    for sx in (-1, 1):
        parts.append(G.box(0.22, h, 0.22, {"front": "walnut", "back": "walnut", "left": "walnut", "right": "walnut"})
                     .translate(sx * (w / 2 + 0.11), 0, 0))
    parts.append(G.beam((-w / 2 - 0.35, h + 0.05, 0), (w / 2 + 0.35, h + 0.05, 0), 0.2, 0.18, "walnut"))
    parts.append(roof_slab(-w / 2 - 0.5, w / 2 + 0.5, -0.45, 0.45, h + 0.14, 0.18, beam_side=None, lod=lod))
    if leaves:
        for sx, mir in ((-1, False), (1, True)):
            uvs = ((1, 1), (0, 1), (0, 0), (1, 0)) if mir else ((0, 1), (1, 1), (1, 0), (0, 0))
            x0, x1 = (-w / 2, 0.0) if sx < 0 else (0.0, w / 2)
            f = G.quad((x0, 0.05, 0.02), (x1, 0.05, 0.02), (x1, h - 0.05, 0.02), (x0, h - 0.05, 0.02), "gate", uvs=uvs)
            parts.append(f)
            parts.append(f.copy().flip().translate(0, 0, -0.04))
    m = Mesh.merge(parts)
    return G.shade(m, lambda P: 0.78 + 0.22 * np.clip(P[:, 1] / h, 0, 1)).translate(x, 0, z)


def ground_patch(x0, x1, z0, z1, region="earth", y=0.02, shade_k=0.62, tile=None):
    """Утоптанная земля двора (узел Ground*: без тени)."""
    m = G.face((0, y, 0), (1, 0, 0), (0, 0, -1), x0, x1, region, tile, -z1, -z0)
    return G.shade(m, shade_k)


def tandyr(lod=0):
    """Тандыр: глиняная печь-купол с отверстием сверху, на подставке."""
    seg = q(lod, 10, 6)
    base = G.box(1.2, 0.35, 1.2, {"front": "clay", "back": "clay", "left": "clay", "right": "clay", "top": "clay"})
    body = K.lathe([(0.55, 0.0), (0.58, 0.35), (0.5, 0.75), (0.3, 1.0), (0.22, 1.05)], seg, 1.0)
    G.to_region(body, "clay")
    hole = G.disc_uv(0.21, seg, "embers", y=1.0)
    G.shade(hole, 0.25)
    m = Mesh.merge([base, body.translate(0, 0.35, 0), hole.translate(0, 0.35, 0)])
    return G.ground_ao(m, 0.4, 0.3)


def weapon_rack(n=6, lod=0, seed=0):
    """Стойка с копьями и мушкетами: две стойки, две перекладины, прислонённое оружие."""
    rs = np.random.default_rng(abs(int(seed)))
    L = 2.4
    parts = []
    for x in (-L / 2, L / 2):
        parts.append(G.pole((x, 0, 0), (x, 1.5, 0), 0.06, sides=4, region="wood"))
    for y in (0.5, 1.35):
        parts.append(G.pole((-L / 2, y, 0), (L / 2, y, 0), 0.04, sides=4, region="wood"))
    for i in range(n if lod == 0 else n // 2):
        x = -L / 2 + 0.2 + i * (L - 0.4) / max(n - 1, 1)
        lean = rs.uniform(0.25, 0.35)
        top = (x + rs.uniform(-0.05, 0.05), 2.4 + rs.uniform(-0.1, 0.2), -lean)
        parts.append(G.pole((x, 0, 0.35), top, 0.025, sides=3, region="walnut"))
        tip = np.asarray(top) + (np.asarray(top) - np.array([x, 0, 0.35])) * 0.1
        parts.append(G.pole(top, tuple(tip), 0.03, 0.002, sides=3, region="iron"))
    return G.ground_ao(Mesh.merge(parts), 0.3, 0.3)


def wheel(radius, width, lod=0, spokes=8, paddles=0, region="wood"):
    """Колесо в плоскости YZ (ось вдоль X), центр в начале: обода, спицы, ступица, лопасти."""
    seg = q(lod, 16, 10)
    parts = []
    for sx in (-1, 1):
        x = sx * width / 2
        rim = K.lathe([(radius, -0.05), (radius, 0.05), (radius - 0.14, 0.05), (radius - 0.14, -0.05), (radius, -0.05)],
                      seg, 1.0, normals="crease")
        G.to_region(rim, region)
        rim.rotate_z(-90).translate(x, 0, 0)
        parts.append(rim)
        for k in range(spokes if lod == 0 else spokes // 2):
            a = 2 * math.pi * k / spokes
            d = np.array([0, math.cos(a), math.sin(a)])
            parts.append(G.pole(d * 0.15 + [x, 0, 0], d * (radius - 0.1) + [x, 0, 0], 0.04, sides=4, region=region))
    hub = K.lathe([(0.16, -width / 2 - 0.1), (0.16, width / 2 + 0.1)], q(lod, 8, 5), 1.0, cap_bottom=True, cap_top=True)
    G.to_region(hub, "walnut")
    hub.rotate_z(-90)
    parts.append(hub)
    for k in range(paddles if lod == 0 else paddles // 2):
        a = 2 * math.pi * (k + 0.5) / paddles
        d = np.array([0, math.cos(a), math.sin(a)])
        t = np.array([0, -math.sin(a), math.cos(a)])
        c = d * (radius - 0.05)
        p0 = c - [width / 2, 0, 0] - d * 0.25
        p1 = c + [width / 2, 0, 0] - d * 0.25
        p2 = c + [width / 2, 0, 0] + d * 0.12
        p3 = c - [width / 2, 0, 0] + d * 0.12
        pad = G.quad(p0, p1, p2, p3, "planks", uvs=((0, 1), (0.5, 1), (0.5, 0.8), (0, 0.8)), two_sided=True)
        parts.append(pad.translate(*(t * 0.0)))
    return Mesh.merge(parts)


def cannon(lod=0):
    """Зарбзан на лафете: бронзовый ствол, два колеса, хобот лафета (смотрит в +Z)."""
    parts = []
    barrel = K.lathe([(0.22, 0.0), (0.24, 0.12), (0.2, 0.2), (0.19, 0.9), (0.165, 1.6), (0.15, 2.1), (0.19, 2.18),
                      (0.19, 2.3), (0.09, 2.31)], q(lod, 10, 6), 1.0, v_mode="height", normals="smooth")
    barrel.UV[:, 1] = 1 - barrel.UV[:, 1]
    G.to_region(barrel, "bronze")
    knob = K.ellipsoid(0.11, 0.11, 0.11, 6, 3).translate(0, -0.08, 0)
    G.to_region(knob, "bronze")
    b = Mesh.merge([barrel, knob]).rotate_x(84).translate(0, 0.98, -0.75)
    parts.append(b)
    # лафет: две щеки и хобот
    for sx in (-1, 1):
        parts.append(G.beam((sx * 0.24, 0.95, -0.9), (sx * 0.2, 0.15, -2.4), 0.1, 0.28, "walnut"))
    parts.append(G.beam((0, 0.85, -0.6), (0, 0.85, 0.2), 0.5, 0.12, "walnut"))
    parts.append(G.pole((-0.75, 0.75, -0.6), (0.75, 0.75, -0.6), 0.06, sides=6, region="iron"))
    for sx in (-1, 1):
        parts.append(wheel(0.75, 0.12, lod, spokes=10, region="wood").translate(sx * 0.62, 0.75, -0.6))
    return G.ground_ao(Mesh.merge(parts), 0.3, 0.3)


def ball_pyramid(rows=3, r=0.13, lod=0):
    """Пирамида ядер."""
    parts = []
    for k in range(rows):
        n = rows - k
        for i in range(n):
            for j in range(n):
                x = (i - (n - 1) / 2) * 2 * r
                z = (j - (n - 1) / 2) * 2 * r
                y = r + k * r * 1.41
                s = K.ellipsoid(r, r, r, q(lod, 6, 4), q(lod, 4, 3)).translate(x, y, z)
                s.UV = np.column_stack([0.5 + s.P[:, 0] * 0.0 + (s.N[:, 0] * 0.4), 0.5 - s.N[:, 1] * 0.4])
                parts.append(G.to_region(s, "iron"))
    return G.ground_ao(Mesh.merge(parts), 0.25, 0.3)


def barrel(r=0.3, h=0.8, lod=0):
    b = K.lathe([(r * 0.88, 0.0), (r, h * 0.5), (r * 0.88, h)], q(lod, 8, 5), 1.0, cap_top=True)
    G.to_region(b, "planks")
    hoops = [G.ring_band(r * 0.92, r * 0.92, y, y + 0.05, "iron", 1, q(lod, 8, 5)) for y in (0.12, h - 0.17)]
    return G.ground_ao(Mesh.merge([b] + (hoops if lod == 0 else [])), 0.2, 0.3)


def trough(L=2.0, lod=0):
    """Каменная колода с водой (узел Water — отдельно)."""
    box = G.box(L, 0.55, 0.7, {"front": "stones", "back": "stones", "left": "stones", "right": "stones",
                               "top": "stones"})
    water = G.quad((-L / 2 + 0.1, 0.5, 0.25), (L / 2 - 0.1, 0.5, 0.25), (L / 2 - 0.1, 0.5, -0.25),
                   (-L / 2 + 0.1, 0.5, -0.25), "water", uvs=((0, 1), (1, 1), (1, 0.6), (0, 0.6)))
    return G.ground_ao(box, 0.3, 0.3), water


def hitching_rail(L=4.0, lod=0):
    parts = []
    n = 3
    for i in range(n):
        x = -L / 2 + i * L / (n - 1)
        parts.append(G.pole((x, 0, 0), (x, 1.15, 0), 0.08, 0.07, 5, "bark"))
    parts.append(G.pole((-L / 2 - 0.1, 1.05, 0), (L / 2 + 0.1, 1.05, 0), 0.05, sides=5, region="pole"))
    return G.ground_ao(Mesh.merge(parts), 0.3, 0.3)


def pergola(x0, x1, z0, z1, h=2.3, lod=0):
    """Навес-сўри для винограда: столбы, балки, частые жерди."""
    parts = []
    for x in (x0, x1):
        for z in (z0, z1):
            parts.append(G.pole((x, 0, z), (x, h, z), 0.07, sides=5, region="bark"))
    for z in (z0, z1):
        parts.append(G.pole((x0 - 0.2, h, z), (x1 + 0.2, h, z), 0.06, sides=4, region="bark"))
    for x in np.linspace(x0, x1, q(lod, 6, 3)):
        parts.append(G.pole((x, h + 0.08, z0 - 0.2), (x, h + 0.08, z1 + 0.2), 0.035, sides=3, region="pole"))
    return Mesh.merge(parts)


def carpet_supa(x, z, w=2.0, d=1.4, h=0.45, yaw=0.0):
    """Суфа (глиняный помост) с ковром."""
    base = G.box(w, h, d, {"front": "clay", "back": "clay", "left": "clay", "right": "clay", "top": "clay"})
    rug = G.quad((-w / 2 + 0.1, h + 0.01, d / 2 - 0.1), (w / 2 - 0.1, h + 0.01, d / 2 - 0.1),
                 (w / 2 - 0.1, h + 0.01, -d / 2 + 0.1), (-w / 2 + 0.1, h + 0.01, -d / 2 + 0.1), "carpet")
    m = Mesh.merge([G.ground_ao(base, 0.3, 0.3), G.shade(rug, 0.85)])
    return G.place(m, x, 0, z, yaw)


def jug(x, z, s=1.0, lod=0):
    m = K.lathe([(0.1, 0.0), (0.2, 0.15), (0.22, 0.3), (0.12, 0.5), (0.07, 0.6), (0.09, 0.66)], q(lod, 8, 5), 1.0,
                v_mode="height")
    m.UV[:, 1] = 1 - m.UV[:, 1]
    G.to_region(m, "pottery")
    return G.ground_ao(m.scale(s).translate(x, 0, z), 0.2, 0.3)


def hay_lump(x, z, s=1.0, seed=0, lod=0, y=0.0):
    m = G.lump(1.0 * s, 0.8 * s, 0.85 * s, q(lod, 9, 6), q(lod, 4, 3), "hay", seed=seed, amount=0.15)
    return G.ground_ao(m.translate(x, y, z), 0.35, 0.3, y0=y)
