"""Стройка (_site) и руины (_ruin) для зданий и укреплений Коканда.

Стройка: цоколь-фундамент по контуру стен, стены поднялись на треть с неровным верхом
кладки, леса из жердей (стойки, ригели, раскосы, настил из досок), штабеля кирпича,
брёвна, мешки, лестница. Высота — около 30–40% готового силуэта.

Руины: обломки стен с рваным верхом, обрушенные плиты крыши, кучи щебня и битого
кирпича, обгорелые балки; всё притемнено копотью (цвет вершин). Пролом стены —
пологий вал щебня, по которому можно пройти.

Стены задаются отрезками в плане: Wall(a=(x, z), b=(x, z), h, t, region) — h высота готовой
стены, t толщина, region — область атласа (brick, pakhsa, clay).
"""
from __future__ import annotations

import math
from dataclasses import dataclass

import numpy as np

import gen_kokand_kit as G
import meshkit as K
from meshkit import Mesh


@dataclass
class Wall:
    a: tuple
    b: tuple
    h: float
    t: float = 0.6
    region: str = "brick"
    plinth: float = 0.0       # высота каменного цоколя (0 — без цоколя)


def _frame(a, b):
    a, b = np.asarray(a, float), np.asarray(b, float)
    d = b - a
    L = float(np.linalg.norm(d))
    d /= max(L, 1e-9)
    n = np.array([d[1], -d[0]])      # правая нормаль в плане (x, z)
    return a, b, d, n, L


def wall_piece(w: Wall, top=None, y0=0.0, region=None, lod=0, caps=True, top_region=None) -> Mesh:
    """Стена вдоль отрезка a→b толщиной t: две лицевые грани (top — ломаная верха вдоль длины
    [(s, y)], s от 0 до L), верх и торцы. Лицо «+n» — правая сторона по ходу a→b."""
    a, b, d, n, L = _frame(w.a, w.b)
    region = region or w.region
    top = w.h if top is None else top
    parts = []
    for sg in (1, -1):
        o = a + n * w.t / 2 * sg
        O = np.array([o[0], 0.0, o[1]])
        U = np.array([d[0], 0.0, d[1]]) * (-sg)      # U×V смотрит в sg·n
        V = np.array([0.0, 1.0, 0.0])
        x0, x1 = (-L, 0.0) if sg > 0 else (0.0, L)
        tp = top
        if not np.isscalar(top):
            tp = [((-s if sg > 0 else s), y) for s, y in top]
        f = G.face(O, U, V, x0, x1, region, y0=y0, y1=w.h, top=tp, off=(0.0, 0.0))
        # нормаль наружу
        nn = np.array([n[0] * sg, 0.0, n[1] * sg])
        if len(f.F):
            fn = np.cross(f.P[f.F[0, 1]] - f.P[f.F[0, 0]], f.P[f.F[0, 2]] - f.P[f.F[0, 0]])
            if np.dot(fn, nn) < 0:
                f.F = f.F[:, ::-1].copy()
            f.N[:] = nn
        parts.append(f)
    # верх: полоса вдоль ломаной верха
    tpts = [(0.0, top), (L, top)] if np.isscalar(top) else list(top)
    treg = top_region or ("rubble" if not np.isscalar(top) else region)
    for i in range(len(tpts) - 1):
        (s0, y_0), (s1, y_1) = tpts[i], tpts[i + 1]
        p0 = a + d * s0
        p1 = a + d * s1
        q = G.quad((p0[0] - n[0] * w.t / 2, y_0, p0[1] - n[1] * w.t / 2),
                   (p1[0] - n[0] * w.t / 2, y_1, p1[1] - n[1] * w.t / 2),
                   (p1[0] + n[0] * w.t / 2, y_1, p1[1] + n[1] * w.t / 2),
                   (p0[0] + n[0] * w.t / 2, y_0, p0[1] + n[1] * w.t / 2), treg,
                   uvs=((0, 0.2), ((s1 - s0) / 3.0, 0.2), ((s1 - s0) / 3.0, 0.2 + w.t / 3.0), (0, 0.2 + w.t / 3.0)))
        if q.N[0][1] < 0:
            q.flip()
        parts.append(q)
    if caps:
        for p, sg, yy in ((a, -1, tpts[0][1]), (b, 1, tpts[-1][1])):
            c0 = (p[0] - n[0] * w.t / 2, y0, p[1] - n[1] * w.t / 2)
            c1 = (p[0] + n[0] * w.t / 2, y0, p[1] + n[1] * w.t / 2)
            q = G.quad(c0, c1, (c1[0], yy, c1[2]), (c0[0], yy, c0[2]), region,
                       uvs=((0.1, 0.9), (0.1 + w.t / 3.2, 0.9), (0.1 + w.t / 3.2, 0.9 - yy / 1.6 * 0.5),
                            (0.1, 0.9 - yy / 1.6 * 0.5)))
            out = np.array([d[0] * sg, 0, d[1] * sg])
            if np.dot(q.N[0], out) < 0:
                q.flip()
            parts.append(q)
    return Mesh.merge(parts)


def jagged(L, h_lo, h_hi, seed, step=0.55, edge_drop=0.0):
    """Рваный верх стены: ломаная (s, y) от 0 до L, высоты между h_lo и h_hi, ступеньками кладки."""
    rs = np.random.default_rng(abs(int(seed)))
    n = max(2, int(L / step))
    s = np.linspace(0, L, n + 1)
    base = rs.uniform(h_lo, h_hi)
    y = []
    for i, si in enumerate(s):
        base += rs.normal(0, (h_hi - h_lo) * 0.25)
        base = float(np.clip(base, h_lo, h_hi))
        y.append(base)
    y = np.array(y)
    if edge_drop:
        y[0] = max(h_lo * 0.6, y[0] - edge_drop)
        y[-1] = max(h_lo * 0.6, y[-1] - edge_drop)
    return list(zip(s, y))


def ring_walls(cx, cz, r, h, region, n, seed, frac=(0.5, 1.0), skip=0.0, lod=0, t=0.6, y0=0.0) -> Mesh:
    """Круглая стена (башня, столб) многоугольником из n кусков с рваным верхом: у каждого куска
    обе грани и верх (видно толщину кладки). skip — доля выпавших кусков (пролом)."""
    rs = np.random.default_rng(abs(int(seed)))
    parts = []
    for k in range(n):
        if skip and rs.random() < skip:
            continue
        a0 = 2 * math.pi * k / n
        a1 = 2 * math.pi * (k + 1) / n
        p0 = (cx + r * math.sin(a0), cz + r * math.cos(a0))
        p1 = (cx + r * math.sin(a1), cz + r * math.cos(a1))
        L = float(np.hypot(p1[0] - p0[0], p1[1] - p0[1]))
        lo, hi = h * frac[0], h * frac[1] * rs.uniform(0.75, 1.0)
        top = jagged(L + 0.12, max(lo, y0 + 0.3), max(hi, y0 + 0.4), seed * 13 + k, step=0.5 if lod == 0 else 1.0)
        d = (np.asarray(p1) - np.asarray(p0)) / L
        a = tuple(np.asarray(p0) - d * 0.06)
        b = tuple(np.asarray(p1) + d * 0.06)
        parts.append(wall_piece(Wall(a, b, hi, t, region), top=top, y0=y0, top_region="rubble", lod=lod,
                                caps=skip > 0))
    return Mesh.merge(parts)


# ================================================================ стройка

def scaffold(a, b, h, offset=0.9, lod=0, seed=0, step=2.2) -> Mesh:
    """Леса вдоль отрезка a→b (в плане), снаружи со стороны правой нормали на offset м:
    стойки в два ряда, ригели по ярусам, раскосы, настил из досок на верхнем ярусе."""
    rs = np.random.default_rng(abs(int(seed)))
    a, b, d, n, L = _frame(a, b)
    parts = []
    n_posts = max(2, int(round(L / step)) + 1)
    sides = 5 if lod == 0 else 4
    rows = (offset, offset + 0.9) if lod == 0 else (offset + 0.45,)
    levels = [lv for lv in np.arange(1.2, h + 0.01, 1.2)] or [h]
    for r in rows:
        pts = []
        for i in range(n_posts):
            p = a + d * (L * i / (n_posts - 1)) + n * r
            top = h + 0.8 + rs.uniform(-0.15, 0.25)
            lean = rs.normal(0, 0.03, 2)
            parts.append(G.pole((p[0], 0, p[1]), (p[0] + lean[0], top, p[1] + lean[1]), 0.06, 0.05, sides, "bark"))
            pts.append(p)
        for lv in levels:
            q0, q1 = pts[0], pts[-1]
            parts.append(G.pole((q0[0], lv, q0[1]), (q1[0], lv + rs.uniform(-0.05, 0.05), q1[1]), 0.045, sides=sides,
                                region="pole"))
        if lod == 0:
            for i in range(n_posts - 1):   # раскосы через пролёт
                if i % 2:
                    continue
                p0, p1 = pts[i], pts[i + 1]
                parts.append(G.pole((p0[0], 0.2, p0[1]), (p1[0], levels[-1], p1[1]), 0.035, sides=4, region="pole"))
    # поперечины и настил на верхнем ярусе
    lv = levels[-1]
    for i in range(n_posts):
        p = a + d * (L * i / (n_posts - 1))
        parts.append(G.pole((p[0] + n[0] * 0.05, lv + 0.05, p[1] + n[1] * 0.05),
                            (p[0] + n[0] * (offset + 1.0), lv + 0.05, p[1] + n[1] * (offset + 1.0)), 0.04, sides=4,
                            region="pole"))
    c0 = a + n * (offset - 0.15)
    c1 = b + n * (offset - 0.15)
    c2 = b + n * (offset + 0.85)
    c3 = a + n * (offset + 0.85)
    deck = G.quad((c0[0], lv + 0.12, c0[1]), (c3[0], lv + 0.12, c3[1]), (c2[0], lv + 0.12, c2[1]),
                  (c1[0], lv + 0.12, c1[1]), "planks", uvs=((0, 1), (0.5, 1), (0.5, 1 - min(L / 2.0, 1.0)),
                                                             (0, 1 - min(L / 2.0, 1.0))))
    if deck.N[0][1] < 0:
        deck.flip()
    parts.append(deck)
    return G.ground_ao(Mesh.merge(parts), 0.4, 0.25)


def brick_stack(x, z, yaw=0.0, sx=1.1, sy=0.7, sz=0.8) -> Mesh:
    """Штабель кирпича на поддоне из досок."""
    pal = G.box(sx + 0.1, 0.12, sz + 0.1, {"front": "planks", "back": "planks", "left": "planks", "right": "planks",
                                           "top": "planks"})
    st = G.box(sx, sy, sz, {"front": "brick", "back": "brick", "left": "brick", "right": "brick", "top": "brick"})
    # UV кирпича: кусок области (кирпичи нужного размера)
    st.UV = st.UV  # (область целиком — 3,2 м; на штабеле кирпич крупнее, но читается)
    st.translate(0, 0.12, 0)
    m = Mesh.merge([pal, st])
    return G.ground_ao(G.place(m, x, 0, z, yaw), 0.3, 0.3)


def log_pile(x, z, yaw=0.0, n=6, L=3.0, r=0.13, lod=0, seed=0) -> Mesh:
    rs = np.random.default_rng(abs(int(seed)))
    parts = []
    rows = [(3, 0), (2, 1), (1, 2)] if n >= 6 else [(2, 0), (1, 1)]
    for cnt, k in rows:
        for i in range(cnt):
            xx = (i - (cnt - 1) / 2) * 2 * r * 1.02
            y = r + k * r * 1.75
            dz = rs.uniform(-0.1, 0.1)
            parts.append(log((xx, y, -L / 2 + dz), (xx, y, L / 2 + dz), r * rs.uniform(0.85, 1.05), lod))
    m = Mesh.merge(parts)
    return G.ground_ao(G.place(m, x, 0, z, yaw), 0.3, 0.3)


def log(a, b, r, lod=0, region="bark") -> Mesh:
    m = G.pole(a, b, r, r * 0.95, sides=6 if lod == 0 else 4, region=region)
    a, b = np.asarray(a, float), np.asarray(b, float)
    d = (b - a) / np.linalg.norm(b - a)
    caps = []
    for p, sgn in ((a, -1), (b, 1)):
        c = G.disc_uv(r * 0.97, 6 if lod == 0 else 4, "logend")
        c.align(p, p + d * sgn)
        caps.append(c)
    return Mesh.merge([m] + caps)


def sack(x, z, yaw=0.0, s=1.0, seed=0, lod=0, y=0.0) -> Mesh:
    """Мешок: приплюснутый ком с завязанной горловиной."""
    m = G.lump(0.32 * s, 0.42 * s, 0.26 * s, 7 if lod == 0 else 5, 3, "sacks", seed=seed, amount=0.1)
    # UV мешка: по кругу (x) и сверху вниз (y)
    th = np.arctan2(m.P[:, 0], m.P[:, 2])
    from gen_kokand_atlas import uv as auv
    u0, v0, u1, v1 = auv("sacks")
    t = 1 - np.clip(m.P[:, 1] / (0.42 * s), 0, 1)
    m.UV = np.column_stack([u0 + (th / (2 * math.pi) + 0.5) * (u1 - u0), v0 + (0.15 + 0.85 * t) * (v1 - v0)])
    parts = [m]
    if lod == 0:
        neck = K.cylinder(0.08 * s, 0.05 * s, 0.14 * s, 5, caps=False).translate(0, 0.38 * s, 0)
        G.to_region(neck, "sacks", inset=2)
        neck.UV[:, 1] = np.clip(neck.UV[:, 1], 0, G.atlas_uv("sacks")[1] + 0.004)
        parts.append(neck)
    out = Mesh.merge(parts)
    return G.ground_ao(G.place(out, x, y, z, yaw), 0.25, 0.3)


def sack_pile(x, z, yaw=0.0, n=5, seed=0, lod=0) -> Mesh:
    rs = np.random.default_rng(abs(int(seed)))
    parts = []
    spots = [(-0.35, 0, 0), (0.35, 0, 0.05), (0.0, 0, 0.55), (-0.2, 0.55, 0.25), (0.25, 0.5, 0.2), (0.7, 0, 0.5)]
    for i, (sx, sy, sz) in enumerate(spots[:n]):
        m = sack(0, 0, rs.uniform(0, 360), rs.uniform(0.9, 1.1), seed=seed * 10 + i, lod=lod)
        if sy:
            m.rotate_z(rs.uniform(-60, 60))
        parts.append(m.translate(sx, sy * 0.6, sz))
    m = Mesh.merge(parts)
    return G.place(m, x, 0, z, yaw)


def stone_pile(x, z, r=0.9, n=7, seed=0, lod=0) -> Mesh:
    rs = np.random.default_rng(abs(int(seed)))
    parts = [G.lump(r, r * 0.45, r * 0.85, 8 if lod == 0 else 6, 3, "stones", seed=seed, amount=0.2)]
    for i in range(n if lod == 0 else n // 2):
        a = rs.uniform(0, 2 * math.pi)
        rr = rs.uniform(r * 0.6, r * 1.2)
        s = rs.uniform(0.18, 0.32)
        parts.append(G.lump(s, s * 0.7, s * 0.9, 5, 2, "stones", seed=seed + i + 1, amount=0.25)
                     .translate(math.cos(a) * rr, 0, math.sin(a) * rr))
    return G.ground_ao(Mesh.merge(parts).translate(x, 0, z), 0.3, 0.3)


def ladder(a, b, w=0.5, lod=0) -> Mesh:
    """Лестница из жердей от a (низ) к b (верх)."""
    a, b = np.asarray(a, float), np.asarray(b, float)
    d = b - a
    L = np.linalg.norm(d)
    side = np.cross(d / L, [0, 1, 0])
    if np.linalg.norm(side) < 1e-6:
        side = np.array([1.0, 0, 0])
    side /= np.linalg.norm(side)
    parts = [G.pole(a + side * w / 2, b + side * w / 2, 0.035, sides=4, region="pole"),
             G.pole(a - side * w / 2, b - side * w / 2, 0.035, sides=4, region="pole")]
    for t in np.arange(0.35, L, 0.4 if lod == 0 else 0.8):
        p = a + d / L * t
        parts.append(G.pole(p - side * w / 2, p + side * w / 2, 0.025, sides=3, region="wood"))
    return Mesh.merge(parts)


def site(walls, lod=0, seed=0, frac=0.35, stacks=(), scaff=None, round_walls=(), mats=None) -> Mesh:
    """Стройка по контуру стен: цоколь, стены на frac высоты с неровным верхом, леса, материалы.
    stacks — [(вид, x, z, yaw)], вид: bricks | logs | sacks | stones | ladder.
    scaff — список индексов стен, у которых стоят леса (по умолчанию — первая и самая длинная).
    round_walls — [(cx, cz, r, h, region)] круглые основания (башни)."""
    rs = np.random.default_rng(abs(int(seed)))
    parts = []
    for i, w in enumerate(walls):
        a, b, d, n, L = _frame(w.a, w.b)
        # фундамент: каменная полоса чуть шире стены
        base = Wall(tuple(a - d * 0.1), tuple(b + d * 0.1), 0.35, w.t + 0.2, "plinth")
        parts.append(wall_piece(base, region="plinth", top_region="stones", lod=lod))
        hh = max(0.6, w.h * frac)
        top = jagged(L, hh * 0.45, hh, seed * 31 + i, step=0.8 if lod == 0 else 1.6, edge_drop=hh * 0.2)
        parts.append(wall_piece(Wall(w.a, w.b, hh, w.t, w.region), top=top, y0=0.35, top_region=w.region, lod=lod))
    for (cx, cz, r, h, region) in round_walls:
        seg = 14 if lod == 0 else 9
        parts.append(G.lathe_bands([(r + 0.15, 0.0), (r + 0.15, 0.35)], "plinth", tiles=3, seg_per_tile=seg // 3,
                                   v_span=(0, 0.35)).translate(cx, 0, cz))
        parts.append(G.ring_flat(r - 0.6, r + 0.15, 0.35, seg // 3, "stones", tiles=3).translate(cx, 0, cz))
        hh = max(0.8, h * frac)
        parts.append(ring_walls(cx, cz, r - 0.3, hh, region, 10 if lod == 0 else 7, seed, (0.55, 1.0), 0.0, lod,
                                t=0.6, y0=0.35))
    sc = scaff if scaff is not None else ([max(range(len(walls)), key=lambda k: _frame(walls[k].a, walls[k].b)[4])]
                                          if walls else [])
    for k in sc:
        w = walls[k]
        parts.append(scaffold(w.a, w.b, max(1.2, w.h * frac + 0.4), offset=w.t / 2 + 0.5, lod=lod, seed=seed + k))
    for kind, x, z, yaw in stacks:
        if kind == "bricks":
            parts.append(brick_stack(x, z, yaw))
        elif kind == "logs":
            parts.append(log_pile(x, z, yaw, lod=lod, seed=seed + int(x * 10)))
        elif kind == "sacks":
            parts.append(sack_pile(x, z, yaw, n=4 if lod == 0 else 2, seed=seed + int(z * 10), lod=lod))
        elif kind == "stones":
            parts.append(stone_pile(x, z, 0.8, seed=seed + int(x * 7), lod=lod))
        elif kind == "ladder":
            parts.append(ladder((x, 0.0, z), (x + math.sin(math.radians(yaw)) * 0.8, 2.6,
                                              z + math.cos(math.radians(yaw)) * 0.8), lod=lod))
    m = Mesh.merge(parts)
    return G.ground_ao(m, 0.4, 0.25)


# ================================================================ руины

def rubble(cx, cz, rx, rz, h, seed=0, lod=0, chunks=6, region="rubble") -> Mesh:
    """Куча щебня (пологий вал) с кусками кладки."""
    rs = np.random.default_rng(abs(int(seed)))
    parts = [G.lump(rx, h, rz, 10 if lod == 0 else 7, 4 if lod == 0 else 3, region, seed=seed, amount=0.18)]
    for i in range(chunks if lod == 0 else chunks // 2):
        a = rs.uniform(0, 2 * math.pi)
        rr = rs.uniform(0.4, 1.1)
        s = rs.uniform(0.2, 0.45)
        px, pz = math.cos(a) * rx * rr, math.sin(a) * rz * rr
        py = max(0.0, h * (1 - min(rr, 1.0) ** 2) * 0.8 - s * 0.3)
        ch = G.box(s * 1.6, s, s * 1.1, {"front": "brick", "back": "brick", "left": "brick", "right": "brick",
                                         "top": "rubble"})
        ch.rotate_y(rs.uniform(0, 360)).rotate_z(rs.uniform(-25, 25)).translate(px, py, pz)
        parts.append(ch)
    m = Mesh.merge(parts).translate(cx, 0, cz)
    return G.ground_ao(m, 0.4, 0.3)


def slab(p0, p1, p2, p3, thick=0.25, region="roof", side="earth") -> Mesh:
    """Обрушенная плита крыши: четырёхугольник (верх) с толщиной (торцы)."""
    P = [np.asarray(p, float) for p in (p0, p1, p2, p3)]
    top = G.quad(*P, region, uvs=((0, 1), (0.5, 1), (0.5, 0.5), (0, 0.5)))
    if top.N[0][1] < 0:
        top.flip()
    n = top.N[0]
    parts = [top]
    for i in range(4):
        a, b = P[i], P[(i + 1) % 4]
        q = G.quad(a, b, b - n * thick, a - n * thick, side, uvs=((0, 0.1), (0.3, 0.1), (0.3, 0), (0, 0)))
        c = sum(P) / 4
        mid = (a + b) / 2 - n * thick / 2
        if np.dot(q.N[0], mid - c) < 0:
            q.flip()
        parts.append(q)
    return Mesh.merge(parts)


def burnt_beam(a, b, r=0.1, lod=0) -> Mesh:
    m = log(a, b, r, lod)
    return G.shade(m, lambda P: np.full(len(P), 0.35))


def ruin(walls, lod=0, seed=0, frac=(0.15, 0.55), roofs=(), piles=(), beams=4, round_walls=(), soot=0.7) -> Mesh:
    """Руины: обломки стен (рваный верх frac·h), кучи щебня вдоль стен, обрушенные плиты крыш
    (roofs — [(x0, z0, x1, z1, y)]), обгорелые балки, копоть. piles — [(x, z, rx, rz, h)]."""
    rs = np.random.default_rng(abs(int(seed)))
    parts = []
    for i, w in enumerate(walls):
        a, b, d, n, L = _frame(w.a, w.b)
        # стена разбита на 1–3 обломка с провалами
        cuts = sorted(rs.uniform(0.2, 0.8, size=1 if L < 5 else 2)) if L > 2.5 else []
        pts = [0.0] + [c * L for c in cuts] + [L]
        for k in range(len(pts) - 1):
            s0, s1 = pts[k], pts[k + 1]
            if s1 - s0 < 0.8:
                continue
            if k % 2 == 1 and rs.random() < 0.6:
                continue      # провал: на месте стены — щебень
            seg_a = a + d * s0
            seg_b = a + d * s1
            lo, hi = w.h * frac[0], w.h * frac[1] * rs.uniform(0.7, 1.0)
            top = jagged(s1 - s0, lo, hi, seed * 17 + i * 5 + k, step=0.5 if lod == 0 else 1.0, edge_drop=hi * 0.3)
            parts.append(wall_piece(Wall(tuple(seg_a), tuple(seg_b), hi, w.t, w.region), top=top,
                                    top_region="rubble", lod=lod))
        # щебень у основания по обе стороны
        for k in range(max(1, int(L / 4))):
            s = rs.uniform(0.15, 0.85) * L
            side = rs.choice([-1, 1])
            p = a + d * s + n * side * (w.t / 2 + 0.4)
            parts.append(rubble(p[0], p[1], rs.uniform(0.8, 1.5), rs.uniform(0.6, 1.1), rs.uniform(0.3, 0.6),
                                seed=seed * 7 + i * 3 + k, lod=lod, chunks=4))
    for (cx, cz, r, h, region) in round_walls:
        hh = h * frac[1]
        parts.append(ring_walls(cx, cz, r - 0.35, hh, region, 10 if lod == 0 else 7, seed, (0.25, 1.0), 0.3, lod,
                                t=0.7))
        parts.append(rubble(cx + r * 0.9, cz + r * 0.5, r * 0.9, r * 0.7, max(0.6, h * 0.1), seed=seed + 3, lod=lod))
        parts.append(rubble(cx - r * 0.2, cz, r * 0.75, r * 0.75, max(0.5, h * 0.07), seed=seed + 4, lod=lod))
    for j, (x0, z0, x1, z1, y) in enumerate(roofs):
        # плита сползла: один край на обломке стены, другой на земле
        cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
        hw, hd = (x1 - x0) / 2 * 0.8, (z1 - z0) / 2 * 0.5
        yh = y * frac[1] * 0.7
        p0 = (cx - hw, 0.15, cz + hd)
        p1 = (cx + hw * 0.9, 0.25, cz + hd * 1.1)
        p2 = (cx + hw, yh, cz - hd * 0.6)
        p3 = (cx - hw * 0.8, yh * 0.8, cz - hd * 0.7)
        parts.append(slab(p0, p1, p2, p3))
        parts.append(rubble(cx + rs.uniform(-1, 1), cz + hd + 0.6, hw * 0.8, 1.0, 0.5, seed=seed + 50 + j, lod=lod))
    for (x, z, rx, rz, h) in piles:
        parts.append(rubble(x, z, rx, rz, h, seed=seed + int(x * 13 + z), lod=lod))
    for k in range(beams if lod == 0 else beams // 2):
        x, z = rs.uniform(-1, 1, 2)
        if walls:
            w = walls[k % len(walls)]
            a, b, d, n, L = _frame(w.a, w.b)
            p = a + d * rs.uniform(0.2, 0.8) * L + n * rs.uniform(-1.5, 1.5)
            x, z = p
        ang = rs.uniform(0, 2 * math.pi)
        L = rs.uniform(2.0, 3.5)
        a3 = (x, 0.12, z)
        b3 = (x + math.cos(ang) * L, rs.uniform(0.1, 0.9), z + math.sin(ang) * L)
        parts.append(burnt_beam(a3, b3, 0.1, lod))
    m = Mesh.merge(parts)
    # копоть: сверху темнее (обгорело), пятнами
    m = G.shade(m, lambda P: soot * (0.9 + 0.1 * np.sin(P[:, 0] * 1.3 + P[:, 2] * 0.9)) * (1.05 - 0.12 * np.clip(P[:, 1] / 3, 0, 1)))
    return G.ground_ao(m, 0.4, 0.25)
