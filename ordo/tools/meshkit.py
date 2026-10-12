"""Процедурные меши для Ордо: примитивы, трансформации, слияние, LOD.

Соглашения ТЗ 11.6: метры, Y вверх, фасад и дверь смотрят в +Z, начало
координат в центре основания на уровне земли. Нижние грани и интерьер не нужны.

Каждый Mesh хранит:
    P   (n,3) позиции        N  (n,3) нормали
    UV  (n,2) текстура       UV2 (n,2) служебный канал (номер части для толпы)
    C   (n,4) цвет вершины   F  (m,3) треугольники (против часовой снаружи)

Пример:
    wall = lathe([(3.5, 0), (3.5, 1.6)], 24)        # стена юрты
    pole = tube([(0, 0, 0), (0, 6, 0)], 0.06, sides=6)
    m = Mesh.merge([wall, pole.translate(4, 0, 0)])
"""
from __future__ import annotations

import math

import numpy as np


class Mesh:
    def __init__(self, P, F, N=None, UV=None, UV2=None, C=None):
        self.P = np.asarray(P, dtype=np.float64).reshape(-1, 3)
        self.F = np.asarray(F, dtype=np.int64).reshape(-1, 3)
        n = len(self.P)
        self.UV = np.zeros((n, 2)) if UV is None else np.asarray(UV, dtype=np.float64).reshape(-1, 2)
        self.UV2 = np.zeros((n, 2)) if UV2 is None else np.asarray(UV2, dtype=np.float64).reshape(-1, 2)
        self.C = np.ones((n, 4)) if C is None else np.asarray(C, dtype=np.float64).reshape(-1, 4)
        self.has_uv2 = UV2 is not None
        self.has_color = C is not None
        self.N = self._face_weighted_normals() if N is None else _unit(np.asarray(N, dtype=np.float64).reshape(-1, 3))

    # ---------- основное ----------
    def copy(self) -> "Mesh":
        m = Mesh(self.P.copy(), self.F.copy(), self.N.copy(), self.UV.copy(), self.UV2.copy(), self.C.copy())
        m.has_uv2, m.has_color = self.has_uv2, self.has_color
        return m

    @property
    def tris(self) -> int:
        return len(self.F)

    def bounds(self):
        return self.P.min(axis=0), self.P.max(axis=0)

    @staticmethod
    def merge(meshes) -> "Mesh":
        meshes = [m for m in meshes if m is not None and len(m.P)]
        if not meshes:
            return Mesh(np.zeros((0, 3)), np.zeros((0, 3), dtype=np.int64))
        offs, F = 0, []
        for m in meshes:
            F.append(m.F + offs)
            offs += len(m.P)
        out = Mesh(np.vstack([m.P for m in meshes]), np.vstack(F),
                   np.vstack([m.N for m in meshes]), np.vstack([m.UV for m in meshes]),
                   np.vstack([m.UV2 for m in meshes]), np.vstack([m.C for m in meshes]))
        out.has_uv2 = any(m.has_uv2 for m in meshes)
        out.has_color = any(m.has_color for m in meshes)
        return out

    # ---------- трансформации (возвращают self для цепочек) ----------
    def transform(self, M) -> "Mesh":
        M = np.asarray(M, dtype=np.float64)
        if M.shape == (3, 3):
            M4 = np.eye(4)
            M4[:3, :3] = M
            M = M4
        self.P = self.P @ M[:3, :3].T + M[:3, 3]
        nm = np.linalg.inv(M[:3, :3]).T
        self.N = _unit(self.N @ nm.T)
        if np.linalg.det(M[:3, :3]) < 0:
            self.F = self.F[:, ::-1].copy()
        return self

    def translate(self, x=0.0, y=0.0, z=0.0) -> "Mesh":
        self.P = self.P + np.array([x, y, z], dtype=np.float64)
        return self

    def scale(self, sx, sy=None, sz=None) -> "Mesh":
        sy = sx if sy is None else sy
        sz = sx if sz is None else sz
        return self.transform(np.diag([sx, sy, sz]))

    def rotate(self, axis: str, deg: float) -> "Mesh":
        return self.transform(rot(axis, deg))

    def rotate_x(self, deg):
        return self.rotate("x", deg)

    def rotate_y(self, deg):
        return self.rotate("y", deg)

    def rotate_z(self, deg):
        return self.rotate("z", deg)

    def align(self, a, b) -> "Mesh":
        """Поворачивает ось +Y меша по направлению a→b и ставит основание в a."""
        a, b = np.asarray(a, float), np.asarray(b, float)
        d = b - a
        L = np.linalg.norm(d)
        if L < 1e-9:
            return self.translate(*a)
        self.transform(_rot_from_to(np.array([0.0, 1.0, 0.0]), d / L))
        return self.translate(*a)

    # ---------- атрибуты ----------
    def set_part(self, part_id: float, aux: float = 0.0) -> "Mesh":
        """Номер части (кость толпы) в UV2.x, вспомогательное значение в UV2.y."""
        self.UV2 = np.tile([float(part_id), float(aux)], (len(self.P), 1))
        self.has_uv2 = True
        return self

    def set_color(self, rgba) -> "Mesh":
        rgba = tuple(rgba) + (1.0,) * (4 - len(rgba))
        self.C = np.tile(np.asarray(rgba, dtype=np.float64), (len(self.P), 1))
        self.has_color = True
        return self

    def map_uv(self, rect) -> "Mesh":
        """Переносит UV из 0..1 в прямоугольник атласа (u0, v0, u1, v1)."""
        u0, v0, u1, v1 = rect
        self.UV = np.column_stack([u0 + self.UV[:, 0] * (u1 - u0), v0 + self.UV[:, 1] * (v1 - v0)])
        return self

    def uv_scale(self, su, sv=None) -> "Mesh":
        sv = su if sv is None else sv
        self.UV = self.UV * np.array([su, sv])
        return self

    def planar_uv(self, axis="y", scale=1.0, offset=(0.0, 0.0)) -> "Mesh":
        """Плоская развёртка: проекция вдоль оси (метры × scale)."""
        i = {"x": (2, 1), "y": (0, 2), "z": (0, 1)}[axis]
        self.UV = np.column_stack([self.P[:, i[0]] * scale + offset[0], self.P[:, i[1]] * scale + offset[1]])
        return self

    def flip(self) -> "Mesh":
        self.F = self.F[:, ::-1].copy()
        self.N = -self.N
        return self

    def flat(self) -> "Mesh":
        """Плоское затенение: каждый треугольник получает свои вершины."""
        idx = self.F.reshape(-1)
        P, UV, UV2, C = self.P[idx], self.UV[idx], self.UV2[idx], self.C[idx]
        F = np.arange(len(idx)).reshape(-1, 3)
        fn = _face_normals(P, F)
        out = Mesh(P, F, np.repeat(fn, 3, axis=0), UV, UV2, C)
        out.has_uv2, out.has_color = self.has_uv2, self.has_color
        return out

    def smooth(self) -> "Mesh":
        """Сглаженные нормали с учётом совпадающих позиций (через швы UV)."""
        key = np.round(self.P, 5)
        _, inv = np.unique(key, axis=0, return_inverse=True)
        inv = inv.reshape(-1)
        fn = _face_normals(self.P, self.F, weighted=True)
        acc = np.zeros((inv.max() + 1, 3))
        for k in range(3):
            np.add.at(acc, inv[self.F[:, k]], fn)
        self.N = _unit(acc[inv])
        return self

    def recalc_normals(self) -> "Mesh":
        self.N = self._face_weighted_normals()
        return self

    def _face_weighted_normals(self):
        n = np.zeros_like(self.P)
        if len(self.F):
            fn = _face_normals(self.P, self.F, weighted=True)
            for k in range(3):
                np.add.at(n, self.F[:, k], fn)
        return _unit(n)

    def jitter(self, amount: float, seed: int = 0) -> "Mesh":
        """Лёгкая «рукотворная» неровность: сдвиг совпадающих вершин одинаково."""
        rng = np.random.default_rng(seed)
        key = np.round(self.P, 5)
        _, inv = np.unique(key, axis=0, return_inverse=True)
        d = rng.normal(0, amount, (inv.max() + 1, 3))
        self.P = self.P + d[inv.reshape(-1)]
        return self


# =====================================================================
# Примитивы
# =====================================================================

def lathe(profile, segments=16, u_repeat=1.0, sweep=360.0, start=0.0, cap_bottom=False,
          cap_top=False, v_mode="length", normals="smooth") -> Mesh:
    """Тело вращения вокруг оси Y. profile: [(радиус, высота), ...] снизу вверх.

    UV: u — по окружности (0..u_repeat), v — по длине профиля (0..1) или по высоте.
    normals: "smooth" — гладко вдоль профиля, "crease" — излом в каждой точке профиля.
    """
    prof = np.asarray(profile, dtype=np.float64)
    if normals == "crease":
        parts = [lathe(prof[i:i + 2], segments, u_repeat, sweep, start, v_mode=v_mode)
                 for i in range(len(prof) - 1)]
        # согласуем v по всей длине
        L = np.r_[0, np.cumsum(np.linalg.norm(np.diff(prof, axis=0), axis=1))]
        for i, p in enumerate(parts):
            p.UV[:, 1] = (L[i] + p.UV[:, 1] * (L[i + 1] - L[i])) / max(L[-1], 1e-9)
        m = Mesh.merge(parts)
    else:
        n = len(prof)
        seg = segments
        closed = abs(sweep - 360.0) < 1e-6
        cols = seg + 1
        ang = np.radians(start + np.linspace(0, sweep, cols))
        # нормаль профиля в плоскости (r, y)
        d = np.gradient(prof, axis=0) if n > 2 else np.repeat(np.diff(prof, axis=0), 2, axis=0)
        nr, ny = d[:, 1], -d[:, 0]
        ln = np.hypot(nr, ny)
        ln[ln == 0] = 1
        nr, ny = nr / ln, ny / ln
        if v_mode == "length":
            L = np.r_[0, np.cumsum(np.linalg.norm(np.diff(prof, axis=0), axis=1))]
            v = L / max(L[-1], 1e-9)
        else:
            v = (prof[:, 1] - prof[:, 1].min()) / max(np.ptp(prof[:, 1]), 1e-9)
        ca, sa = np.cos(ang), np.sin(ang)
        P = np.zeros((n, cols, 3))
        N = np.zeros((n, cols, 3))
        UV = np.zeros((n, cols, 2))
        # угол 0 смотрит в +Z (фасад), рост угла — к +X
        P[..., 0] = prof[:, 0:1] * sa[None]
        P[..., 1] = prof[:, 1:2]
        P[..., 2] = prof[:, 0:1] * ca[None]
        N[..., 0] = nr[:, None] * sa[None]
        N[..., 1] = ny[:, None]
        N[..., 2] = nr[:, None] * ca[None]
        UV[..., 0] = np.linspace(0, u_repeat, cols)[None]
        UV[..., 1] = v[:, None]
        F = []
        for i in range(n - 1):
            for j in range(seg):
                a, b = i * cols + j, i * cols + j + 1
                c, e = (i + 1) * cols + j, (i + 1) * cols + j + 1
                F += [(a, b, e), (a, e, c)]
        m = Mesh(P.reshape(-1, 3), F, N.reshape(-1, 3), UV.reshape(-1, 2))
        m.F = _drop_degenerate(m)
        del closed
    caps = []
    if cap_bottom and prof[0, 0] > 1e-6:
        caps.append(disc(prof[0, 0], segments, sweep=sweep, start=start).flip().translate(0, prof[0, 1], 0))
    if cap_top and prof[-1, 0] > 1e-6:
        caps.append(disc(prof[-1, 0], segments, sweep=sweep, start=start).translate(0, prof[-1, 1], 0))
    return Mesh.merge([m] + caps) if caps else m


def disc(r, segments=16, sweep=360.0, start=0.0) -> Mesh:
    """Круг в плоскости XZ, нормаль +Y. UV — проекция сверху в 0..1."""
    ang = np.radians(start + np.linspace(0, sweep, segments + 1))
    P = np.vstack([[0, 0, 0], np.column_stack([r * np.sin(ang), np.zeros_like(ang), r * np.cos(ang)])])
    UV = 0.5 + 0.5 * np.column_stack([P[:, 0], P[:, 2]]) / max(r, 1e-9)
    F = [(0, i + 1, i + 2) for i in range(segments)]
    return Mesh(P, F, np.tile([0, 1, 0], (len(P), 1)), UV)


def cylinder(r_bottom, r_top, h, segments=12, caps=True, u_repeat=1.0) -> Mesh:
    return lathe([(r_bottom, 0.0), (r_top, h)], segments, u_repeat, cap_bottom=caps, cap_top=caps,
                 normals="crease")


def cone(r, h, segments=12, u_repeat=1.0) -> Mesh:
    return lathe([(r, 0.0), (0.0, h)], segments, u_repeat, normals="crease")


def ellipsoid(rx, ry, rz, seg_u=12, seg_v=8, y_from=-1.0, y_to=1.0) -> Mesh:
    """Эллипсоид с центром в начале координат; y_from/y_to обрезают его (−1..1)."""
    t = np.linspace(math.asin(np.clip(y_from, -1, 1)), math.asin(np.clip(y_to, -1, 1)), seg_v + 1)
    prof = np.column_stack([np.cos(t), np.sin(t)])
    prof[np.abs(prof[:, 0]) < 1e-9, 0] = 0.0
    m = lathe(prof, seg_u)
    m.transform(np.diag([rx, ry, rz]))
    return m


def sphere(r, seg_u=12, seg_v=8) -> Mesh:
    return ellipsoid(r, r, r, seg_u, seg_v)


def box(sx, sy, sz, uv_scale=None) -> Mesh:
    """Параллелепипед с центром основания в начале координат (Y от 0 до sy)."""
    hx, hz = sx / 2, sz / 2
    faces = [  # нормаль, 4 угла (против часовой снаружи)
        ((0, 0, 1), [(-hx, 0, hz), (hx, 0, hz), (hx, sy, hz), (-hx, sy, hz)]),
        ((0, 0, -1), [(hx, 0, -hz), (-hx, 0, -hz), (-hx, sy, -hz), (hx, sy, -hz)]),
        ((1, 0, 0), [(hx, 0, hz), (hx, 0, -hz), (hx, sy, -hz), (hx, sy, hz)]),
        ((-1, 0, 0), [(-hx, 0, -hz), (-hx, 0, hz), (-hx, sy, hz), (-hx, sy, -hz)]),
        ((0, 1, 0), [(-hx, sy, hz), (hx, sy, hz), (hx, sy, -hz), (-hx, sy, -hz)]),
        ((0, -1, 0), [(-hx, 0, -hz), (hx, 0, -hz), (hx, 0, hz), (-hx, 0, hz)]),
    ]
    P, N, UV, F = [], [], [], []
    for nrm, q in faces:
        b = len(P)
        P += q
        N += [nrm] * 4
        if uv_scale:
            q = np.asarray(q)
            ax = np.argmax(np.abs(nrm))
            ij = [k for k in range(3) if k != ax]
            UV += (q[:, ij] * uv_scale).tolist()
        else:
            UV += [(0, 0), (1, 0), (1, 1), (0, 1)]
        F += [(b, b + 1, b + 2), (b, b + 2, b + 3)]
    return Mesh(P, F, N, UV)


def grid(w, h, nx=1, ny=1) -> Mesh:
    """Прямоугольник в плоскости XY (нормаль +Z), левый край на x=0, низ на y=0.
    Для знамён и вымпелов: x — вдоль полотна от древка, y — вверх."""
    xs, ys = np.linspace(0, w, nx + 1), np.linspace(0, h, ny + 1)
    X, Y = np.meshgrid(xs, ys)
    P = np.column_stack([X.ravel(), Y.ravel(), np.zeros(X.size)])
    UV = np.column_stack([X.ravel() / w, Y.ravel() / h])
    F = []
    for j in range(ny):
        for i in range(nx):
            a = j * (nx + 1) + i
            F += [(a, a + 1, a + nx + 2), (a, a + nx + 2, a + nx + 1)]
    return Mesh(P, F, np.tile([0, 0, 1], (len(P), 1)), UV)


def tube(path, radius, sides=6, caps=False, closed=False, uv_len=1.0, roll=0.0) -> Mesh:
    """Трубка вдоль ломаной path. radius — число или список по точкам.
    UV: u — по окружности (0..1), v — длина в метрах × uv_len."""
    path = np.asarray(path, dtype=np.float64)
    n = len(path)
    r = np.broadcast_to(np.asarray(radius, dtype=np.float64), (n,)).copy()
    T = np.gradient(path, axis=0) if n > 2 else np.repeat(np.diff(path, axis=0), 2, axis=0)
    if closed:
        T = np.roll(path, -1, 0) - np.roll(path, 1, 0)
    T = _unit(T)
    # перенос рамки без скручивания
    up = np.array([0.0, 1.0, 0.0]) if abs(T[0][1]) < 0.9 else np.array([1.0, 0.0, 0.0])
    Nf = _unit(np.cross(up, T[0])[None])[0]
    frames = []
    for i in range(n):
        if i > 0:
            Nf = Nf - T[i] * np.dot(Nf, T[i])
            Nf = Nf / max(np.linalg.norm(Nf), 1e-9)
        B = np.cross(T[i], Nf)
        frames.append((Nf.copy(), B))
    cols = sides + 1
    ang = np.radians(roll) + np.linspace(0, 2 * np.pi, cols)
    L = np.r_[0, np.cumsum(np.linalg.norm(np.diff(path, axis=0), axis=1))]
    P, N, UV = [], [], []
    for i in range(n):
        Nf, B = frames[i]
        for k in range(cols):
            d = Nf * math.cos(ang[k]) + B * math.sin(ang[k])
            P.append(path[i] + d * r[i])
            N.append(d)
            UV.append((k / sides, L[i] * uv_len))
    F = []
    rows = n if not closed else n + 1
    for i in range(rows - 1):
        i0, i1 = i % n, (i + 1) % n
        for k in range(sides):
            a, b = i0 * cols + k, i0 * cols + k + 1
            c, e = i1 * cols + k, i1 * cols + k + 1
            F += [(a, b, e), (a, e, c)]
    m = Mesh(P, F, N, UV)
    if caps and not closed:
        ends = []
        for i, sgn in ((0, -1), (n - 1, 1)):
            c = len(m.P)
            ring = m.P[i * cols:i * cols + sides]
            P2 = np.vstack([path[i], ring])
            F2 = [(0, k + 1, (k + 1) % sides + 1) for k in range(sides)]
            if sgn < 0:
                F2 = [f[::-1] for f in F2]
            ends.append(Mesh(P2, F2, np.tile(T[i] * sgn, (len(P2), 1)), np.full((len(P2), 2), 0.5)))
            del c
        m = Mesh.merge([m] + ends)
    return m


def loft(sections, closed_sections=True, cap_start=False, cap_end=False, u_repeat=1.0) -> Mesh:
    """Обтяжка по сечениям одинаковой длины (список массивов (k,3)).
    Для тел людей и коней: сечения от хвоста к голове, каждое — кольцо точек."""
    S = [np.asarray(s, dtype=np.float64) for s in sections]
    k = len(S[0])
    cols = k + 1 if closed_sections else k
    P, UV = [], []
    L = np.r_[0, np.cumsum([np.linalg.norm(S[i + 1].mean(0) - S[i].mean(0)) for i in range(len(S) - 1)])]
    for i, s in enumerate(S):
        ring = np.vstack([s, s[:1]]) if closed_sections else s
        for j, p in enumerate(ring):
            P.append(p)
            UV.append((j / (cols - 1) * u_repeat, L[i] / max(L[-1], 1e-9)))
    F = []
    for i in range(len(S) - 1):
        for j in range(cols - 1):
            a, b = i * cols + j, i * cols + j + 1
            c, e = (i + 1) * cols + j, (i + 1) * cols + j + 1
            F += [(a, b, e), (a, e, c)]
    m = Mesh(P, F, None, UV)
    caps = []
    if cap_start:
        caps.append(_fan_cap(S[0], reverse=False))
    if cap_end:
        caps.append(_fan_cap(S[-1], reverse=True))
    m = Mesh.merge([m] + caps) if caps else m
    return m.smooth()


def ring(center, rx, rz, k=8, y=0.0, phase=0.0, squash=None):
    """Кольцо k точек (эллипс) в плоскости, перпендикулярной оси Y; для loft.
    squash: функция угла → множитель радиуса (форма сечения)."""
    a = np.radians(phase) + np.linspace(0, 2 * np.pi, k, endpoint=False)
    f = np.ones(k) if squash is None else np.array([squash(t) for t in a])
    cx, cy, cz = center
    return np.column_stack([cx + rx * f * np.sin(a), np.full(k, cy + y), cz + rz * f * np.cos(a)])


def ring_z(center, rx, ry, k=8, phase=0.0, squash=None):
    """Кольцо в плоскости XY (ось — Z); для тел, вытянутых вдоль Z (конь).
    Сечения для loft идут от хвоста (−Z) к голове (+Z). Угол 0 — верх (+Y)."""
    a = np.radians(phase) + np.linspace(0, 2 * np.pi, k, endpoint=False)
    f = np.ones(k) if squash is None else np.array([squash(t) for t in a])
    cx, cy, cz = center
    return np.column_stack([cx - rx * f * np.sin(a), cy + ry * f * np.cos(a), np.full(k, cz)])


def extrude(poly2d, depth, cap=True, side_uv_scale=1.0) -> Mesh:
    """Выдавливание многоугольника (в плоскости XY, против часовой) вдоль +Z на depth.
    Передняя крышка смотрит в +Z, задняя в −Z."""
    poly = np.asarray(poly2d, dtype=np.float64)
    if _area2(poly) < 0:
        poly = poly[::-1]
    k = len(poly)
    tri = triangulate(poly)
    lo, hi = poly.min(0), poly.max(0)
    span = np.maximum(hi - lo, 1e-9)
    parts = []
    if cap:
        Pf = np.column_stack([poly, np.full(k, depth)])
        parts.append(Mesh(Pf, tri, np.tile([0, 0, 1], (k, 1)), (poly - lo) / span))
        Pb = np.column_stack([poly, np.zeros(k)])
        parts.append(Mesh(Pb, [t[::-1] for t in tri], np.tile([0, 0, -1], (k, 1)), (poly - lo) / span))
    P, N, UV, F = [], [], [], []
    per = np.r_[0, np.cumsum(np.linalg.norm(np.diff(np.vstack([poly, poly[:1]]), axis=0), axis=1))]
    for i in range(k):
        a, b = poly[i], poly[(i + 1) % k]
        e = b - a
        nrm = _unit(np.array([[e[1], -e[0], 0.0]]))[0]
        base = len(P)
        P += [(a[0], a[1], 0), (b[0], b[1], 0), (b[0], b[1], depth), (a[0], a[1], depth)]
        N += [nrm] * 4
        UV += [(per[i] * side_uv_scale, 0), (per[i + 1] * side_uv_scale, 0),
               (per[i + 1] * side_uv_scale, depth * side_uv_scale), (per[i] * side_uv_scale, depth * side_uv_scale)]
        F += [(base, base + 1, base + 2), (base, base + 2, base + 3)]
    parts.append(Mesh(P, F, N, UV))
    return Mesh.merge(parts)


def triangulate(poly2d):
    """Отсечение ушей для простого многоугольника (против часовой)."""
    pts = np.asarray(poly2d, dtype=np.float64)
    idx = list(range(len(pts)))
    out = []
    guard = 0
    while len(idx) > 3 and guard < 10000:
        guard += 1
        n = len(idx)
        for i in range(n):
            a, b, c = idx[i - 1], idx[i], idx[(i + 1) % n]
            pa, pb, pc = pts[a], pts[b], pts[c]
            if _cross2(pb - pa, pc - pb) <= 1e-12:
                continue
            ok = True
            for j in idx:
                if j in (a, b, c):
                    continue
                if _in_tri(pts[j], pa, pb, pc):
                    ok = False
                    break
            if ok:
                out.append((a, b, c))
                idx.pop(i)
                break
        else:
            break
    if len(idx) == 3:
        out.append(tuple(idx))
    return out


# =====================================================================
# LOD и проверки
# =====================================================================

def budget_report(name, mesh: Mesh, lo: int, hi: int) -> str:
    t = mesh.tris
    mark = "ok" if lo <= t <= hi else ("мало" if t < lo else "МНОГО")
    return f"{name}: {t} треуг. (бюджет {lo}–{hi}) {mark}"


# =====================================================================
# Вспомогательное
# =====================================================================

def rot(axis: str, deg: float):
    a = math.radians(deg)
    c, s = math.cos(a), math.sin(a)
    if axis == "x":
        return np.array([[1, 0, 0], [0, c, -s], [0, s, c]])
    if axis == "y":
        return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]])
    return np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]])


def _rot_from_to(a, b):
    a, b = a / np.linalg.norm(a), b / np.linalg.norm(b)
    v = np.cross(a, b)
    c = float(np.dot(a, b))
    if c < -0.999999:
        axis = np.cross(a, [1, 0, 0])
        if np.linalg.norm(axis) < 1e-6:
            axis = np.cross(a, [0, 0, 1])
        axis = axis / np.linalg.norm(axis)
        return 2 * np.outer(axis, axis) - np.eye(3)
    vx = np.array([[0, -v[2], v[1]], [v[2], 0, -v[0]], [-v[1], v[0], 0]])
    return np.eye(3) + vx + vx @ vx / (1 + c)


def _unit(v):
    v = np.asarray(v, dtype=np.float64)
    l = np.linalg.norm(v, axis=-1, keepdims=True)
    l[l == 0] = 1
    return v / l


def _face_normals(P, F, weighted=False):
    if len(F) == 0:
        return np.zeros((0, 3))
    n = np.cross(P[F[:, 1]] - P[F[:, 0]], P[F[:, 2]] - P[F[:, 0]])
    return n if weighted else _unit(n)


def _drop_degenerate(m: Mesh):
    n = np.cross(m.P[m.F[:, 1]] - m.P[m.F[:, 0]], m.P[m.F[:, 2]] - m.P[m.F[:, 0]])
    return m.F[np.linalg.norm(n, axis=1) > 1e-12]


def _fan_cap(section, reverse=False):
    s = np.asarray(section)
    c = s.mean(0)
    P = np.vstack([c, s])
    k = len(s)
    F = [(0, (i + 1) % k + 1, i + 1) for i in range(k)]
    if reverse:
        F = [f[::-1] for f in F]
    return Mesh(P, F, None, np.full((len(P), 2), 0.5))


def _area2(p):
    x, y = p[:, 0], p[:, 1]
    return float(np.dot(x, np.roll(y, -1)) - np.dot(np.roll(x, -1), y))


def _cross2(a, b):
    return a[0] * b[1] - a[1] * b[0]


def _in_tri(p, a, b, c):
    d1, d2, d3 = _cross2(b - a, p - a), _cross2(c - b, p - b), _cross2(a - c, p - c)
    return d1 >= 0 and d2 >= 0 and d3 >= 0
