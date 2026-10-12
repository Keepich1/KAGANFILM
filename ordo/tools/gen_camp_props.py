"""Туг, загоны, арба и мелкие предметы лагеря кыпчаков.

JOBS: имя → функция(lod) → узлы glb [(имя узла, Mesh, вид материала)].
Вид материала: "opaque" — атлас; "cloth" — вырез по альфе, двусторонний
(ткань, в сцене — cloth.gdshader); "cutout" — вырез, односторонний (пятно земли).

Соглашения ТЗ 11.6: метры, Y вверх, фасад/вход в +Z, начало — центр основания.
"""
from __future__ import annotations

import math

import numpy as np

import gen_camp_kit as G
import meshkit as K
from meshkit import Mesh


def _q(lod, hi, lo):
    return hi if lod == 0 else lo


# ================================================================ туг

def tug(lod=0):
    """Высокое древко (~8.6 м) с трезубцем, конским хвостом и вымпелом с волнистым краем
    на каменной подсыпке с растяжками. Вымпел — узел «Pennant» (колышется в cloth.gdshader)."""
    sides = _q(lod, 8, 5)
    H = 8.4
    parts = [G.pole((0, 0, 0), (0, H, 0), 0.07, 0.045, sides=sides, region="pole")]
    # каменная подсыпка и колышки
    rs = np.random.default_rng(7)
    n_st = _q(lod, 9, 5)
    for i in range(n_st):
        a = i / n_st * 2 * math.pi + rs.uniform(-0.2, 0.2)
        r = rs.uniform(0.32, 0.55)
        st = G.lump(rs.uniform(0.18, 0.28), rs.uniform(0.12, 0.22), rs.uniform(0.16, 0.26), _q(lod, 7, 5), 3,
                    "stones", seed=i, amount=0.18)
        st.rotate_y(math.degrees(a)).translate(r * math.sin(a), 0, r * math.cos(a))
        parts.append(G.ground_ao(st, 0.2, 0.35))
    top = G.lump(0.3, 0.22, 0.3, _q(lod, 8, 5), 3, "stones", seed=21, amount=0.15)
    parts.append(G.ground_ao(top, 0.25, 0.3))
    # латунное яблоко и обмотка под трезубцем
    ball = K.ellipsoid(0.1, 0.09, 0.1, _q(lod, 8, 6), 4).translate(0, H + 0.02, 0)
    parts.append(G.to_region(ball, "brass"))
    # трезубец: средний зуб прямой, боковые изогнуты наружу и вверх
    prong_r = 0.022
    mid = [(0, H + 0.08, 0), (0, H + 0.5, 0), (0, H + 0.95, 0)]
    parts.append(_spike(mid, prong_r * 1.2, "brass", _q(lod, 4, 3)))
    for sx in (-1, 1):
        path = [(0, H + 0.12, 0), (sx * 0.16, H + 0.16, 0), (sx * 0.27, H + 0.3, 0), (sx * 0.29, H + 0.52, 0),
                (sx * 0.25, H + 0.72, 0)]
        parts.append(_spike(path, prong_r, "brass", _q(lod, 4, 3)))
    cross = G.pole((-0.2, H + 0.13, 0), (0.2, H + 0.13, 0), 0.025, sides=4, region="brass")
    parts.append(cross)
    # конский хвост (туг): пучок волоса вокруг древка под яблоком
    hair = K.lathe([(0.05, -1.25), (0.2, -1.0), (0.22, -0.55), (0.15, -0.15), (0.07, 0.0)], _q(lod, 10, 6), 1.0,
                   normals="smooth")
    hair.UV[:, 1] = 1 - hair.UV[:, 1]
    G.to_region(hair, "hair")
    G.radial_warp(hair, lambda th, y, r: 1 + 0.12 * np.sin(np.radians(th) * 5 + y * 4) * np.clip(-y, 0, 1))
    hair.translate(0, H - 0.06, 0)
    parts.append(hair)
    wrap = K.lathe([(0.06, 0.0), (0.075, 0.06), (0.06, 0.14)], _q(lod, 8, 6), 1.0).translate(0, H - 0.08, 0)
    G.to_region(wrap, "tassel", inset=2)
    wrap.UV[:, 1] = np.clip(wrap.UV[:, 1], 0, G.atlas_uv("tassel")[1] + 0.02)
    parts.append(wrap)
    # растяжки к колышкам
    if lod == 0:
        for k in range(3):
            a = math.radians(30 + k * 120)
            peg = (2.3 * math.sin(a), 0.0, 2.3 * math.cos(a))
            parts.append(G.path_tube([(0, 4.6, 0), (peg[0], 0.25, peg[2])], 0.012, sides=3, region="rope",
                                     tile_len=6.0))
            parts.append(G.pole(peg, (peg[0] * 0.97, 0.35, peg[2] * 0.97), 0.03, 0.02, sides=4, region="wood"))
    for p in parts:
        if not p.has_color:
            G.white(p)
    # вымпел: полотно 3.2 × 0.95 м от древка вдоль +X, верх под конским хвостом
    pen = pennant(3.2, 0.95, _q(lod, 16, 8), _q(lod, 3, 1)).translate(0.05, H - 1.45 - 0.95, 0)
    return [("Tug", Mesh.merge(parts), "opaque"), ("Pennant", G.white(pen), "cloth")]


def pennant(w, h, nx, ny):
    """Полотно вымпела: сетка в плоскости XY от x=0 (у древка); UV — область «pennant»,
    UV2.x — доля длины (размах колыхания), UV2.y — доля сверху вниз."""
    m = K.grid(w, h, nx, ny)
    s = m.P[:, 0] / w
    q = 1 - m.P[:, 1] / h
    m.UV = np.column_stack([s, q])
    m.UV2 = np.column_stack([s, q])
    m.has_uv2 = True
    return G.to_region(m, "pennant")


def _spike(path, r, region, sides):
    path = np.asarray(path, float)
    n = len(path)
    radii = np.linspace(r, r * 0.25, n)
    radii[-1] = 0.002
    m = K.tube(path, radii, sides=sides, uv_len=1.0)
    m.UV[:, 1] = np.clip(m.UV[:, 1], 0, 1)
    return G.to_region(m, region)


# ================================================================ ограды

def wattle_panel(a, b, h, lod=0, lean=0.0):
    """Звено плетня между точками a и b (на земле): две грани (наружу и внутрь) и верх."""
    a, b = np.asarray(a, float), np.asarray(b, float)
    d = b - a
    L = np.linalg.norm(d)
    d /= L
    n = np.array([-d[2], 0.0, d[0]])
    th = 0.09
    parts = []
    u1 = L / 3.0  # область плетня ~3 м по ширине
    for sgn in (1, -1):
        o = n * th / 2 * sgn
        p0, p1 = a + o, b + o
        top0 = p0 + np.array([0, h, 0]) + n * lean
        top1 = p1 + np.array([0, h, 0]) + n * lean
        if sgn > 0:
            q = G.quad(p0, p1, top1, top0, "wattle", uvs=((0, 1), (u1, 1), (u1, 0), (0, 0)))
        else:
            q = G.quad(p1, p0, top0, top1, "wattle", uvs=((0, 1), (u1, 1), (u1, 0), (0, 0)))
        parts.append(q)
    top = G.quad(a - n * th / 2 + [0, h, 0] + n * lean, b - n * th / 2 + [0, h, 0] + n * lean,
                 b + n * th / 2 + [0, h, 0] + n * lean, a + n * th / 2 + [0, h, 0] + n * lean, "bark")
    if np.dot(top.N[0], [0, 1, 0]) < 0:
        top.flip()
    parts.append(top)
    m = Mesh.merge(parts)
    return G.ground_ao(m, 0.5, 0.35)


def rounded_rect(wx, wz, r, n_side, gap=None):
    """Точки периметра скруглённого прямоугольника (против часовой сверху), начиная у входа (+Z).
    gap — (ширина) проём в середине стороны +Z: возвращает список отрезков-ломаных."""
    pts = []
    hx, hz = wx / 2 - r, wz / 2 - r
    corners = [(hx, hz, 0), (hx, -hz, 90), (-hx, -hz, 180), (-hx, hz, 270)]
    # обход: от середины +Z стороны к +X, по часовой если смотреть сверху (x вправо, z вниз)
    path = []
    path.append((0.0, wz / 2))
    for cx, cz, a0 in corners:
        for k in range(n_side + 1):
            a = math.radians(a0 + 90 * k / n_side)
            path.append((cx + r * math.sin(a), cz + r * math.cos(a)))
    path.append((0.0, wz / 2))
    path = np.array(path)
    if gap is None:
        return [path]
    # разрезаем у входа
    L = np.r_[0, np.cumsum(np.linalg.norm(np.diff(path, axis=0), axis=1))]
    total = L[-1]
    s0, s1 = gap / 2, total - gap / 2
    keep = [np.array([np.interp(s0, L, path[:, 0]), np.interp(s0, L, path[:, 1])])]
    for i in range(len(path)):
        if s0 < L[i] < s1:
            keep.append(path[i])
    keep.append(np.array([np.interp(s1, L, path[:, 0]), np.interp(s1, L, path[:, 1])]))
    return [np.array(keep)]


def resample(poly, step):
    poly = np.asarray(poly, float)
    L = np.r_[0, np.cumsum(np.linalg.norm(np.diff(poly, axis=0), axis=1))]
    n = max(1, int(round(L[-1] / step)))
    s = np.linspace(0, L[-1], n + 1)
    return np.column_stack([np.interp(s, L, poly[:, 0]), np.interp(s, L, poly[:, 1])])


def koroo(lod=0):
    """Короо — загон для овец 14×14 м: плетень на кольях, ворота (вход в +Z), колода,
    сено, вытоптанная земля. Середина свободна для отары."""
    rs = np.random.default_rng(31)
    parts = []
    gap = 2.8
    for poly in rounded_rect(13.2, 13.2, 3.0, _q(lod, 3, 2), gap=gap):
        pts = resample(poly, _q(lod, 1.7, 2.6))
        for i in range(len(pts) - 1):
            a = (pts[i][0], 0, pts[i][1])
            b = (pts[i + 1][0], 0, pts[i + 1][1])
            h = 1.05 + rs.uniform(-0.08, 0.06)
            parts.append(wattle_panel(a, b, h, lod, lean=rs.uniform(-0.04, 0.04)))
        for i, p in enumerate(pts):  # колья выше плетня
            top = 1.3 + rs.uniform(-0.1, 0.15)
            parts.append(G.ground_ao(G.pole((p[0], 0, p[1]), (p[0] + rs.uniform(-0.04, 0.04), top,
                                                               p[1] + rs.uniform(-0.04, 0.04)),
                                            0.055, 0.04, sides=_q(lod, 5, 4), region="bark"), 0.4, 0.3))
    # ворота: два толстых столба и створка из жердей, приоткрыта внутрь
    zg = 6.6
    for sx in (-1, 1):
        parts.append(G.ground_ao(G.pole((sx * gap / 2, 0, zg), (sx * gap / 2, 1.55, zg), 0.09, 0.075,
                                        sides=_q(lod, 6, 4), region="bark"), 0.4, 0.3))
    gate = []
    gw = gap - 0.2
    for y in (0.3, 0.65, 1.0):
        gate.append(G.pole((0, y, 0), (gw, y + 0.02, 0), 0.035, sides=4, region="pole"))
    for x in (0.05, gw * 0.5, gw - 0.05):
        gate.append(G.pole((x, 0.15, 0), (x, 1.12, 0), 0.03, sides=4, region="pole"))
    gate.append(G.pole((0.05, 0.3, 0), (gw - 0.05, 1.0, 0), 0.03, sides=4, region="pole"))
    gm = Mesh.merge(gate).rotate_y(-35).translate(-gap / 2 + 0.05, 0, zg)
    parts.append(gm)
    # колода-поилка у стены
    parts.append(trough(2.4, lod).rotate_y(90).translate(-4.9, 0, -1.0))
    # сено у стены
    for (x, z, s) in ((4.4, -4.4, 1.0), (3.2, -5.0, 0.7), (-4.6, 4.2, 0.6)):
        parts.append(G.ground_ao(G.lump(0.9 * s, 0.55 * s, 0.75 * s, _q(lod, 9, 6), _q(lod, 4, 3), "hay",
                                        seed=int(x * 10), amount=0.2).translate(x, 0, z), 0.3, 0.3))
    for i in range(_q(lod, 10, 4)):
        x, z = rs.uniform(-5, 5), rs.uniform(-5, 5)
        parts.append(G.lump(0.25, 0.08, 0.2, 5, 2, "hay", seed=100 + i, amount=0.25)
                     .rotate_y(rs.uniform(0, 360)).translate(x, 0, z))
    for p in parts:
        if not p.has_color:
            G.white(p)
    ground = earth_patch(7.4, 7.0, lod)
    return [("Koroo", Mesh.merge(parts), "opaque"), ("Ground", G.white(ground), "cutout")]


def earth_patch(rx, rz, lod=0, y=0.03):
    """Пятно вытоптанной земли (рваный край — по альфе атласа)."""
    seg = _q(lod, 16, 10)
    m = K.disc(1.0, seg)
    # кольцо посередине, чтобы пятно ложилось на неровную землю мягче
    inner = K.disc(0.55, seg)
    m = K.lathe([(1.0, 0.0), (0.55, 0.0), (0.0, 0.0)], seg, 1.0)
    m.P[:, 0] *= rx
    m.P[:, 2] *= rz
    m.N[:] = (0, 1, 0)
    m.UV = np.column_stack([0.5 + m.P[:, 0] / (2 * rx), 0.5 + m.P[:, 2] / (2 * rz)])
    if m.N[:, 1].mean() < 0:
        m.flip()
    fn = np.cross(m.P[m.F[0, 1]] - m.P[m.F[0, 0]], m.P[m.F[0, 2]] - m.P[m.F[0, 0]])
    if fn[1] < 0:
        m.F = m.F[:, ::-1].copy()
    del inner
    return G.to_region(m.translate(0, y, 0), "earth")


def trough(length, lod=0):
    """Колода: выдолбленное бревно, внутри вода."""
    seg = _q(lod, 8, 5)
    r = 0.24
    outer = K.lathe([(r, 0.0), (r * 1.03, length * 0.5), (r, length)], seg, 1.0, sweep=200, start=-10,
                    normals="smooth")
    G.to_region(outer, "bark")
    outer.rotate_z(-90).translate(-length / 2, 0, 0)
    # outer — полукруглое бревно вдоль X, срез вверх; поднимаем, чтобы стояло на земле
    water = G.quad((-length / 2 + 0.08, 0.0, -r * 0.8), (length / 2 - 0.08, 0.0, -r * 0.8),
                   (length / 2 - 0.08, 0.0, r * 0.8), (-length / 2 + 0.08, 0.0, r * 0.8), "trough_in")
    if water.N[0][1] < 0:
        water.flip()
    water.translate(0, -0.05, 0)
    ends = []
    for sx in (-1, 1):
        e = G.disc_uv(r, seg, "logend")
        e.rotate_z(-90 * sx).translate(sx * length / 2, 0, 0)
        ends.append(e)
    m = Mesh.merge([outer, water] + ends)
    lo = m.P[:, 1].min()
    m.translate(0, -lo, 0)
    return G.ground_ao(m, 0.3, 0.3)


def jylky(lod=0):
    """Жылкы короосу — конный двор 16×12 м: изгородь из жердей, коновязь (кермé) между
    столбами, сёдла с чепраками на жердях, колода с водой. Вход — проём в +Z."""
    rs = np.random.default_rng(41)
    parts = []
    gap = 3.4
    for poly in rounded_rect(15.4, 11.4, 1.6, _q(lod, 2, 1), gap=gap):
        pts = resample(poly, _q(lod, 2.4, 3.6))
        for i, p in enumerate(pts):
            top = 1.45 + rs.uniform(-0.08, 0.12)
            parts.append(G.ground_ao(G.pole((p[0], 0, p[1]), (p[0], top, p[1]), 0.07, 0.055,
                                            sides=_q(lod, 5, 4), region="bark"), 0.4, 0.3))
        for y in ((0.6, 1.2) if lod == 0 else (1.0,)):
            for i in range(len(pts) - 1):
                a = (pts[i][0], y + rs.uniform(-0.04, 0.04), pts[i][1])
                b = (pts[i + 1][0], y + rs.uniform(-0.04, 0.04), pts[i + 1][1])
                parts.append(G.pole(a, b, 0.04, sides=_q(lod, 5, 3), region="pole"))
    # коновязь: два столба с развилкой и натянутая верёвка
    for x in (-4.8, 4.8):
        parts.append(G.ground_ao(G.pole((x, 0, -1.2), (x, 2.1, -1.2), 0.09, 0.07, sides=_q(lod, 6, 4),
                                        region="bark"), 0.4, 0.3))
    rope = [(-4.8, 1.85, -1.2), (-2.4, 1.72, -1.2), (0, 1.68, -1.2), (2.4, 1.72, -1.2), (4.8, 1.85, -1.2)]
    parts.append(G.path_tube(rope, 0.025, sides=4, region="rope", tile_len=10.0))
    # сёдла с чепраками на жердях изгороди (задняя сторона)
    for k, x in enumerate((-4.5, -2.6, 2.2) if lod == 0 else (-4.5, 2.2)):
        sd = saddle(lod, seed=k).translate(x, 1.2, -5.65)
        parts.append(sd)
    parts.append(trough(2.8, lod).translate(4.2, 0, 4.1))
    parts.append(G.ground_ao(G.lump(0.8, 0.5, 0.7, _q(lod, 9, 6), _q(lod, 4, 3), "hay", seed=5, amount=0.2)
                             .translate(-6.0, 0, 3.6), 0.3, 0.3))
    for p in parts:
        if not p.has_color:
            G.white(p)
    ground = earth_patch(8.2, 6.4, lod)
    return [("Jylky", Mesh.merge(parts), "opaque"), ("Ground", G.white(ground), "cutout")]


def saddle(lod=0, seed=0):
    """Седло с чепраком, перекинутое через жердь (жердь вдоль X на y=0). Начало — на жерди."""
    rs = np.random.default_rng(seed)
    parts = []
    # чепрак: полотно, свисающее по обе стороны жерди
    nx, nz = _q(lod, 4, 2), _q(lod, 6, 3)
    w, d = 0.9, 1.25
    P, UV, F = [], [], []
    for j in range(nz + 1):
        q = j / nz
        for i in range(nx + 1):
            s = i / nx
            ang = (q - 0.5) * math.pi * 0.95
            z = math.sin(ang) * 0.42
            y = math.cos(ang) * 0.12 - abs(q - 0.5) ** 1.3 * 0.75
            P.append(((s - 0.5) * w, y + 0.02, z))
            UV.append((s, q))
    for j in range(nz):
        for i in range(nx):
            a = j * (nx + 1) + i
            b = a + nx + 1
            F += [(a, a + 1, b + 1), (a, b + 1, b)]
    cloth = Mesh(P, F, None, UV)
    if cloth.N[(nz // 2) * (nx + 1) + nx // 2][1] < 0:
        cloth.flip()
    G.to_region(cloth, "saddlecloth")
    parts.append(cloth)
    parts.append(cloth.copy().flip())
    # само седло: кожаная подушка и высокая передняя лука
    seat = K.ellipsoid(0.3, 0.11, 0.24, _q(lod, 8, 5), 3, y_from=0.0).translate(0, 0.12, 0)
    seat.UV = np.column_stack([0.5 + seat.P[:, 0], 0.5 + seat.P[:, 2]])
    parts.append(G.to_region(seat, "leather"))
    for xx, hh in ((0.26, 0.24), (-0.25, 0.14)):
        horn = G.pole((xx, 0.15, 0), (xx * 1.15, 0.15 + hh, 0), 0.07, 0.05, sides=_q(lod, 6, 4), region="leather")
        parts.append(horn)
    m = Mesh.merge(parts)
    m.rotate_y(rs.uniform(-8, 8))
    return m


# ================================================================ арба

def wheel(radius, lod=0):
    """Большое колесо арбы (в плоскости YZ, ось вдоль X): обод, ступица, спицы."""
    seg = _q(lod, 18, 10)
    w = 0.09
    rim = K.lathe([(radius - 0.07, -w), (radius, -w), (radius, w), (radius - 0.07, w), (radius - 0.07, -w)], seg,
                  1.0, normals="crease")
    G.to_region(rim, "wood")
    rim.rotate_z(-90)
    parts = [rim]
    hub = K.lathe([(0.06, -0.22), (0.13, -0.14), (0.14, 0.14), (0.06, 0.22)], _q(lod, 8, 5), 1.0)
    G.to_region(hub, "walnut")
    hub.rotate_z(-90)
    parts.append(hub)
    n_sp = _q(lod, 12, 8)
    for k in range(n_sp):
        a = 2 * math.pi * k / n_sp
        d = np.array([0, math.cos(a), math.sin(a)])
        parts.append(G.pole(d * 0.12, d * (radius - 0.05), 0.03, 0.025, sides=_q(lod, 4, 3), region="wood"))
    return Mesh.merge(parts)


def arba(lod=0):
    """Арба с двумя большими колёсами, гружённая свёрнутой юртой (көч): рулоны войлока
    вдоль арбы (спирали торцов видны спереди и сзади), связка решётки-кереге, жерди уука
    торчат назад, тюндюк стоит наклонно сзади. Оглобли — в +Z, лежат на земле."""
    parts = []
    R = 0.85
    bed_y = 1.0
    L, W = 2.5, 1.45
    zc = -0.15
    for sx in (-1, 1):
        parts.append(wheel(R, lod).translate(sx * (W / 2 + 0.2), R, zc))
    parts.append(G.pole((-(W / 2 + 0.3), R, zc), (W / 2 + 0.3, R, zc), 0.06, sides=_q(lod, 6, 4), region="walnut"))
    bed = G.box(W, 0.1, L, {"top": "planks", "front": "wood", "back": "wood", "left": "wood", "right": "wood"})
    parts.append(bed.translate(0, bed_y, zc))
    for sx in (-1, 1):  # борта: стойки и верхняя жердь
        parts.append(G.pole((sx * W / 2, bed_y + 0.42, zc - L / 2), (sx * W / 2, bed_y + 0.42, zc + L / 2), 0.035,
                            sides=4, region="pole"))
        for z in (-L / 2 + 0.08, 0.0, L / 2 - 0.08):
            parts.append(G.pole((sx * W / 2, bed_y, zc + z), (sx * W / 2, bed_y + 0.46, zc + z), 0.03, sides=4,
                                region="pole"))
    # оглобли: от передка вперёд и вниз, концы лежат на земле
    front = zc + L / 2
    for sx in (-1, 1):
        parts.append(G.pole((sx * 0.5, bed_y - 0.02, zc - L / 2 + 0.3), (sx * 0.36, 0.08, front + 1.9), 0.055, 0.04,
                            sides=_q(lod, 5, 4), region="pole"))
    parts.append(G.pole((-0.47, bed_y - 0.25, front + 0.45), (0.47, bed_y - 0.25, front + 0.45), 0.035, sides=4,
                        region="pole"))
    # груз: три рулона войлока вдоль арбы, второй ярус — ещё два
    top = bed_y + 0.1
    rolls = [(-0.45, 0.27, "felt_white"), (0.0, 0.29, "koshma"), (0.45, 0.27, "felt_grey")]
    for x, r, reg in rolls:
        parts.append(felt_roll(L - 0.1, r, reg, lod).rotate_y(90).translate(x, top + r, zc))
    for x, r, reg in ((-0.24, 0.25, "felt_grey"), (0.24, 0.25, "felt_white")):
        parts.append(felt_roll(L - 0.4, r, reg, lod).rotate_y(90).translate(x, top + 0.5 + r, zc + 0.1))
    # связка решётки-кереге сверху и жерди уука, торчащие назад
    lat = G.box(0.62, 0.3, 2.2, {"top": "lattice", "front": "lattice", "back": "lattice", "left": "lattice",
                                  "right": "lattice"})
    parts.append(lat.rotate_y(3).translate(0.05, top + 0.98, zc + 0.15))
    rs = np.random.default_rng(3)
    n_poles = _q(lod, 8, 4)
    for k in range(n_poles):
        x = -0.3 + 0.6 * k / max(n_poles - 1, 1)
        y = top + 1.32 + rs.uniform(-0.03, 0.05)
        parts.append(G.pole((x * 0.5, y, zc + 1.0), (x, y - 0.25, zc - 3.0 + rs.uniform(-0.2, 0.2)), 0.026, 0.02,
                            sides=3, region="pole"))
    # тюндюк стоит наклонно у заднего борта
    tun = K.lathe([(0.6, 0.0), (0.6, 0.1), (0.48, 0.12), (0.48, 0.0)], _q(lod, 14, 8), 1.0, normals="crease")
    G.to_region(tun, "walnut")
    for d in ((1, 0), (0, 1)):
        p0 = np.array([-0.48 * d[0], 0.1, -0.48 * d[1]])
        p1 = np.array([0.48 * d[0], 0.1, 0.48 * d[1]])
        mid = np.array([0, 0.32, 0])
        pts = np.array([p0, (p0 + mid) / 2 + [0, 0.08, 0], mid, (p1 + mid) / 2 + [0, 0.08, 0], p1])
        tun = Mesh.merge([tun, G.path_tube(pts, 0.03, sides=4, region="walnut", tile_len=2.0)])
    parts.append(tun.rotate_x(-62).translate(0.0, top + 0.95, zc - L / 2 - 0.05))
    # верёвки поперёк груза
    for z in (-0.7, 0.55):
        path = [(-W / 2 - 0.02, bed_y + 0.42, zc + z), (-0.55, top + 1.05, zc + z), (0.0, top + 1.16, zc + z),
                (0.55, top + 1.05, zc + z), (W / 2 + 0.02, bed_y + 0.42, zc + z)]
        parts.append(G.path_tube(path, 0.022, sides=4, region="rope", tile_len=4.0))
    for p in parts:
        if not p.has_color:
            G.white(p)
    out = Mesh.merge(parts)
    return [("Arba", out, "opaque")]


def felt_roll(length, r, region, lod=0):
    """Рулон войлока вдоль X с торцами-спиралями."""
    seg = _q(lod, 10, 6)
    m = K.lathe([(r, 0.0), (r * 1.04, length * 0.5), (r, length)], seg, 1.0)
    G.to_region(m, region)
    m.rotate_z(-90).translate(-length / 2, 0, 0)
    parts = [m]
    for sx in (-1, 1):
        cap = G.disc_uv(r * 0.98, seg, "koshma_end")
        cap.rotate_z(-90 * sx).translate(sx * length / 2, 0, 0)
        parts.append(cap)
    out = Mesh.merge(parts)
    return G.shade(out, lambda P: 0.8 + 0.2 * np.clip((P[:, 1] + r) / (2 * r), 0, 1))


# ================================================================ мелкие предметы

def campfire(lod=0):
    """Кострище: кольцо камней, шалаш из поленьев, угли (узел «Embers» светится)."""
    rs = np.random.default_rng(51)
    parts = []
    n = _q(lod, 9, 6)
    for i in range(n):
        a = i / n * 2 * math.pi + rs.uniform(-0.12, 0.12)
        st = G.lump(rs.uniform(0.16, 0.22), rs.uniform(0.1, 0.16), rs.uniform(0.13, 0.18), _q(lod, 6, 5), 3,
                    "stones", seed=i + 3, amount=0.2)
        st.rotate_y(math.degrees(a)).translate(0.62 * math.sin(a), 0, 0.62 * math.cos(a))
        parts.append(G.ground_ao(st, 0.18, 0.4))
    for k in range(_q(lod, 5, 4)):
        a = k / 5 * 2 * math.pi + 0.3
        foot = np.array([0.42 * math.sin(a), 0.02, 0.42 * math.cos(a)])
        tip = np.array([0.05 * math.sin(a + 2), 0.5, 0.05 * math.cos(a + 2)])
        lg = G.pole(foot, tip, 0.055, 0.04, sides=_q(lod, 5, 4), region="bark")
        parts.append(G.shade(lg, lambda P: 0.35 + 0.65 * np.clip(np.hypot(P[:, 0], P[:, 2]) / 0.42, 0, 1)))
    for p in parts:
        if not p.has_color:
            G.white(p)
    emb = K.lathe([(0.5, 0.0), (0.32, 0.06), (0.0, 0.1)], _q(lod, 10, 6), 1.0)
    emb.UV = np.column_stack([0.5 + emb.P[:, 0], 0.5 + emb.P[:, 2]])
    G.to_region(emb, "embers")
    return [("Campfire", Mesh.merge(parts), "opaque"), ("Embers", G.white(emb), "opaque")]


def kazan(lod=0):
    """Казан на треноге: чугунный котёл с медным краем, три жерди, цепь-верёвка."""
    parts = []
    seg = _q(lod, 14, 8)
    cy = 0.42
    body = K.lathe([(0.0, 0.0), (0.24, 0.03), (0.4, 0.14), (0.47, 0.32), (0.46, 0.44), (0.5, 0.47), (0.49, 0.5),
                    (0.42, 0.49)], seg, 1.0)
    body.UV[:, 1] = 1 - body.UV[:, 1]
    G.to_region(body, "iron")
    parts.append(body.translate(0, cy, 0))
    inside = G.disc_uv(0.43, seg, "trough_in", y=cy + 0.4)
    parts.append(G.shade(inside, lambda P: np.full(len(P), 0.6)))
    top = np.array([0, 2.1, 0])
    for k in range(3):
        a = k / 3 * 2 * math.pi + 0.4
        foot = np.array([1.05 * math.sin(a), 0, 1.05 * math.cos(a)])
        parts.append(G.ground_ao(G.pole(foot, top + (foot - top) * -0.08, 0.04, 0.035, sides=_q(lod, 5, 4),
                                        region="bark"), 0.3, 0.3))
    parts.append(G.path_tube([(0, 2.1, 0), (0, cy + 0.9, 0)], 0.015, sides=3, region="rope", tile_len=2.0))
    for sx in (-1, 1):
        parts.append(G.path_tube([(0, cy + 0.9, 0), (sx * 0.3, cy + 0.7, 0), (sx * 0.46, cy + 0.5, 0)], 0.012,
                                 sides=3, region="rope", tile_len=2.0))
    for p in parts:
        if not p.has_color:
            G.white(p)
    return [("Kazan", Mesh.merge(parts), "opaque")]


def log(a, b, r, lod=0, region="bark"):
    m = G.pole(a, b, r, r * 0.95, sides=_q(lod, 6, 4), region=region)
    a, b = np.asarray(a, float), np.asarray(b, float)
    d = (b - a) / np.linalg.norm(b - a)
    caps = []
    for p, sgn in ((a, -1), (b, 1)):
        c = G.disc_uv(r * 0.97, _q(lod, 6, 4), "logend")
        c.align(p, p + d * sgn)
        caps.append(c)
    return Mesh.merge([m] + caps)


def woodpile(lod=0):
    """Поленница: брёвна штабелем и колода для рубки с воткнутым топором."""
    rs = np.random.default_rng(61)
    parts = []
    r = 0.11
    rows = [(5, 0), (4, 1), (3, 2), (2, 3)] if lod == 0 else [(4, 0), (3, 1), (2, 2)]
    for n, k in rows:
        for i in range(n):
            x = (i - (n - 1) / 2) * 2 * r * 1.02
            y = r + k * r * 1.75
            L = 1.3 + rs.uniform(-0.15, 0.1)
            dz = rs.uniform(-0.08, 0.08)
            parts.append(log((x, y, -L / 2 + dz), (x + rs.uniform(-0.03, 0.03), y, L / 2 + dz), r * rs.uniform(0.85, 1.05),
                             lod))
    stump = log((1.2, 0, 0.4), (1.2, 0.45, 0.4), 0.24, lod)
    parts.append(G.ground_ao(stump, 0.25, 0.3))
    if lod == 0:
        parts.append(G.pole((1.2, 0.42, 0.4), (1.45, 0.95, 0.55), 0.02, sides=4, region="wood"))
        blade = G.box(0.03, 0.14, 0.16, {"front": "iron", "back": "iron", "left": "iron", "right": "iron",
                                          "top": "iron"})
        parts.append(blade.rotate_z(-25).translate(1.21, 0.38, 0.4))
    for _ in range(_q(lod, 5, 2)):
        x, z = rs.uniform(0.6, 1.9), rs.uniform(-0.1, 1.0)
        parts.append(log((x, 0.05, z), (x + rs.uniform(-0.3, 0.3), 0.05, z + 0.3), 0.05, lod))
    out = Mesh.merge(parts)
    G.ground_ao(out, 0.3, 0.3)
    return [("Woodpile", out, "opaque")]


def felt_rolls(lod=0):
    """Свёрнутые кошмы и войлоки у юрты, связанные верёвкой."""
    parts = []
    spec = [((0, 0.32, 0), 0.32, 2.0, "koshma", 5), ((0.05, 0.28, 0.66), 0.28, 1.9, "felt_white", -4),
            ((0.0, 0.84, 0.33), 0.27, 1.8, "felt_grey", 3)]
    for (x, y, z), r, L, reg, yaw in spec:
        parts.append(felt_roll(L, r, reg, lod).rotate_y(yaw).translate(x, y, z))
    # сложенный войлок плоской стопкой
    fold = G.box(1.2, 0.22, 0.9, {"top": "felt_white", "front": "koshma", "back": "felt_white",
                                   "left": "felt_white", "right": "felt_white"})
    parts.append(fold.rotate_y(-12).translate(1.7, 0, 0.2))
    fold2 = G.box(1.1, 0.16, 0.85, {"top": "saddlecloth", "front": "koshma", "left": "felt_grey",
                                     "right": "felt_grey", "back": "felt_grey"})
    parts.append(fold2.rotate_y(-4).translate(1.7, 0.22, 0.18))
    out = Mesh.merge(parts)
    G.ground_ao(out, 0.3, 0.3)
    return [("FeltRolls", out, "opaque")]


def hay(lod=0):
    """Копна сена с выбившимися пучками."""
    rs = np.random.default_rng(71)
    parts = [G.lump(1.1, 1.2, 1.0, _q(lod, 12, 7), _q(lod, 6, 4), "hay", seed=1, amount=0.14)]
    for i in range(_q(lod, 6, 2)):
        a = rs.uniform(0, 2 * math.pi)
        parts.append(G.lump(0.35, 0.18, 0.28, 6, 2, "hay", seed=10 + i, amount=0.25)
                     .rotate_y(math.degrees(a)).translate(1.2 * math.sin(a), 0, 1.15 * math.cos(a)))
    out = Mesh.merge(parts)
    G.ground_ao(out, 0.4, 0.35)
    return [("Hay", out, "opaque")]


def saddle_rack(lod=0):
    """Стойка для сёдел: две козлы и перекладина, на ней два седла с чепраками."""
    parts = []
    for x in (-1.0, 1.0):
        for dz in (-1, 1):
            parts.append(G.pole((x, 0, dz * 0.35), (x, 1.05, 0), 0.04, 0.035, sides=_q(lod, 5, 4), region="wood"))
    parts.append(G.pole((-1.2, 1.02, 0), (1.2, 1.02, 0), 0.05, sides=_q(lod, 6, 4), region="wood"))
    for k, x in enumerate((-0.5, 0.55)):
        parts.append(saddle(lod, seed=k + 5).translate(x, 1.04, 0))
    out = Mesh.merge(parts)
    G.ground_ao(out, 0.3, 0.3)
    return [("SaddleRack", out, "opaque")]


JOBS = {
    "tug": tug,
    "koroo": koroo,
    "jylky": jylky,
    "arba": arba,
    "campfire": campfire,
    "kazan": kazan,
    "woodpile": woodpile,
    "felt_rolls": felt_rolls,
    "hay": hay,
    "saddle_rack": saddle_rack,
}
