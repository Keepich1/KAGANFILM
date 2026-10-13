"""Постройки лагеря кыпчаков второй очереди (ТЗ 5.3, 11.6): кен (стан у жилы), жоокер үйү
(юрта воинов с учебным двором), курултай (совет рода).

JOBS: имя → функция(lod) → узлы [(имя, Mesh, вид[, начало узла])]. Для каждой постройки —
стройка <имя>_site и руины <имя>_ruin.

Юрты — та же одобренная форма, что у боз үй и ордо (gen_camp_yurt.build по своим YurtSpec).
Вымпелы — узлы «Pennant_N» с началом у древка (вымпел разворачивается по ветру вокруг древка).
"""
from __future__ import annotations

import math

import numpy as np

import gen_camp_kit as G
import gen_camp_props as P
import gen_camp_yurt as Y
import meshkit as K
from gen_kipchak2_kit import (ash_patch, char, felt_sheet, finish, local, q, scorch, stake_line, yurt_parts,
                              yurt_ruin, yurt_site)
from meshkit import Mesh


def place(m: Mesh, x, z, yaw=0.0, y=0.0) -> Mesh:
    if yaw:
        m.rotate_y(yaw)
    return m.translate(x, y, z)


# ================================================================ общее: туг, инструменты, руда

def standard(h, lod=0, seed=0, pennant=(2.0, 0.62), hair=True, stones=True):
    """Лёгкий туг: древко, латунное яблоко, трезубец, конский хвост, каменная подсыпка.
    → (меш у начала координат, вымпел в осях древка или None)."""
    rs = np.random.default_rng(seed)
    parts = [G.pole((0, -0.05, 0), (0, h, 0), 0.06, 0.04, sides=q(lod, 6, 4), region="pole")]
    parts.append(G.to_region(K.ellipsoid(0.085, 0.075, 0.085, q(lod, 6, 4), 3).translate(0, h + 0.02, 0), "brass"))
    if lod == 0:
        parts.append(P._spike([(0, h + 0.06, 0), (0, h + 0.4, 0), (0, h + 0.78, 0)], 0.022, "brass", 3))
        for sx in (-1, 1):
            parts.append(P._spike([(0, h + 0.1, 0), (sx * 0.15, h + 0.16, 0), (sx * 0.23, h + 0.36, 0),
                                   (sx * 0.2, h + 0.58, 0)], 0.018, "brass", 3))
    else:
        parts.append(P._spike([(0, h + 0.06, 0), (0, h + 0.78, 0)], 0.03, "brass", 3))
    if hair:
        # конский хвост: пышный пучок, пряди рваные по низу (как у туга лагеря)
        hr = K.lathe([(0.13, -1.45), (0.21, -1.2), (0.2, -0.75), (0.12, -0.25), (0.055, 0.0)] if lod == 0 else
                     [(0.16, -1.4), (0.19, -0.7), (0.055, 0.0)], q(lod, 9, 5), 1.0)
        hr.UV[:, 1] = 0.25 + 0.75 * (1 - hr.UV[:, 1])
        G.to_region(hr, "tassel")
        G.radial_warp(hr, lambda th, y, r: 1 + 0.2 * np.sin(np.radians(th) * 5 + y * 4 + seed) * np.clip(-y, 0, 1.4))
        th = np.arctan2(hr.P[:, 0], hr.P[:, 2])
        tip = np.clip((-hr.P[:, 1] - 1.1) / 0.35, 0, 1)
        hr.P[:, 1] -= tip * (0.1 + 0.18 * np.abs(np.sin(th * 3.5 + seed)))
        hr.smooth()
        parts.append(hr.translate(0, h - 0.05, 0))
        wrap = K.lathe([(0.06, 0.0), (0.075, 0.07), (0.06, 0.15)], q(lod, 7, 5), 1.0).translate(0, h - 0.1, 0)
        G.to_region(wrap, "tassel", inset=2)
        wrap.UV[:, 1] = np.clip(wrap.UV[:, 1], 0, G.atlas_uv("tassel")[1] + 0.02)
        parts.append(wrap)
    if stones:
        for i in range(q(lod, 4, 2)):
            a = i / 4 * 2 * math.pi + rs.uniform(-0.3, 0.3)
            st = G.lump(rs.uniform(0.16, 0.24), rs.uniform(0.1, 0.18), rs.uniform(0.14, 0.22), q(lod, 6, 4), 2, "stones",
                        seed=seed * 7 + i, amount=0.18)
            parts.append(G.ground_ao(st.translate(0.24 * math.sin(a), 0, 0.24 * math.cos(a)), 0.2, 0.35))
    pen = None
    if pennant:
        w, ph = pennant
        drop = 1.25 if hair else 0.2
        pen = G.white(P.pennant(w, ph, q(lod, 10, 5), q(lod, 2, 1)).translate(0.04, h - drop - ph, 0))
    return finish(parts), pen


def tool(kind, lod=0):
    """Инструмент у основания (рукоять вдоль +Y от y=0): «pick» кайло, «ketmen», «shovel»."""
    parts = [G.pole((0, 0, 0), (0, 1.05, 0), 0.022, 0.02, sides=q(lod, 4, 3), region="wood")]
    if kind == "pick":
        head = G.pole((-0.28, 1.0, 0), (0.28, 1.0, 0), 0.025, 0.012, sides=4, region="iron")
        parts.append(head)
    elif kind == "ketmen":
        blade = G.box(0.22, 0.02, 0.24, {"top": "iron", "bottom": "iron", "front": "iron"})
        parts.append(blade.rotate_x(-65).translate(0, 1.02, 0.02))
    return Mesh.merge(parts)


def ore_heap(cx, cz, rx, rz, n, lod=0, seed=0, gold=0.35, grey=True):
    """Куча руды: низкая подсыпка щебня, на ней камни разной величины (серые) и куски кварца
    с золотом (латунь) — россыпь, а не гладкий ком."""
    rs = np.random.default_rng(seed)
    base = G.lump(rx, min(rx, rz) * 0.3, rz, q(lod, 9, 6), q(lod, 3, 2), "stones", seed=seed, amount=0.22)
    parts = [G.shade(base.translate(cx, 0, cz), lambda p: np.full(len(p), 0.62))]
    for i in range(n):
        a = rs.uniform(0, 2 * math.pi)
        r = math.sqrt(rs.uniform(0, 1)) * 0.85
        x, z = cx + rx * r * math.sin(a), cz + rz * r * math.cos(a)
        top = min(rx, rz) * 0.3 * math.sqrt(max(0.0, 1 - r * r))
        is_gold = rs.random() < gold
        s = rs.uniform(0.1, 0.26) * (0.6 if is_gold else 1.0) * (1.3 - 0.5 * r)
        st = G.lump(s * rs.uniform(0.9, 1.4), s * 0.75, s, q(lod, 5, 4), 2, "brass" if is_gold else "stones",
                    seed=seed * 13 + i, amount=0.35)
        if not is_gold:
            st = G.shade(st, lambda p, k=rs.uniform(0.75, 1.1): np.full(len(p), k))
        parts.append(st.rotate_y(rs.uniform(0, 360)).translate(x, top * 0.7, z))
    return G.ground_ao(Mesh.merge(parts), 0.25, 0.3)


def basket(r=0.3, h=0.45, lod=0, load="ore", seed=0):
    """Плетёная корзина (область «wattle») с рудой."""
    b = K.lathe([(r * 0.82, 0.0), (r, h * 0.7), (r * 1.04, h)], q(lod, 8, 5), 1.0)
    b.UV[:, 0] *= 1.0
    b.UV[:, 1] = 1.0 - b.UV[:, 1]
    G.to_region(b, "wattle")
    rim = K.lathe([(r * 1.04, h), (r * 0.98, h + 0.03), (r * 0.92, h)], q(lod, 8, 5), 1.0)
    G.to_region(rim, "bark")
    parts = [b, rim]
    if load:
        top = G.lump(r * 0.95, r * 0.45, r * 0.95, q(lod, 7, 4), 2, "stones" if load == "ore" else "hay", seed=seed,
                     amount=0.3).translate(0, h * 0.82, 0)
        parts.append(top)
        if load == "ore" and lod == 0:
            rs = np.random.default_rng(seed + 3)
            for i in range(3):
                a = rs.uniform(0, 6.28)
                parts.append(G.lump(0.07, 0.05, 0.06, 4, 2, "brass", seed=seed * 5 + i, amount=0.3)
                             .translate(r * 0.45 * math.sin(a), h * 0.82 + r * 0.32, r * 0.45 * math.cos(a)))
    return G.ground_ao(Mesh.merge(parts), 0.2, 0.3)


def light_wheel(radius, lod=0):
    """Колесо двуколки (плоскость YZ, ось по X): обод, ступица, шесть спиц."""
    seg = q(lod, 12, 7)
    w = 0.06
    rim = K.lathe([(radius - 0.06, -w), (radius, -w), (radius, w), (radius - 0.06, w), (radius - 0.06, -w)], seg, 1.0,
                  normals="crease")
    G.to_region(rim, "wood")
    rim.rotate_z(-90)
    hub = K.lathe([(0.05, -0.14), (0.1, -0.08), (0.1, 0.08), (0.05, 0.14)], q(lod, 6, 4), 1.0)
    G.to_region(hub, "walnut")
    hub.rotate_z(-90)
    parts = [rim, hub]
    for k in range(q(lod, 6, 4)):
        a = 2 * math.pi * k / q(lod, 6, 4)
        d = np.array([0, math.cos(a), math.sin(a)])
        parts.append(G.pole(d * 0.08, d * (radius - 0.04), 0.022, 0.018, sides=3, region="wood"))
    return Mesh.merge(parts)


def hand_cart(lod=0, load=True, seed=0):
    """Двуколка для руды: два колеса, кузов из досок, оглобли вперёд (+Z) на земле."""
    parts = []
    R = 0.55
    W, L = 1.0, 1.35
    bed_y = 0.62
    for sx in (-1, 1):
        parts.append(light_wheel(R, lod).translate(sx * (W / 2 + 0.12), R, 0))
    parts.append(G.pole((-(W / 2 + 0.2), R, 0), (W / 2 + 0.2, R, 0), 0.045, sides=q(lod, 5, 4), region="walnut"))
    bed = G.box(W, 0.08, L, {"top": "planks", "front": "wood", "back": "wood", "left": "wood", "right": "wood"})
    parts.append(bed.translate(0, bed_y, 0))
    for sx in (-1, 1):
        side = G.box(0.05, 0.32, L, {"left": ("planks", True), "right": ("planks", True), "top": "wood"})
        parts.append(side.translate(sx * W / 2, bed_y + 0.08, 0))
        parts.append(G.pole((sx * 0.38, bed_y - 0.02, -L / 2 + 0.2), (sx * 0.3, 0.06, L / 2 + 1.35), 0.04, 0.032,
                            sides=q(lod, 4, 3), region="pole"))
    back = G.box(W, 0.3, 0.05, {"front": ("planks", True), "back": ("planks", True)})
    parts.append(back.translate(0, bed_y + 0.08, -L / 2))
    if load:
        parts.append(ore_heap(0, 0, W * 0.42, L * 0.42, q(lod, 8, 3), lod, seed=seed + 50, gold=0.45)
                     .translate(0, bed_y + 0.06, 0))
    return finish(parts)


def stone_block(sx, sy, sz, seed=0, lod=0):
    """Тёсаный камень: грубо обтёсанный брус со скруглёнными рёбрами и сколами (не «кубик»)."""
    rs = np.random.default_rng(seed + 77)
    m = K.ellipsoid(1.0, 1.0, 1.0, q(lod, 8, 6), q(lod, 4, 3), y_from=-0.05, y_to=1.0)
    d = m.P.copy()
    k = np.max(np.abs(d), axis=1, keepdims=True) ** 0.82
    d = d / np.maximum(k, 1e-6)
    d *= 1 + rs.normal(0, 0.035, d.shape)
    m.P = np.column_stack([d[:, 0] * sx / 2, np.maximum(d[:, 1], 0) * sy, d[:, 2] * sz / 2])
    m.UV = np.column_stack([0.5 + (m.P[:, 0] + m.P[:, 2]) / (2.4 * max(sx, sz)), 0.5 - m.P[:, 1] / (2.4 * sy)])
    m.smooth()
    G.to_region(m, "stones")
    G.shade(m, lambda p: 0.85 + 0.25 * np.clip(p[:, 1] / sy, 0, 1))
    return G.ground_ao(m, 0.2, 0.25)


# ================================================================ кен

def alachyk(lod=0, r=1.55, h=2.85):
    """Алачык: шатёр из жердей, крытый войлоком (купол юрты без стены): сетка верёвок,
    торчащие концы жердей, входной полог-кошма спереди (+Z)."""
    tiles = 3
    prof = [(r * 1.02, 0.0), (r * 0.96, h * 0.22), (r * 0.68, h * 0.6), (r * 0.22, h)]
    if lod:
        prof = [prof[0], prof[2], prof[3]]
    cover = G.lathe_tiled(prof, tiles, q(lod, 8, 6), 0, 360, "dome", flip_v=True)
    G.radial_warp(cover, lambda th, y, rr: 1 - 0.03 * (0.5 - 0.5 * np.cos(np.radians(th) * 12)) * np.sin(np.pi * np.clip(y / h, 0, 1)))
    cover.smooth()
    G.shade(cover, lambda p: 0.82 + 0.18 * np.clip(p[:, 1] / 0.6, 0, 1))
    parts = [cover]
    # концы жердей над дымоходом
    for k in range(q(lod, 7, 4)):
        a = math.radians(360 * k / q(lod, 7, 4) + 10)
        p0 = np.array([r * 0.25 * math.sin(a), h - 0.12, r * 0.25 * math.cos(a)])
        p1 = np.array([-r * 0.18 * math.sin(a), h + 0.42, -r * 0.18 * math.cos(a)])
        parts.append(G.pole(p0, p1, 0.028, 0.02, sides=3, region="pole"))
    # полог входа: кошма на передней стороне
    zf = r * 0.97
    door = G.quad((-0.42, 0.02, zf + 0.04), (0.42, 0.02, zf + 0.04), (0.3, 1.45, zf * 0.83 + 0.04), (-0.3, 1.45, zf * 0.83 + 0.04),
                  "koshma", uvs=((0, 1), (1, 1), (1, 0), (0, 0)))
    parts.append(door)
    # верёвка-обвязка по низу
    if lod == 0:
        pts = [(r * 1.0 * math.sin(math.radians(a)), 0.55, r * 1.0 * math.cos(math.radians(a))) for a in range(0, 361, 30)]
        up = np.array([(math.sin(math.radians(a)), 0.2, math.cos(math.radians(a))) for a in range(0, 361, 30)])
        parts.append(G.strip(pts, up, 0.07, 0.035, "rope", tile_len=1.5, lift=0.01))
    return finish(parts)


def ken(lod=0):
    """Кен — стан у жилы 8×8: алачык старателей, куча руды у жилы (сзади справа), двуколка
    с рудой, корзины, колода для промывки золота, кайло и кетмень, тёсаные камни,
    шест с киноварным вымпелом."""
    rs = np.random.default_rng(201)
    parts = []
    parts.append(place(alachyk(lod), -1.75, -1.35, 25))
    parts.append(ore_heap(1.75, -2.35, 1.35, 1.0, q(lod, 14, 6), lod, seed=7))
    parts.append(place(hand_cart(lod, seed=3), 2.35, 1.05, -35))
    for i, (x, z) in enumerate(((-0.55, 1.75), (0.05, 2.35), (0.6, 1.8))):
        parts.append(place(basket(0.28 + 0.03 * (i % 2), 0.44, lod, "ore", seed=10 + i), x, z, rs.uniform(0, 360)))
    tr = P.trough(2.0, lod)
    parts.append(place(tr, -2.55, 1.85, 80))
    # кайло и кетмень воткнуты в кучу руды
    parts.append(tool("pick", lod).rotate_z(18).rotate_y(30).translate(1.1, 0.1, -2.0))
    parts.append(tool("ketmen", lod).rotate_x(-20).rotate_y(-60).translate(2.5, 0.05, -1.6))
    # тёсаные камни штабелем
    for i, (x, y, z, yaw) in enumerate(((3.05, 0, -0.25, 8), (3.15, 0, 0.45, -5), (3.1, 0.42, 0.1, 12))):
        parts.append(place(stone_block(0.62, 0.42, 0.55, seed=i, lod=lod), x, z, yaw, y))
    # мешки у алачыка
    for i, (x, z) in enumerate(((-0.25, -0.35), (-0.05, 0.15))):
        sk = G.lump(0.28, 0.36, 0.24, q(lod, 7, 5), q(lod, 3, 2), "felt_grey", seed=30 + i, amount=0.12)
        parts.append(G.ground_ao(sk.translate(x, 0, z), 0.25, 0.3))
    # шест с вымпелом (узел «Pennant»: начало у древка)
    pole_at = (-3.25, 0.0, 2.95)
    std, pen = standard(4.2, lod, seed=5, pennant=(1.7, 0.55), hair=False)
    parts.append(std.translate(*pole_at))
    nodes = [("Ken", G.ground_ao(finish(parts), 0.2, 0.2), "opaque"),
             ("Pennant", pen, "cloth", pole_at),
             ("Ground", P.earth_patch(4.1, 4.0, lod), "cutout")]
    return nodes


def ken_site(lod=0):
    """Стройка кена: разметка, жерди алачыка связкой, рулон войлока, пустые корзины, камни."""
    rs = np.random.default_rng(211)
    parts = [stake_line([(-3.6, 3.6), (3.6, 3.6), (3.6, -3.6), (-3.6, -3.6)], 0.42, lod)]
    for k in range(q(lod, 8, 4)):
        z = -1.6 + k * 0.07
        parts.append(G.pole((-3.0, 0.05 + (k % 3) * 0.05, z), (0.2, 0.06 + (k % 3) * 0.05, z + rs.uniform(-0.15, 0.15)),
                            0.03, 0.022, sides=3, region="pole"))
    # треножник из трёх жердей (начало алачыка), невысоко
    for k in range(3):
        a = math.radians(120 * k + 20)
        parts.append(G.pole((-1.75 + 1.0 * math.sin(a), 0, -1.35 + 1.0 * math.cos(a)), (-1.75, 1.25, -1.35), 0.03, 0.025,
                            sides=3, region="pole"))
    parts.append(P.felt_roll(1.8, 0.27, "felt_grey", lod).rotate_y(20).translate(0.6, 0.27, 0.6))
    parts.append(P.felt_roll(1.6, 0.24, "koshma", lod).rotate_y(10).translate(0.7, 0.75, 0.5))
    for i, (x, z) in enumerate(((1.8, 2.0), (2.4, 2.2))):
        parts.append(basket(0.28, 0.44, lod, None, seed=i).translate(x, 0, z))
    parts.append(ore_heap(1.75, -2.35, 0.9, 0.7, q(lod, 6, 3), lod, seed=17, gold=0.2))
    parts.append(P.trough(2.0, lod).rotate_y(80).translate(-2.55, 0, 1.85))
    return [("KenSite", G.ground_ao(finish(parts), 0.2, 0.2), "opaque")]


def ken_ruin(lod=0):
    """Разорённый кен: алачык сгорел (осевший войлок, торчат жерди), двуколка перевёрнута,
    корзины рассыпаны, руда растащена."""
    rs = np.random.default_rng(221)
    parts = [char(scorch(felt_sheet(-1.75, -1.35, 1.7, 1.5, 0.6, "felt_grey", q(lod, 9, 6), 3, 25), 3, 0.35, 0.7), 0.65)]
    for k in range(q(lod, 6, 3)):
        a = math.radians(60 * k + rs.uniform(-10, 10))
        p0 = (-1.75 + 1.3 * math.sin(a), 0.05, -1.35 + 1.3 * math.cos(a))
        p1 = (-1.75 + 0.3 * math.sin(a + 1), 0.9 + rs.uniform(0, 0.6), -1.35 + 0.3 * math.cos(a + 1))
        parts.append(char(G.pole(p0, p1, 0.03, 0.02, sides=3, region="pole"), 0.4))
    cart = hand_cart(lod, load=False)
    cart.rotate_z(95)
    cart.translate(2.4, -cart.P[:, 1].min(), 1.1)
    parts.append(char(cart, 0.6))
    parts.append(ore_heap(1.75, -2.35, 1.0, 0.8, q(lod, 8, 3), lod, seed=27, gold=0.15))
    for i in range(q(lod, 3, 2)):
        b = basket(0.28, 0.44, lod, None, seed=i)
        parts.append(char(b.rotate_x(85).rotate_y(rs.uniform(0, 360)).translate(rs.uniform(-1, 1), 0.28, rs.uniform(1, 2.6)), 0.6))
    for i in range(q(lod, 8, 3)):
        x, z = rs.uniform(-1.2, 3.0), rs.uniform(-0.5, 3.2)
        parts.append(G.lump(rs.uniform(0.08, 0.16), 0.08, rs.uniform(0.08, 0.14), 4, 2, "stones", seed=300 + i, amount=0.3)
                     .translate(x, 0, z))
    std, _ = standard(4.2, lod, seed=5, pennant=None, hair=False, stones=False)
    parts.append(char(std.rotate_z(-84).translate(-3.25, 0.12, 2.95), 0.55))
    return [("KenRuin", finish(parts), "opaque"), ("Ground", ash_patch(3.0, 2.6, lod), "cutout")]


# ================================================================ жоокер үйү

def jooker_spec(lod=0):
    return Y.YurtSpec("jooker", R=3.5, wall_h=2.05, top_y=4.75, tunduk_r=0.78, door_w=1.05, door_h=1.9, post_w=0.17,
                      post_d=0.28, lintel_h=0.22, roll_r=0.17, wall_region="wall_boz", eave_region="eave_boz",
                      tiles_wall=4, tiles_dome=4, seg=12 if lod == 0 else 10, rope_w=0.09, rope_h=0.05, rope_seg=6,
                      arch_h=0.34, shields=[], lod=lod)


JOOKER_SHIELDS = [-40, 40, -82, 82]


def wall_shields(spec, angles, lod=0, scale=0.8):
    """Щиты с одной конской кистью на стене юрты (как у ханской, но скромнее)."""
    parts = []
    k = spec.R / 3.1
    for ang in angles:
        a = math.radians(ang)
        r = spec.R * 1.004
        y = spec.wall_h * 0.6
        sh = Y.shield(0.42 * k * scale, lod)
        parts.append(sh.rotate_y(ang).translate(r * math.sin(a), y, r * math.cos(a)))
        ta = Y.tassel(0.62 * k * scale, 0.075 * k, lod)
        parts.append(ta.translate(r * math.sin(a) + math.sin(a) * 0.1, y - 0.3 * k * scale, r * math.cos(a) + math.cos(a) * 0.1))
    return parts


JOOKER_YURT = (-2.4, -1.25)


def spear(length=2.6, lod=0):
    """Найза: древко вдоль +Y от y=0, железный наконечник."""
    parts = [G.pole((0, 0, 0), (0, length, 0), 0.022, 0.018, sides=q(lod, 4, 3), region="pole")]
    tip = K.lathe([(0.026, 0.0), (0.04, 0.06), (0.0, 0.28)], 3, 1.0, normals="crease")
    tip.UV[:, 1] = 0.3 + 0.7 * tip.UV[:, 1]
    G.to_region(tip, "iron")
    parts.append(tip.translate(0, length, 0))
    return Mesh.merge(parts)


def weapon_rack(lod=0, seed=0, shields=2, bow=True):
    """Стойка для оружия: козлы, перекладины, прислонённые копья, щиты, лук в налучье."""
    rs = np.random.default_rng(seed)
    parts = []
    W = 2.2
    for x in (-W / 2, W / 2):
        for dz in (-1, 1):
            parts.append(G.pole((x, -0.05, dz * 0.42), (x, 1.75, 0), 0.045, 0.04, sides=q(lod, 5, 4), region="wood"))
    parts.append(G.pole((-W / 2 - 0.15, 1.62, 0), (W / 2 + 0.15, 1.62, 0), 0.05, sides=q(lod, 5, 4), region="wood"))
    parts.append(G.pole((-W / 2, 0.4, -0.3), (W / 2, 0.4, -0.3), 0.04, sides=q(lod, 4, 3), region="wood"))
    n = q(lod, 5, 3)
    for k in range(n):
        x = -W / 2 + 0.2 + (W - 0.4) * k / (n - 1)
        sp = spear(2.5 + rs.uniform(-0.15, 0.2), lod)
        sp.rotate_x(-16 + rs.uniform(-3, 3)).rotate_z(rs.uniform(-4, 4)).translate(x, 0.0, -0.75)
        parts.append(sp)
    for k in range(shields):
        x = -0.55 + 1.1 * k
        parts.append(Y.shield(0.3, 1).rotate_x(-12).translate(x, 1.22, 0.07))
        if lod == 0 and k == 0:
            parts.append(Y.tassel(0.42, 0.05, 1).translate(x, 0.98, 0.12))
    if bow and lod == 0:
        pts = [(0.95 + 0.1 * math.sin(t * math.pi) - 0.02, 1.6 - t * 1.2, 0.06 + 0.12 * math.sin(t * math.pi))
               for t in np.linspace(0, 1, 7)]
        parts.append(G.path_tube(pts, 0.018, sides=3, region="walnut", tile_len=2.0))
        parts.append(G.path_tube([pts[0], pts[-1]], 0.004, sides=3, region="rope", tile_len=2.0))
    return G.ground_ao(finish(parts), 0.3, 0.25)


def dummy(lod=0, seed=0, shield=False):
    """Учебное чучело: столб, перекладина-руки, соломенное тело, войлочная голова."""
    parts = [G.pole((0, -0.05, 0), (0, 1.95, 0), 0.1, 0.085, sides=q(lod, 6, 4), region="bark")]
    parts.append(G.pole((-0.62, 1.42, 0), (0.62, 1.45, 0), 0.04, sides=q(lod, 4, 3), region="pole"))
    body = G.lump(0.3, 0.42, 0.24, q(lod, 8, 5), q(lod, 4, 2), "hay", seed=seed, amount=0.18).translate(0, 0.95, 0)
    parts.append(body)
    belt = K.lathe([(0.3, 1.2), (0.31, 1.27)], q(lod, 8, 5), 1.0)
    parts.append(G.to_region(belt, "koshma"))
    head = G.lump(0.15, 0.17, 0.14, q(lod, 6, 4), 2, "felt_grey", seed=seed + 1, amount=0.1).translate(0, 1.68, 0)
    parts.append(head)
    if shield:
        parts.append(Y.shield(0.3, lod).rotate_y(-20).translate(0.32, 1.25, 0.2))
    for k in range(q(lod, 2, 0)):  # стрелы и зарубки
        parts.append(G.pole((0.1 * k - 0.05, 1.1 + 0.15 * k, 0.15), (0.12 * k - 0.1, 1.15 + 0.15 * k, 0.75), 0.008,
                            sides=3, region="wood"))
    return G.ground_ao(finish(parts), 0.4, 0.3)


def target(lod=0):
    """Мишень для стрельбы: соломенный щит на треноге, лицо — круглый щит с киноварным кольцом."""
    parts = []
    face = K.lathe([(0.48, 0.0), (0.46, 0.05), (0.0, 0.08)], q(lod, 10, 6), 1.0)
    face.UV = np.column_stack([0.5 + face.P[:, 0] / 1.0, 0.5 + face.P[:, 2] / 1.0])
    G.to_region(face, "shield")
    drum = K.lathe([(0.5, -0.16), (0.5, 0.0)], q(lod, 10, 6), 1.0)
    G.to_region(drum, "hay")
    disc = Mesh.merge([drum, face]).rotate_x(90).rotate_x(-12).translate(0, 1.15, 0)
    parts.append(disc)
    for a in (0, 120, 240):
        r = math.radians(a)
        parts.append(G.pole((0.55 * math.sin(r), -0.03, -0.3 + 0.5 * math.cos(r)), (0, 1.25, -0.08), 0.035, 0.03,
                            sides=q(lod, 4, 3), region="pole"))
    if lod == 0:
        rs = np.random.default_rng(3)
        for k in range(4):
            x, y = rs.uniform(-0.25, 0.25), 1.15 + rs.uniform(-0.25, 0.25)
            parts.append(G.pole((x, y, 0.05), (x + rs.uniform(-0.08, 0.08), y + 0.08, 0.68), 0.008, sides=3, region="wood"))
    return G.ground_ao(finish(parts), 0.3, 0.25)


def jooker(lod=0):
    """Жоокер үйү 12×10: юрта воинов со щитами и конскими кистями (сзади слева), стойки для
    оружия, учебные чучела, мишень, скамья, туг с вымпелом у входа."""
    spec = jooker_spec(lod)
    yurt, _ = yurt_parts(spec)
    yurt = finish([yurt] + wall_shields(spec, JOOKER_SHIELDS, lod))
    parts = [yurt.translate(JOOKER_YURT[0], 0, JOOKER_YURT[1])]
    parts.append(place(weapon_rack(lod, 1), 3.2, -3.4, 0))
    parts.append(place(weapon_rack(lod, 2, shields=1, bow=False), 5.0, -0.6, -72))
    for i, (x, z, yaw, sh) in enumerate(((1.55, 3.35, 10, False), (3.25, 3.85, -15, True), (4.85, 2.65, -40, False))):
        parts.append(place(dummy(lod, 10 + i, sh), x, z, yaw))
    parts.append(place(target(lod), 4.95, -3.75, -120))
    parts.append(P.log((-5.2, 0.22, 3.2), (-3.4, 0.22, 3.55), 0.2, lod))
    parts.append(P.log((-5.25, 0.2, 2.2), (-5.1, 0.2, 3.9), 0.18, lod) if lod == 0 else None)
    pole_at = (-0.45, 0.0, 3.25)
    std, pen = standard(6.6, lod, seed=9, pennant=(2.2, 0.66))
    parts.append(std.translate(*pole_at))
    nodes = [("Jooker", finish(parts), "opaque"), ("Pennant", pen, "cloth", pole_at),
             ("Ground", P.earth_patch(6.2, 5.0, lod), "cutout")]
    return nodes


def jooker_site(lod=0):
    """Стройка жоокер үйү: стройка юрты, козлы стоек лежат, столбы чучел вкопаны наполовину."""
    spec = jooker_spec(lod)
    parts = [yurt_site(spec, lod, seed=3, done=0.35).translate(JOOKER_YURT[0], 0, JOOKER_YURT[1])]
    for i, (x, z) in enumerate(((1.55, 3.35), (3.25, 3.85), (4.85, 2.65))):
        parts.append(G.pole((x, -0.05, z), (x, 0.9, z), 0.1, 0.09, sides=q(lod, 6, 4), region="bark"))
    for k in range(q(lod, 4, 2)):
        parts.append(G.pole((2.0, 0.05 + k * 0.08, -3.6 + k * 0.12), (4.6, 0.06 + k * 0.08, -3.3 + k * 0.12), 0.045,
                            sides=q(lod, 5, 4), region="wood"))
    parts.append(stake_line([(-6, 5), (6, 5), (6, -5), (-6, -5)], 0.42, lod))
    return [("JookerSite", G.ground_ao(finish(parts), 0.3, 0.3), "opaque")]


def jooker_ruin(lod=0):
    """Разорённый жоокер үйү: пепелище юрты, стойка повалена, копья раскиданы, чучела сломаны,
    туг лежит."""
    rs = np.random.default_rng(231)
    spec = jooker_spec(lod)
    parts = [yurt_ruin(spec, lod, seed=5).translate(JOOKER_YURT[0], 0, JOOKER_YURT[1])]
    rack = weapon_rack(lod, 1, shields=1, bow=False)
    rack.rotate_x(80)
    rack.translate(3.2, -rack.P[:, 1].min(), -2.6)
    parts.append(char(rack, 0.6))
    for k in range(q(lod, 5, 2)):
        sp = spear(2.4, lod)
        parts.append(sp.rotate_z(88).rotate_y(rs.uniform(0, 360)).translate(rs.uniform(1.5, 5), 0.05, rs.uniform(-3, 2)))
    for i, (x, z) in enumerate(((1.55, 3.35), (3.25, 3.85), (4.85, 2.65))):
        h = rs.uniform(0.5, 1.2)
        parts.append(char(G.pole((x, -0.05, z), (x, h, z), 0.1, 0.09, sides=q(lod, 6, 4), region="bark"), 0.5))
        parts.append(G.lump(0.3, 0.12, 0.3, q(lod, 6, 4), 2, "hay", seed=40 + i, amount=0.3).translate(x + 0.4, 0, z + 0.2))
    std, _ = standard(6.6, lod, seed=9, pennant=None, stones=False)
    std.rotate_x(86).rotate_y(200)
    parts.append(char(std.translate(-0.45, 0.06 - std.P[:, 1].min(), 3.25), 0.6))
    return [("JookerRuin", finish(parts), "opaque"), ("Ground", ash_patch(4.4, 4.0, lod), "cutout")]


# ================================================================ курултай

def kurultai_yurt_spec(lod=0):
    return Y.YurtSpec("kurultai", R=2.55, wall_h=1.75, top_y=3.8, tunduk_r=0.6, door_w=0.9, door_h=1.66,
                      post_w=0.14, post_d=0.24, lintel_h=0.19, roll_r=0.14, wall_region="wall_ordo",
                      eave_region="eave_ordo", tiles_wall=4, tiles_dome=4, seg=10 if lod == 0 else 8,
                      rope_w=0.075, rope_h=0.04, rope_seg=5, arch_h=0.26, shields=[-42, 42], lod=lod)


KUR_YURTS = [(-4.05, -3.55), (4.05, -3.55)]
KUR_TUGS = [25, -25, 62, -62, 98, -98, 168, -168]   # углы от +Z, радиус 6.35
KUR_TUG_R = 6.35
PAV_R = 3.0          # радиус свеса шатра
PAV_POST_R = 2.7
PAV_EAVE = 2.6
PAV_PEAK = 4.35


def pavilion(lod=0):
    """Шатёр совета: восемь резных столбов, восьмигранная войлочная кровля (ткань «Awning»:
    киноварная крыша, кремовый подзор с рогами и фестонами), латунное навершие с туг-хвостом.
    → (опаковые части, кровля-ткань)."""
    n = 8
    parts = []
    for k in range(n):
        a = math.radians(360 * k / n + 22.5)
        x, z = PAV_POST_R * math.sin(a), PAV_POST_R * math.cos(a)
        post = G.box(0.17, PAV_EAVE + 0.05, 0.17, {"front": "frame", "back": "frame", "left": "frame", "right": "frame"})
        post.rotate_y(math.degrees(a)).translate(x, -0.03, z)
        parts.append(G.ground_ao(post, 0.4, 0.3))
        parts.append(G.to_region(K.ellipsoid(0.11, 0.08, 0.11, q(lod, 6, 4), 3).translate(x, PAV_EAVE + 0.04, z), "brass"))
        base = K.lathe([(0.16, 0.0), (0.15, 0.12), (0.1, 0.16)], q(lod, 6, 4), 1.0)
        parts.append(G.to_region(base, "stones").translate(x, 0, z))
    # обвязка по верху столбов и стропила к центру
    for k in range(n):
        a0 = math.radians(360 * k / n + 22.5)
        a1 = math.radians(360 * (k + 1) / n + 22.5)
        p0 = (PAV_POST_R * math.sin(a0), PAV_EAVE - 0.05, PAV_POST_R * math.cos(a0))
        p1 = (PAV_POST_R * math.sin(a1), PAV_EAVE - 0.05, PAV_POST_R * math.cos(a1))
        parts.append(G.pole(p0, p1, 0.06, sides=q(lod, 5, 3), region="walnut"))
    # навершие: латунное яблоко, трезубец, туг-хвост; вымпел — отдельный узел у древка (центр)
    parts.append(G.pole((0, PAV_PEAK - 0.3, 0), (0, PAV_PEAK + 1.4, 0), 0.05, 0.035, sides=q(lod, 5, 4), region="pole"))
    parts.append(G.to_region(K.ellipsoid(0.1, 0.09, 0.1, q(lod, 6, 4), 3).translate(0, PAV_PEAK + 1.42, 0), "brass"))
    parts.append(P._spike([(0, PAV_PEAK + 1.48, 0), (0, PAV_PEAK + 2.05, 0)], 0.022, "brass", 3))
    for sx in ((-1, 1) if lod == 0 else ()):
        parts.append(P._spike([(0, PAV_PEAK + 1.5, 0), (sx * 0.14, PAV_PEAK + 1.56, 0), (sx * 0.2, PAV_PEAK + 1.78, 0)],
                              0.017, "brass", 3))
    roof = _pavilion_roof(n, lod)
    return finish(parts), roof


def _pavilion_roof(n, lod):
    """Восьмигранная кровля и подзор одним полотном (UV2.x — свобода колыхания)."""
    P_, UV, UV2, F = [], [], [], []
    nv = q(lod, 3, 2)
    nu = q(lod, 2, 1)
    drop = 0.55

    def add_quad_grid(rows):
        base = len(P_)
        cols = len(rows[0])
        for row in rows:
            for p, uv, f in row:
                P_.append(p)
                UV.append(uv)
                UV2.append(f)
        for j in range(len(rows) - 1):
            for i in range(cols - 1):
                a = base + j * cols + i
                b = a + cols
                F.extend([(a, b, b + 1), (a, b + 1, a + 1)])

    for k in range(n):
        a0 = math.radians(360 * k / n)
        a1 = math.radians(360 * (k + 1) / n)
        c0 = np.array([PAV_R * math.sin(a0), PAV_EAVE, PAV_R * math.cos(a0)])
        c1 = np.array([PAV_R * math.sin(a1), PAV_EAVE, PAV_R * math.cos(a1)])
        apex = np.array([0.0, PAV_PEAK, 0.0])
        rows = []
        for j in range(nv + 1):
            t = j / nv               # 0 — вершина, 1 — свес
            row = []
            for i in range(nu + 1):
                s = i / nu
                edge = c0 + (c1 - c0) * s
                p = apex + (edge - apex) * t
                sag = 0.13 * math.sin(math.pi * t) * (1 - abs(2 * s - 1) ** 2)
                p = p - np.array([0, sag, 0])
                row.append((p, (s, t * 0.52), (t * 0.35, s)))
            rows.append(row)
        add_quad_grid(rows)
        vrows = []
        for j in range(2):
            t = j
            row = []
            for i in range(nu + 1):
                s = i / nu
                edge = c0 + (c1 - c0) * s
                p = edge + np.array([0, -drop * t, 0]) + (edge / PAV_R) * np.array([1, 0, 1]) * 0.03 * t
                row.append((p, (s, 0.52 + 0.48 * t), (0.35 + 0.65 * t, s)))
            vrows.append(row)
        add_quad_grid(vrows)
    m = Mesh(P_, F, None, UV, UV2)
    # наружу: проверим ориентацию по первой грани
    fn = np.cross(m.P[m.F[0, 1]] - m.P[m.F[0, 0]], m.P[m.F[0, 2]] - m.P[m.F[0, 0]])
    cen = m.P[m.F[0]].mean(0)
    if np.dot(fn, cen - np.array([0, 1.0, 0])) < 0:
        m.F = m.F[:, ::-1].copy()
    m.recalc_normals()
    G.to_region(m, "awning")
    return G.white(m)


def council_floor(lod=0):
    """Под шатром: шырдаки (кошмы), круглый войлок, подушки по кругу, почётное место хана."""
    parts = []
    car = G.quad((-1.7, 0.035, 1.25), (1.7, 0.035, 1.25), (1.7, 0.035, -1.25), (-1.7, 0.035, -1.25), "saddlecloth")
    parts.append(car)
    rd = G.disc_uv(1.0, q(lod, 12, 8), "felt_white", y=0.045)
    parts.append(G.shade(rd, lambda p: np.full(len(p), 0.92)).translate(0, 0, 0.1))
    for k in range(q(lod, 8, 4)):
        a = math.radians(360 * k / q(lod, 8, 4) + 22.5)
        if abs(math.degrees(a) % 360 - 0) < 10:
            continue
        x, z = 2.15 * math.sin(a), 2.15 * math.cos(a)
        cu = G.lump(0.42, 0.16, 0.3, q(lod, 6, 4), 2, "koshma" if k % 2 else "felt_white", seed=60 + k, amount=0.12)
        parts.append(G.ground_ao(cu.rotate_y(math.degrees(a)).translate(x, 0, z), 0.15, 0.3))
    seat = G.box(1.3, 0.35, 0.7, {"top": "saddlecloth", "front": "koshma", "left": "felt_white", "right": "felt_white",
                                   "back": "felt_white"})
    parts.append(G.ground_ao(seat.translate(0, 0, -2.05), 0.3, 0.3))
    return finish(parts)


def kurultai(lod=0):
    """Курултай 14×14 — совет рода: шатёр совета посередине (киноварная восьмигранная кровля
    на резных столбах, кошмы и подушки под ней), две богатые юрты сзади (пояс ордо),
    кольцо из восьми тугов с вымпелами — лес знамён читается издали."""
    spec = kurultai_yurt_spec(lod)
    parts = []
    for x, z in KUR_YURTS:
        y, _ = yurt_parts(spec)
        yaw = math.degrees(math.atan2(-x, -z))
        parts.append(y.rotate_y(yaw).translate(x, 0, z))
    pav, roof = pavilion(lod)
    parts.append(pav)
    parts.append(council_floor(lod))
    pen_nodes = []
    for i, ang in enumerate(KUR_TUGS):
        a = math.radians(ang)
        at = (KUR_TUG_R * math.sin(a), 0.0, KUR_TUG_R * math.cos(a))
        std, pen = standard(6.4 + 0.5 * (i % 2), lod, seed=20 + i, pennant=(1.9, 0.6))
        parts.append(std.translate(*at))
        pen_nodes.append((f"Pennant_{i + 1}", pen, "cloth", at))
    # верхний вымпел шатра (древко по оси Y модели)
    top = G.white(P.pennant(2.0, 0.6, q(lod, 10, 5), q(lod, 2, 1)).translate(0.04, PAV_PEAK + 1.35 - 0.6 - 0.1, 0))
    nodes = [("Kurultai", finish(parts), "opaque"), ("Awning", roof, "cloth"), ("Pennant", top, "cloth")] + pen_nodes
    nodes.append(("Ground", P.earth_patch(6.9, 6.9, lod), "cutout"))
    return nodes


def kurultai_site(lod=0):
    """Стройка курултая: столбы шатра поставлены, две юрты на стройке, туги лежат связкой."""
    spec = kurultai_yurt_spec(lod)
    parts = []
    for x, z in KUR_YURTS:
        s = yurt_site(spec, lod, seed=int(x * 10), done=0.3)
        yaw = math.degrees(math.atan2(-x, -z))
        parts.append(s.rotate_y(yaw).translate(x, 0, z))
    for k in range(8):
        a = math.radians(360 * k / 8 + 22.5)
        x, z = PAV_POST_R * math.sin(a), PAV_POST_R * math.cos(a)
        post = G.box(0.17, PAV_EAVE + 0.05, 0.17, {"front": "frame", "back": "frame", "left": "frame", "right": "frame"})
        parts.append(G.ground_ao(post.rotate_y(math.degrees(a)).translate(x, -0.03, z), 0.4, 0.3))
    for k in range(q(lod, 5, 2)):
        parts.append(G.pole((-2.0, 0.06 + 0.07 * (k % 2), 4.6 + k * 0.14), (4.4, 0.07, 4.9 + k * 0.1), 0.06, 0.045,
                            sides=q(lod, 5, 4), region="pole"))
    parts.append(P.felt_roll(2.2, 0.3, "koshma", lod).rotate_y(15).translate(-0.5, 0.3, -0.4))
    parts.append(P.felt_roll(2.0, 0.28, "felt_white", lod).rotate_y(-10).translate(0.4, 0.3, 0.4))
    pts = [(KUR_TUG_R * math.sin(math.radians(a)), KUR_TUG_R * math.cos(math.radians(a))) for a in range(0, 360, 45)]
    parts.append(stake_line(pts, 0.42, lod))
    return [("KurultaiSite", G.ground_ao(finish(parts), 0.3, 0.3), "opaque")]


def kurultai_ruin(lod=0):
    """Разорённый курултай: юрты сгорели, кровля шатра рухнула на обломанные столбы,
    туги повалены, кошмы раскиданы."""
    rs = np.random.default_rng(241)
    spec = kurultai_yurt_spec(lod)
    parts = []
    for i, (x, z) in enumerate(KUR_YURTS):
        r = yurt_ruin(spec, lod, seed=7 + i)
        yaw = math.degrees(math.atan2(-x, -z))
        parts.append(r.rotate_y(yaw).translate(x, 0, z))
    for k in range(8):
        a = math.radians(360 * k / 8 + 22.5)
        x, z = PAV_POST_R * math.sin(a), PAV_POST_R * math.cos(a)
        h = rs.uniform(0.6, 2.0)
        post = G.box(0.17, h, 0.17, {"front": "frame", "back": "frame", "left": "frame", "right": "frame"})
        parts.append(char(post.rotate_y(math.degrees(a)).translate(x, -0.03, z), 0.5, top_y=h, soft=0.6))
    parts.append(char(scorch(felt_sheet(0.3, 0.2, 3.0, 2.7, 1.1, "koshma", q(lod, 10, 7), 11, 15), 11, 0.35, 0.9), 0.6))
    for i, ang in enumerate(KUR_TUGS):
        a = math.radians(ang)
        at = (KUR_TUG_R * math.sin(a), 0.0, KUR_TUG_R * math.cos(a))
        if i % 3 == 2:
            std, _ = standard(rs.uniform(1.0, 2.4), lod, seed=20 + i, pennant=None, hair=False)
            parts.append(char(std.translate(*at), 0.55))
            continue
        std, _ = standard(6.4, lod, seed=20 + i, pennant=None, stones=False)
        std.rotate_x(86).rotate_y(ang + 180 + rs.uniform(-25, 25))     # валится внутрь, на свою площадку
        parts.append(char(std.translate(at[0], 0.06 - std.P[:, 1].min(), at[2]), 0.6))
    car = G.quad((-1.7, 0.035, 1.25), (1.7, 0.035, 1.25), (1.7, 0.035, -1.25), (-1.7, 0.035, -1.25), "saddlecloth")
    parts.append(scorch(car.rotate_y(28).translate(1.8, 0, 4.2), 2, 0.5))
    return [("KurultaiRuin", finish(parts), "opaque"), ("Ground", ash_patch(6.0, 6.0, lod), "cutout")]


JOBS = {
    "ken": ken, "ken_site": ken_site, "ken_ruin": ken_ruin,
    "jooker": jooker, "jooker_site": jooker_site, "jooker_ruin": jooker_ruin,
    "kurultai": kurultai, "kurultai_site": kurultai_site, "kurultai_ruin": kurultai_ruin,
}
