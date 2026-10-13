"""Принятые идеи экономики Коканда (бонус): базар (bozor 14×10) и печь для кирпича
(xumdon 8×8). Размеры предварительные, имена — как в задании.
"""
from __future__ import annotations

import math

import numpy as np

import gen_kokand_fort as FO
import gen_kokand_kit as G
import gen_kokand_parts as PT
import gen_kokand_ruins as R
import meshkit as K
from gen_kokand_atlas import arch_curve
from gen_kokand_models import Model
from meshkit import Mesh

q = PT.q


# ================================================================ базар

def awning(x0, x1, z_back, z_front, y_back, y_front, nx=4, nz=2):
    """Навес-полотно: от заднего края (закреплён, UV2.x = 0) к переднему (свободный край — фестоны).
    Узел «Awning» (ткань, cloth.gdshader)."""
    P, UV, UV2, F = [], [], [], []
    for j in range(nz + 1):
        t = j / nz
        z = z_back + (z_front - z_back) * t
        y = y_back + (y_front - y_back) * t - 0.12 * math.sin(math.pi * t)
        for i in range(nx + 1):
            s = i / nx
            x = x0 + (x1 - x0) * s
            P.append((x, y, z))
            UV.append((s, t))
            UV2.append((t, s))
    for j in range(nz):
        for i in range(nx):
            a = j * (nx + 1) + i
            b = a + nx + 1
            F += [(a, b, b + 1), (a, b + 1, a + 1)]
    m = Mesh(P, F, None, UV)
    if m.N[:, 1].mean() < 0:
        m.flip()
    m.UV2 = np.array(UV2, float)
    m.has_uv2 = True
    return G.white(G.to_region(m, "awning"))


def melon(x, y, z, s=1.0, seed=0):
    m = G.lump(0.22 * s, 0.17 * s, 0.17 * s, 7, 3, "hay", seed=seed, amount=0.05, flat_bottom=False)
    G.shade(m, lambda P: np.tile([0.95, 1.0, 0.55], (len(P), 1)))
    return m.translate(x, y + 0.15 * s, z)


def stall(x, z, w=3.6, d=2.4, lod=0, seed=0, goods="pottery"):
    """Прилавок: глиняная суфа с ковром, четыре шеста и полосатый навес; товар сверху."""
    rs = np.random.default_rng(seed)
    parts = [PT.carpet_supa(0.0, 0.0, w, d, 0.55)]
    for sx in (-1, 1):
        for sz in (-1, 1):
            h = 2.5 if sz < 0 else 2.2
            parts.append(G.pole((sx * (w / 2 - 0.1), 0.0, sz * (d / 2 - 0.1)), (sx * (w / 2 - 0.1), h, sz * (d / 2 - 0.1)),
                                0.05, sides=4, region="pole"))
    for sz, h in ((-1, 2.5), (1, 2.2)):
        parts.append(G.pole((-w / 2, h, sz * (d / 2 - 0.1)), (w / 2, h, sz * (d / 2 - 0.1)), 0.035, sides=3,
                            region="pole"))
    if goods == "pottery":
        for k in range(6 if lod == 0 else 3):
            parts.append(PT.jug(rs.uniform(-w / 2 + 0.4, w / 2 - 0.4), rs.uniform(-d / 2 + 0.3, d / 2 - 0.3),
                                rs.uniform(0.7, 1.2), lod).translate(0, 0.56, 0))
    elif goods == "melons":
        for k in range(10 if lod == 0 else 4):
            parts.append(melon(rs.uniform(-w / 2 + 0.3, w / 2 - 0.3), 0.56, rs.uniform(-d / 2 + 0.3, d / 2 - 0.3),
                               rs.uniform(0.8, 1.3), seed=seed * 20 + k))
    else:
        parts.append(R.sack_pile(0.0, 0.0, 0.0, n=4 if lod == 0 else 2, seed=seed, lod=lod).translate(0, 0.56, 0))
    m = Mesh.merge(parts)
    aw = awning(-w / 2 - 0.15, w / 2 + 0.15, -d / 2 - 0.1, d / 2 + 0.35, 2.55, 2.0, q(lod, 4, 2), q(lod, 2, 1))
    return m.translate(x, 0, z), aw.translate(x, 0, z)


def bozor(lod=0):
    """Базар 14×10: ряд лавок (глиняная аркада с нишами-дуконами и ставнями), перед ней три
    прилавка под полосатыми навесами (керамика, дыни, мешки со специями), ковры на жерди."""
    parts = []
    x0, x1, z0, z1, h = -6.8, 6.8, -4.8, -2.4, 3.2
    parts.append(PT.clay_block(x0, x1, z0, z1, h, region="clay", footing=0.3, over=(0.5, 0.1, 0.15, 0.15), lod=lod,
                               chimney=(5.6, -4.2)))
    for k in range(4):
        cx = x0 + (k + 0.5) * (x1 - x0) / 4
        # ниша лавки: тёмное нутро, деревянные ставни раскрыты
        nw, nh = 2.2, 2.3
        parts.append(G.shade(G.quad((cx - nw / 2, 0.35, z1 + 0.01), (cx + nw / 2, 0.35, z1 + 0.01),
                                    (cx + nw / 2, nh, z1 + 0.01), (cx - nw / 2, nh, z1 + 0.01), "panjara",
                                    uvs=((0.42, 0.58), (0.58, 0.58), (0.58, 0.42), (0.42, 0.42))), 0.35))
        parts.append(PT.frame_strips(nw, nh - 0.35, 0.12, 0.06).translate(cx, 0.35, z1))
        for sx in (-1, 1):
            sh = G.quad((0, 0.4, 0), (sx * 1.0, 0.4, 0.5), (sx * 1.0, nh - 0.1, 0.5), (0, nh - 0.1, 0),
                        "planks", uvs=((0, 1), (0.5, 1), (0.5, 0.2), (0, 0.2)), two_sided=True)
            parts.append(sh.translate(cx + sx * nw / 2, 0, z1 + 0.02))
        parts.append(G.box(nw, 0.5, 0.6, {"front": "planks", "top": "carpet", "left": "planks", "right": "planks"})
                     .translate(cx, 0.0, z1 + 0.3))
    # ковры на жерди у края
    parts.append(G.pole((-6.6, 0, 3.6), (-6.6, 2.3, 3.6), 0.05, sides=4, region="pole"))
    parts.append(G.pole((-3.6, 0, 3.6), (-3.6, 2.3, 3.6), 0.05, sides=4, region="pole"))
    parts.append(G.pole((-6.7, 2.2, 3.6), (-3.5, 2.2, 3.6), 0.04, sides=4, region="pole"))
    for k, x in enumerate((-6.2, -4.9)):
        c = G.quad((x - 0.6, 0.4, 3.62), (x + 0.6, 0.4, 3.62), (x + 0.6, 2.18, 3.62), (x - 0.6, 2.18, 3.62), "carpet",
                   uvs=((0, 1), (1, 1), (1, 0), (0, 0)) if k == 0 else ((1, 0), (0, 0), (0, 1), (1, 1)), two_sided=True)
        parts.append(G.shade(c, 0.9))
    aws = []
    for k, (x, goods) in enumerate(((-4.0, "pottery"), (0.3, "melons"), (4.6, "sacks"))):
        m, a = stall(x, 0.9, 3.4, 2.2, lod, seed=200 + k, goods=goods)
        parts.append(m)
        aws.append(a)
    m = Mesh.merge(parts)
    G.grime(m, 0.05, seed=31)
    ground = PT.ground_patch(-6.9, 6.9, -2.4, 4.9, "earth", shade_k=0.6)
    return Model().add("Bozor", m).add("Ground", ground).add("Awning", Mesh.merge(aws), "cloth")


def bozor_site(lod=0):
    walls = [R.Wall((-6.8, -2.4), (6.8, -2.4), 3.2, 0.5, "clay"), R.Wall((6.8, -4.8), (-6.8, -4.8), 3.2, 0.5, "clay"),
             R.Wall((-6.8, -4.8), (-6.8, -2.4), 3.2, 0.5, "clay"), R.Wall((6.8, -2.4), (6.8, -4.8), 3.2, 0.5, "clay")]
    m = R.site(walls, lod, seed=171, frac=0.4, stacks=[("logs", -3.0, 1.5, 0), ("bricks", 2.5, 1.0, 10)])
    poles = [G.pole((x, 0, 1.6), (x, 2.4, 1.6), 0.05, sides=4, region="pole") for x in (-5.7, -2.3, 1.2, 2.8)]
    return Model().add("Site", Mesh.merge([m] + poles))


def bozor_ruin(lod=0):
    walls = [R.Wall((-6.8, -2.4), (6.8, -2.4), 3.2, 0.5, "clay"), R.Wall((6.8, -4.8), (-6.8, -4.8), 3.2, 0.5, "clay"),
             R.Wall((-6.8, -4.8), (-6.8, -2.4), 3.2, 0.5, "clay"), R.Wall((6.8, -2.4), (6.8, -4.8), 3.2, 0.5, "clay")]
    m = R.ruin(walls, lod, seed=173, frac=(0.2, 0.55), roofs=[(-6.8, -4.8, 6.8, -2.4, 3.2)], beams=6)
    rs = np.random.default_rng(174)
    extra = []
    for k in range(6 if lod == 0 else 3):
        j = PT.jug(rs.uniform(-5, 5), rs.uniform(0, 3), 1.0, lod).rotate_z(90).translate(0, 0.15, 0)
        extra.append(G.shade(j, 0.6))
    return Model().add("Ruin", Mesh.merge([m] + extra))


# ================================================================ печь для кирпича

def xumdon(lod=0):
    """Печь для кирпича 8×8: круглое кирпичное основание и купол с дымовым отверстием,
    топка-арка с жаром спереди, штабеля сырца (сохнет) и обожжённого кирпича, дрова, яма с глиной."""
    parts = []
    seg = q(lod, 4, 3)
    R0 = 2.4
    base = [G.lathe_bands([(R0 + 0.1, 0.0), (R0 + 0.08, 0.6)], "plinth", 4, seg, v_span=(0, 0.8)),
            G.lathe_bands([(R0, 0.6), (R0 - 0.08, 1.9)], "brick", 4, seg, tile_h=1.6),
            G.dome([(R0 - 0.08, 0.0), (R0 - 0.1, 0.5), (R0 * 0.82, 1.35), (R0 * 0.5, 2.0), (0.62, 2.25), (0.55, 2.3)],
                   "brick", 4, seg).translate(0, 1.9, 0),
            G.lathe_bands([(0.55, 4.2), (0.62, 4.45), (0.4, 4.45)], "brick", 2, seg, v_span=(4.0, 4.5))]
    bm = Mesh.merge(base)
    G.wall_light(bm, 4.5, base=0.74, top=1.0)
    G.grime(bm, 0.12, seed=9)
    G.shade(bm, lambda P: 1.0 - 0.45 * np.clip((P[:, 1] - 3.6) / 0.9, 0, 1))   # копоть к устью
    parts.append(bm)
    top = G.disc_uv(0.4, 8, "embers", y=4.44)
    G.shade(top, 0.15)
    parts.append(top)
    # топка спереди: арка из кирпича, тёмная глубина
    mouth = arch_curve(0.55, 0.6, 1.2, 6)
    fr = FO.arch_ribbon(mouth, 0.18, R0 + 0.02, "brick", out=1, lod=lod)
    parts.append(fr)
    hole = G.face((0, 0, R0 + 0.01), (1, 0, 0), (0, 1, 0), -0.55, 0.55, "brick", (1.1, 1.2), 0.0, 1.2,
                  top=[(x, y) for x, y in mouth], off=(0.55, 0.0))
    parts.append(G.shade(hole, 0.25))
    # сырец сохнет рядами на земле, обожжённый — штабелями
    rs = np.random.default_rng(41)
    for r in range(3 if lod == 0 else 2):
        for k in range(5 if lod == 0 else 3):
            x = -3.4 + k * 0.62
            z = 2.6 + r * 0.55
            br = G.box(0.5, 0.12, 0.42, {"top": "pakhsa", "front": "pakhsa", "left": "pakhsa", "right": "pakhsa"})
            parts.append(br.rotate_y(rs.uniform(-6, 6)).translate(x, 0, z))
    parts.append(R.brick_stack(2.6, 2.8, 15, 1.1, 0.8, 0.8))
    parts.append(R.brick_stack(3.4, 1.6, -10, 1.0, 0.6, 0.7))
    parts.append(R.log_pile(-3.0, -2.6, 30, n=6, L=2.4, r=0.12, lod=lod, seed=43))
    # яма с глиной и вода в колоде
    pit = G.lump(1.0, 0.25, 0.8, q(lod, 8, 6), 3, "earth", seed=45, amount=0.1)
    G.shade(pit, 0.7)
    parts.append(pit.translate(2.8, 0, -2.6))
    tr, water = PT.trough(1.6, lod)
    parts.append(tr.rotate_y(90).translate(3.6, 0, -0.6))
    m = Mesh.merge(parts)
    ground = PT.ground_patch(-3.9, 3.9, -3.9, 3.9, "earth", shade_k=0.55)
    emb = G.face((0, 0, R0 + 0.03), (1, 0, 0), (0, 1, 0), -0.42, 0.42, "embers", (0.84, 0.6), 0.02, 0.62,
                 off=(0.42, -0.02))
    model = Model().add("Xumdon", m).add("Ground", ground).add("Embers", emb)
    model.add("Water", G.shade(water.rotate_y(90).translate(3.6, 0, -0.6), 0.85))
    return model


def xumdon_site(lod=0):
    m = R.site([], lod, seed=181, frac=0.4, round_walls=[(0, 0, 2.4, 4.5, "brick")],
               stacks=[("bricks", 2.8, 2.8, 15), ("logs", -3.0, -2.6, 30), ("ladder", 0.0, 3.0, 0)])
    return Model().add("Site", m)


def xumdon_ruin(lod=0):
    m = R.ruin([], lod, seed=183, frac=(0.2, 0.45), round_walls=[(0, 0, 2.4, 4.5, "brick")], beams=2)
    return Model().add("Ruin", m)


SCENES = {
    "bozor": {"node": "Bozor", "footprint": (14, 10),
              "markers": [("Door", (0.0, 0.0, 5.4)), ("WorkSpot_1", (-4.0, 0.0, 2.6)), ("WorkSpot_2", (0.3, 0.0, 2.6)),
                          ("WorkSpot_3", (4.6, 0.0, 2.6)), ("Smoke_1", (5.6, 3.9, -4.2), {"amount": 6}),
                          ("Fire_1", (-2.0, 1.0, -3.6)), ("Fire_2", (3.0, 0.8, 0.5), {"amount": 14})]},
    "xumdon": {"node": "Xumdon", "footprint": (8, 8),
               "markers": [("Door", (0.0, 0.0, 3.6)), ("WorkSpot_1", (-2.0, 0.0, 3.2)), ("WorkSpot_2", (2.6, 0.0, -1.6)),
                           ("Smoke_1", (0.0, 4.5, 0.0), {"amount": 18, "dark": True}),
                           ("Fire_1", (0.0, 1.5, 0.5))]},
}

JOBS = {
    "bozor": {"": bozor, "_site": bozor_site, "_ruin": bozor_ruin},
    "xumdon": {"": xumdon, "_site": xumdon_site, "_ruin": xumdon_ruin},
}
