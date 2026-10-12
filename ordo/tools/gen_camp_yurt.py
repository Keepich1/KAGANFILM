"""Боз үй и Хан ордосу — одобренная автором форма юрты (ТЗ 11.3).

Прямая войлочная стена; конический купол, перетянутый верёвками крест-накрест
в ромбическую сетку; небольшой тюндюк с перекрестьем (кайчы); пояса коричневых
завитков и ромбов на стене (рисунок атласа); высокая дверь в резной раме со
свёрнутой кошмой над ней. У ханской юрты — щиты с конскими кистями и навес.

Войлок не идеальный цилиндр: провисает между жердями уука и решёткой,
низ чуть расходится, рука мастера — лёгкая неровность.
"""
from __future__ import annotations

import math
from dataclasses import dataclass, field

import numpy as np

import gen_camp_kit as G
import meshkit as K
from gen_camp_atlas import NET_ROOTS_PER_TILE, net_curve
from meshkit import Mesh


@dataclass
class YurtSpec:
    name: str
    R: float                 # радиус стены
    wall_h: float            # высота стены
    top_y: float             # высота верха купола (низ кольца тюндюка)
    tunduk_r: float          # внешний радиус кольца тюндюка
    door_w: float
    door_h: float
    post_w: float
    post_d: float
    lintel_h: float
    roll_r: float
    wall_region: str
    eave_region: str
    tiles_wall: int
    tiles_dome: int
    seg: int                 # сегментов на плитку
    rope_w: float
    rope_h: float
    rope_seg: int
    arch_h: float
    shields: list = field(default_factory=list)   # углы щитов, градусы от двери
    awning: bool = False
    lod: int = 0


def boz_spec(lod=0) -> YurtSpec:
    return YurtSpec("boz", R=3.1, wall_h=1.9, top_y=4.3, tunduk_r=0.7, door_w=0.98, door_h=1.8, post_w=0.15,
                    post_d=0.26, lintel_h=0.2, roll_r=0.15, wall_region="wall_boz", eave_region="eave_boz",
                    tiles_wall=4, tiles_dome=4, seg=12 if lod == 0 else 11, rope_w=0.085, rope_h=0.045,
                    rope_seg=6, arch_h=0.3, lod=lod)


def ordo_spec(lod=0) -> YurtSpec:
    return YurtSpec("ordo", R=6.0, wall_h=2.7, top_y=7.75, tunduk_r=1.25, door_w=1.5, door_h=2.5, post_w=0.24,
                    post_d=0.36, lintel_h=0.3, roll_r=0.24, wall_region="wall_ordo", eave_region="eave_ordo",
                    tiles_wall=6, tiles_dome=6, seg=14 if lod == 0 else 11, rope_w=0.13, rope_h=0.06,
                    rope_seg=8, arch_h=0.55, shields=[-28, 28, -62, 62, -98, 98, -135, 135], awning=True, lod=lod)


# ---------------------------------------------------------------- профиль

def profiles(s: YurtSpec):
    """Профили (радиус, высота): стена, свес-плечо, купол."""
    R, H = s.R, s.wall_h
    k = R / 3.1  # масштаб деталей относительно боз үй
    wall = [(R + 0.06 * k, 0.0), (R + 0.025 * k, 0.12 * k), (R, 0.32 * k), (R + 0.02 * k, H * 0.5),
            (R + 0.005 * k, H * 0.82), (R - 0.01 * k, H)]
    if s.lod:
        wall = [wall[0], wall[2], wall[3], wall[5]]
    eave = [(R + 0.12 * k, H - 0.15 * k), (R + 0.15 * k, H + 0.02 * k), (R + 0.03 * k, H + 0.3 * k),
            (R - 0.33 * k, H + 0.64 * k)]
    b = eave[-1]
    t = (s.tunduk_r + 0.03 * k, s.top_y)
    n = 5 if s.lod == 0 else 3
    dome = []
    for i in range(n + 1):
        f = i / n
        r = b[0] + (t[0] - b[0]) * f
        y = b[1] + (t[1] - b[1]) * f
        r += 0.07 * k * math.sin(math.pi * f) ** 1.2  # лёгкая выпуклость жердей уука
        dome.append((r, y))
    return wall, eave, dome


def warp_dome(s: YurtSpec):
    """Провис войлока между жердями уука и рукотворная неровность."""
    n_uuk = 64 if s.name == "ordo" else 44
    k = s.R / 3.1

    def fn(th, y, r):
        t = np.clip((y - s.wall_h) / (s.top_y - s.wall_h), 0, 1)
        sag = 0.017 * (0.5 - 0.5 * np.cos(np.radians(th) * n_uuk)) * np.sin(np.pi * np.clip(t * 1.2, 0, 1))
        hand = 0.008 * np.sin(np.radians(th) * 3 + 1.3) + 0.006 * np.sin(np.radians(th) * 5 + y * 1.7) \
            + 0.004 * np.sin(np.radians(th) * 11 + 0.4)
        return 1.0 - sag * (1.0 / k) ** 0.3 + hand * (1 - 0.6 * t)
    return fn


def warp_wall(s: YurtSpec):
    def fn(th, y, r):
        a = np.radians(th)
        mid = np.sin(np.pi * np.clip(y / s.wall_h, 0, 1))
        hand = 0.007 * np.sin(a * 3 + 0.6) + 0.005 * np.sin(a * 7 + 2.1) + 0.004 * np.sin(a * 13 + y * 3)
        lattice = 0.006 * np.abs(np.sin(a * (70 if s.name == "ordo" else 40))) * mid
        # войлок чуть выпирает между горизонтальными верёвками стены и провисает у них
        belly = 0.006 * np.sin(np.pi * np.clip(y / s.wall_h, 0, 1) * 2.0) ** 2
        return 1.0 + hand * mid + lattice + belly
    return fn


# ---------------------------------------------------------------- части

def door_geometry(s: YurtSpec):
    """Рама, створки, порог, свёрнутая кошма и завязки. Возвращает (меши, z передней плоскости, угол проёма)."""
    half = s.door_w / 2 + s.post_w
    zc = math.sqrt(s.R ** 2 - half ** 2)
    z_back = zc - 0.03
    parts = []
    for side in (-1, 1):
        p = G.box(s.post_w, s.door_h, s.post_d, {"front": "frame", "left": "walnut", "right": "walnut"})
        p.translate(side * (s.door_w / 2 + s.post_w / 2), 0, z_back + s.post_d / 2)
        parts.append(p)
    lw = s.door_w + 2 * s.post_w + 0.12
    lint = G.box(lw, s.lintel_h, s.post_d + 0.05, {"front": ("frame", True), "top": "walnut", "bottom": "walnut",
                                                     "left": "walnut", "right": "walnut"})
    lint.translate(0, s.door_h, z_back + (s.post_d + 0.05) / 2)
    parts.append(lint)
    thr = G.box(s.door_w + 0.02, 0.07, s.post_d * 0.8, {"front": "walnut", "top": "walnut"})
    thr.translate(0, 0, z_back + s.post_d * 0.4)
    parts.append(thr)
    zl = z_back + 0.06
    leaf = G.quad((-s.door_w / 2, 0.07, zl), (s.door_w / 2, 0.07, zl), (s.door_w / 2, s.door_h, zl),
                  (-s.door_w / 2, s.door_h, zl), "door")
    parts.append(leaf)
    # свёрнутая кошма над дверью (рулон вдоль X)
    L = lw - 0.04
    roll = K.lathe([(s.roll_r, 0.0), (s.roll_r * 1.02, L * 0.5), (s.roll_r, L)], 12 if s.lod == 0 else 8, 1.0,
                   normals="smooth")
    G.to_region(roll, "koshma")
    roll.rotate_z(-90).translate(-L / 2, 0, 0)
    caps = []
    if s.lod == 0:
        for sx in (-1, 1):
            cap = G.disc_uv(s.roll_r * 0.98, 12, "koshma_end")
            cap.rotate_z(-90 * sx).translate(sx * L / 2, 0, 0)
            caps.append(cap)
    ry = s.door_h + s.lintel_h + s.roll_r * 0.92
    rz = z_back + s.post_d * 0.55
    roll = Mesh.merge([roll] + caps).translate(0, ry, rz)
    roll = G.shade(roll, lambda P: 0.88 + 0.12 * np.clip((P[:, 1] - ry + s.roll_r) / (2 * s.roll_r), 0, 1))
    parts.append(roll)
    # завязки кошмы: два кожаных ремня свисают с рулона
    if s.lod == 0:
        for sx in (-0.32, 0.32):
            x = sx * L
            path = np.array([[x, ry + s.roll_r, rz - 0.02], [x, ry + s.roll_r * 0.2, rz + s.roll_r + 0.01],
                             [x + 0.01, ry - s.roll_r * 0.9, rz + s.roll_r * 0.9],
                             [x + 0.02, ry - s.roll_r - 0.28, rz + s.roll_r * 0.75]])
            up = np.tile([0, 0, 1.0], (4, 1))
            up[0] = (0, 1, 0)
            parts.append(G.ribbon(path, up, 0.045 * s.R / 3.1, "leather", tile_len=1.0, lift=0.012, two_sided=True))
    front = z_back + s.post_d
    gap = math.degrees(math.asin((s.door_w / 2 + s.post_w * 0.55) / s.R))
    return parts, front, gap


def tunduk(s: YurtSpec):
    """Кольцо тюндюка, тёмное нутро и перекрестье из гнутых планок (кайчы)."""
    k = s.R / 3.1
    ro, ri = s.tunduk_r + 0.03 * k, s.tunduk_r - 0.1 * k
    y0 = s.top_y
    segs = 24 if s.lod == 0 else 12
    ring = K.lathe([(ro, y0 - 0.06 * k), (ro, y0 + 0.11 * k), (ri, y0 + 0.13 * k), (ri, y0 - 0.12 * k)], segs, 1.0,
                   normals="crease")
    G.to_region(ring, "walnut")
    hole = G.disc_uv(ri, segs, "tunduk_hole", y=y0 - 0.1 * k)
    parts = [ring, hole]
    w, hgt = 0.075 * k, 0.06 * k
    offsets = (-0.42, 0.0, 0.42) if s.lod == 0 else (0.0,)
    n = 6 if s.lod == 0 else 4
    for fam in (0, 1):
        for d in offsets:
            dd = d * ri
            L = math.sqrt(ri ** 2 - dd ** 2) + 0.02 * k
            ss = np.linspace(-L, L, n + 1)
            yy = y0 + 0.12 * k + s.arch_h * (1 - (ss / L) ** 2) * (1 - 0.25 * abs(d))
            pts = np.column_stack([ss, yy, np.full_like(ss, dd)]) if fam == 0 else \
                np.column_stack([np.full_like(ss, dd), yy + 0.02 * k, ss])
            parts.append(_beam(pts, w, hgt, "walnut"))
    return Mesh.merge(parts)


def _beam(pts, w, h, region):
    """Брусок по ломаной: верх и две боковые грани."""
    pts = np.asarray(pts, float)
    T = np.gradient(pts, axis=0)
    T /= np.linalg.norm(T, axis=1, keepdims=True)
    up0 = np.array([0, 1.0, 0])
    side = np.cross(T, up0)
    side /= np.linalg.norm(side, axis=1, keepdims=True)
    up = np.cross(side, T)
    parts = []
    # три грани: левая, верхняя, правая
    corners = [(-side * w / 2 - up * h / 2), (-side * w / 2 + up * h / 2), (side * w / 2 + up * h / 2),
               (side * w / 2 - up * h / 2)]
    faces = [(0, 1, -side), (1, 2, up), (2, 3, side)]
    L = np.r_[0, np.cumsum(np.linalg.norm(np.diff(pts, axis=0), axis=1))]
    for ia, ib, nrm in faces:
        P, N, UV, F = [], [], [], []
        for i in range(len(pts)):
            P += [pts[i] + corners[ia][i], pts[i] + corners[ib][i]]
            N += [nrm[i], nrm[i]]
            v = L[i] / max(L[-1], 1e-9)
            UV += [(0.2, v), (0.8, v)]
        for i in range(len(pts) - 1):
            a = i * 2
            F += [(a, a + 2, a + 3), (a, a + 3, a + 1)]
        m = Mesh(P, F, N, UV)
        fn = np.cross(m.P[F[0][1]] - m.P[F[0][0]], m.P[F[0][2]] - m.P[F[0][0]])
        if np.dot(fn, nrm[0]) < 0:
            m.F = m.F[:, ::-1].copy()
        parts.append(G.to_region(m, region))
    return Mesh.merge(parts)


def rope_net(s: YurtSpec, eave, dome):
    """Ромбическая сетка верёвок по куполу (совпадает с рисунком атласа) и спуски по плечу."""
    roots = NET_ROOTS_PER_TILE * s.tiles_dome
    tile_deg = 360.0 / s.tiles_dome
    at = G.profile_sampler(dome)
    warp = warp_dome(s)
    parts = []
    for fam in (-1, 1):
        for j in range(roots):
            u, ts = net_curve(j % NET_ROOTS_PER_TILE, fam, s.rope_seg + 1)
            th = (u + j // NET_ROOTS_PER_TILE) * tile_deg
            r, y, nr, ny = at(ts)
            rr = r * warp(th, y, r)
            a = np.radians(th)
            P = np.column_stack([rr * np.sin(a), y, rr * np.cos(a)])
            N = np.column_stack([nr * np.sin(a), ny, nr * np.cos(a)])
            if s.lod == 0:
                parts.append(G.strip(P, N, s.rope_w, s.rope_h, "rope", tile_len=1.2, lift=0.006))
            else:
                parts.append(G.ribbon(P, N, s.rope_w * 1.1, "rope", tile_len=99.0, lift=0.02))
    if s.lod == 0:
        # спуски по плечу к стене: по одной верёвке от каждого корня
        at_e = G.profile_sampler(eave)
        te = np.linspace(1.0, 0.08, 4)
        for j in range(roots):
            th = np.full_like(te, j * 360.0 / roots)
            r, y, nr, ny = at_e(te)
            a = np.radians(th)
            rr = r * warp(th, y, r)
            P = np.column_stack([rr * np.sin(a), y, rr * np.cos(a)])
            N = np.column_stack([nr * np.sin(a), ny, nr * np.cos(a)])
            parts.append(G.strip(P, N, s.rope_w * 1.2, s.rope_h, "rope", tile_len=1.2, lift=0.006))
    return Mesh.merge(parts)


def shield(radius, lod=0):
    """Круглый щит (лицом в +Z): чуть выпуклый, обод, латунный умбон. Начало — центр задней кромки."""
    segs = 14 if lod == 0 else 8
    face = K.lathe([(radius, 0.0), (radius * 0.94, radius * 0.03), (radius * 0.55, radius * 0.11),
                    (0.0, radius * 0.16)], segs, 1.0, normals="smooth")
    face.UV = np.column_stack([0.5 + face.P[:, 0] / (2.04 * radius), 0.5 + face.P[:, 2] / (2.04 * radius)])
    G.to_region(face, "shield")
    rim = K.lathe([(radius * 0.9, -radius * 0.09), (radius * 1.02, -radius * 0.05), (radius, 0.0)], segs, 1.0,
                  normals="smooth")
    rim.UV[:] = (0.5, 0.012)
    G.to_region(rim, "shield")
    parts = [face, rim]
    boss = K.lathe([(radius * 0.24, radius * 0.13), (radius * 0.22, radius * 0.2), (radius * 0.12, radius * 0.28),
                    (0.0, radius * 0.3)], 8, 1.0, normals="smooth")
    G.to_region(boss, "brass")
    parts.append(boss)
    m = Mesh.merge(parts).rotate_x(90)
    return m


def tassel(length, radius, lod=0, region="tassel"):
    """Кисть из конского волоса: обмотка-узел сверху, расходящийся пучок вниз. Начало — верх."""
    prof = [(0.0, 0.0), (radius * 0.45, -length * 0.03), (radius * 0.5, -length * 0.16), (radius * 0.32, -length * 0.22),
            (radius * 0.55, -length * 0.3), (radius * 0.95, -length * 0.85), (radius * 0.7, -length * 0.98),
            (0.0, -length)]
    if lod:
        prof = [prof[0], prof[2], prof[3], prof[5], prof[7]]
    m = K.lathe(prof[::-1], 6, 1.0, normals="smooth")
    m.UV[:, 1] = 1.0 - m.UV[:, 1]
    G.to_region(m, region, flip_v=False)
    return m


def awning(s: YurtSpec, front_z):
    """Войлочный навес над дверью ордо: крыша от стены над дверью к двум шестам и
    свисающая спереди кайма-подзор с фестонами (верх области атласа — крыша, низ — кайма).
    UV2.x — доля «свободы» (0 у стены → 1 у края подзора) для колыхания в cloth.gdshader."""
    W, D, drop = 4.0, 1.7, 0.5
    y_back, y_front = s.wall_h + 0.45, s.door_h + s.lintel_h - 0.3
    nx, nz, nv = 8, 4, 2
    P, UV, UV2, F = [], [], [], []
    rows = []
    for j in range(nz + 1):  # крыша
        q = j / nz
        z = front_z - 0.1 + q * D
        rows.append((q, z, None))
    for j in range(1, nv + 1):  # подзор
        rows.append((1.0 + j / nv, front_z - 0.1 + D + 0.02 * j, j / nv))
    for k, (q, z, vq) in enumerate(rows):
        for i in range(nx + 1):
            sx = i / nx
            x = (sx - 0.5) * W
            pin = abs(sx - 0.5) * 2
            if vq is None:
                sag = 0.22 * math.sin(math.pi * q) * (1 - 0.5 * pin ** 2) + 0.1 * q * (1 - pin ** 2)
                y = y_back + (y_front - y_back) * q ** 0.9 - sag
                v = q * 0.52
                free = q * 0.7
            else:
                y = y_front - 0.1 * (1 - pin ** 2) - drop * vq
                v = 0.52 + vq * 0.48
                free = 0.7 + 0.3 * vq
            P.append((x, y, z))
            UV.append((sx, v))
            UV2.append((free, sx))
    for k in range(len(rows) - 1):
        for i in range(nx):
            a = k * (nx + 1) + i
            b = a + nx + 1
            F += [(a, b, b + 1), (a, b + 1, a + 1)]
    m = Mesh(P, F, None, UV, UV2)
    m.recalc_normals()
    G.to_region(m, "awning")
    # шесты и растяжки
    parts = []
    for sx in (-1, 1):
        x, z = sx * W / 2 * 0.96, front_z - 0.1 + D
        parts.append(G.pole((x, 0, z), (x, y_front + 0.3, z), 0.06, 0.045, sides=6, region="pole"))
        knob = K.ellipsoid(0.08, 0.07, 0.08, 6, 3).translate(x, y_front + 0.33, z)
        parts.append(G.to_region(knob, "brass"))
        peg = (x * 1.2, 0.05, z + 0.9)
        parts.append(G.path_tube([(x, y_front + 0.25, z), peg], 0.018, sides=4, region="rope", tile_len=3.0))
        parts.append(G.pole(peg, (peg[0], 0.32, peg[2] - 0.05), 0.03, 0.025, sides=4, region="wood"))
    return m, Mesh.merge(parts)


# ---------------------------------------------------------------- сборка

def build(s: YurtSpec):
    """Узлы glb: ("Yurt", меш, opaque), ("Awning", меш, cloth) — материал выбирает вызывающий."""
    wall_p, eave_p, dome_p = profiles(s)
    door, front_z, gap = door_geometry(s)
    wall = G.lathe_tiled(wall_p, s.tiles_wall, s.seg, gap, 360 - gap, s.wall_region, flip_v=True)
    G.radial_warp(wall, warp_wall(s))
    wall.smooth()
    # тень под свесом и у земли — в цвете вершин
    G.shade(wall, lambda P: (1 - 0.22 * np.clip(1 - P[:, 1] / 0.45, 0, 1) ** 1.6)
            * (1 - 0.18 * np.clip((P[:, 1] - (s.wall_h - 0.35)) / 0.35, 0, 1)))
    eave = G.lathe_tiled(eave_p, s.tiles_dome, s.seg, 0, 360, s.eave_region, flip_v=True)
    dome = G.lathe_tiled(dome_p, s.tiles_dome, s.seg, 0, 360, "dome", flip_v=True)
    for m in (eave, dome):
        G.radial_warp(m, warp_dome(s))
        m.smooth()
        G.white(m)
    parts = [wall, eave, dome, tunduk(s)] + door
    parts.append(rope_net(s, eave_p, dome_p))
    k = s.R / 3.1
    for ang in s.shields:
        a = math.radians(ang)
        r = s.R * 1.004
        sh = shield(0.42 * k * 0.8, s.lod)
        y = s.wall_h * 0.6
        sh.rotate_y(ang).translate(r * math.sin(a), y, r * math.cos(a))
        parts.append(sh)
        for dx in ((-0.22, 0.22) if s.lod == 0 else (0.0,)):
            ta = tassel(0.62 * k * 0.8, 0.075 * k, s.lod)
            off = dx * k * 0.8
            px = r * math.sin(a) + math.cos(a) * off + math.sin(a) * 0.1
            pz = r * math.cos(a) - math.sin(a) * off + math.cos(a) * 0.1
            ta.translate(px, y - 0.3 * k * 0.8, pz)
            parts.append(ta)
    for p in parts:
        if not p.has_color:
            G.white(p)
    nodes = [("Yurt", Mesh.merge(parts), "opaque")]
    if s.awning:
        cloth, rig = awning(s, front_z)
        G.white(rig)
        nodes[0] = ("Yurt", Mesh.merge(parts + [rig]), "opaque")
        nodes.append(("Awning", G.white(cloth), "cloth"))
    return nodes
