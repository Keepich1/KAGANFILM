"""Укрепления Коканда (ТЗ 6, 11.3, 11.6): звенья стен tosh и devor, торцы-столбы,
ворота darvoza, башня burj — с облегчёнными версиями, стройкой и руинами.

tosh — ОДОБРЕННАЯ ФОРМА (ТЗ 11.3): тёплый обожжённый кирпич на каменном цоколе,
бирюзовый изразцовый пояс с золотым кантом, скруглённые зубцы.

Звено вытянуто вдоль X (3,6 м), центрировано; наружная сторона (зубцы) — +Z.
Звенья ставятся с шагом 3,2 м (перекрытие 0,4 м): все рисунки по X имеют период,
делящий 3,2 м, зубцы стоят через 0,8 м — в линии шаг зубцов ровный, швов нет.
Для линии длиной L: n = ceil(L / 3,2), шаг s = L / n, масштаб звена по X = s / 3,2.
"""
from __future__ import annotations

import math

import numpy as np

import gen_kokand_kit as G
import gen_kokand_ruins as R
import meshkit as K
from gen_kokand_atlas import arch_curve
from gen_kokand_models import Model
from meshkit import Mesh

HALF = 1.8          # половина длины звена
STEP = 3.2          # шаг звеньев в линии
OFF = (1.6, 0.0)    # сдвиг рисунка: границы плиток на x = ±1,6 (совпадают у соседних звеньев)


def _q(lod, hi, lo):
    return hi if lod == 0 else lo


def _merlon_row(xs, y, z_front, depth, w, h, region, lod, seed=0, jitter=0.0):
    parts = []
    for i, x in enumerate(xs):
        m = G.merlon(w, h, depth, region, arc_seg=_q(lod, 5, 2), back=lod == 0, seed=seed + i)
        if jitter:
            m.jitter(jitter, seed + i)
        parts.append(m.translate(x, y, z_front - depth))
    return Mesh.merge(parts)


def _merlon_ring(n, r, y, depth, w, h, region, lod, seed=0, start=0.0, sweep=360.0, jitter=0.0):
    parts = []
    full = abs(sweep - 360.0) < 1e-6
    for i in range(n):
        a = start + (sweep * i / n if full else sweep * i / max(n - 1, 1))
        m = G.merlon(w, h, depth, region, arc_seg=_q(lod, 5, 2), back=lod == 0, seed=seed + i)
        if jitter:
            m.jitter(jitter, seed + i)
        m.translate(0, y, r - depth).rotate_y(a)
        parts.append(m)
    return Mesh.merge(parts)


def _end_caps(z_half_plinth, plinth_h, z_half_body, top, region, plinth_region="plinth"):
    parts = []
    for side, x in (("right", HALF), ("left", -HALF)):
        if plinth_h > 0:
            parts.append(G.box_face(side, -x, x, -z_half_plinth, z_half_plinth, 0, plinth_h, plinth_region,
                                    tile=(3.2, None), v_span=(0, max(plinth_h, 0.8)) if plinth_h < 0.8 else None))
        parts.append(G.box_face(side, -x, x, -z_half_body, z_half_body, plinth_h, top, region))
    return Mesh.merge(parts)


# ================================================================ tosh — кирпичная стена

TOSH = dict(D=1.1, P_H=0.9, BD0=0.96, BD1=0.86, BODY=3.35, BAND=3.75, MER_H=0.65, MER_W=0.5, MER_D=0.42)


def _battered(side, x0, x1, z_bot, z_top, y0, y1, region, off=OFF, tile=None):
    """Наклонная грань вдоль X: внизу z_bot, вверху z_top (side: front +Z / back −Z)."""
    h = y1 - y0
    if side == "front":
        V = np.array([0.0, h, z_top - z_bot])
        L = np.linalg.norm(V)
        return G.face((0, y0, z_bot), (1, 0, 0), V / L, x0, x1, region, tile, 0.0, L, off=off)
    V = np.array([0.0, h, -(z_top - z_bot)])
    L = np.linalg.norm(V)
    return G.face((0, y0, -z_bot), (-1, 0, 0), V / L, -x1, -x0, region, tile, 0.0, L, off=off)


def tosh(lod=0):
    T = TOSH
    D, P_H, BD0, BD1, BODY, BAND = T["D"], T["P_H"], T["BD0"], T["BD1"], T["BODY"], T["BAND"]
    zb = BD1 + 0.03          # плоскость пояса и зубцов
    parts = []
    # каменный цоколь
    for s in ("front", "back"):
        parts.append(G.box_face(s, -HALF, HALF, -D, D, 0.0, P_H, "plinth", tile=(3.2, None), off=OFF))
    if lod == 0:
        # уступ цоколя (видна верхняя кромка камня)
        parts.append(G.face((0, P_H, 0), (1, 0, 0), (0, 0, -1), -HALF, HALF, "stones", (1.6, 1.6), -D, -BD0,
                            off=OFF))
        parts.append(G.face((0, P_H, 0), (-1, 0, 0), (0, 0, 1), -HALF, HALF, "stones", (1.6, 1.6), -D, -BD0,
                            off=OFF))
    # кирпичное тело с наклоном
    for s in ("front", "back"):
        parts.append(_battered(s, -HALF, HALF, BD0, BD1, P_H, BODY, "brick"))
    # бирюзовый пояс с золотым кантом (чуть выступает)
    for s in ("front", "back"):
        parts.append(G.box_face(s, -HALF, HALF, -zb, zb, BODY, BAND, "tileband", tile=(3.2, None), off=OFF))
    if lod == 0:
        # нижняя кромка пояса (тонкая полочка — тень под поясом)
        for sg in (1, -1):
            q = G.quad((-HALF, BODY, sg * zb), (HALF, BODY, sg * zb), (HALF, BODY, sg * BD1), (-HALF, BODY, sg * BD1),
                       "tileband", uvs=((0, 0.98), (1, 0.98), (1, 1), (0, 1)))
            if q.N[0][1] > 0:
                q.flip()
            parts.append(q)
    # боевой ход (кирпичный пол) и низкий парапет со стороны города
    parts.append(G.face((0, BAND, 0), (1, 0, 0), (0, 0, -1), -HALF, HALF, "brick", None, -zb, zb, off=OFF))
    pz0, pz1 = -zb, -zb + 0.28
    ph = 0.32
    sides = ("front", "back", "top") if lod == 0 else ("front", "top")
    for s in sides:
        parts.append(G.box_face(s, -HALF, HALF, pz0, pz1, BAND, BAND + ph, "brick", off=OFF))
    # зубцы снаружи (+Z), шаг 0,8 м
    xs = [-1.2, -0.4, 0.4, 1.2]
    parts.append(_merlon_row(xs, BAND, zb, T["MER_D"], T["MER_W"], T["MER_H"], "brick", lod, seed=7))
    body = Mesh.merge(parts)
    G.wall_light(body, BAND + T["MER_H"], base=0.7, top=1.06)
    caps = _end_caps(D, P_H, zb, BAND, "brick")
    G.wall_light(caps, BAND, base=0.7, top=1.0)
    m = Mesh.merge([body, caps])
    # пол боевого хода не «горит» при низком солнце
    top = (np.abs(m.N[:, 1]) > 0.9) & (m.P[:, 1] > BAND - 0.01) & (m.P[:, 1] < BAND + 0.01)
    m.C[top, :3] *= 0.82
    return Model().add("Tosh", m)


def tosh_end(lod=0):
    """Круглый столб-торец кирпичной стены (конец линии, угол): цоколь, кирпич, пояс, зубцы кольцом."""
    seg = _q(lod, 4, 3)
    tiles = 3
    parts = [G.lathe_bands([(1.5, 0.0), (1.5, 0.9)], "plinth", tiles, seg, v_span=(0, 0.9)),
             G.ring_flat(1.38, 1.5, 0.9, seg, "stones", tiles),
             G.lathe_bands([(1.42, 0.9), (1.36, 3.45)], "brick", tiles, seg, tile_h=1.6, off_y=-0.9),
             G.ring_band(1.39, 1.39, 3.45, 3.85, "tileband", tiles, seg),
             G.disc_uv(1.39, tiles * seg, "brick", y=3.85)]
    parts.append(_merlon_ring(6, 1.39, 3.85, 0.4, 0.55, 0.75, "brick", lod, seed=11, start=30))
    m = Mesh.merge(parts)
    G.wall_light(m, 4.6, base=0.7, top=1.06)
    return Model().add("ToshEnd", m)


# ================================================================ devor — пахса

DEVOR = dict(D=0.9, F_H=0.35, BD0=0.86, BD1=0.6, BODY=2.95, MER_H=0.65, MER_W=0.56, MER_D=0.36)


def devor(lod=0):
    T = DEVOR
    D, F_H, BD0, BD1, BODY = T["D"], T["F_H"], T["BD0"], T["BD1"], T["BODY"]
    parts = []
    # низкий бутовый фундамент
    for s in ("front", "back"):
        parts.append(G.box_face(s, -HALF, HALF, -D, D, 0.0, F_H, "plinth", tile=(3.2, None), off=OFF,
                                v_span=(0.0, 0.7)))
    if lod == 0:
        parts.append(G.face((0, F_H, 0), (1, 0, 0), (0, 0, -1), -HALF, HALF, "stones", (1.6, 1.6), -D, -BD0, off=OFF))
        parts.append(G.face((0, F_H, 0), (-1, 0, 0), (0, 0, 1), -HALF, HALF, "stones", (1.6, 1.6), -D, -BD0, off=OFF))
    for s in ("front", "back"):
        parts.append(_battered(s, -HALF, HALF, BD0, BD1, F_H, BODY, "pakhsa", tile=(3.2, 2.4)))
    parts.append(G.face((0, BODY, 0), (1, 0, 0), (0, 0, -1), -HALF, HALF, "pakhsa", (3.2, 2.4), -BD1, BD1, off=OFF))
    # низкий валик со стороны города
    for s in (("front", "top", "back") if lod == 0 else ("front", "top")):
        parts.append(G.box_face(s, -HALF, HALF, -BD1, -BD1 + 0.26, BODY, BODY + 0.24, "pakhsa", tile=(3.2, 2.4),
                                off=OFF))
    parts.append(_merlon_row([-1.2, -0.4, 0.4, 1.2], BODY, BD1, T["MER_D"], T["MER_W"], T["MER_H"], "pakhsa", lod,
                             seed=17, jitter=0.012))
    body = Mesh.merge(parts)
    G.wall_light(body, BODY + T["MER_H"], base=0.7, top=1.05)
    caps = _end_caps(D, F_H, BD1, BODY, "pakhsa")
    G.wall_light(caps, BODY, base=0.7, top=1.0)
    m = Mesh.merge([body, caps])
    top = (m.N[:, 1] > 0.9) & (np.abs(m.P[:, 1] - BODY) < 0.01)
    m.C[top, :3] *= 0.85
    return Model().add("Devor", m)


def devor_end(lod=0):
    seg = _q(lod, 4, 3)
    tiles = 3
    parts = [G.lathe_bands([(1.3, 0.0), (1.3, 0.35)], "plinth", tiles, seg, v_span=(0, 0.7)),
             G.ring_flat(1.22, 1.3, 0.35, seg, "stones", tiles),
             G.lathe_bands([(1.24, 0.35), (1.0, 3.05)], "pakhsa", tiles, seg, tile_h=2.4),
             G.disc_uv(1.0, tiles * seg, "pakhsa", y=3.05)]
    parts.append(_merlon_ring(5, 1.0, 3.05, 0.34, 0.56, 0.7, "pakhsa", lod, seed=21, jitter=0.012))
    m = Mesh.merge(parts)
    G.wall_light(m, 3.75, base=0.7, top=1.05)
    return Model().add("DevorEnd", m)


# ================================================================ darvoza — ворота

GATE = dict(px=2.5, pr=1.1, pz=0.4, depth=1.5, P_H=1.0, BODY=5.4, BAND=5.8, AW=1.4, SPRING=3.0, APEX=4.3,
            C_TOP=5.4, C_BAND0=5.0, DOOR_Z=-0.3)


def arch_ribbon(curve, width, z, region, out=1.0, lod=0) -> Mesh:
    """Лента-обрамление вдоль арки (в плоскости z, лицом в +Z при out=1): от кривой наружу на width."""
    c = np.asarray(curve, float)
    ctr = np.array([0.0, c[:, 1].min()])
    parts = []
    half = len(c) // 2
    for piece in (c[:half + 1], c[half:]):
        L = np.r_[0, np.cumsum(np.linalg.norm(np.diff(piece, axis=0), axis=1))]
        P, UV, F = [], [], []
        for i, p in enumerate(piece):
            d = p - ctr
            d = d / max(np.linalg.norm(d), 1e-9)
            q = p + d * width
            P += [(p[0], p[1], z), (q[0], q[1], z)]
            u = L[i] / max(L[-1], 1e-9)
            UV += [(u, 1.0), (u, 0.0)]
        for i in range(len(piece) - 1):
            a = 2 * i
            F += [(a, a + 2, a + 3), (a, a + 3, a + 1)]
        m = Mesh(P, F, np.tile([0, 0, out], (len(P), 1)), UV)
        fn = np.cross(m.P[m.F[0, 1]] - m.P[m.F[0, 0]], m.P[m.F[0, 2]] - m.P[m.F[0, 0]])
        if fn[2] * out < 0:
            m.F = m.F[:, ::-1].copy()
        parts.append(G.to_region(m, region))
    return Mesh.merge(parts)


def vault(curve, z0, z1, region="brick") -> Mesh:
    """Свод прохода: арка, вытянутая вдоль Z, лицом вниз-внутрь."""
    c = np.asarray(curve, float)
    L = np.r_[0, np.cumsum(np.linalg.norm(np.diff(c, axis=0), axis=1))]
    P, UV, F = [], [], []
    for i, p in enumerate(c):
        v = min(L[i] / 3.2, 1.0)
        P += [(p[0], p[1], z0), (p[0], p[1], z1)]
        UV += [(0.0, v), ((z1 - z0) / 3.2, v)]
    for i in range(len(c) - 1):
        a = 2 * i
        F += [(a, a + 1, a + 3), (a, a + 3, a + 2)]
    m = Mesh(P, F, None, UV)
    # нормали внутрь (к оси арки)
    ctr = np.array([0.0, c[:, 1].min() - 0.5, (z0 + z1) / 2])
    fn = np.cross(m.P[m.F[:, 1]] - m.P[m.F[:, 0]], m.P[m.F[:, 2]] - m.P[m.F[:, 0]])
    fc = m.P[m.F].mean(axis=1)
    if np.mean(np.einsum("ij,ij->i", fn, ctr - fc)) < 0:
        m.F = m.F[:, ::-1].copy()
    m.recalc_normals()
    return G.to_region(m, region)


def door_leaf(w, h, t, region="gate", mirror=False, hinge_left=True) -> Mesh:
    """Створка (локально: петля в начале, створка вдоль +X или −X), лицо +Z и изнанка −Z."""
    sx = 1 if hinge_left else -1
    x0, x1 = (0.02, w - 0.02) if hinge_left else (-w + 0.02, -0.02)
    uvs = ((1, 1), (0, 1), (0, 0), (1, 0)) if mirror else ((0, 1), (1, 1), (1, 0), (0, 0))
    front = G.quad((x0, 0.04, t / 2), (x1, 0.04, t / 2), (x1, h, t / 2), (x0, h, t / 2), region, uvs=uvs)
    back = G.quad((x1, 0.04, -t / 2), (x0, 0.04, -t / 2), (x0, h, -t / 2), (x1, h, -t / 2), region,
                  uvs=tuple((1 - u, v) for u, v in uvs))
    edge = G.box(abs(x1 - x0), 0.06, t, {"top": "walnut", "front": None, "back": None})
    edge.translate((x0 + x1) / 2, h - 0.06, 0)
    side = G.quad((x1, 0.04, -t / 2), (x1, 0.04, t / 2), (x1, h, t / 2), (x1, h, -t / 2), "walnut") if sx > 0 else \
        G.quad((x0, 0.04, t / 2), (x0, 0.04, -t / 2), (x0, h, -t / 2), (x0, h, t / 2), "walnut")
    return Mesh.merge([front, back, edge, side])


def banner_pole(base, height, flag_w=2.2, flag_h=1.5, lod=0, finial=True):
    """Древко с золотым навершием (полумесяц) и знамя (узел «Banner», ткань) вдоль +X.
    Возвращает (меш древка, меш знамени в мировых координатах модели)."""
    bx, by, bz = base
    sides = _q(lod, 6, 4)
    parts = [G.pole((bx, by, bz), (bx, by + height, bz), 0.06, 0.045, sides, "walnut")]
    if finial:
        ball = K.ellipsoid(0.1, 0.09, 0.1, _q(lod, 6, 5), 3).translate(bx, by + height + 0.05, bz)
        parts.append(G.to_region(ball, "bronze"))
        if lod == 0:
            # полумесяц: дуга из трубки
            a = np.linspace(math.radians(200), math.radians(-20), 7)
            pts = [(bx + 0.16 * math.cos(t), by + height + 0.32 + 0.16 * math.sin(t), bz) for t in a]
            parts.append(G.path_tube(pts, 0.025, sides=4, region="bronze", tile_len=1.0))
    pole = G.white(Mesh.merge(parts))
    nx, ny = _q(lod, 8, 4), _q(lod, 3, 1)
    m = K.grid(flag_w, flag_h, nx, ny)
    s = m.P[:, 0] / flag_w
    q = 1 - m.P[:, 1] / flag_h
    m.UV = np.column_stack([s, q])
    m.UV2 = np.column_stack([s, q])
    m.has_uv2 = True
    G.to_region(m, "banner")
    m.translate(bx + 0.05, by + height - 0.2 - flag_h, bz)
    return pole, G.white(m)


def cupola(cx, cz, y, r, lod=0, drum_h=0.5, dome_h=None, finial=True):
    """Маленький бирюзовый купол на барабане (беседка-гульдаста над башней или порталом)."""
    seg = _q(lod, 4, 3)
    tiles = 2
    dh = dome_h or r * 1.35
    prof = [(r * 1.0, 0.0), (r * 1.05, dh * 0.25), (r * 0.95, dh * 0.5), (r * 0.62, dh * 0.78), (r * 0.25, dh * 0.95),
            (0.0, dh)]
    if lod:
        prof = [prof[0], prof[2], prof[3], prof[5]]
    parts = [G.lathe_bands([(r * 0.92, 0.0), (r * 0.92, drum_h)], "band2", tiles, seg, v_span=(0, drum_h)),
             G.dome(prof, "dome_tile", tiles, seg).translate(0, drum_h, 0)]
    if finial:
        f = K.lathe([(0.06, 0.0), (0.09, 0.12), (0.03, 0.3), (0.0, 0.42)], _q(lod, 6, 4), 1.0)
        G.to_region(f, "bronze")
        parts.append(f.translate(0, drum_h + dh - 0.02, 0))
    m = Mesh.merge(parts)
    return m.translate(cx, y, cz)


def darvoza(lod=0):
    """Ворота 7,2×3: две круглые башни-пилона по бокам, стрельчатый проход посередине
    (ширина 2,8 м), над ним — фриз-надпись и изразцовый пояс, зубцы, знамя, купола на пилонах.
    Створки — узлы Door_L / Door_R под «Door» (петли на x = ∓1,4, z = −0,3)."""
    g = GATE
    px, pr, pz, D = g["px"], g["pr"], g["pz"], g["depth"]
    P_H, BODY, BAND = g["P_H"], g["BODY"], g["BAND"]
    aw, spring, apex = g["AW"], g["SPRING"], g["APEX"]
    seg = _q(lod, 6, 4)
    parts = []
    for sx in (-1, 1):
        cx = sx * px
        # круглый фасад пилона (передняя половина)
        front = [G.lathe_bands([(pr + 0.1, 0.0), (pr + 0.1, P_H)], "plinth", 2, seg, sweep=180, start=-90,
                               v_span=(0, P_H)),
                 G.lathe_bands([(pr, P_H), (pr - 0.08, BODY)], "brick", 2, seg, sweep=180, start=-90, tile_h=1.6,
                               off_y=-P_H),
                 G.lathe_bands([(pr - 0.05, BODY), (pr - 0.05, BAND)], "tileband", 2, seg, sweep=180, start=-90,
                               v_span=(BODY, BAND))]
        if lod == 0:
            ring = K.lathe([(pr + 0.1, P_H), (pr - 0.0, P_H)], seg * 2, 1.0, sweep=180, start=-90)
            ring.N[:] = (0, 1, 0)
            ring.UV = np.column_stack([ring.UV[:, 0], ring.UV[:, 1] * 0.1])
            if np.cross(ring.P[ring.F[0, 1]] - ring.P[ring.F[0, 0]], ring.P[ring.F[0, 2]] - ring.P[ring.F[0, 0]])[1] < 0:
                ring.F = ring.F[:, ::-1].copy()
            front.append(G.to_region(ring, "stones"))
        topd = K.disc(pr - 0.05, seg * 2, sweep=180, start=-90).translate(0, BAND, 0)
        front.append(G.to_region(topd, "brick"))
        fm = Mesh.merge(front).translate(cx, 0, pz)
        parts.append(fm)
        # прямоугольная задняя часть
        x0, x1 = (cx - pr, cx + pr)
        outer = "right" if sx > 0 else "left"
        inner = "left" if sx > 0 else "right"
        for s, y0, y1, reg in ((outer, 0, P_H, "plinth"), (outer, P_H, BODY, "brick"), (outer, BODY, BAND, "tileband"),
                               ("back", 0, P_H, "plinth"), ("back", P_H, BODY, "brick"), ("back", BODY, BAND, "tileband")):
            tile = (3.2, None) if reg in ("plinth", "tileband") else None
            parts.append(G.box_face(s, x0, x1, -D, pz, y0, y1, reg, tile=tile, v_span=(y0, y1) if tile else None,
                                    inset=0.0 if reg != "tileband" else 0.03))
        parts.append(G.box_face(inner, x0, x1, -D, pz, 0, BAND, "brick"))
        parts.append(G.box_face("top", x0, x1, -D, pz, 0, BAND, "brick"))
        # зубцы: полукруг спереди, по наружной и задней сторонам
        parts.append(_merlon_ring(5, pr - 0.05, BAND, 0.36, 0.5, 0.62, "brick", lod, seed=31 + sx, start=-72,
                                  sweep=144).translate(cx, 0, pz))
        side_m = _merlon_row([sx * 0.3, sx * 1.1], BAND, 0.0, 0.36, 0.5, 0.62, "brick", lod, seed=41 + sx)
        side_m.rotate_y(90 * sx).translate(cx + sx * pr, 0, 0.0)
        parts.append(side_m)
        back_m = _merlon_row([-0.6, 0.6], BAND, 0.0, 0.36, 0.5, 0.62, "brick", lod, seed=51 + sx)
        back_m.rotate_y(180).translate(cx, 0, -D)
        parts.append(back_m)
        # купол-гульдаста на пилоне
        parts.append(cupola(cx, pz - 0.25, BAND, 0.55, lod, drum_h=0.45))
    # средний блок над проходом
    curve = arch_curve(aw, spring, apex, _q(lod, 12, 6))
    for z, sgn in ((pz - 0.25, 1), (-D, -1)):
        bottom = [(x, y) for x, y in curve]
        if sgn > 0:
            f = G.face((0, 0, z), (1, 0, 0), (0, 1, 0), -aw, aw, "brick", None, spring, g["C_BAND0"], bottom=bottom,
                       off=OFF)
        else:
            f = G.face((0, 0, z), (-1, 0, 0), (0, 1, 0), -aw, aw, "brick", None, spring, g["C_BAND0"],
                       bottom=[(-x, y) for x, y in bottom], off=OFF)
        parts.append(f)
        parts.append(G.face((0, 0, z + sgn * 0.03), (sgn, 0, 0), (0, 1, 0), -aw, aw, "tileband", (3.2, None),
                            g["C_BAND0"], g["C_TOP"], off=OFF))
        parts.append(arch_ribbon(curve, 0.22, z + sgn * 0.02, "band2" if sgn > 0 else "brick", out=sgn, lod=lod))
    if lod == 0:
        # фриз-надпись над аркой (спереди)
        parts.append(G.face((0, 0, pz - 0.25 + 0.035), (1, 0, 0), (0, 1, 0), -aw * 0.72, aw * 0.72, "band2", (3.2, None),
                            apex + 0.18, apex + 0.58, off=OFF))
    parts.append(G.box_face("top", -aw, aw, -D, pz - 0.25, 0, g["C_TOP"], "brick"))
    parts.append(_merlon_row([-0.85, 0.0, 0.85], g["C_TOP"], pz - 0.25 + 0.03, 0.34, 0.48, 0.6, "brick", lod, seed=61))
    parts.append(vault(curve, -D, pz - 0.25))
    # тимпан над створками: резная решётка
    tz = g["DOOR_Z"]
    tymp = G.face((0, 0, tz), (1, 0, 0), (0, 1, 0), -aw, aw, "panjara", (2.8, 1.3), spring, apex,
                  top=[(x, y) for x, y in curve], off=(aw, -spring))
    parts.append(tymp)
    tb = tymp.copy().flip()
    parts.append(tb)
    # порог
    parts.append(G.box_face("top", -aw, aw, tz - 0.25, tz + 0.25, 0, 0.08, "stones", tile=(1.6, 1.6)))
    body = Mesh.merge(parts)
    G.wall_light(body, 6.4, base=0.7, top=1.05)
    model = Model().add("Darvoza", body)
    # створки
    leaf_h = spring - 0.02
    model.add("Door_L", G.shade(door_leaf(aw, leaf_h, 0.12, "gate", mirror=False, hinge_left=True),
                                lambda P: 0.75 + 0.25 * np.clip(P[:, 1] / 2.5, 0, 1)), pivot=(-aw, 0.0, tz))
    model.add("Door_R", G.shade(door_leaf(aw, leaf_h, 0.12, "gate", mirror=True, hinge_left=False),
                                lambda P: 0.75 + 0.25 * np.clip(P[:, 1] / 2.5, 0, 1)), pivot=(aw, 0.0, tz))
    model.groups["Door"] = ["Door_L", "Door_R"]
    pole, flag = banner_pole((0.0, g["C_TOP"], -0.9), 3.6, 2.0, 1.4, lod)
    model.add("Pole", pole)
    model.add("Banner", flag, "cloth")
    return model


# ================================================================ burj — башня

BURJ = dict(R=3.45, P_H=1.2, B0=3.3, B1=3.02, CORB0=6.8, CORB1=7.3, BAND1=7.7, PAR_TOP=8.9, PLAT=8.4, R_PAR=3.26,
            R_IN=2.86, MER_H=0.72)
BURJ_SLOTS = [(2.15 * math.sin(math.radians(22.5 + 45 * k)), 2.15 * math.cos(math.radians(22.5 + 45 * k)))
              for k in range(8)] + [(-0.75, 0.55), (0.75, 0.55)]


def burj(lod=0):
    """Башня 7×7: круглая, кирпич на каменном цоколе, напуск-машикули, бирюзовый пояс,
    парапет со скруглёнными зубцами; площадка на 8,4 м (10 воинов, метки Slot_* в обёртке).
    Дверь — со стороны города (−Z); стены линии подходят по ±X."""
    b = BURJ
    tiles = 6 if lod == 0 else 4
    seg = 4
    parts = [G.lathe_bands([(b["R"], 0.0), (b["R"] - 0.04, b["P_H"])], "plinth", tiles, seg, v_span=(0, b["P_H"])),
             G.ring_flat(b["B0"] - 0.02, b["R"] - 0.04, b["P_H"], seg, "stones", tiles),
             G.lathe_bands([(b["B0"], b["P_H"]), (b["B1"], b["CORB0"])], "brick", tiles, seg, tile_h=1.6,
                           off_y=-b["P_H"]),
             # напуск: кирпичный карниз расширяется наружу
             G.lathe_bands([(b["B1"], b["CORB0"]), (b["R_PAR"], b["CORB1"])], "brick", tiles, seg, v_span=(6.6, 7.6)),
             G.ring_band(b["R_PAR"] + 0.02, b["R_PAR"] + 0.02, b["CORB1"], b["BAND1"], "tileband", tiles, seg),
             G.lathe_bands([(b["R_PAR"], b["BAND1"]), (b["R_PAR"], b["PAR_TOP"])], "brick", tiles, seg, tile_h=1.6),
             G.ring_flat(b["R_IN"], b["R_PAR"], b["PAR_TOP"], seg, "brick", tiles),
             G.disc_uv(b["R_IN"], tiles * seg, "brick", y=b["PLAT"])]
    inner = G.lathe_bands([(b["R_IN"], b["PAR_TOP"]), (b["R_IN"], b["PLAT"])], "brick", tiles, seg, tile_h=1.6)
    parts.append(inner)
    if lod == 0:
        # тени-кронштейны напуска: тёмные зубчики под поясом (машикули)
        for k in range(18):
            a = k / 18 * 2 * math.pi
            br = G.box(0.22, 0.42, 0.3, {"front": "brick", "left": "brick", "right": "brick", "bottom": "brick"})
            br.translate(0, b["CORB0"] + 0.05, b["B1"] + 0.02).rotate_y(math.degrees(a))
            parts.append(G.shade(br, lambda P: np.full(len(P), 0.8)))
    n_mer = 14
    parts.append(_merlon_ring(n_mer, b["R_PAR"] + 0.01, b["PAR_TOP"], 0.4, 0.62, b["MER_H"], "brick", lod, seed=71,
                              start=360 / n_mer / 2))
    # бойницы: узкие тёмные щели
    for k, a in enumerate((25, 70, -25, -70, 130, -130)):
        y = 4.2 if k % 2 == 0 else 2.6
        r = b["B0"] - (b["B0"] - b["B1"]) * (y - b["P_H"]) / (b["CORB0"] - b["P_H"]) + 0.02
        sl = G.quad((-0.08, y, r), (0.08, y, r), (0.08, y + 0.75, r), (-0.08, y + 0.75, r), "panjara",
                    uvs=((0.45, 0.55), (0.55, 0.55), (0.55, 0.45), (0.45, 0.45)))
        sl.rotate_y(a)
        parts.append(G.shade(sl, lambda P: np.full(len(P), 0.5)))
    # дверь со стороны города и рамка-арка
    r_door = b["B0"] - 0.03
    d = G.quad((0.62, 0.05, -r_door), (-0.62, 0.05, -r_door), (-0.62, 2.3, -r_door), (0.62, 2.3, -r_door), "door")
    parts.append(d)
    frame = arch_ribbon(arch_curve(0.62, 2.3, 2.9, _q(lod, 8, 4)), 0.18, 0.0, "tileband", out=1, lod=lod)
    frame.rotate_y(180).translate(0, 0, -r_door - 0.02)
    parts.append(frame)
    tymp = G.face((0, 0, -r_door - 0.01), (-1, 0, 0), (0, 1, 0), -0.62, 0.62, "panjara", (1.24, 0.6), 2.3, 2.9,
                  top=[(x, y) for x, y in arch_curve(0.62, 2.3, 2.9, _q(lod, 8, 4))], off=(0.62, -2.3))
    parts.append(tymp)
    # люк на площадке
    parts.append(G.quad((-0.5, b["PLAT"] + 0.02, -1.0), (0.5, b["PLAT"] + 0.02, -1.0), (0.5, b["PLAT"] + 0.02, -2.0),
                        (-0.5, b["PLAT"] + 0.02, -2.0), "planks", uvs=((0, 1), (0.5, 1), (0.5, 0.5), (0, 0.5))))
    body = Mesh.merge(parts)
    G.wall_light(body, 9.6, base=0.7, top=1.06)
    plat = (body.N[:, 1] > 0.9) & (np.abs(body.P[:, 1] - b["PLAT"]) < 0.05)
    body.C[plat, :3] *= 0.8
    model = Model().add("Burj", body)
    pole, flag = banner_pole((0.0, b["PLAT"], -2.4), 4.2, 2.2, 1.5, lod)
    model.add("Pole", pole)
    model.add("Banner", flag, "cloth")
    return model


# ================================================================ стройка и руины укреплений

def tosh_site(lod=0):
    T = TOSH
    walls = [R.Wall((-HALF, 0.0), (HALF, 0.0), T["BAND"], 1.9, "brick")]
    parts = []
    # цоколь уже сложен целиком
    for s in ("front", "back"):
        parts.append(G.box_face(s, -HALF, HALF, -T["D"], T["D"], 0.0, T["P_H"], "plinth", tile=(3.2, None), off=OFF))
    parts.append(G.box_face("top", -HALF, HALF, -T["D"], T["D"], 0, T["P_H"], "stones", tile=(1.6, 1.6), off=OFF))
    top = R.jagged(3.6, 1.2, 1.7, 5, step=0.45 if lod == 0 else 0.9, edge_drop=0.2)
    parts.append(R.wall_piece(R.Wall((-HALF, 0.0), (HALF, 0.0), 1.7, 1.8, "brick"),
                              top=top, y0=T["P_H"], top_region="brick", lod=lod))
    parts.append(R.scaffold((-HALF, 1.1), (HALF, 1.1), 1.8, offset=0.3, lod=lod, seed=3, step=1.8))
    parts.append(R.brick_stack(0.6, -1.75, 8, 1.0, 0.6, 0.7))
    if lod == 0:
        parts.append(R.ladder((-1.0, 0, -1.5), (-1.0, 1.9, -0.95), lod=lod))
    del walls
    m = G.ground_ao(Mesh.merge(parts), 0.4, 0.25)
    return Model().add("Site", m)


def tosh_ruin(lod=0):
    """Пролом: пологий вал щебня поперёк линии (проходим), по краям — обломки стены."""
    parts = [R.rubble(0.0, 0.0, 1.9, 1.7, 1.0, seed=3, lod=lod, chunks=8)]
    for x0, x1, s in ((-HALF, -1.05, 1), (1.05, HALF, 2)):
        top = R.jagged(x1 - x0, 1.3, 2.4, 40 + s, step=0.3 if lod == 0 else 0.6, edge_drop=0.5)
        parts.append(R.wall_piece(R.Wall((x0, 0.0), (x1, 0.0), 2.4, 1.85, "brick"), top=top, top_region="rubble",
                                  lod=lod))
        for side in (1, -1):
            parts.append(G.box_face("front" if side > 0 else "back", x0, x1, -TOSH["D"], TOSH["D"], 0, 0.9, "plinth",
                                    tile=(3.2, None), off=OFF))
    parts.append(R.burnt_beam((-1.2, 0.3, 0.9), (0.9, 0.9, -0.3), 0.08, lod))
    m = Mesh.merge(parts)
    G.shade(m, lambda P: 0.78 + 0.1 * np.sin(P[:, 0] * 2.1))
    return Model().add("Ruin", G.ground_ao(m, 0.4, 0.3))


def devor_site(lod=0):
    """Пахса строится в опалубке: первый слой готов, на нём — щиты из досок и стойки."""
    T = DEVOR
    parts = []
    for s in ("front", "back"):
        parts.append(G.box_face(s, -HALF, HALF, -T["D"], T["D"], 0.0, T["F_H"], "plinth", tile=(3.2, None), off=OFF,
                                v_span=(0, 0.7)))
        parts.append(_battered(s, -HALF, HALF, T["BD0"], 0.8, T["F_H"], 1.15, "pakhsa", tile=(3.2, 2.4)))
    parts.append(G.face((0, 1.15, 0), (1, 0, 0), (0, 0, -1), -HALF, HALF, "pakhsa", (3.2, 2.4), -0.8, 0.8, off=OFF))
    # опалубка: две доски-щита по бокам и стойки-зажимы
    for sg in (1, -1):
        z = sg * 0.86
        q = G.quad((-1.6, 1.1, z), (1.6, 1.1, z), (1.6, 1.75, z), (-1.6, 1.75, z), "planks",
                   uvs=((0, 1), (1, 1), (1, 0.62), (0, 0.62)))
        if q.N[0][2] * sg < 0:
            q.flip()
        parts.append(q)
        parts.append(q.copy().flip().translate(0, 0, -sg * 0.04))
        for x in (-1.3, 0.0, 1.3):
            parts.append(G.pole((x, 0.9, sg * 0.92), (x, 2.0, sg * 0.92), 0.05, sides=4, region="bark"))
    for x in (-1.3, 0.0, 1.3):
        parts.append(G.pole((x, 1.9, -0.95), (x, 1.9, 0.95), 0.035, sides=4, region="pole"))
    # куча глины рядом
    parts.append(G.lump(1.1, 0.55, 0.8, 8 if lod == 0 else 6, 3, "earth", seed=4, amount=0.2).translate(0.4, 0, -1.9))
    m = G.ground_ao(Mesh.merge(parts), 0.4, 0.25)
    return Model().add("Site", m)


def devor_ruin(lod=0):
    parts = [R.rubble(0.0, 0.0, 1.9, 1.5, 0.8, seed=7, lod=lod, chunks=0, region="earth")]
    for x0, x1, s in ((-HALF, -1.0, 1), (1.0, HALF, 2)):
        top = R.jagged(x1 - x0, 1.0, 2.2, 60 + s, step=0.3 if lod == 0 else 0.6, edge_drop=0.5)
        parts.append(R.wall_piece(R.Wall((x0, 0.0), (x1, 0.0), 2.2, 1.5, "pakhsa"), top=top, top_region="earth",
                                  lod=lod))
    for k in range(4 if lod == 0 else 2):
        parts.append(G.lump(0.35, 0.25, 0.3, 6, 2, "pakhsa", seed=80 + k, amount=0.3).translate(-1.4 + k * 0.9, 0,
                                                                                               1.2 - (k % 2) * 2.3))
    m = Mesh.merge(parts)
    G.shade(m, lambda P: 0.82 + 0.08 * np.sin(P[:, 0] * 1.7))
    return Model().add("Ruin", G.ground_ao(m, 0.4, 0.3))


def tosh_end_site(lod=0):
    return Model().add("Site", R.site([], lod, seed=12, round_walls=[(0, 0, 1.42, 4.6, "brick")],
                                      stacks=[("bricks", 0.0, -2.2, 10)]))


def tosh_end_ruin(lod=0):
    return Model().add("Ruin", R.ruin([], lod, seed=13, round_walls=[(0, 0, 1.42, 4.6, "brick")], beams=1))


def devor_end_site(lod=0):
    return Model().add("Site", R.site([], lod, seed=14, round_walls=[(0, 0, 1.2, 3.75, "pakhsa")]))


def devor_end_ruin(lod=0):
    return Model().add("Ruin", R.ruin([], lod, seed=15, round_walls=[(0, 0, 1.2, 3.75, "pakhsa")], beams=0))


def darvoza_site(lod=0):
    g = GATE
    walls = [R.Wall((-3.6, -1.5), (-1.4, -1.5), 5.8, 0.7, "brick"), R.Wall((1.4, -1.5), (3.6, -1.5), 5.8, 0.7, "brick")]
    m = R.site(walls, lod, seed=21, frac=0.33, scaff=[0, 1],
               round_walls=[(-g["px"], g["pz"], g["pr"], 5.8, "brick"), (g["px"], g["pz"], g["pr"], 5.8, "brick")],
               stacks=[("bricks", -0.6, 2.2, 15), ("bricks", 0.8, 2.4, -10), ("logs", 0.0, -2.6, 90),
                       ("ladder", 1.6, 1.0, 180)])
    # временная рама арки из брёвен (кружало)
    parts = [m]
    for x in (-1.3, 1.3):
        parts.append(G.pole((x, 0, 0.0), (x, 2.6, 0.0), 0.08, sides=5, region="bark"))
    parts.append(G.pole((-1.45, 2.6, 0.0), (1.45, 2.6, 0.0), 0.08, sides=5, region="bark"))
    return Model().add("Site", Mesh.merge(parts))


def darvoza_ruin(lod=0):
    g = GATE
    walls = [R.Wall((-3.6, -1.5), (-1.4, -1.5), 5.8, 0.8, "brick"), R.Wall((1.4, -1.5), (3.6, -1.5), 5.8, 0.8, "brick")]
    m = R.ruin(walls, lod, seed=23, frac=(0.2, 0.5),
               round_walls=[(-g["px"], g["pz"], g["pr"], 5.8, "brick"), (g["px"], g["pz"], g["pr"], 5.8, "brick")],
               piles=[(0.0, 0.2, 1.6, 1.4, 0.9)], beams=3)
    # сорванная створка лежит у прохода
    leaf = door_leaf(1.4, 2.9, 0.12, "gate").rotate_x(-86).rotate_y(20).translate(-0.4, 0.15, 1.2)
    G.shade(leaf, lambda P: np.full(len(P), 0.45))
    return Model().add("Ruin", Mesh.merge([m, leaf]))


def burj_site(lod=0):
    b = BURJ
    m = R.site([], lod, seed=31, frac=0.36, round_walls=[(0, 0, b["B0"], 9.6, "brick")],
               stacks=[("bricks", 2.2, 3.6, 30), ("bricks", -2.6, 3.3, -20), ("stones", 3.8, -1.8, 0),
                       ("ladder", 0.0, -3.9, 0)])
    parts = [m]
    for k in range(3):
        a = math.radians(30 + k * 120)
        p0 = np.array([math.sin(a - 0.5), math.cos(a - 0.5)]) * 4.0
        p1 = np.array([math.sin(a + 0.5), math.cos(a + 0.5)]) * 4.0
        parts.append(R.scaffold(tuple(p1), tuple(p0), 3.4, offset=0.2, lod=lod, seed=40 + k, step=1.9))
    return Model().add("Site", Mesh.merge(parts))


def burj_ruin(lod=0):
    b = BURJ
    m = R.ruin([], lod, seed=33, frac=(0.2, 0.45), round_walls=[(0, 0, b["B0"], 9.6, "brick")],
               piles=[(2.2, 2.8, 2.0, 1.6, 1.1), (-2.6, 1.8, 1.6, 1.4, 0.8)], beams=3)
    return Model().add("Ruin", m)


SCENES = {
    "tosh": {"node": "Tosh", "props": {"ground_decal": False}, "footprint": (3.6, 2.2), "meta": {"pitch": STEP}, "markers": [("Fire_1", (0.3, 1.0, 0.2))]},
    "tosh_end": {"node": "ToshEnd", "props": {"ground_decal": False}, "footprint": (3.0, 3.0), "markers": [("Fire_1", (0.0, 1.0, 0.6))]},
    "devor": {"node": "Devor", "props": {"ground_decal": False}, "footprint": (3.6, 1.8), "meta": {"pitch": STEP}, "markers": [("Fire_1", (0.0, 0.8, 0.0))]},
    "devor_end": {"node": "DevorEnd", "props": {"ground_decal": False}, "footprint": (2.6, 2.6), "markers": []},
    "darvoza": {"node": "Darvoza", "footprint": (7.2, 3.0),
                "markers": [("Pass_Out", (0.0, 0.0, 2.4)), ("Pass_In", (0.0, 0.0, -2.4), {"yaw": 180}),
                            ("Banner", (0.0, GATE["C_TOP"] + 3.6, -0.9)), ("Fire_1", (0.0, 1.0, 0.3)),
                            ("Fire_2", (-2.5, 2.0, 0.0), {"amount": 12})]},
    "burj": {"node": "Burj", "footprint": (7.0, 7.0),
             "markers": [(f"Slot_{i + 1}", (x, BURJ["PLAT"], z), {"yaw": math.degrees(math.atan2(x, z))})
                         for i, (x, z) in enumerate(BURJ_SLOTS)]
             + [("Door", (0.0, 0.0, -4.0), {"yaw": 180}), ("Banner", (0.0, BURJ["PLAT"] + 4.2, -2.4)),
                ("Fire_1", (0.6, 2.2, 0.8))]},
}

JOBS = {
    "tosh": {"": tosh, "_site": tosh_site, "_ruin": tosh_ruin},
    "tosh_end": {"": tosh_end, "_site": tosh_end_site, "_ruin": tosh_end_ruin},
    "devor": {"": devor, "_site": devor_site, "_ruin": devor_ruin},
    "devor_end": {"": devor_end, "_site": devor_end_site, "_ruin": devor_end_ruin},
    "darvoza": {"": darvoza, "_site": darvoza_site, "_ruin": darvoza_ruin},
    "burj": {"": burj, "_site": burj_site, "_ruin": burj_ruin},
}
