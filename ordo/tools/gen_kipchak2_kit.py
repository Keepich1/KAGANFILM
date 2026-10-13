"""Помощники второй очереди лагеря кыпчаков (экономика и укрепления) поверх лагеря среза.

Та же «рука», что у лагеря: меши из gen_camp_kit (развёртка в области общего атласа
assets/textures/kipchak/atlas.png), материалы — gen_camp_models.MAT (один атлас, вырез
для ткани). Новых областей атласа не нужно: всё (брёвна, кора, доски, войлок, верёвка,
железо, латунь, кошма, вымпел, навес) уже нарисовано для лагеря.

Здесь:
    write_model(out, name, nodes, groups)   — glb + сдвиг узлов (начало узла — у древка/петли)
    log_post(...)                           — бревно частокола: кора, затёсанный остриём верх
    char(m, k), scorch(m, …)                — копоть и гарь руин в цвете вершин
    rope_ring, stake_line                   — разметка стройки: колышки и верёвка
    yurt_site / yurt_ruin                   — стройка и пепелище юрты по YurtSpec лагеря
"""
from __future__ import annotations

import json
import math
import os
import struct

import numpy as np

import gen_camp_kit as G
import gen_camp_props as P
import gen_camp_yurt as Y
import meshkit as K
from gen_camp_models import MAT
from glb import read_glb_stats, write_glb
from meshkit import Mesh


def q(lod, hi, lo):
    return hi if lod == 0 else lo


# ================================================================ запись glb

def write_model(out_dir, name, nodes, groups=None):
    """nodes: [(имя, Mesh, "opaque" | "cloth" | "cutout"[, (x, y, z) начало узла])].
    Меш узла со сдвигом задаётся в осях узла (относительно его начала).
    groups: {"Door": ["Door_L", "Door_R"]} — пустой родитель в начале координат модели.
    Возвращает (путь, треугольники)."""
    groups = groups or {}
    gl_nodes, offs = [], {}
    for n in nodes:
        nm, m, kind = n[0], n[1], n[2]
        if m is None or not m.tris:
            continue
        oy = float(n[3][1]) if len(n) > 3 and n[3] is not None else 0.0
        m.P[:, 1] = np.maximum(m.P[:, 1], -0.049 - oy)   # вкопанное — не глубже 5 см (ТЗ 11.6)
        gl_nodes.append((nm, m, MAT[kind]))
        if len(n) > 3 and n[3] is not None:
            offs[nm] = [float(v) for v in n[3]]
    path = os.path.join(out_dir, name + ".glb")
    write_glb(path, gl_nodes)
    if offs or groups:
        _patch_nodes(path, offs, groups)
    return path, sum(m.tris for _, m, _ in gl_nodes)


def _patch_nodes(path, offsets, groups):
    """Дописывает в glb сдвиги узлов и пустых родителей (glb.write_glb пишет только плоский список)."""
    with open(path, "rb") as f:
        data = f.read()
    jlen = struct.unpack_from("<I", data, 12)[0]
    g = json.loads(data[20:20 + jlen])
    rest = data[20 + jlen:]
    names = {n["name"]: i for i, n in enumerate(g["nodes"])}
    for nm, t in offsets.items():
        if nm in names:
            g["nodes"][names[nm]]["translation"] = t
    roots = list(g["scenes"][0]["nodes"])
    for parent, kids in groups.items():
        idx = [names[k] for k in kids if k in names]
        if not idx:
            continue
        g["nodes"].append({"name": parent, "children": idx})
        roots = [r for r in roots if r not in idx] + [len(g["nodes"]) - 1]
    g["scenes"][0]["nodes"] = roots
    js = json.dumps(g, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    js += b" " * ((4 - len(js) % 4) % 4)
    total = 12 + 8 + len(js) + len(rest)
    with open(path, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, total))
        f.write(struct.pack("<II", len(js), 0x4E4F534A))
        f.write(js)
        f.write(rest)


def report(path, tris, base_tris=None):
    st = read_glb_stats(path)
    name = os.path.splitext(os.path.basename(path))[0]
    extra = f"({tris / max(base_tris, 1):.0%} от LOD0)" if base_tris else f"размер {st['size']}  мин.Y {st['min'][1]}"
    print(f"  {name:22s} {tris:6d} треуг. {st['materials']} мат.  {extra}")


def finish(parts):
    """Сливает части; у частей без цвета вершин — белый (множитель 1)."""
    for p in parts:
        if p is not None and not p.has_color:
            G.white(p)
    return Mesh.merge([p for p in parts if p is not None])


def local(m: Mesh, origin) -> Mesh:
    """Меш в осях узла с началом origin (для узлов со сдвигом)."""
    return m.translate(-origin[0], -origin[1], -origin[2])


# ================================================================ брёвна

def log_post(x, z, h, r, sides=6, tip=0.0, seed=0, lean=(0.0, 0.0), sink=0.05, region="bark", flat_tip=True,
             simple_tip=False):
    """Вертикальное бревно: кора (вдоль — вся область), затёсанный остриём верх (светлое дерево
    «wood», грани плоские — следы топора). lean — наклон верха (dx, dz) в метрах."""
    rs = np.random.default_rng(seed)
    a = np.array([x, -sink, z])
    b = np.array([x + lean[0], h, z + lean[1]])
    body = G.pole(a, b, r * 1.04, r * 0.96, sides=sides, region=region)
    parts = [body]
    if tip > 0:
        d = (b - a) / np.linalg.norm(b - a)
        prof = [(r * 0.96, 0.0), (0.0, tip)] if simple_tip else [(r * 0.96, 0.0), (r * 0.12, tip * 0.82), (0.0, tip)]
        t = K.lathe(prof, sides, 1.0, normals="crease", start=rs.uniform(0, 360 / sides))
        t.UV[:, 1] = 1.0 - t.UV[:, 1] * 0.9
        G.to_region(t, "wood")
        if flat_tip:
            t = t.flat()
        t.align(b, b + d)
        parts.append(G.shade(t, lambda P: np.full(len(P), 1.05)))
    else:
        cap = G.disc_uv(r * 0.97, sides, "logend")
        cap.align(b, b + (b - a))
        parts.append(cap)
    return Mesh.merge(parts)


def log_lying(a, b, r, sides=6, ends=True, region="bark"):
    """Лежащее бревно a→b с торцами-спилами."""
    return P.log(a, b, r, 0 if sides >= 6 else 1, region) if ends else G.pole(a, b, r, r * 0.95, sides=sides,
                                                                                  region=region)


def lashing(center, r, h=0.12, sides=6, region="rope"):
    """Обвязка верёвкой вокруг бревна (кольцо на высоте center)."""
    m = K.lathe([(r * 1.06, -h / 2), (r * 1.12, 0.0), (r * 1.06, h / 2)], sides, 1.0)
    G.to_region(m, region)
    return m.translate(*center)


def felt_wrap(center, r, h=0.28, sides=6):
    """Киноварная войлочная обмотка на бревне (цвет стороны виден сверху): верх области «tassel»."""
    m = K.lathe([(r * 1.08, -h / 2), (r * 1.08, h / 2)], sides, 1.0)
    m.UV[:, 1] = 0.02 + m.UV[:, 1] * 0.18          # только киноварная обмотка кисти
    G.to_region(m, "tassel", inset=2)
    return m.translate(*center)


def plank_board(a, b, w, t, region="planks", along_v=True):
    """Доска от a до b (центр торцов), ширина w (по горизонтали поперёк), толщина t."""
    a, b = np.asarray(a, float), np.asarray(b, float)
    L = float(np.linalg.norm(b - a))
    m = G.box(w, L, t, {"front": (region, along_v), "back": (region, along_v), "left": region, "right": region,
                         "top": "logend"})
    return m.align(a, b)


# ================================================================ руины и стройка

def char(m: Mesh, k=0.45, top_y=None, soft=0.6) -> Mesh:
    """Гарь: темнее (множитель k); если top_y — сильнее к обломанному верху."""
    if top_y is None:
        return G.shade(m, lambda P: np.full(len(P), k))
    return G.shade(m, lambda P: 1.0 - (1.0 - k) * np.clip((P[:, 1] - (top_y - soft)) / soft, 0.25, 1.0))


def scorch(m: Mesh, seed=0, k=0.5, cell=1.3) -> Mesh:
    """Пятна копоти по поверхности (низкочастотные, не шум)."""
    ph = np.random.default_rng(seed).uniform(0, 6.28, 4)

    def fn(P):
        n = np.sin(P[:, 0] / cell + ph[0]) * np.sin(P[:, 2] / cell * 1.3 + ph[1]) + \
            0.6 * np.sin((P[:, 0] + P[:, 2]) / (cell * 0.6) + ph[2]) + 0.4 * np.sin(P[:, 1] * 2.2 + ph[3])
        t = np.clip(0.5 + 0.45 * n, 0, 1)
        return k + (1 - k) * (1 - t)
    return G.shade(m, fn)


def stake_line(pts, h=0.45, lod=0, closed=True):
    """Разметка стройки: колышки по углам/точкам и натянутая между ними верёвка."""
    pts = [np.asarray(p, float) for p in pts]
    parts = []
    for p in pts:
        parts.append(G.pole((p[0], 0, p[1]), (p[0], h, p[1]), 0.03, 0.02, sides=q(lod, 4, 3), region="wood"))
    ring = pts + ([pts[0]] if closed else [])
    if lod == 0:
        for i in range(len(ring) - 1):
            a, b = ring[i], ring[i + 1]
            parts.append(G.path_tube([(a[0], h * 0.8, a[1]), ((a[0] + b[0]) / 2, h * 0.68, (a[1] + b[1]) / 2),
                                      (b[0], h * 0.8, b[1])], 0.01, sides=3, region="rope", tile_len=8.0))
    return Mesh.merge(parts)


def circle_pts(cx, cz, r, n, a0=0.0):
    return [(cx + r * math.sin(math.radians(a0 + 360 * k / n)), cz + r * math.cos(math.radians(a0 + 360 * k / n)))
            for k in range(n)]


def lattice_band(R, h, sweep, start, seg, jag=None, seed=0):
    """Решётка-кереге (поставленная стена юрты без войлока): лента области «lattice».
    jag — обломанный верх (руины): доля высоты, на которую верх рвётся."""
    # область «lattice» повторяется по xy, но UV за 0..1 обрезает to_region — кладём куски по плитке ~1.4 м
    m = _tile_lathe(R, h, sweep, start, seg, 1.4)
    if jag is not None:
        rs = np.random.default_rng(seed)
        th = np.degrees(np.arctan2(m.P[:, 0], m.P[:, 2]))
        top = m.P[:, 1] > h * 0.5
        k = 1 - jag * (0.5 + 0.5 * np.sin(np.radians(th) * 7 + rs.uniform(0, 6)) * np.sin(np.radians(th) * 3.3 + 1))
        m.P[top, 1] *= k[top]
    # обе стороны (решётку видно и изнутри)
    return Mesh.merge([m, m.copy().flip()])


def _tile_lathe(R, h, sweep, start, seg, tile):
    """Цилиндрическая лента кусками по плитке tile (область повторяется по xy)."""
    arc = math.radians(sweep) * R
    n_u = max(1, int(round(arc / tile)))
    n_v = max(1, int(round(h / tile)))
    span = sweep / n_u
    per = max(1, int(round(seg / n_u)))
    parts = []
    for i in range(n_u):
        for j in range(n_v):
            p = K.lathe([(R, h * j / n_v), (R, h * (j + 1) / n_v)], per, 1.0, sweep=span, start=start + i * span)
            p.UV[:, 1] = 1.0 - p.UV[:, 1]
            parts.append(G.to_region(p, "lattice"))
    return Mesh.merge(parts)


def felt_sheet(cx, cz, rx, rz, h, region="felt_white", seg=8, seed=0, yaw=0.0, droop=0.4):
    """Упавший/наброшенный кусок войлока: низкий бугор с рваным краем (руины)."""
    rs = np.random.default_rng(seed)
    m = K.lathe([(1.0, 0.0), (0.7, 0.55), (0.0, 1.0)], seg, 1.0)
    th = np.arctan2(m.P[:, 0], m.P[:, 2])
    k = 1 + 0.18 * np.sin(th * 3 + rs.uniform(0, 6)) + 0.1 * np.sin(th * 5 + rs.uniform(0, 6))
    m.P[:, 0] *= rx * k
    m.P[:, 2] *= rz * k
    m.P[:, 1] = m.P[:, 1] * h * (1 - droop * 0.3) + 0.02
    m.UV = np.column_stack([0.5 + m.P[:, 0] / (2.4 * rx), 0.5 + m.P[:, 2] / (2.4 * rz)])
    m.smooth()
    G.to_region(m, region)
    return m.rotate_y(yaw).translate(cx, 0, cz)


def ash_patch(rx, rz, lod=0, y=0.025, k=0.42):
    """Пятно гари (то же пятно земли, темнее) — узел «Ground»."""
    m = P.earth_patch(rx, rz, lod, y=y)
    return G.shade(m, lambda P_: np.full(len(P_), k / 0.62))


# ================================================================ юрта: стройка и пепелище

def yurt_parts(spec):
    """Готовая юрта лагеря (YurtSpec) → один меш (опаковые части) и ткань (если есть)."""
    nodes = Y.build(spec)
    opaque = [m for n, m, k in nodes if k == "opaque"]
    cloth = [m for n, m, k in nodes if k == "cloth"]
    return Mesh.merge(opaque), (Mesh.merge(cloth) if cloth else None)


def yurt_site(spec, lod=0, seed=0, done=0.4):
    """Стройка юрты: разметка, пол-кольца поставленной решётки (кереге), дверная рама,
    связка жердей уука, тюндюк на земле, рулоны войлока. Высота ~ высоте двери (≈40% юрты)."""
    rs = np.random.default_rng(abs(seed))
    R, Hw = spec.R, spec.wall_h
    parts = []
    # решётка поставлена на долю окружности (от двери по часовой), высота стены
    sweep = 360 * done
    gap = math.degrees(math.asin((spec.door_w / 2 + spec.post_w) / R))
    parts.append(lattice_band(R, Hw * 0.92, sweep, gap, q(lod, 16, 8)))
    # дверная рама стоит
    door, front_z, _ = Y.door_geometry(spec)
    for m in door[:3]:   # два косяка и притолока (без створок и кошмы)
        parts.append(m)
    # колышки разметки по кругу
    parts.append(stake_line(circle_pts(0, 0, R + 0.35, q(lod, 10, 6), 18), 0.4, lod))
    # жерди уука связкой (лежат), тюндюк на подкладках
    n_p = q(lod, 9, 4)
    for k in range(n_p):
        x0 = -R * 0.2 + rs.uniform(-0.05, 0.05)
        z0 = -R * 0.55 + k * 0.07
        parts.append(G.pole((x0 - R * 0.7, 0.05 + (k % 3) * 0.05, z0), (x0 + R * 0.75, 0.06 + (k % 3) * 0.05,
                                                                          z0 + rs.uniform(-0.1, 0.1)),
                            0.028, 0.022, sides=3, region="pole"))
    tun_r = spec.tunduk_r
    tun = K.lathe([(tun_r, 0.0), (tun_r, 0.1), (tun_r - 0.1, 0.12), (tun_r - 0.1, 0.0)], q(lod, 14, 8), 1.0,
                  normals="crease")
    G.to_region(tun, "walnut")
    parts.append(tun.rotate_x(8).translate(R * 0.35, 0.12, R * 0.15))
    # рулоны войлока стопкой
    for i, (x, y, reg) in enumerate(((-R * 0.45, 0.25, "felt_white"), (-R * 0.45 + 0.52, 0.25, "felt_grey"),
                                     (-R * 0.45 + 0.26, 0.68, "felt_white"))):
        parts.append(P.felt_roll(1.8, 0.25, reg, lod).rotate_y(90 + rs.uniform(-6, 6)).translate(x, y, R * 0.2))
    # сложенная решётка ещё не поставленной части
    lat = G.box(0.6, 0.35, 1.8, {"top": "lattice", "front": "lattice", "back": "lattice", "left": "lattice",
                                  "right": "lattice"})
    parts.append(lat.rotate_y(70).translate(R * 0.1, 0, -R * 0.2))
    out = finish(parts)
    return G.ground_ao(out, 0.3, 0.3)


def yurt_ruin(spec, lod=0, seed=0):
    """Пепелище юрты: обгоревшие остатки решётки, осевший купол-войлок, тюндюк набок,
    упавшие жерди, рама двери покосилась."""
    rs = np.random.default_rng(seed)
    R, Hw = spec.R, spec.wall_h
    parts = []
    # остатки решётки по кругу: рваный низ стены
    for a0, sw in ((20, 110), (170, 120), (300, 40)):
        lb = lattice_band(R, Hw * 0.62, sw, a0, q(lod, 8, 4), jag=0.55, seed=seed + a0)
        parts.append(char(lb, 0.42, top_y=Hw * 0.62, soft=0.8))
    # осевший купол: низкий бугор войлока со сползшей сеткой (область купола), в копоти
    dome = K.lathe([(R * 0.98, 0.0), (R * 0.8, Hw * 0.28), (R * 0.45, Hw * 0.42), (spec.tunduk_r, Hw * 0.5)],
                   q(lod, 16, 9), 1.0, sweep=250, start=60)
    G.radial_warp(dome, lambda th, y, r: 1 + 0.08 * np.sin(np.radians(th) * 4 + 1.0) - 0.05 * np.sin(np.radians(th) * 9))
    dome.UV[:, 1] = 1 - dome.UV[:, 1]
    dome.UV[:, 0] *= 0.999
    G.to_region(dome, "felt_grey")
    dome.smooth()
    parts.append(char(scorch(dome, seed, 0.3, cell=R * 0.35), 0.48))
    # тюндюк набок на куче
    tr = spec.tunduk_r
    tun = K.lathe([(tr, 0.0), (tr, 0.1), (tr - 0.1, 0.12), (tr - 0.1, 0.0)], q(lod, 14, 7), 1.0, normals="crease")
    G.to_region(tun, "walnut")
    parts.append(char(tun.rotate_z(28).rotate_y(30).translate(R * 0.2, Hw * 0.42, -R * 0.15), 0.5))
    # жерди уука торчат и лежат
    for k in range(q(lod, 8, 4)):
        a = rs.uniform(0, 2 * math.pi)
        r0 = rs.uniform(0.3, 0.8) * R
        p0 = np.array([r0 * math.sin(a), Hw * 0.35, r0 * math.cos(a)])
        p1 = p0 + np.array([math.sin(a + 0.4) * R * 0.7, rs.uniform(-0.3, 0.6), math.cos(a + 0.4) * R * 0.7])
        p1[1] = max(p1[1], 0.05)
        parts.append(char(G.pole(p0, p1, 0.03, 0.022, sides=3, region="pole"), 0.5))
    # покосившаяся дверная рама
    door, front_z, _ = Y.door_geometry(spec)
    post = door[0].copy()
    parts.append(char(post.rotate_z(-12).translate(0.25, -0.05, 0), 0.55))
    lint = door[2].copy()
    parts.append(char(lint.rotate_x(-70).translate(0, -spec.door_h * 0.9, front_z * 0.15 + 0.5), 0.5))
    # куски войлока вокруг
    for i in range(q(lod, 4, 2)):
        a = rs.uniform(0, 2 * math.pi)
        rr = R * rs.uniform(1.0, 1.35)
        parts.append(char(scorch(felt_sheet(rr * math.sin(a), rr * math.cos(a), rs.uniform(0.5, 0.9), rs.uniform(0.4, 0.7),
                                            0.12, "felt_white" if i % 2 else "felt_grey", q(lod, 7, 5), seed + i,
                                            math.degrees(a)), seed + i, 0.45, 0.6), 0.6))
    return finish(parts)
