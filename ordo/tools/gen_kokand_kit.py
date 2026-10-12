"""Помощники мешей Коканда поверх tools/meshkit.py.

Главное — face(): плоская грань в своей рамке, разрезанная по границам плиток атласа
(TILE в gen_kokand_atlas). Узор кирпича, пахсы, изразцового пояса идёт по всему зданию
без шва и с одинаковым мировым шагом: у соседних звеньев стены (шаг 3,2 м) рисунок в
зоне перекрытия совпадает, поэтому перекрытие не видно.

Цвет вершин — нарисованная тень/подсветка (множитель в painterly_surface), как у лагеря.
"""
from __future__ import annotations

import math

import numpy as np

import meshkit as K
from gen_kokand_atlas import TILE
from gen_kokand_atlas import uv as atlas_uv
from meshkit import Mesh

EPS = 1e-6


# ---------------------------------------------------------------- UV и цвет

def to_region(m: Mesh, name, flip_v=False, inset=0.0) -> Mesh:
    """UV 0..1 → область атласа; flip_v — перевернуть v (верх картинки = верх модели)."""
    if flip_v:
        m.UV[:, 1] = 1.0 - m.UV[:, 1]
    m.UV = np.clip(m.UV, 0.0, 1.0)
    return m.map_uv(atlas_uv(name, inset))


def shade(m: Mesh, fn) -> Mesh:
    """Цвет вершин *= fn(P) (n,) или (n,3), или число. Нарисованная тень/подсветка."""
    v = np.asarray(fn(m.P) if callable(fn) else fn, dtype=np.float64)
    if v.ndim == 0:
        v = np.full(len(m.P), float(v))
    if v.ndim == 1:
        v = np.repeat(v[:, None], 3, axis=1)
    old = m.C[:, :3] if m.has_color else np.ones((len(m.P), 3))
    m.C = np.column_stack([np.clip(old * v, 0, 2), np.ones(len(m.P))])
    m.has_color = True
    return m


def tint(m: Mesh, rgb) -> Mesh:
    return shade(m, lambda P: np.tile(np.asarray(rgb, float), (len(P), 1)))


def ground_ao(m: Mesh, depth=0.5, strength=0.3, y0=0.0) -> Mesh:
    """Темнее у земли: контактная тень, нарисованная в цвете вершин."""
    return shade(m, lambda P: 1.0 - strength * np.clip(1.0 - (P[:, 1] - y0) / depth, 0, 1) ** 1.5)


def wall_light(m: Mesh, h, base=0.72, top=1.06, y0=0.0) -> Mesh:
    """Свет стены по высоте (только от y — у соседних звеньев одинаков): тёмный низ, светлый верх."""
    def fn(P):
        t = np.clip((P[:, 1] - y0) / max(h, 1e-6), 0, 1)
        lo = base + (1 - base) * np.clip(t / 0.18, 0, 1) ** 0.8
        return lo * (1 + (top - 1) * np.clip((t - 0.6) / 0.4, 0, 1))
    return shade(m, fn)


def grime(m: Mesh, strength=0.08, seed=0) -> Mesh:
    """Пятна времени по зданию (цвет вершин): медленные волны темнее/светлее ±strength.
    Только для того, что не стыкуется звеньями (башни, здания)."""
    rs = np.random.default_rng(abs(int(seed)))
    ph = rs.uniform(0, 6.28, 4)

    def fn(P):
        x, y, z = P[:, 0], P[:, 1], P[:, 2]
        n = (np.sin(x * 0.9 + z * 0.4 + ph[0]) + 0.6 * np.sin(z * 1.3 - y * 0.5 + ph[1])
             + 0.4 * np.sin(y * 2.1 + x * 0.3 + ph[2]) + 0.3 * np.sin(x * 2.7 - z * 1.9 + ph[3])) / 2.3
        return 1.0 + strength * n
    return shade(m, fn)


def white(m: Mesh) -> Mesh:
    if not m.has_color:
        m.C = np.ones((len(m.P), 4))
        m.has_color = True
    return m


# ---------------------------------------------------------------- плоская грань с плитками

def _poly(spec, x0, x1, default):
    """Число → горизонталь; список точек → ломаная (x по возрастанию)."""
    if spec is None:
        spec = default
    if np.isscalar(spec):
        return np.array([[x0, float(spec)], [x1, float(spec)]])
    p = np.asarray(spec, dtype=np.float64)
    return p[np.argsort(p[:, 0], kind="stable")]


def _interp(poly, x):
    return np.interp(x, poly[:, 0], poly[:, 1])


def face(O, U, V, x0, x1, region, tile=None, y0=0.0, y1=1.0, top=None, bottom=None, off=(0.0, 0.0),
         flip_u=False, v_span=None) -> Mesh:
    """Плоская грань O + x·U + y·V, x ∈ [x0, x1], y от bottom(x) (иначе y0) до top(x) (иначе y1).

    top/bottom — число или ломаная [(x, y), ...]. Нормаль — U×V (снаружи).
    tile=(tw, th) — мировой размер области region в метрах (по умолчанию TILE[region]);
    th=None — по высоте область целиком на v_span (по умолчанию [y0, y1]).
    off — сдвиг рисунка (м). Грань режется по границам плиток и по точкам, где верх/низ
    пересекают границы рядов, — каждая ячейка лежит ровно в одной плитке.
    """
    O, U, V = (np.asarray(a, dtype=np.float64) for a in (O, U, V))
    tw, th = tile if tile is not None else TILE.get(region, (None, None))
    tp = _poly(top, x0, x1, y1)
    bp = _poly(bottom, x0, x1, y0)
    ox, oy = off
    xs = {x0, x1}
    if tw:
        k0, k1 = math.ceil((x0 + ox) / tw - EPS), math.floor((x1 + ox) / tw + EPS)
        xs.update(k * tw - ox for k in range(k0, k1 + 1))
    for p in (tp, bp):
        xs.update(p[:, 0])
    ylo = min(tp[:, 1].min(), bp[:, 1].min())
    yhi = max(tp[:, 1].max(), bp[:, 1].max())
    bands = []
    if th:
        k0, k1 = math.ceil((ylo + oy) / th - EPS), math.floor((yhi + oy) / th + EPS)
        bands = [k * th - oy for k in range(k0, k1 + 1)]
        bands = [b for b in bands if ylo + EPS < b < yhi - EPS]
        # точки, где верх и низ пересекают границы рядов
        for p in (tp, bp):
            for i in range(len(p) - 1):
                (xa, ya), (xb, yb) = p[i], p[i + 1]
                for c in bands:
                    if (ya - c) * (yb - c) < 0:
                        xs.add(xa + (c - ya) / (yb - ya) * (xb - xa))
    xs = np.array(sorted(x for x in xs if x0 - EPS <= x <= x1 + EPS))
    # убрать почти совпадающие
    keep = [xs[0]]
    for x in xs[1:]:
        if x - keep[-1] > 1e-5:
            keep.append(x)
    xs = np.array(keep)
    levels = [ylo - 1.0] + bands + [yhi + 1.0]
    vs0, vs1 = v_span if v_span is not None else (y0, y1)
    P, UVs, F = [], [], []

    def uvof(x, y, i_t, j_t):
        u = (x + ox) / tw - i_t if tw else (x - x0) / max(x1 - x0, EPS)
        if th:
            v = 1.0 - ((y + oy) / th - j_t)
        else:
            v = 1.0 - (y - vs0) / max(vs1 - vs0, EPS)
        return (1.0 - u if flip_u else u), v

    for i in range(len(xs) - 1):
        a, b = xs[i], xs[i + 1]
        ta, tb = _interp(tp, a), _interp(tp, b)
        ba, bb = _interp(bp, a), _interp(bp, b)
        for j in range(len(levels) - 1):
            c, d = levels[j], levels[j + 1]
            yta, ytb = min(ta, d), min(tb, d)
            yba, ybb = max(ba, c), max(bb, c)
            la, lb = yta - yba, ytb - ybb
            if la <= 1e-5 and lb <= 1e-5:
                continue
            xm = (a + b) / 2
            ym = (max(yta, yba) + max(ytb, ybb) + yba + ybb) / 4
            i_t = math.floor((xm + ox) / tw) if tw else 0
            j_t = math.floor((ym + oy) / th) if th else 0
            quad = [(a, yba), (b, ybb)]
            if lb > 1e-5:
                quad.append((b, ytb))
            if la > 1e-5:
                quad.append((a, yta))
            base = len(P)
            for (x, y) in quad:
                P.append(O + x * U + y * V)
                UVs.append(uvof(x, y, i_t, j_t))
            if len(quad) == 4:
                F += [(base, base + 1, base + 2), (base, base + 2, base + 3)]
            else:
                F += [(base, base + 1, base + 2)]
    n = np.cross(U, V)
    n = n / max(np.linalg.norm(n), EPS)
    if not P:
        return Mesh(np.zeros((0, 3)), np.zeros((0, 3), dtype=np.int64))
    m = Mesh(np.array(P), F, np.tile(n, (len(P), 1)), np.array(UVs))
    return to_region(m, region)


# рамки граней прямоугольного блока: (нормаль) → (O(x0..), U, V, x-диапазон)
def box_face(side, x0, x1, z0, z1, y0, y1, region, tile=None, off=(0.0, 0.0), top=None, bottom=None,
             v_span=None, inset=0.0):
    """Грань осевого блока. side: front(+Z) back(−Z) right(+X) left(−X) top(+Y).
    Для боковых граней x — вдоль грани (U), y — высота; top/bottom — в этих координатах."""
    if side == "front":
        return face((0, 0, z1 + inset), (1, 0, 0), (0, 1, 0), x0, x1, region, tile, y0, y1, top, bottom, off,
                    v_span=v_span)
    if side == "back":
        return face((0, 0, z0 - inset), (-1, 0, 0), (0, 1, 0), -x1, -x0, region, tile, y0, y1, top, bottom, off,
                    v_span=v_span)
    if side == "right":
        return face((x1 + inset, 0, 0), (0, 0, -1), (0, 1, 0), -z1, -z0, region, tile, y0, y1, top, bottom, off,
                    v_span=v_span)
    if side == "left":
        return face((x0 - inset, 0, 0), (0, 0, 1), (0, 1, 0), z0, z1, region, tile, y0, y1, top, bottom, off,
                    v_span=v_span)
    if side == "top":
        return face((0, y1 + inset, 0), (1, 0, 0), (0, 0, -1), x0, x1, region, tile, -z1, -z0, None, None, off)
    raise ValueError(side)


def block(x0, x1, z0, z1, y0, y1, region, top_region=None, sides=("front", "back", "left", "right"),
          tile=None, off=(0.0, 0.0), top_tile=None) -> Mesh:
    """Прямоугольный блок с плиточными гранями (без дна)."""
    parts = [box_face(s, x0, x1, z0, z1, y0, y1, region, tile, off) for s in sides]
    if top_region:
        parts.append(box_face("top", x0, x1, z0, z1, y0, y1, top_region, top_tile))
    return Mesh.merge(parts)


def taper(m: Mesh, cx, cz, k, y0, y1) -> Mesh:
    """Наклон стен (батер): к верху блок сужается на k метров с каждой стороны."""
    t = np.clip((m.P[:, 1] - y0) / max(y1 - y0, EPS), 0, 1)
    dx, dz = m.P[:, 0] - cx, m.P[:, 2] - cz
    sx = np.sign(dx) * np.minimum(np.abs(dx), k * t)
    sz = np.sign(dz) * np.minimum(np.abs(dz), k * t)
    m.P = np.column_stack([m.P[:, 0] - sx, m.P[:, 1], m.P[:, 2] - sz])
    return m


# ---------------------------------------------------------------- тела вращения

def lathe_bands(profile, region, tiles=4, seg_per_tile=4, sweep=360.0, start=0.0, tile_h=None, off_y=0.0,
                v_span=None, smooth=False) -> Mesh:
    """Тело вращения с плиточной развёрткой: по окружности `tiles` раз вся ширина области
    (область должна повторяться по x), по высоте — ряды плиток высотой tile_h (м) или
    вся область на v_span=(y0, y1)."""
    prof = [tuple(p) for p in profile]
    if tile_h:
        ys = [p[1] for p in prof]
        cuts = [k * tile_h - off_y for k in range(math.ceil((min(ys) + off_y) / tile_h),
                                                  math.floor((max(ys) + off_y) / tile_h) + 1)]
        out = [prof[0]]
        for i in range(len(prof) - 1):
            (ra, ya), (rb, yb) = prof[i], prof[i + 1]
            for c in sorted(cuts, reverse=yb < ya):
                if (ya - c) * (yb - c) < 0:
                    t = (c - ya) / (yb - ya)
                    out.append((ra + t * (rb - ra), c))
            out.append(prof[i + 1])
        prof = out
    span = sweep / tiles
    parts = []
    segs = range(len(prof) - 1) if not smooth else [None]
    for si in segs:
        sub = prof if si is None else prof[si:si + 2]
        if si is not None and abs(sub[0][1] - sub[1][1]) < 1e-6 and abs(sub[0][0] - sub[1][0]) < 1e-6:
            continue
        for k in range(tiles):
            p = K.lathe(sub, seg_per_tile, 1.0, sweep=span, start=start + k * span,
                        normals="smooth")
            y = p.P[:, 1]
            if tile_h:
                ym = (sub[0][1] + sub[-1][1]) / 2
                j = math.floor((ym + off_y) / tile_h)
                v = 1.0 - ((y + off_y) / tile_h - j)
            else:
                a, b = v_span if v_span else (prof[0][1], prof[-1][1])
                v = 1.0 - (y - a) / max(b - a, EPS)
            p.UV[:, 1] = v
            parts.append(to_region(p, region))
    return Mesh.merge(parts)


def dome(profile, region, tiles=4, seg_per_tile=4, sweep=360.0, start=0.0) -> Mesh:
    """Купол: гладкий профиль снизу вверх, v области — от вершины (верх картинки) к низу."""
    parts = []
    span = sweep / tiles
    for k in range(tiles):
        p = K.lathe(profile, seg_per_tile, 1.0, sweep=span, start=start + k * span, normals="smooth")
        p.UV[:, 1] = 1.0 - p.UV[:, 1]
        parts.append(to_region(p, region))
    return Mesh.merge(parts)


def ring_band(r_bottom, r_top, y0, y1, region, tiles=4, seg_per_tile=4, sweep=360.0, start=0.0) -> Mesh:
    """Кольцевой пояс (изразец по барабану, по башне): вся высота области на [y0, y1]."""
    return lathe_bands([(r_bottom, y0), (r_top, y1)], region, tiles, seg_per_tile, sweep, start,
                       v_span=(y0, y1))


# ---------------------------------------------------------------- призмы (зубцы, арки)

def arc_merlon_poly(w, h, arc_seg=4, pointed=0.0):
    """Скруглённый зубец: прямоугольник w×(h−w/2) и полукруг сверху (pointed — заострение)."""
    r = w / 2
    hr = h - r
    pts = [(-r, 0.0), (r, 0.0)]
    for i in range(arc_seg + 1):
        a = math.pi * i / arc_seg
        y = hr + r * math.sin(a) * (1 + pointed * math.sin(a) ** 4)
        pts.append((r * math.cos(a), y))
    return pts


def prism(poly, depth, region, uv_rect=(0.0, 0.0, 1.0, 1.0), side_region=None, skip_bottom=True, back=True,
          scale=None) -> Mesh:
    """Выдавливание многоугольника (XY, против часовой) вдоль +Z на depth; лицо — +Z.
    uv_rect — часть области (доли) для лица; scale — метров на всю область (иначе — по габариту)."""
    poly = np.asarray(poly, dtype=np.float64)
    lo, hi = poly.min(0), poly.max(0)
    span = np.maximum(hi - lo, EPS) if scale is None else np.asarray(scale, float)
    u0, v0, u1, v1 = uv_rect
    tri = K.triangulate(poly)
    k = len(poly)

    def cap_uv(p):
        t = (p - lo) / span
        return np.column_stack([u0 + t[:, 0] * (u1 - u0), v1 - t[:, 1] * (v1 - v0)])
    parts = []
    Pf = np.column_stack([poly, np.full(k, depth)])
    parts.append(to_region(Mesh(Pf, tri, np.tile([0, 0, 1], (k, 1)), cap_uv(poly)), region))
    if back:
        Pb = np.column_stack([poly, np.zeros(k)])
        parts.append(to_region(Mesh(Pb, [t[::-1] for t in tri], np.tile([0, 0, -1], (k, 1)), cap_uv(poly)), region))
    sreg = side_region or region
    per = np.r_[0, np.cumsum(np.linalg.norm(np.diff(np.vstack([poly, poly[:1]]), axis=0), axis=1))]
    total = per[-1]
    P, N, UV, F = [], [], [], []
    for i in range(k):
        a, b = poly[i], poly[(i + 1) % k]
        if skip_bottom and abs(a[1]) < 1e-6 and abs(b[1]) < 1e-6:
            continue
        e = b - a
        n = np.array([e[1], -e[0], 0.0])
        n /= max(np.linalg.norm(n), EPS)
        s0, s1 = per[i] / total, per[i + 1] / total
        base = len(P)
        P += [(a[0], a[1], 0), (b[0], b[1], 0), (b[0], b[1], depth), (a[0], a[1], depth)]
        N += [n] * 4
        UV += [(u0 + s0 * (u1 - u0), v0), (u0 + s1 * (u1 - u0), v0), (u0 + s1 * (u1 - u0), v0 + 0.15 * (v1 - v0)),
               (u0 + s0 * (u1 - u0), v0 + 0.15 * (v1 - v0))]
        F += [(base, base + 1, base + 2), (base, base + 2, base + 3)]
    if P:
        side = Mesh(P, F, N, UV)
        # смягчить нормали боковин дуги (скругление читается мягко)
        parts.append(to_region(side, sreg))
    return Mesh.merge(parts)


def merlon(w, h, depth, region="brick", arc_seg=5, back=True, seed=0, pointed=0.0) -> Mesh:
    """Скруглённый зубец (ТЗ 11.3): основание в y=0, лицо в +Z (z от 0 до depth), центр по x=0."""
    rs = np.random.default_rng(abs(int(seed)))
    poly = arc_merlon_poly(w, h, arc_seg, pointed)
    tw, th = TILE.get(region, (3.2, 1.6))
    uw, vh = w / tw, h / (th or 1.6)
    u0 = rs.uniform(0.05, max(0.06, 0.95 - uw))
    v0 = rs.uniform(0.05, max(0.06, 0.95 - vh))
    m = prism(poly, depth, region, (u0, v0, u0 + uw, v0 + vh), back=back)
    return m


# ---------------------------------------------------------------- жерди, трубки, мелочи

def pole(a, b, r0, r1=None, sides=6, region="pole", caps=False, tile_len=None) -> Mesh:
    """Жердь от a к b: конус r0→r1, UV в область (v вдоль длины или tile_len)."""
    a, b = np.asarray(a, float), np.asarray(b, float)
    L = float(np.linalg.norm(b - a))
    r1 = r0 if r1 is None else r1
    m = K.lathe([(r0, 0.0), (r1, L)], sides, 1.0, cap_top=caps, normals="smooth")
    m.UV[:, 1] = np.clip(m.UV[:, 1] * (L / tile_len if tile_len else 1.0), 0, 1)
    to_region(m, region)
    return m.align(a, b)


def beam(a, b, w, h, region="wood", up=(0, 1, 0), ends=True) -> Mesh:
    """Брус прямоугольного сечения от a к b (4 грани вдоль, торцы по желанию)."""
    a, b = np.asarray(a, float), np.asarray(b, float)
    d = b - a
    L = np.linalg.norm(d)
    d /= L
    up = np.asarray(up, float)
    s = np.cross(d, up)
    if np.linalg.norm(s) < 1e-6:
        s = np.cross(d, [1, 0, 0])
    s /= np.linalg.norm(s)
    u = np.cross(s, d)
    parts = []
    corners = [(-1, -1), (1, -1), (1, 1), (-1, 1)]
    for i in range(4):
        c0, c1 = corners[i], corners[(i + 1) % 4]
        p0 = s * c0[0] * w / 2 + u * c0[1] * h / 2
        p1 = s * c1[0] * w / 2 + u * c1[1] * h / 2
        q = quad(a + p0, a + p1, b + p1, b + p0, region, uvs=((0, 1), (0.3, 1), (0.3, 0), (0, 0)))
        parts.append(q)
    m = Mesh.merge(parts)
    ctr = (a + b) / 2
    if ends:
        for p, sg in ((a, -1), (b, 1)):
            pts = [p + s * cx * w / 2 + u * cy * h / 2 for cx, cy in corners]
            q = quad(*pts, "logend") if sg > 0 else quad(*pts[::-1], "logend")
            parts.append(q)
        m = Mesh.merge(parts)
    _orient_out(m, ctr)
    return m


def _orient_out(m: Mesh, center):
    """Разворачивает треугольники, чьи нормали смотрят внутрь (для выпуклых тел)."""
    P, F = m.P, m.F
    fn = np.cross(P[F[:, 1]] - P[F[:, 0]], P[F[:, 2]] - P[F[:, 0]])
    fc = P[F].mean(axis=1)
    bad = np.einsum("ij,ij->i", fn, fc - np.asarray(center)) < 0
    m.F[bad] = m.F[bad][:, ::-1]
    # плоские нормали по граням-четвёркам: пересчитать по треугольникам
    n = np.zeros_like(P)
    fn = np.cross(P[m.F[:, 1]] - P[m.F[:, 0]], P[m.F[:, 2]] - P[m.F[:, 0]])
    for k in range(3):
        np.add.at(n, m.F[:, k], fn)
    ln = np.linalg.norm(n, axis=1, keepdims=True)
    ln[ln == 0] = 1
    m.N = n / ln
    return m


def path_tube(path, radius, sides=5, region="rope", tile_len=1.0) -> Mesh:
    m = K.tube(path, radius, sides=sides, uv_len=1.0 / tile_len)
    m.UV[:, 1] = np.clip(m.UV[:, 1], 0, 1)
    return to_region(m, region)


def quad(p0, p1, p2, p3, region, uvs=((0, 1), (1, 1), (1, 0), (0, 0)), two_sided=False) -> Mesh:
    """Четырёхугольник p0-p1-p2-p3 (против часовой, если смотреть с лица)."""
    P = np.array([p0, p1, p2, p3], float)
    n = np.cross(P[1] - P[0], P[2] - P[0])
    n /= max(np.linalg.norm(n), EPS)
    m = Mesh(P, [(0, 1, 2), (0, 2, 3)], np.tile(n, (4, 1)), np.array(uvs, float))
    m = to_region(m, region)
    if two_sided:
        m = Mesh.merge([m, m.copy().flip()])
    return m


def box(sx, sy, sz, faces, default=None) -> Mesh:
    """Параллелепипед (основание на y=0) с областью атласа на каждую грань (UV 0..1 на грань)."""
    names = ["front", "back", "right", "left", "top", "bottom"]
    m = K.box(sx, sy, sz)
    parts = []
    for i, nm in enumerate(names):
        spec = faces.get(nm, default)
        if spec is None:
            continue
        name, rotq = (spec if isinstance(spec, tuple) else (spec, False))
        f = Mesh(m.P[i * 4:i * 4 + 4], [(0, 1, 2), (0, 2, 3)], m.N[i * 4:i * 4 + 4],
                 [(0, 1), (1, 1), (1, 0), (0, 0)])
        if rotq:
            f.UV = np.array([(0, 0), (0, 1), (1, 1), (1, 0)], float)
        parts.append(to_region(f, name))
    return Mesh.merge(parts)


def lump(rx, ry, rz, seg_u=8, seg_v=4, region="stones", seed=0, amount=0.12, flat_bottom=True) -> Mesh:
    """Неровный ком (камень, куча щебня, мешок): эллипсоид с низкочастотной неровностью, UV сверху."""
    m = K.ellipsoid(rx, ry, rz, seg_u, seg_v, y_from=0.0 if flat_bottom else -1.0, y_to=1.0)
    rs = np.random.default_rng(abs(int(seed)))
    ph = rs.uniform(0, 6.28, 6)
    th = np.arctan2(m.P[:, 0], m.P[:, 2])
    yy = m.P[:, 1] / max(ry, 1e-6)
    k = 1 + amount * (np.sin(th * 2 + ph[0]) * 0.5 + np.sin(th * 3 + ph[1] + yy * 2) * 0.35
                      + np.sin(yy * 3 + ph[2]) * 0.3)
    m.P = m.P * np.column_stack([k, np.where(m.P[:, 1] > 1e-6, k, 1), k])
    m.UV = np.column_stack([0.5 + m.P[:, 0] / (2.2 * rx), 0.5 + m.P[:, 2] / (2.2 * rz)])
    m.UV = 0.5 + (m.UV - 0.5) * 0.9 + rs.uniform(-0.04, 0.04, 2)
    m.smooth()
    return to_region(m, region)


def disc_uv(r, segments, region, y=0.0, up=True) -> Mesh:
    m = K.disc(r, segments)
    if not up:
        m.flip()
    m.translate(0, y, 0)
    return to_region(m, region)


def ring_flat(r_in, r_out, y, segments, region, tiles=4) -> Mesh:
    """Плоское кольцо (площадка башни, верх стены по кругу), нормаль +Y; по окружности tiles плиток."""
    parts = []
    span = 360.0 / tiles
    for k in range(tiles):
        p = K.lathe([(r_out, y), (r_in, y)], segments, 1.0, sweep=span, start=k * span, normals="smooth")
        p.N[:] = (0, 1, 0)
        fn = np.cross(p.P[p.F[0, 1]] - p.P[p.F[0, 0]], p.P[p.F[0, 2]] - p.P[p.F[0, 0]])
        if fn[1] < 0:
            p.F = p.F[:, ::-1].copy()
        p.UV[:, 1] = 1 - p.UV[:, 1]
        parts.append(to_region(p, region))
    return Mesh.merge(parts)


def place(m: Mesh, x=0.0, y=0.0, z=0.0, yaw=0.0, scale=1.0) -> Mesh:
    if scale != 1.0:
        m.scale(scale)
    if yaw:
        m.rotate_y(yaw)
    return m.translate(x, y, z)


def tris(meshes) -> int:
    return sum(m.tris for m in meshes)


def deg(a):
    return math.degrees(a)
