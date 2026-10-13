"""Поле (дала) и арыки Коканда: поле 16×16 в трёх стадиях урожая, арык (прямой участок,
поворот) и запруда-тугон. С облегчёнными версиями, стройкой и руинами.

Поле: глиняные валики по краю, арык вдоль северного края (−Z) с водой и деревянным
затвором, борозды вдоль Z (вода идёт по бороздам от арыка). Поверхность поля — рисунок
сверху (furrows / canopy_green / canopy_gold, шаг борозд 0,5 м), над ней ряды карточек
колосьев (узел «Crop», вырез по альфе; в сцене — cloth.gdshader: стебли качаются,
UV2.x — доля высоты стебля, UV2.y — фаза волны ветра по полю).
  dala_s0 — вспахано и полито (борозды, без всходов),
  dala_s1 — зелёные всходы (короткие карточки),
  dala_s2 — спелая пшеница (высокие золотые колосья).
"""
from __future__ import annotations

import math

import numpy as np

import gen_kokand_kit as G
import gen_kokand_parts as PT
import gen_kokand_ruins as R
import meshkit as K
from gen_kokand_atlas import FURROW_ROWS, TILE
from gen_kokand_models import Model
from meshkit import Mesh

q = PT.q
HALF = 8.0
DITCH = (-8.0, -6.85)          # арык вдоль −Z: z от, до
FIELD = (-7.45, 7.45, -6.2, 7.45)   # поверхность поля x0, x1, z0, z1
ROW = TILE["furrows"][0] / FURROW_ROWS     # 0,5 м


def berm(a, b, w=0.5, h=0.22, region="earth", lod=0) -> Mesh:
    """Валик (глиняный бортик) вдоль отрезка a→b в плане: два ската и гребень."""
    a, b = np.asarray(a, float), np.asarray(b, float)
    d = b - a
    L = float(np.linalg.norm(d))
    d /= L
    n = np.array([d[1], -d[0]])
    parts = []
    tw = TILE.get(region, (4.0, 4.0))[0]
    k = max(1, int(math.ceil(L / tw)))
    for i in range(k):
        s0, s1 = L * i / k, L * (i + 1) / k
        p0, p1 = a + d * s0, a + d * s1
        u1 = (s1 - s0) / tw
        for sg in (1, -1):
            e0 = p0 + n * sg * w / 2
            e1 = p1 + n * sg * w / 2
            quad = G.quad((e0[0], 0.0, e0[1]), (e1[0], 0.0, e1[1]), (p1[0], h, p1[1]), (p0[0], h, p0[1]), region,
                          uvs=((0, 1), (u1, 1), (u1, 0.85), (0, 0.85)))
            out = np.array([n[0] * sg, 0.5, n[1] * sg])
            if np.dot(quad.N[0], out) < 0:
                quad.flip()
            parts.append(quad)
    m = Mesh.merge(parts)
    m.N = np.where(m.N[:, 1:2] < 0, -m.N, m.N)
    return G.shade(m, 0.85)


def ditch(x0, x1, z0, z1, lod=0, water=True):
    """Арык вдоль X: два валика по краям и вода между ними. Возвращает (берега, вода)."""
    banks = Mesh.merge([berm((x0, z0 + 0.2), (x1, z0 + 0.2), 0.45, 0.26, lod=lod),
                        berm((x1, z1 - 0.2), (x0, z1 - 0.2), 0.45, 0.26, lod=lod)])
    # дно у воды темнее (влажная глина) — полоса под водой
    bed = G.face((0, 0.015, 0), (1, 0, 0), (0, 0, -1), x0, x1, "earth", None, -(z1 - 0.38), -(z0 + 0.38))
    G.shade(bed, 0.45)
    banks = Mesh.merge([banks, bed])
    w = None
    if water:
        w = G.face((0, 0.07, 0), (0, 0, 1), (1, 0, 0), z0 + 0.32, z1 - 0.32, "water", (z1 - z0 - 0.64, 4.0), x0, x1,
                   off=(-(z0 + 0.32), 0.0))
        G.shade(w, 0.9)
    return banks, w


def sluice(x, z, lod=0, open_=0.5):
    """Деревянный затвор (тугон в малом): два столба, перекладина, поднятый щит из досок."""
    parts = []
    for sx in (-1, 1):
        parts.append(G.pole((x + sx * 0.35, 0, z), (x + sx * 0.35, 0.9, z), 0.06, sides=4, region="bark"))
    parts.append(G.pole((x - 0.5, 0.85, z), (x + 0.5, 0.85, z), 0.05, sides=4, region="bark"))
    y0 = 0.05 + open_ * 0.35
    parts.append(G.quad((x - 0.32, y0, z + 0.02), (x + 0.32, y0, z + 0.02), (x + 0.32, y0 + 0.45, z + 0.02),
                        (x - 0.32, y0 + 0.45, z + 0.02), "planks", uvs=((0, 1), (0.6, 1), (0.6, 0.6), (0, 0.6)),
                        two_sided=True))
    return G.ground_ao(Mesh.merge(parts), 0.3, 0.3)


def field_base(lod=0, surface="furrows", shade_k=0.7, dark=1.0):
    """Основа поля: поверхность, валики по краю, арык с водой и затвором."""
    x0, x1, z0, z1 = FIELD
    surf = G.face((0, 0.03, 0), (1, 0, 0), (0, 0, -1), x0, x1, surface, None, -z1, -z0)
    G.shade(surf, shade_k * dark)
    borders = Mesh.merge([berm((-7.75, 7.75), (7.75, 7.75), lod=lod), berm((7.75, 7.75), (7.75, -6.45), lod=lod),
                          berm((-7.75, -6.45), (-7.75, 7.75), lod=lod),
                          berm((-7.75, -6.5), (-0.6, -6.5), lod=lod), berm((0.6, -6.5), (7.75, -6.5), lod=lod)])
    banks, water = ditch(-HALF, HALF, DITCH[0], DITCH[1], lod)
    sl = sluice(0.0, -6.55, lod)
    base = Mesh.merge([borders, banks, sl])
    if dark != 1.0:
        G.shade(base, dark)
    return surf, base, water


def crop_cards(lod=0, kind="wheat_gold", height=1.0, seed=0, every=1, clump=1.6, lean=16.0):
    """Ряды карточек над поверхностью: по центру каждого гребня (шаг 0,5 м), кусты по clump м
    вдоль ряда, в каждом кусте две карточки, наклонённые в стороны (видны и сверху)."""
    rs = np.random.default_rng(abs(int(seed)))
    x0, x1, z0, z1 = FIELD
    P, UV, UV2, F, N = [], [], [], [], []
    k0 = math.ceil((x0 + 0.25) / ROW)
    k1 = math.floor((x1 - 0.3) / ROW)
    from gen_kokand_atlas import uv as auv
    u0, v0, u1, v1 = auv(kind, inset=1.0)
    for k in range(k0, k1 + 1):
        if (k - k0) % every:
            continue
        xr = k * ROW + ROW * 0.575
        if xr > x1 - 0.2:
            continue
        n = max(1, int((z1 - z0 - 0.3) / clump))
        zs = np.linspace(z0 + 0.15, z1 - 0.15, n + 1)
        for i in range(n):
            za, zb = zs[i], zs[i + 1]
            hh = height * rs.uniform(0.85, 1.12)
            for sg in (-1, 1):
                a = math.radians(lean * sg + rs.normal(0, 4))
                dx, dy = math.sin(a) * hh, math.cos(a) * hh
                xb = xr + rs.normal(0, 0.03)
                base = len(P)
                P += [(xb, 0.03, za), (xb, 0.03, zb), (xb + dx, 0.03 + dy, zb), (xb + dx, 0.03 + dy, za)]
                flip = rs.random() < 0.5
                ua, ub = (u1, u0) if flip else (u0, u1)
                UV += [(ua, v1), (ub, v1), (ub, v0), (ua, v0)]
                ph = xr * 0.35 + (za + zb) * 0.5 * 0.21
                UV2 += [(0.0, ph), (0.0, ph), (1.0, ph), (1.0, ph)]
                F += [(base, base + 1, base + 2), (base, base + 2, base + 3)]
    m = Mesh(P, F, None, UV)
    # нормали: поперёк карточки (по ним качает ветер) и чуть вверх — свет мягче, как у куста
    m.recalc_normals()
    m.N = m.N + np.array([0.0, 0.45, 0.0])
    m.N /= np.linalg.norm(m.N, axis=1, keepdims=True)
    m.UV2 = np.array(UV2, float)
    m.has_uv2 = True
    return m


def dala_stage(stage):
    def fn(lod=0):
        surface = ("furrows", "canopy_green", "canopy_gold")[stage]
        surf, base, water = field_base(lod, surface, shade_k=(0.62, 0.68, 0.72)[stage])
        model = Model().add("Dala", base)
        model.add("Ground", surf)
        if water is not None:
            model.add("Water", water)
        if stage == 1:
            model.add("Crop", G.white(crop_cards(lod, "wheat_green", 0.5, seed=11, every=q(lod, 1, 2), clump=q(lod, 1.6, 2.2),
                                                 lean=20)), "cutout")
        elif stage == 2:
            model.add("Crop", G.white(crop_cards(lod, "wheat_gold", 1.0, seed=12, every=q(lod, 1, 2), clump=q(lod, 1.6, 2.2),
                                                 lean=14)), "cutout")
        return model
    return fn


def dala_site(lod=0):
    """Разметка поля: колышки с бечёвкой по углам, готов один валик и часть арыка (без воды),
    вспахана половина, деревянная соха-омач и кетмень, мешок семян."""
    parts = []
    x0, x1, z0, z1 = FIELD
    surf = G.face((0, 0.03, 0), (1, 0, 0), (0, 0, -1), x0, 0.0, "furrows", None, -z1, -z0)
    G.shade(surf, 0.6)
    parts.append(berm((-7.75, 7.75), (7.75, 7.75), lod=lod))
    parts.append(berm((-7.75, -6.45), (-7.75, 7.75), lod=lod))
    banks, _ = ditch(-HALF, -1.0, DITCH[0], DITCH[1], lod, water=False)
    parts.append(banks)
    corners = [(-7.8, -6.4), (7.8, -6.4), (7.8, 7.8), (-7.8, 7.8)]
    for x, z in corners:
        parts.append(G.pole((x, 0, z), (x, 0.9, z), 0.04, sides=4, region="pole"))
    for i in range(4):
        a, b = corners[i], corners[(i + 1) % 4]
        parts.append(G.path_tube([(a[0], 0.8, a[1]), (b[0], 0.75, b[1])], 0.01, 3, "rope", tile_len=16.0))
    # соха-омач: грядиль, рукоять, лемех
    if lod == 0:
        parts.append(G.pole((2.0, 0.1, 1.0), (4.4, 0.55, 1.4), 0.05, sides=4, region="wood"))
        parts.append(G.pole((2.1, 0.1, 1.0), (1.6, 1.0, 0.9), 0.04, sides=4, region="wood"))
        parts.append(G.pole((2.0, 0.08, 1.0), (2.4, 0.02, 1.05), 0.05, 0.01, sides=4, region="iron"))
        parts.append(G.pole((3.2, 0.0, 2.6), (3.6, 1.1, 2.2), 0.03, sides=4, region="wood"))
    parts.append(R.sack_pile(4.5, 3.5, 20, n=2, seed=71, lod=lod))
    m = Mesh.merge(parts)
    return Model().add("Site", m).add("Ground", surf)


def dala_ruin(lod=0):
    """Вытоптанное и выжженное поле: тёмная стерня пятнами, разрушенный валик, сухой арык."""
    surf, base, _ = field_base(lod, "canopy_gold", shade_k=0.72, dark=1.0)
    rs = np.random.default_rng(81)
    # выжженные пятна: поверхность темнее к пятнам
    spots = rs.uniform(-6, 6, (5, 2))

    def burn(P):
        d = np.min(np.hypot(P[:, 0:1] - spots[:, 0], P[:, 2:3] - spots[:, 1]), axis=1)
        return 0.28 + 0.4 * np.clip(d / 6.0, 0, 1)
    G.shade(surf, burn)
    stub = crop_cards(lod, "wheat_gold", 0.35, seed=82, every=q(lod, 2, 4), clump=1.6, lean=35)
    G.shade(stub, 0.35)
    banks, _ = ditch(-HALF, HALF, DITCH[0], DITCH[1], lod, water=False)
    m = Mesh.merge([base, banks])
    G.shade(m, 0.8)
    return Model().add("Ruin", m).add("Ground", surf).add("Crop", stub, "cutout")


# ================================================================ арыки (бонус)

def aryk(lod=0):
    """Прямой участок арыка 4 м вдоль X (шире 1,6 м): валики, влажное дно, вода."""
    banks, water = ditch(-2.0, 2.0, -0.8, 0.8, lod)
    return Model().add("Aryk", banks).add("Water", water)


def aryk_turn(lod=0):
    """Поворот арыка на 90° в клетке 4×4: вход с −X (по оси z = 0), выход на −Z (по оси x = 0)."""
    c = np.array([-2.0, -2.0])
    seg = q(lod, 8, 4)
    parts = []
    for r, sg in ((2.0 - 0.6, 1), (2.0 + 0.6, -1)):
        pts = [c + r * np.array([math.sin(a), math.cos(a)]) for a in np.linspace(0, math.pi / 2, seg + 1)]
        for i in range(seg):
            a, b = pts[i], pts[i + 1]
            parts.append(berm(tuple(a), tuple(b), 0.45, 0.26, lod=lod))
    # вода: кольцевой сектор
    P, UV, F = [], [], []
    for i in range(seg + 1):
        a = math.pi / 2 * i / seg
        for j, r in enumerate((2.0 - 0.32, 2.0 + 0.32)):
            P.append((c[0] + r * math.sin(a), 0.07, c[1] + r * math.cos(a)))
            UV.append((j, i / seg))
    for i in range(seg):
        k = i * 2
        F += [(k, k + 1, k + 3), (k, k + 3, k + 2)]
    w = Mesh(P, F, np.tile([0, 1, 0], (len(P), 1)), UV)
    if np.cross(w.P[w.F[0, 1]] - w.P[w.F[0, 0]], w.P[w.F[0, 2]] - w.P[w.F[0, 0]])[1] < 0:
        w.F = w.F[:, ::-1].copy()
    G.to_region(w, "water")
    bed = Mesh(np.array(P) - [0, 0.055, 0], w.F, np.tile([0, 1, 0], (len(P), 1)), w.UV.copy())
    bed = G.shade(bed, 0.4)
    return Model().add("Aryk", Mesh.merge(parts + [bed])).add("Water", G.shade(w, 0.9))


def tugon(lod=0):
    """Запруда-тугон: арык, перегороженный валом из камня и земли с деревянным затвором
    посередине; за затвором вода выше (подпор). Её можно разрушить (tugon_ruin)."""
    banks, water = ditch(-2.0, 2.0, -0.8, 0.8, lod)
    parts = [banks]
    # вал поперёк арыка с проходом под затвор
    for z0, z1 in ((-1.3, -0.35), (0.35, 1.3)):
        parts.append(R.stone_pile(0.0, (z0 + z1) / 2, 0.55, n=4, seed=int(z0 * 10) + 91, lod=lod))
    parts.append(G.lump(0.9, 0.45, 1.4, q(lod, 8, 6), 3, "earth", seed=93, amount=0.15).translate(-0.6, 0, 0))
    # затвор: рама и щит
    for z in (-0.38, 0.38):
        parts.append(G.box(0.18, 1.3, 0.18, {"front": "walnut", "back": "walnut", "left": "walnut", "right": "walnut",
                                             "top": "walnut"}).translate(0.25, 0, z))
    parts.append(G.beam((0.25, 1.25, -0.6), (0.25, 1.25, 0.6), 0.16, 0.14, "walnut"))
    gate = G.quad((0.27, 0.12, 0.33), (0.27, 0.12, -0.33), (0.27, 0.75, -0.33), (0.27, 0.75, 0.33), "planks",
                  uvs=((0, 1), (0.6, 1), (0.6, 0.6), (0, 0.6)), two_sided=True)
    parts.append(gate)
    parts.append(G.path_tube([(0.27, 0.75, 0.0), (0.27, 1.25, 0.0)], 0.015, 3, "rope"))
    m = G.ground_ao(Mesh.merge(parts), 0.3, 0.3)
    # вода выше затвора
    up = G.face((0, 0.16, 0), (0, 0, 1), (1, 0, 0), -0.48, 0.48, "water", (0.96, 4.0), -2.0, 0.2, off=(0.48, 2.0))
    G.shade(up, 0.95)
    return Model().add("Tugon", m).add("Water", Mesh.merge([water, up]))


def aryk_site(lod=0):
    banks, _ = ditch(-2.0, 0.6, -0.8, 0.8, lod, water=False)
    sp = G.pole((1.2, 0.0, 0.3), (1.0, 1.1, 0.7), 0.03, sides=4, region="wood")
    pile = G.lump(0.7, 0.3, 0.5, 6, 3, "earth", seed=5).translate(1.4, 0, -0.6)
    return Model().add("Site", Mesh.merge([banks, sp, pile]))


def aryk_ruin(lod=0):
    banks, _ = ditch(-2.0, 2.0, -0.8, 0.8, lod, water=False)
    G.shade(banks, 0.7)
    pile = G.lump(1.0, 0.35, 0.8, 7, 3, "earth", seed=9, amount=0.3).translate(0.3, 0, 0.1)
    return Model().add("Ruin", Mesh.merge([banks, pile]))


def tugon_site(lod=0):
    m = aryk_site(lod).nodes[0][1]
    st = R.stone_pile(0.0, -1.0, 0.5, n=4, seed=97, lod=lod)
    posts = [G.pole((0.25, 0, z), (0.25, 1.2, z), 0.08, sides=4, region="walnut") for z in (-0.38, 0.38)]
    return Model().add("Site", Mesh.merge([m, st] + posts))


def tugon_ruin(lod=0):
    """Разрушенная запруда: вал размыт, затвор сорван и лежит, вода ушла."""
    banks, _ = ditch(-2.0, 2.0, -0.8, 0.8, lod, water=False)
    parts = [banks, R.stone_pile(0.5, -1.0, 0.5, n=3, seed=99, lod=lod), R.stone_pile(-0.6, 1.0, 0.4, n=3, seed=98, lod=lod)]
    gate = G.quad((0.0, 0.05, 0.4), (0.7, 0.08, 0.1), (0.9, 0.12, 0.65), (0.2, 0.06, 0.9), "planks", two_sided=True)
    parts.append(G.shade(gate, 0.6))
    parts.append(G.pole((0.25, 0, -0.38), (0.25, 0.7, -0.38), 0.08, sides=4, region="walnut"))
    parts.append(R.burnt_beam((-0.8, 0.1, -0.2), (0.6, 0.2, 0.6), 0.07, lod))
    return Model().add("Ruin", G.ground_ao(Mesh.merge(parts), 0.3, 0.3))


SCENES = {
    "dala": {"node": "Dala", "props": {"ground_decal": False}, "footprint": (16, 16), "model": "dala_s2",
             "markers": [("WorkSpot_1", (-4.0, 0.0, -2.0)), ("WorkSpot_2", (4.0, 0.0, -2.0)), ("WorkSpot_3", (-4.0, 0.0, 4.0)),
                         ("WorkSpot_4", (4.0, 0.0, 4.0)), ("Door", (0.0, 0.0, 8.6)), ("Water_In", (0.0, 0.0, -7.4)),
                         ("Fire_1", (-3.0, 0.3, 1.0), {"amount": 16}), ("Fire_2", (3.5, 0.3, -2.5), {"amount": 14})]},
    "aryk": {"node": "Aryk", "props": {"ground_decal": False}, "footprint": (4, 1.6), "markers": []},
    "aryk_turn": {"node": "ArykTurn", "props": {"ground_decal": False}, "footprint": (4, 4), "markers": []},
    "tugon": {"node": "Tugon", "props": {"ground_decal": False}, "footprint": (4, 2.6), "markers": [("WorkSpot_1", (0.9, 0.0, 1.2))]},
}

JOBS = {
    "dala": {"_s0": dala_stage(0), "_s1": dala_stage(1), "_s2": dala_stage(2), "_site": dala_site, "_ruin": dala_ruin},
    "aryk": {"": aryk, "_site": aryk_site, "_ruin": aryk_ruin},
    "aryk_turn": {"": aryk_turn, "_site": aryk_site, "_ruin": aryk_ruin},
    "tugon": {"": tugon, "_site": tugon_site, "_ruin": tugon_ruin},
}
