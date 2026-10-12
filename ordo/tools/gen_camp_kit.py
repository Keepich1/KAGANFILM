"""Помощники мешей лагеря поверх tools/meshkit.py: развёртка в область атласа,
повтор плиток, верёвки по поверхности, ящики с UV по граням, нарисованная тень
в цвете вершин (множитель в painterly_surface).
"""
from __future__ import annotations

import math

import numpy as np

import meshkit as K
from meshkit import Mesh
from gen_camp_atlas import uv as atlas_uv


# ---------------------------------------------------------------- UV и цвет

def to_region(m: Mesh, name, flip_v=False, inset=0.0) -> Mesh:
    """UV 0..1 → область атласа; flip_v — перевернуть v (верх картинки = верх модели)."""
    if flip_v:
        m.UV[:, 1] = 1.0 - m.UV[:, 1]
    m.UV = np.clip(m.UV, 0.0, 1.0)
    return m.map_uv(atlas_uv(name, inset))


def shade(m: Mesh, fn) -> Mesh:
    """Цвет вершин = fn(P) → множитель (n,) или (n,3). Нарисованная тень/подсветка."""
    v = np.asarray(fn(m.P), dtype=np.float64)
    if v.ndim == 1:
        v = np.repeat(v[:, None], 3, axis=1)
    old = m.C[:, :3] if m.has_color else np.ones((len(m.P), 3))
    m.C = np.column_stack([np.clip(old * v, 0, 2), np.ones(len(m.P))])
    m.has_color = True
    return m


def ground_ao(m: Mesh, depth=0.35, strength=0.3, y0=0.0) -> Mesh:
    """Темнее у земли: контактная тень, нарисованная в цвете вершин."""
    return shade(m, lambda P: 1.0 - strength * np.clip(1.0 - (P[:, 1] - y0) / depth, 0, 1) ** 1.5)


def white(m: Mesh) -> Mesh:
    m.C = np.ones((len(m.P), 4))
    m.has_color = True
    return m


# ---------------------------------------------------------------- тела вращения

def lathe_tiled(profile, tiles, seg_per_tile, start_deg, end_deg, region, flip_v=True, normals="smooth"):
    """Тело вращения из `tiles` кусков, каждый получает всю область атласа (u 0..1).
    Область должна повторяться по x (бесшовно), тогда шва не видно."""
    span = (end_deg - start_deg) / tiles
    parts = []
    for k in range(tiles):
        p = K.lathe(profile, seg_per_tile, 1.0, sweep=span, start=start_deg + k * span, normals=normals)
        to_region(p, region, flip_v=flip_v)
        parts.append(p)
    return Mesh.merge(parts)


def radial_warp(m: Mesh, fn) -> Mesh:
    """Радиус каждой вершины × fn(θ, y, r): провис войлока, неровность руки.
    θ — угол от +Z к +X (как в meshkit.lathe), градусы."""
    x, y, z = m.P[:, 0], m.P[:, 1], m.P[:, 2]
    r = np.hypot(x, z)
    th = np.degrees(np.arctan2(x, z))
    k = fn(th, y, r)
    m.P = np.column_stack([x * k, y, z * k])
    return m


def profile_sampler(profile):
    """Функция s∈[0,1] (доля длины профиля) → (r, y, nr, ny) — точка и нормаль профиля."""
    p = np.asarray(profile, float)
    L = np.r_[0, np.cumsum(np.linalg.norm(np.diff(p, axis=0), axis=1))]
    L /= L[-1]

    def at(s):
        s = np.clip(s, 0, 1)
        r = np.interp(s, L, p[:, 0])
        y = np.interp(s, L, p[:, 1])
        i = np.clip(np.searchsorted(L, s, side="right") - 1, 0, len(p) - 2)
        d = p[i + 1] - p[i]
        d = d / np.linalg.norm(d, axis=-1, keepdims=True)
        return r, y, d[..., 1], -d[..., 0]
    return at


# ---------------------------------------------------------------- полосы и верёвки

def strip(path, up, width, height, region, tile_len=1.0, lift=0.01) -> Mesh:
    """Верёвка-«гребень» вдоль ломаной path, лежащая на поверхности с нормалями up.
    Сечение — домик (левый край, гребень, правый край): 4 треуг. на отрезок.
    UV: u поперёк (0 — 0.5 — 1), v вдоль, кусками по tile_len (область повторяется по y)."""
    path = np.asarray(path, float)
    up = np.asarray(up, float)
    up = up / np.linalg.norm(up, axis=1, keepdims=True)
    T = np.gradient(path, axis=0)
    T = T / np.maximum(np.linalg.norm(T, axis=1, keepdims=True), 1e-9)
    Bn = np.cross(T, up)
    Bn = Bn / np.maximum(np.linalg.norm(Bn, axis=1, keepdims=True), 1e-9)
    seg = np.linalg.norm(np.diff(path, axis=0), axis=1)
    cum = np.r_[0, np.cumsum(seg)]
    # разрезаем по плиткам
    cuts = np.arange(tile_len, cum[-1], tile_len)
    s_all = np.unique(np.r_[cum, cuts])
    P = np.column_stack([np.interp(s_all, cum, path[:, k]) for k in range(3)])
    U = np.column_stack([np.interp(s_all, cum, up[:, k]) for k in range(3)])
    Bx = np.column_stack([np.interp(s_all, cum, Bn[:, k]) for k in range(3)])
    U /= np.linalg.norm(U, axis=1, keepdims=True)
    Bx /= np.linalg.norm(Bx, axis=1, keepdims=True)
    parts = []
    tile_id = np.floor((s_all[:-1] + s_all[1:]) / 2 / tile_len).astype(int)
    for t in np.unique(tile_id):
        idx = np.where(tile_id == t)[0]
        ii = np.r_[idx, idx[-1] + 1]
        verts, nrm, uvs = [], [], []
        for i in ii:
            base = P[i] + U[i] * lift
            v = (s_all[i] - t * tile_len) / tile_len
            verts += [base - Bx[i] * width / 2, base + U[i] * height, base + Bx[i] * width / 2]
            nrm += [U[i] * 0.35 - Bx[i], U[i], U[i] * 0.35 + Bx[i]]
            uvs += [(0.0, v), (0.5, v), (1.0, v)]
        F = []
        for j in range(len(ii) - 1):
            a = j * 3
            F += [(a, a + 3, a + 4), (a, a + 4, a + 1), (a + 1, a + 4, a + 5), (a + 1, a + 5, a + 2)]
        m = Mesh(verts, F, nrm, uvs)
        # ориентация: проверим, что лицевая сторона смотрит по up
        fn = np.cross(m.P[m.F[0, 1]] - m.P[m.F[0, 0]], m.P[m.F[0, 2]] - m.P[m.F[0, 0]])
        if np.dot(fn, U[ii[0]]) < 0:
            m.F = m.F[:, ::-1].copy()
        parts.append(to_region(m, region))
    return Mesh.merge(parts)


def ribbon(path, up, width, region, tile_len=1.0, lift=0.01, two_sided=False) -> Mesh:
    """Плоская лента вдоль path (ремень, пояс, полоса ткани), лицом по up."""
    path = np.asarray(path, float)
    up = np.asarray(up, float)
    up = up / np.linalg.norm(up, axis=1, keepdims=True)
    T = np.gradient(path, axis=0)
    T = T / np.maximum(np.linalg.norm(T, axis=1, keepdims=True), 1e-9)
    Bn = np.cross(T, up)
    Bn = Bn / np.maximum(np.linalg.norm(Bn, axis=1, keepdims=True), 1e-9)
    seg = np.linalg.norm(np.diff(path, axis=0), axis=1)
    cum = np.r_[0, np.cumsum(seg)]
    verts, nrm, uvs, F = [], [], [], []
    for i in range(len(path)):
        b = path[i] + up[i] * lift
        v = min(cum[i] / max(tile_len, 1e-9), 1.0)
        verts += [b - Bn[i] * width / 2, b + Bn[i] * width / 2]
        nrm += [up[i], up[i]]
        uvs += [(0.0, v), (1.0, v)]
    for j in range(len(path) - 1):
        a = j * 2
        F += [(a, a + 2, a + 3), (a, a + 3, a + 1)]
    m = Mesh(verts, F, nrm, uvs)
    fn = np.cross(m.P[m.F[0, 1]] - m.P[m.F[0, 0]], m.P[m.F[0, 2]] - m.P[m.F[0, 0]])
    if np.dot(fn, up[0]) < 0:
        m.F = m.F[:, ::-1].copy()
    m = to_region(m, region)
    if two_sided:
        back = m.copy().flip()
        m = Mesh.merge([m, back])
    return m


# ---------------------------------------------------------------- ящики и трубы

def box(sx, sy, sz, faces, default=None, center_y=False) -> Mesh:
    """Параллелепипед (основание на y=0) с областью атласа на каждую грань.
    faces: {"front"/"back"/"left"/"right"/"top"/"bottom": имя | (имя, повернуть) | None}.
    Повернуть — True: v идёт по горизонтали (резной пояс по перемычке)."""
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
    out = Mesh.merge(parts)
    if center_y:
        out.translate(0, -sy / 2, 0)
    return out


def pole(a, b, r0, r1=None, sides=6, region="pole", caps=False, tile_len=None) -> Mesh:
    """Жердь от a к b: конус r0→r1, UV в область (v растянута на длину или tile_len)."""
    a, b = np.asarray(a, float), np.asarray(b, float)
    L = float(np.linalg.norm(b - a))
    r1 = r0 if r1 is None else r1
    m = K.lathe([(r0, 0.0), (r1, L)], sides, 1.0, cap_top=caps, normals="smooth")
    m.UV[:, 1] = np.clip(m.UV[:, 1] * (L / tile_len if tile_len else 1.0), 0, 1)
    to_region(m, region)
    return m.align(a, b)


def path_tube(path, radius, sides=5, region="rope", tile_len=1.0) -> Mesh:
    """Трубка по ломаной (верёвка, ветка), UV v вдоль, растянута на tile_len."""
    m = K.tube(path, radius, sides=sides, uv_len=1.0 / tile_len)
    m.UV[:, 1] = np.clip(m.UV[:, 1], 0, 1)
    return to_region(m, region)


def quad(p0, p1, p2, p3, region, uvs=((0, 1), (1, 1), (1, 0), (0, 0)), two_sided=False) -> Mesh:
    """Четырёхугольник p0-p1-p2-p3 (против часовой, если смотреть с лица)."""
    P = np.array([p0, p1, p2, p3], float)
    n = np.cross(P[1] - P[0], P[2] - P[0])
    n /= np.linalg.norm(n)
    m = Mesh(P, [(0, 1, 2), (0, 2, 3)], np.tile(n, (4, 1)), np.array(uvs, float))
    m = to_region(m, region)
    if two_sided:
        m = Mesh.merge([m, m.copy().flip()])
    return m


def lump(rx, ry, rz, seg_u=8, seg_v=5, region="stones", seed=0, amount=0.12, flat_bottom=True) -> Mesh:
    """Неровный ком (камень, копна): эллипсоид с низкочастотной неровностью, UV сверху."""
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


def lod_halve(m: Mesh) -> Mesh:
    """Заглушка: для лагеря LOD собирается отдельно с меньшим числом сегментов."""
    return m


def rot_y(m: Mesh, deg) -> Mesh:
    return m.rotate_y(deg)


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
