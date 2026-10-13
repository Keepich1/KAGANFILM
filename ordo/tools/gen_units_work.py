"""Работники с инструментами (ТЗ 3.1, 3.2, 11.4: «рубят, копают, строят, несут груз»).

    python3 tools/gen_units_work.py            # атлас деҳқона, kok_dehqon, kip_malchy с инструментами
    python3 tools/gen_units_work.py --no-tex   # без перерисовки атласа

Пишет:
    assets/textures/units/kokand_dehqon.png         атлас деҳқона (1024², та же «рука», что у юнитов)
    assets/models/units/kok_dehqon(_lod1).glb       деҳқон: белая хлопковая рубаха, полосатые штаны,
                                                    дўппи, бирюзовый кушак (цвет стороны)
    assets/models/units/kip_malchy(_lod1).glb       малчы как в gen_units.py + инструменты

Инструменты — отдельные части (UV2.x — номер кости), в позе покоя хват в правой кисти
(HAND_R), ось инструмента +Y, лезвие/боёк в +Z. Какая видна — решает шейдер толпы по
доп. значению WORK (crowd_human.gdshaderinc): невидимые сжимаются в точку.
    17 TOOL_AXE     топор (рубит, z = 0)
    18 TOOL_HOE     кетмень (копает, z = 0.25)
    19 TOOL_HAMMER  молот / деревянная колотушка (строит, z = 0.5)
    20 TOOL_LOAD    бревно на плече (несёт дерево, z = 0.875); мешок (z = 0.75) — прежняя часть ITEM
Номера частей 17–20 продолжают HUMAN_PARTS из gen_units_kit.py (просьба к «Юнитам»: добавить их
туда, тогда константы попадут в crowd_skeletons.gdshaderinc сами).
"""
from __future__ import annotations

import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))

import numpy as np  # noqa: E402
from PIL import Image  # noqa: E402

import gen_units as U  # noqa: E402
import gen_units_tex as T  # noqa: E402
from gen_units_kit import (GLB_IMPORT, HP, HUMAN_PIV, PNG_IMPORT, ROOT, Atlas, Mesh, bake_shade, ellipsoid,  # noqa: E402
                           ensure_import, lathe, limb, seg, tag, two_sided, v3)
from glb import Material, write_glb  # noqa: E402
from paint import Canvas  # noqa: E402
from palette import KOKAND, MATERIAL  # noqa: E402

OUT_MODELS = os.path.join(ROOT, "assets/models/units")
OUT_TEX = os.path.join(ROOT, "assets/textures/units")

TOOL = {"AXE": 17, "HOE": 18, "HAMMER": 19, "LOAD": 20}
LOAD_PT = (-0.2, 1.565, -0.06)    # точка бревна на правом плече (поза покоя) — H_LOAD_PT в шейдере

# ---------------------------------------------------------------- атлас деҳқона

DEHQON_ATLAS = Atlas("kokand_dehqon", 1024, 1024, {
    "hat0": (0, 0, 256, 128), "hat1": (256, 0, 256, 128), "hat2": (512, 0, 256, 128), "hat3": (768, 0, 256, 128),
    "skin": (0, 128, 512, 256), "leather": (512, 128, 512, 256),
    "metal": (0, 384, 512, 256), "wood": (512, 384, 512, 256),
    "torso": (0, 640, 256, 256), "skirt": (256, 640, 256, 256), "sleeve": (512, 640, 256, 256),
    "trousers": (768, 640, 256, 256),
    "sash": (0, 896, 256, 128), "sack": (256, 896, 256, 128), "log": (512, 896, 256, 128), "cotton": (768, 896, 256, 128),
})

SHIRT = "#e6dcc6"
SHIRT_DARK = "#a59a84"
TURQ = KOKAND["tile"]


def doppi(base, pattern, edge, seed=0):
    """Чустская дўппи: u — вокруг (четыре грани), v — сверху (макушка) вниз к околышу.
    Чёрный бархат, белые «қалампир» (стручки перца) на гранях, белая кайма по околышу."""
    def p(c: Canvas, w, h):
        c.underpaint([base, T._shade(base, 1.25), T._shade(base, 0.85)], cell=24, seed=seed)
        c.strokes(240, [T._shade(base, 1.4), T._shade(base, 0.7)], length=(8, 20), width=(3, 6), angle=90, angle_jitter=25,
                  alpha=(0.15, 0.35))
        rim = h * 0.8
        c.rect(0, rim, w, h, edge)
        T.trim(c, [(-4, rim + 2), (w + 4, rim + 2)], T._shade(edge, 0.6), 2.5, seed=seed)
        for k in range(8):                                        # строчка по околышу
            c.ellipse((k + 0.5) * w / 8, (rim + h) / 2, 3.5, 2.2, base, 0.85)
        for k in range(4):                                        # стручки перца на гранях
            cx = (k + 0.5) * w / 4
            pts = [(cx - 10, rim - 8), (cx - 12, rim - 34), (cx - 2, rim - 56), (cx + 9, rim - 70), (cx + 4, rim - 52),
                   (cx + 10, rim - 30), (cx + 4, rim - 8)]
            c.polygon(pts, pattern, 0.95, wobble=0.6, seed=seed + k)
            c.line([(cx - 4, rim - 14), (cx - 2, rim - 40), (cx + 4, rim - 58)], 2.4, base, 0.8, wobble=0.4, seed=seed + 9 + k)
            c.ellipse(cx, rim - 92, 6, 5, pattern, 0.9)           # арка-завиток к макушке
        for k in range(4):                                        # рёбра граней (углы шапки)
            x = k * w / 4
            c.line([(x, 0), (x, rim)], 2.6, T._shade(pattern, 0.9), 0.7, wobble=0.5, seed=seed + 20 + k)
        T.vgrad(c, 1.15, 0.8)
        c.grain(0.02)
    return p


def shirt_torso(main, dark, light, emb, seed=0):
    """Рубаха-куйлак: u — вокруг (0.5 — перёд), вверх — плечи; разрез ворота с вышивкой, пыль внизу."""
    def p(c: Canvas, w, h):
        T.plain_cloth(main, light, dark, seed=seed)(c, w, h)
        T.folds(c, w, h, T._shade(main, 0.7), T._mix(main, "#ffffff", 0.3), n=26, vertical=True)
        T.temperature(c, w, h)
        cx = w * 0.5
        c.line([(cx, -4), (cx, h * 0.34)], 4.0, T._shade(dark, 0.6), 0.9, wobble=0.5, seed=seed)    # разрез
        for s in (-1, 1):                                          # вышивка по разрезу
            T.trim(c, [(cx + s * 7, -4), (cx + s * 7, h * 0.34)], emb, 4.0, T._shade(emb, 0.5), seed=seed + s)
        T.trim(c, [(-4, 8), (w + 4, 8)], emb, 6.0, T._shade(emb, 0.5), seed=seed + 5)               # ворот
        c.strokes(140, ["#8a7458", "#9c8a6a"], length=(12, 30), width=(5, 10), angle=90, angle_jitter=30,
                  alpha=(0.06, 0.14), region=(0, h * 0.7, w, h))   # пыль и пот работы
        c.grain(0.025)
    return p


def shirt_skirt(main, dark, light, emb, seed=0):
    def p(c: Canvas, w, h):
        T.plain_cloth(main, light, dark, seed=seed)(c, w, h)
        T.folds(c, w, h, T._shade(main, 0.68), T._mix(main, "#ffffff", 0.3), n=30, vertical=True, flare=0.4)
        c.strokes(220, ["#8a7458", "#7a6448", "#9c8a6a"], length=(10, 28), width=(5, 11), angle=90, angle_jitter=35,
                  alpha=(0.08, 0.2), region=(0, h * 0.55, w, h))   # пыльный подол
        T.trim(c, [(-4, h - 10), (w + 4, h - 10)], emb, 5.0, T._shade(emb, 0.5), seed=seed + 3)
        c.grain(0.025)
    return p


def sack_cloth(seed=0):
    def p(c: Canvas, w, h):
        T.plain_cloth("#cbbd9c", "#efe4c8", "#8a7a5a", seed=seed)(c, w, h)
        c.rect(w * 0.6, h * 0.2, w * 0.78, h * 0.55, "#b8a47c", 0.9)                               # заплата
        c.line([(w * 0.6, h * 0.2), (w * 0.78, h * 0.2), (w * 0.78, h * 0.55), (w * 0.6, h * 0.55), (w * 0.6, h * 0.2)],
               1.6, "#6a5a40", 0.8, wobble=0.4)
        T.trim(c, [(-4, h * 0.12), (w + 4, h * 0.12)], "#8a6a40", 6, "#4a3820", seed=seed)            # завязка
        c.grain(0.03)
    return p


def log_bark(seed=0):
    """Бревно на плечо: u — вокруг, v — вдоль; кора, у концов светлый спил (верх/низ области)."""
    def p(c: Canvas, w, h):
        c.underpaint(["#4e3e30", "#5e4c3a", "#3e3226"], cell=24, seed=seed)
        c.strokes(400, ["#2e241a", "#7e6a50", "#45372a"], length=(30, 90), width=(1.5, 4), angle=0, angle_jitter=6,
                  alpha=(0.3, 0.7), bristles=1)
        for y0, y1 in ((0, 10), (h - 10, h)):
            c.rect(0, y0, w, y1, "#c09a6a")
        c.grain(0.03)
    return p


def build_dehqon_atlas(path):
    A = DEHQON_ATLAS
    img = Image.new("RGB", (A.w, A.h), (40, 40, 40))
    hats = [("#1c1a1c", "#f2ece0", "#f2ece0"), ("#1f3a2e", "#efe8d8", "#e8dcc0"), ("#3a1418", "#ecd8a8", "#d8b878"),
            ("#18161a", "#ece6d6", "#2aa39a")]
    for i, (b, pt, e) in enumerate(hats):
        T.region(img, A, f"hat{i}", doppi(b, pt, e, seed=900 + i), seed=900 + i)
    T.region(img, A, "skin", T.skin_region("#b07a58", MATERIAL["skin_dark"], "#1a120e", True, seed=910), seed=910)
    T.region(img, A, "leather", T.leather_region("#3a281c", "#6e4428", "#d8ccb0", seed=911), seed=911)
    T.region(img, A, "metal", T.metal_region(912), seed=912)
    T.region(img, A, "wood", T.wood_region(913), seed=913)
    T.region(img, A, "torso", shirt_torso(SHIRT, SHIRT_DARK, "#ffffff", TURQ, seed=920), seed=920)
    T.region(img, A, "skirt", shirt_skirt(SHIRT, SHIRT_DARK, "#ffffff", TURQ, seed=921), seed=921)
    T.region(img, A, "sleeve", T.plain_cloth(SHIRT, "#ffffff", SHIRT_DARK, seed=922, grad=(1.1, 0.8)), seed=922)
    # штаны из «алача»: тёмно-синие в тонкую красную и белую полоску
    T.region(img, A, "trousers", T.plain_cloth("#34345a", "#6a6a98", seed=923,
                                               stripes=[("#8e3a3a", 0.2, 3), ("#d8d0c0", 0.4, 2), ("#8e3a3a", 0.6, 3),
                                                        ("#d8d0c0", 0.8, 2)]), seed=923)
    # кушак: бирюза с золотой нитью (цвет стороны)
    T.region(img, A, "sash", T.plain_cloth(TURQ, "#7fe8c8", seed=924, vertical=False,
                                           stripes=[(KOKAND["gold"], 0.3, 4), (KOKAND["tile_deep"], 0.55, 6),
                                                    (KOKAND["gold"], 0.8, 4)]), seed=924)
    T.region(img, A, "sack", sack_cloth(925), seed=925)
    T.region(img, A, "log", log_bark(926), seed=926)
    T.region(img, A, "cotton", T.plain_cloth("#e9e0c8", "#ffffff", seed=927), seed=927)
    img.save(path, optimize=True)
    return img


# ---------------------------------------------------------------- инструменты

def _metal(A, kind):
    return U.S(A, "metal", U.METAL_SUB[kind])


def _wood(A, kind="shaft", frac=None):
    r = U.WOOD_SUB[kind]
    if frac:   # часть полосы без золотых накладок ложа
        r = (r[0], frac[0], r[2], frac[1])
    return U.S(A, "wood", r)


def axe(A, d, W=None):
    """Топор-балта: рукоять 0.74 м (хват правой кистью ниже середины), клин железа вперёд (+Z)."""
    W = v3(HUMAN_PIV["HAND_R"] if W is None else W)
    part = TOOL["AXE"]
    h = limb([W + (0, -0.13, 0), W + (0, 0.6, 0.0)], [0.017, 0.015], sides=3)
    out = [tag(h, part, _wood(A, "shaft"), flip=False)]
    # клин: плоская двусторонняя пластина в плоскости YZ (на юните 15 см — толщина не читается)
    q_ = [W + (0, 0.52, -0.02), W + (0, 0.62, -0.02), W + (0, 0.665, 0.13), W + (0, 0.47, 0.13)]
    pl = Mesh(q_, [(0, 1, 2), (0, 2, 3)], None, [(0, 0), (0, 1), (1, 1), (1, 0)])
    out.append(tag(two_sided(pl), part, _metal(A, "iron"), metal=0.7, flip=False))
    return out


def hoe(A, d, W=None):
    """Кетмень: рукоять 0.98 м, широкое лезвие у конца под углом к рукояти (вперёд и к хвату)."""
    W = v3(HUMAN_PIV["HAND_R"] if W is None else W)
    part = TOOL["HOE"]
    tip = W + (0, 0.86, 0)
    h = limb([W + (0, -0.12, 0), tip], [0.019, 0.017], sides=3)
    out = [tag(h, part, _wood(A, "shaft"), flip=False)]
    b = np.array([0.0, -0.38, 1.0])
    b /= np.linalg.norm(b)
    x = np.array([1.0, 0, 0])
    p0, p1 = tip - x * 0.08, tip + x * 0.08
    p2, p3 = tip + x * 0.115 + b * 0.25, tip - x * 0.115 + b * 0.25
    pl = Mesh([p0, p1, p2, p3], [(0, 1, 2), (0, 2, 3)], None, [(0, 0), (1, 0), (1, 1), (0, 1)])
    if pl.N[0][1] < 0:   # лицо — вверх-назад (к хвату), изнанка тоже видна
        pl.flip()
    out.append(tag(two_sided(pl), part, _metal(A, "steel"), metal=0.8, flip=False))
    return out


def hammer(A, d, W=None, wooden=False):
    """Молот (деҳқон: железный боёк) или деревянная колотушка (малчы — колья юрт и частокола).
    Боёк — трёхгранная призма поперёк рукояти, ударные грани ±Z."""
    W = v3(HUMAN_PIV["HAND_R"] if W is None else W)
    part = TOOL["HAMMER"]
    L = 0.4 if wooden else 0.36
    h = limb([W + (0, -0.08, 0), W + (0, L, 0)], [0.017, 0.015], sides=3)
    out = [tag(h, part, _wood(A, "shaft"), flip=False)]
    r, hl = (0.065, 0.12) if wooden else (0.036, 0.085)
    head = lathe([(r, -hl), (r, hl)], 3, start=0.0, cap_bottom=True, cap_top=True, normals="crease")
    head.rotate_x(90).translate(W[0], W[1] + L, W[2])
    rect = _wood(A, "walnut", (0.47, 0.66)) if wooden else _metal(A, "iron")
    out.append(tag(head, part, rect, metal=0.0 if wooden else 0.7, flip=False))
    return out


def load_log(A, d):
    """Бревно на правом плече: вдоль оси Z, впереди короче, сзади длиннее; кора и спилы."""
    part = TOOL["LOAD"]
    c = v3(LOAD_PT)
    m = lathe([(0.085, 0.0), (0.08, 1.5)], seg(5, d), cap_bottom=True, cap_top=True)
    m.rotate_x(90).translate(c[0], c[1], c[2] - 1.05)
    return [tag(m, part, DEHQON_ATLAS.rect("log"), flip=False)]


def staff3(A, part, W, d):
    """Посох малчы как в gen_units.staff, трёхгранный (бюджет: инструменты не выходят за 600)."""
    W = v3(W)
    path = [W + (0, -0.82, 0), W + (0, 0.7, 0), W + (0, 0.88, 0.07), W + (0, 0.84, 0.17)]
    if d < 0.8:
        path = [path[0], path[1], path[3]]
    st = limb(path, [0.019, 0.017, 0.016, 0.015][:len(path)], sides=3)
    return [tag(st, part, U.S(A, "wood", U.WOOD_SUB["shaft"]), flip=False)]


def sack_cotton(A, d):
    sk = ellipsoid(0.2, 0.13, 0.14, seg(6, d), 3).rotate_z(20).translate(-0.17, 1.58, -0.05)
    return [tag(sk, HP["ITEM"], A.rect("sack"))]


def doppi_mesh(A, part, c, d):
    """Дўппи: невысокая четырёхгранная шапочка со скруглёнными углами по макушке."""
    cx, cy, cz = c
    n = 8
    prof = [(0.108, 0.03), (0.112, 0.085), (0.075, 0.135), (0.0, 0.15)] if d > 0.8 else \
        [(0.108, 0.03), (0.105, 0.09), (0.0, 0.15)]
    m = lathe(prof, n, start=22.5)
    th = np.arctan2(m.P[:, 0], m.P[:, 2])
    sq = 1.0 / np.maximum(np.abs(np.cos(th)), np.abs(np.sin(th))) ** 0.55   # квадрат со скруглением
    m.P[:, 0] *= sq * 0.94
    m.P[:, 2] *= sq * 1.04
    m.translate(cx, cy, cz - 0.004)
    m.smooth()
    return tag(m, part, A.rect("hat0"), coat=0.5)


# ---------------------------------------------------------------- юниты

DEHQON = dict(torso="torso", skirt="skirt", sleeve="sleeve", trousers="trousers", hat="doppi", sash="sash",
              side_sash=1.0, side_torso=0.0, side_skirt=0.0, side_sleeve=0.0, hem=0.56, hat_variant=True)


def tools_parts(A, d, wooden_hammer=False, log=True):
    out = axe(A, d) + hoe(A, d) + hammer(A, d, wooden=wooden_hammer)
    if log:
        out += load_log(A, d)
    return out


def build_dehqon(d):
    A = DEHQON_ATLAS
    parts = U.human_upper(A, DEHQON, d, HUMAN_PIV, HP) + U.human_legs(A, DEHQON, d)
    hc = (0.0, 1.638, 0.012)
    parts.append(doppi_mesh(A, HP["HEAD"], hc, d))
    if d < 0.8:   # кушак и вдали: цвет стороны узнаётся с RTS-камеры (ТЗ 11.2)
        sash = lathe([(0.168, 0.955), (0.172, 1.05)], 6)
        parts.append(tag(sash, HP["PELVIS"], A.rect("sash"), side=1.0, flip=False))
    parts += sack_cotton(A, d)
    parts += tools_parts(A, d, wooden_hammer=False, log=True)
    m = Mesh.merge(parts)
    bake_shade(m, 0.0, 1.75, low=0.62, down=0.82)
    return m, A


def build_malchy(d):
    """Малчы как в gen_units.py (MALCHY), посох трёхгранный, плюс топор, кетмень, колотушка."""
    A = U.KIPCHAK_ATLAS
    spec = dict(U.MALCHY, weapon=None)
    m0 = U.build_infantry(A, spec, d)          # тело, мешок (bake_shade уже нанесён)
    extra = staff3(A, HP["WEAPON"], HUMAN_PIV["HAND_R"], d) + tools_parts(A, d, wooden_hammer=True, log=False)
    ex = Mesh.merge(extra)
    bake_shade(ex, 0.0, 1.75, low=0.62, down=0.82)
    return Mesh.merge([m0, ex]), A


def write_unit(name, builder):
    for lod, d in ((0, 1.0), (1, U.LOD_DETAIL)):
        m, A = builder(d)
        nm = name + ("_lod1" if lod else "")
        p = os.path.join(OUT_MODELS, nm + ".glb")
        write_glb(p, [(nm, m, Material(A.name, texture_uri=A.uri, roughness=0.85))])
        ensure_import(p, GLB_IMPORT)
        lo, hi = m.bounds()
        print(f"{nm:22s} {m.tris:5d} треуг. высота {hi[1]:.2f} м  ширина {hi[0] - lo[0]:.2f}  длина {hi[2] - lo[2]:.2f}")


def main(argv):
    os.makedirs(OUT_MODELS, exist_ok=True)
    if "--no-tex" not in argv:
        p = os.path.join(OUT_TEX, "kokand_dehqon.png")
        build_dehqon_atlas(p)
        ensure_import(p, PNG_IMPORT)
        print("атлас", os.path.relpath(p, ROOT))
    write_unit("kok_dehqon", build_dehqon)
    write_unit("kip_malchy", build_malchy)


if __name__ == "__main__":
    main(sys.argv[1:])
