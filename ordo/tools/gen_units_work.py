"""Работники с инструментами (ТЗ 3.1, 3.2, 11.4: «рубят, копают, строят, несут груз»).

    python3 tools/gen_units_work.py            # атлас деҳқона, kok_dehqon, kip_malchy с инструментами
    python3 tools/gen_units_work.py --no-tex   # без перерисовки атласа
(tools/gen_units.py зовёт этот генератор сам — общий запуск пересобирает и работников.)

Пишет:
    assets/textures/units/kokand_dehqon.png         атлас деҳқона (2048×1024, та же «рука» и разметка
                                                    вариантов, что у атласов сторон: шаг 512 px)
    assets/models/units/kok_dehqon(_lod1).glb       деҳқон: хлопковая рубаха (четыре варианта),
                                                    полосатые штаны, дўппи, бирюзовый кушак (цвет стороны)
    assets/models/units/kip_malchy(_lod1).glb       малчы (тело как у кыпчакской пехоты) + инструменты

Инструменты — отдельные части (UV2.x — номер кости), в позе покоя хват в правой кисти
(HAND_R), ось инструмента +Y, лезвие/боёк в +Z. Какая видна — решает шейдер толпы по
доп. значению WORK (crowd_human.gdshaderinc): невидимые сжимаются в точку.
    17 TOOL_AXE     топор (рубит, z = 0)
    18 TOOL_HOE     кетмень (копает, z = 0.25)
    19 TOOL_HAMMER  молот / деревянная колотушка (строит, z = 0.5)
    20 TOOL_LOAD    бревно на плече (несёт дерево, z = 0.875); мешок (z = 0.75) — прежняя часть ITEM
Номера 17–20 — в HUMAN_PARTS (gen_units_kit.py), константы H_TOOL_* — в crowd_skeletons.gdshaderinc.
"""
from __future__ import annotations

import os
import sys

sys.path.insert(0, os.path.dirname(__file__))

import numpy as np  # noqa: E402
from PIL import Image  # noqa: E402

import gen_units as U  # noqa: E402
import gen_units_tex as T  # noqa: E402
from gen_units_kit import (GLB_IMPORT, HP, HUMAN_PIV, PNG_IMPORT, ROOT, Atlas, Mesh, ellipsoid,  # noqa: E402
                           ensure_import, lathe, limb, seg, tag, two_sided, v3)
from glb import Material, write_glb  # noqa: E402
from paint import Canvas  # noqa: E402
from palette import KOKAND  # noqa: E402

OUT_MODELS = os.path.join(ROOT, "assets/models/units")
OUT_TEX = os.path.join(ROOT, "assets/textures/units")

TOOL = {"AXE": HP["TOOL_AXE"], "HOE": HP["TOOL_HOE"], "HAMMER": HP["TOOL_HAMMER"], "LOAD": HP["TOOL_LOAD"]}
LOAD_PT = (-0.2, 1.565, -0.06)    # точка бревна на правом плече (поза покоя) — H_LOAD_PT в шейдере


# ---------------------------------------------------------------- атлас деҳқона

def _dehqon_layout():
    L = {}
    for k in range(4):
        x = 512 * k
        L[f"hat{k}"] = (x, 0, 256, 256)
        L[f"face{k}"] = (x + 256, 0, 256, 256)
        L[f"torso{k}"] = (x, 256, 256, 256)
        L[f"skirt{k}"] = (x + 256, 256, 256, 256)
        L[f"sleeve{k}"] = (x, 512, 256, 128)
        L[f"trousers{k}"] = (x, 640, 256, 128)
        L[f"sash{k}"] = (x + 256, 512, 256, 128)
        L[f"shirt{k}"] = (x + 256, 640, 256, 128)
    L.update({"leather": (0, 768, 512, 256), "metal": (512, 768, 512, 128), "wood": (512, 896, 512, 128),
              "hand": (1024, 768, 128, 128), "flask": (1024, 896, 128, 128), "sack": (1152, 768, 256, 128),
              "log": (1408, 768, 256, 128), "cotton": (1664, 768, 256, 128), "fur": (1152, 896, 256, 128)})
    return L


DEHQON_ATLAS = Atlas("kokand_dehqon", 2048, 1024, _dehqon_layout())

TURQ = KOKAND["tile"]


def sack_cloth(seed=0):
    def p(c: Canvas, w, h):
        T.plain_weave(c, w, h, "#cbbd9c", "#efe4c8", "#8a7a5a", seed=seed)
        T.folds(c, w, h, "#8a7a5a", "#efe4c8", n=14)
        c.rect(w * 0.6, h * 0.2, w * 0.78, h * 0.55, "#b8a47c", 0.9)                               # заплата
        c.line([(w * 0.6, h * 0.2), (w * 0.78, h * 0.2), (w * 0.78, h * 0.55), (w * 0.6, h * 0.55), (w * 0.6, h * 0.2)],
               1.6, "#6a5a40", 0.8, wobble=0.4)
        T.trim(c, [(-4, h * 0.12), (w + 4, h * 0.12)], "#8a6a40", 6, "#4a3820", seed=seed)            # завязка
        T.vgrad(c, 1.1, 0.75)
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


def dehqon_robes():
    """Рубахи деҳқонов: некрашеный хлопок, синяя полоска, выцветшее индиго, короткий бурый чапан;
    штаны из алачи; цвет стороны (ТЗ 11.2) — дўппи, кушак, обшлага и кайма подола: бирюза и изумруд."""
    gold, turq, emer = KOKAND["gold"], TURQ, KOKAND["main"]
    return [
        dict(base="#e2d8c2", cloth=lambda c, w, h: T.plain_weave(c, w, h, "#e2d8c2", "#ffffff", "#a59a84", seed=501),
             cuff=turq, trim=turq, edge="#145f63", lining="#e9e0c8", band=turq,
             trousers=("#34345a", "#6a6a98", "#8e3a3a"), sash=(turq, "#7fe8c8", [(gold, 0.3, 0.05), (gold, 0.8, 0.05)])),
        dict(base="#d6d2c4", cloth=lambda c, w, h: T.stripes_alacha(c, w, h, "#ddd6c4", [("#4a5a8a", 0.2, 2.5),
                                                                                     ("#4a5a8a", 0.6, 2.5)], seed=502),
             cuff=emer, trim=emer, edge="#2a3050", lining="#e9e0c8", band=emer,
             trousers=("#3a2c22", "#6a5444", "#c49a4a"), sash=(emer, "#7fe8c8", [("#e9e0c8", 0.5, 0.08)])),
        dict(base="#5a6a8e", cloth=lambda c, w, h: T.plain_weave(c, w, h, "#5a6a8e", "#9aa8c8", "#3a4460", seed=503),
             cuff=turq, trim="#e2d8c2", edge="#2a3050", lining="#e2d8c2", band=turq,
             trousers=("#2a2a3e", "#565878", None), sash=(turq, "#7fe8c8", [("#145f63", 0.5, 0.12)])),
        dict(base="#7a5a3c", cloth=lambda c, w, h: T.stripes_alacha(c, w, h, "#7a5a3c", [("#a8844a", 0.15, 3),
                                                                                     ("#3a2a1e", 0.4, 2),
                                                                                     ("#a8844a", 0.7, 3)], seed=504),
             cuff=emer, trim=emer, edge="#17463a", lining="#e2d8c2", band=emer,
             trousers=("#34345a", "#6a6a98", "#d8d0c0"), sash=(turq, "#7fe8c8", [(gold, 0.5, 0.06)])),
    ]


def build_dehqon_atlas(path):
    A = DEHQON_ATLAS
    img = Image.new("RGB", (A.w, A.h), (40, 40, 40))
    # дўппи — цвет стороны (бирюза и изумруд с белым «қалампир»): работник Коканда узнаётся и сверху
    hats = [(KOKAND["main"], "#f2ece0", "#f2ece0"), (KOKAND["tile"], "#efe8d8", KOKAND["gold"]),
            ("#1f7a5c", "#ecd8a8", "#f2ece0"), (KOKAND["tile_deep"], "#ece6d6", KOKAND["tile"])]
    for i, (b, pt, e) in enumerate(hats):
        T.region(img, A, f"hat{i}", T.doppi_hat(b, pt, e, seed=900 + i), seed=900 + i)
    faces = [("#b07a58", "#1e1612", "short", 0.1), ("#a8724f", "#241a14", "moustache", 0.0),
             ("#b98466", "#2a2420", "full", 0.75), ("#9c6a4c", "#1a1210", "none", 0.0)]
    for i, (sk, hr, bd, age) in enumerate(faces):
        T.region(img, A, f"face{i}", T.face(sk, hr, bd, "round", age, seed=960 + i, stubble="#2a2420"), seed=960 + i)
    T.region(img, A, "hand", T.hands("#b07a58", seed=969), seed=969)
    T.paint_robes(img, A, dehqon_robes(), 500)
    T.region(img, A, "leather", T.leather_region("#3a281c", "#6e4428", "#d8ccb0", seed=911), seed=911)
    T.region(img, A, "metal", T.metal_region(912), seed=912)
    T.region(img, A, "wood", T.wood_region(913), seed=913)
    T.region(img, A, "sack", sack_cloth(925), seed=925)
    T.region(img, A, "log", log_bark(926), seed=926)
    T.region(img, A, "cotton", lambda c, w, h: T.plain_weave(c, w, h, "#e9e0c8", "#ffffff", "#a59a84", seed=927), seed=927)
    T.region(img, A, "flask", lambda c, w, h: T.plain_weave(c, w, h, "#b58a3c", "#f0c878", "#6e4a1e", seed=928), seed=928)
    T.region(img, A, "fur", T.fur("#5a3a22", "#a07a50", seed=929), seed=929)
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
    sk = ellipsoid(0.2, 0.13, 0.14, seg(5, d), 3).rotate_z(20).translate(-0.17, 1.58, -0.05)
    return [tag(sk, HP["ITEM"], A.rect("sack"))]


# ---------------------------------------------------------------- юниты

DEHQON = dict(U.ROBE, hat="doppi", hem=0.56, cuff_side=True, hem_side=True)


def tools_parts(A, d, wooden_hammer=False, log=True):
    out = axe(A, d) + hoe(A, d) + hammer(A, d, wooden=wooden_hammer)
    if log:
        out += load_log(A, d)
    return out


def build_dehqon(d):
    A = DEHQON_ATLAS
    parts = U.human_upper(A, DEHQON, d, HUMAN_PIV, HP) + U.human_legs(A, DEHQON, d)
    parts += sack_cotton(A, d)
    parts += tools_parts(A, d, wooden_hammer=False, log=True)
    return U.finish_human(parts, d), A


def build_malchy(d):
    """Малчы: тело кыпчакской пехоты (халат-вариант, калпак, кушак киноварью), посох трёхгранный,
    мешок на плече, топор, кетмень, колотушка."""
    A = U.KIPCHAK_ATLAS
    spec = dict(U.MALCHY, weapon=None)
    parts = U.build_infantry(A, spec, d, finish=False)
    parts += staff3(A, HP["WEAPON"], HUMAN_PIV["HAND_R"], d) + tools_parts(A, d, wooden_hammer=True, log=False)
    return U.finish_human(parts, d), A


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
