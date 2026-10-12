"""Модели юнитов для толпы (ТЗ 11.3–11.6): жёсткие части + рисованные атласы.

    python3 tools/gen_units.py            # все юниты, атласы, константы скелетов
    python3 tools/gen_units.py --no-tex   # без перерисовки атласов (быстрее)

Пишет:
    assets/models/units/<id>.glb и <id>_lod1.glb       (ссылка на общий атлас стороны)
    assets/textures/units/{kokand_units,kipchak_units,animals}.png
    shaders/include/crowd_skeletons.gdshaderinc        (точки вращения частей)

Каждая часть — одна кость (UV2.x), см. gen_units_kit.py. Модель смотрит в +Z,
ноги на y = 0 (ТЗ 11.6). Силуэт чуть утрирован: широкие плечи, высокие шапки,
крупное оружие, знамёна (ТЗ 11.1).
"""
from __future__ import annotations

import os
import sys

sys.path.insert(0, os.path.dirname(__file__))

from gen_units_kit import (GLB_IMPORT, HORSE_PIV, HP, HUMAN_PIV, PNG_IMPORT, ROOT, RP, SHEEP_PIV, SP, Mesh, bake_shade,  # noqa: E402
                           ellipsoid, ensure_import, lathe, limb, loft, ring, ring_axis, seg, tag, two_sided, v3,
                           write_skeleton_include, np, math, grid)
from gen_units_tex import (ANIMALS_ATLAS, HORSE_SUB, KIPCHAK_ATLAS, KOKAND_ATLAS, LEATHER_SUB, METAL_SUB, SHEEP_SUB,  # noqa: E402
                           SKIN_SUB, WOOD_SUB, build_animals, build_kipchak, build_kokand)
from glb import Material, write_glb  # noqa: E402
from meshkit import disc, ring_z  # noqa: E402

OUT_MODELS = os.path.join(ROOT, "assets/models/units")
OUT_TEX = os.path.join(ROOT, "assets/textures/units")


def S(A, name, frac):
    """Прямоугольник части области (frac — доли)."""
    return A.sub(name, *frac)


# =====================================================================
# Человек: тело (пехота и всадник — одна верхняя половина)
# =====================================================================

def _head(A, part, c, d, hat):
    """Голова-яйцо: лицо на u = 0.5 (start=180), низ — подбородок."""
    rx, ry, rz = 0.098, 0.122, 0.11
    lo = d < 0.8
    t = np.linspace(-math.pi / 2, math.radians(48 if hat else 90), (3 if lo else 4) + 1)
    prof = np.column_stack([np.cos(t), np.sin(t)])
    prof[np.abs(prof[:, 0]) < 1e-6, 0] = 0
    h = lathe(prof, 6, start=180.0)
    h.transform(np.diag([rx, ry, rz])).translate(*c)
    # подбородок и борода вперёд, скулы шире — не «яйцо»
    low = h.P[:, 1] < c[1] - 0.03
    h.P[low, 2] += 0.016
    front = (h.P[:, 2] > c[2] + 0.05) & (np.abs(h.P[:, 1] - c[1] + 0.01) < 0.05)
    h.P[front, 2] += 0.012  # нос и надбровья
    tag(h, part, S(A, "skin", SKIN_SUB["head"]))
    # нос: маленькая трёхгранная пирамидка — профиль лица читается
    nose = lathe([(0.019, 0.0), (0.0, 0.034)], 3, start=60.0, normals="crease")
    nose.rotate_x(100).translate(c[0], c[1] - 0.004, c[2] + rz - 0.012)
    tag(nose, part, S(A, "skin", (0.22, 0.4, 0.28, 0.6)))
    return Mesh.merge([h, nose])


def _hat(A, part, c, d, kind, variant=True):
    """Шапки: высокие силуэты (ТЗ 11.1). c — центр головы."""
    cx, cy, cz = c
    out = []
    coat = 0.5 if variant else 0.0  # 0.5 — группа вариантов «шапка» (масть — 1.0)
    lo = d < 0.8
    n = 6 if lo else 7
    if kind == "turban":
        prof = [(0.104, 0.025), (0.145, 0.09), (0.132, 0.2), (0.078, 0.255)]
        if lo:
            prof = [prof[0], prof[1], prof[3]]
        t = lathe(prof, n).translate(cx, cy, cz - 0.005)
        # витки чалмы чуть наискось: спереди ниже, сзади выше
        t.P[:, 1] += 0.025 * (cz - t.P[:, 2]) / 0.15
        out.append(tag(t, part, S(A, "hat0", (0, 0.34, 1, 1)), coat=coat))
        kp = [(0.082, 0.24), (0.0, 0.5)] if lo else [(0.082, 0.24), (0.058, 0.38), (0.0, 0.5)]
        k = lathe(kp, n).translate(cx, cy, cz - 0.015)
        out.append(tag(k, part, S(A, "hat0", (0, 0, 1, 0.34)), coat=coat, side=1.0))  # кулах — цвет стороны
    elif kind == "kalpak":
        bp = [(0.102, 0.025), (0.132, 0.05), (0.127, 0.088)]
        brim = lathe([bp[0], bp[2]] if lo else bp, n).translate(cx, cy, cz)
        # раздвоенный отворот: спереди чуть выше
        brim.P[:, 1] += 0.012 * np.clip(brim.P[:, 2] - cz, 0, None) / 0.13
        out.append(tag(brim, part, S(A, "hat0", (0, 0.8, 1, 1)), coat=coat))
        cp = [(0.108, 0.07), (0.1, 0.2), (0.062, 0.34), (0.0, 0.43)]
        crown = lathe([cp[0], cp[2], cp[3]] if lo else cp, n).translate(cx, cy, cz - 0.004)
        crown.P[:, 2] -= 0.05 * np.clip(crown.P[:, 1] - cy - 0.2, 0, None)  # макушка чуть назад
        out.append(tag(crown, part, S(A, "hat0", (0, 0, 1, 0.8)), coat=coat))
    elif kind in ("helmet", "helmet_plume"):
        sub = "gold" if kind == "helmet_plume" else "steel"
        hp = [(0.106, 0.02), (0.113, 0.1), (0.084, 0.235), (0.03, 0.32), (0.0, 0.43)]
        hm = lathe([hp[0], hp[2], hp[4]] if lo else hp, n).translate(cx, cy, cz)
        out.append(tag(hm, part, S(A, "metal", METAL_SUB[sub]), metal=1.0))
        # бармица (кольчужная сетка) вокруг шеи сзади и с боков
        av = lathe([(0.114, 0.06), (0.14, -0.16)], 4 if lo else 7, sweep=250, start=55).translate(cx, cy, cz)
        out.append(tag(av, part, S(A, "metal", METAL_SUB["iron"]), metal=0.6))
        if kind == "helmet_plume":
            path = [(cx, cy + 0.40, cz), (cx, cy + 0.52, cz - 0.03), (cx, cy + 0.66, cz - 0.10), (cx, cy + 0.74, cz - 0.20)]
            pl = limb([path[0], path[2], path[3]], [0.018, 0.055, 0.012], sides=3)
            out.append(tag(pl, part, A.rect("plume"), side=0.0, flip=False,
                           weight=lambda m: (m.P[:, 1] - (cy + 0.4)) / 0.34))
    return out


def human_upper(A, spec, d, P, ids):
    """Торс, голова, руки, пояс. P — точки вращения (человек или всадник), ids — номера частей."""
    out = []
    pel, ch = v3(P["PELVIS"]), v3(P["CHEST"])
    dy = pel[1] - 0.98
    dz = pel[2]
    reg_t, reg_sl = spec["torso"], spec["sleeve"]
    side_t, side_sl = spec.get("side_torso", 1.0), spec.get("side_sleeve", 1.0)
    lo = d < 0.8
    k = 7 if lo else 8
    # торс: от пояса до шеи; грудь колесом, широкие покатые плечи (плечевые «шапки» — у рук)
    sec = [(0.985, 0.152, 0.116, 0.0), (1.22, 0.182, 0.138, 0.02), (1.39, 0.208, 0.128, 0.008),
           (1.47, 0.16, 0.098, -0.012), (1.52, 0.082, 0.078, 0.0), (1.57, 0.068, 0.07, 0.01)]
    if lo:
        sec = [sec[0], sec[2], sec[3], sec[5]]
    # кольцо чуть уже спереди-сзади у боков: плоская грудь и спина, круглые бока
    sq = lambda a: 1.0 + 0.06 * math.cos(2.0 * a)  # noqa: E731
    rings = [ring((0, y + dy, z + dz), rx, rz, k, phase=180.0, squash=sq) for y, rx, rz, z in sec]
    torso = loft(rings)
    if spec.get("bulk", 1.0) != 1.0:
        b = spec["bulk"]
        torso.P[:, 0] *= b
        torso.P[:, 2] = (torso.P[:, 2] - dz) * b + dz
    out.append(tag(torso, ids["CHEST"], A.rect(reg_t), side=side_t))
    # голова и шапка
    hc = (0.0, 1.638 + dy, 0.012 + dz)
    out.append(_head(A, ids["HEAD"], hc, d, spec["hat"]))
    for m in _hat(A, ids["HEAD"], hc, d, spec["hat"], spec.get("hat_variant", True)):
        out.append(m)
    # пояс-кушак: закрывает шов торса и подола
    if spec.get("sash") and not lo:
        sash = lathe([(0.17, 0.955 + dy), (0.172, 1.05 + dy)], seg(8, d)).translate(0, 0, dz)
        sash.transform(np.diag([spec.get("bulk", 1.0), 1, spec.get("bulk", 1.0) * 0.9]))
        sash.P[:, 2] += dz * (1 - spec.get("bulk", 1.0) * 0.9)
        out.append(tag(sash, ids["PELVIS"], A.rect(spec["sash"]), side=spec.get("side_sash", 0.0), flip=False))
        if d > 0.8 and dy < 0.1 and not spec.get("lean"):  # свисающие концы кушака (у пехоты)
            for sx in (0.09,):
                g = two_sided(grid(0.05, 0.2, 1, 2).translate(-0.025, -0.2, 0))
                g.translate(sx, 0.985 + dy, 0.118 + dz)
                out.append(tag(g, ids["PELVIS"], A.rect(spec["sash"]), side=spec.get("side_sash", 0.0),
                               weight=lambda m, y0=0.985 + dy: (y0 - m.P[:, 1]) / 0.2))
    # руки: рукав кафтана широкий, к запястью раструб
    for s, ua, fa in ((1, "UARM_L", "FARM_L"), (-1, "UARM_R", "FARM_R")):
        side = "L" if s > 0 else "R"
        sh, el, hd = v3(P["SHOULDER_" + side]), v3(P["ELBOW_" + side]), v3(P["HAND_" + side])
        rs = 5 if (lo or spec.get("rider")) else 6
        if lo:
            up = limb([sh + (0.01 * s, 0.0, 0), el], [0.078, 0.064], sides=4)
        else:
            up = limb([sh + (0.01 * s, 0.0, 0), sh + (0.016 * s, -0.12, -0.005), el], [0.078, 0.075, 0.066], sides=rs)
        out.append(tag(up, ids[ua], S(A, reg_sl, (0, 0, 1, 0.5)), side=side_sl, flip=False))
        # плечевая «шапка»: круглое плечо вместо торца трубы
        dl = lathe([(0.0, 0.07), (0.07, 0.035), (0.084, -0.02)], 4 if lo else 5)
        dl.transform(np.diag([1.0, 1.0, 0.95])).translate(sh[0] + 0.012 * s, sh[1] - 0.005, sh[2])
        out.append(tag(dl, ids[ua], S(A, reg_sl, (0, 0, 1, 0.12)), side=side_sl))
        dirv = (hd - el) / np.linalg.norm(hd - el)
        cuff = hd - dirv * 0.04
        fo = limb([el, cuff], [0.066, 0.084], sides=4) if lo else \
            limb([el, (el + cuff) / 2, cuff], [0.064, 0.068, 0.086], sides=rs)
        out.append(tag(fo, ids[fa], S(A, reg_sl, (0, 0.5, 1, 1)), side=side_sl, flip=False))
        hand = ellipsoid(0.04, 0.056, 0.048, 3 if lo else 4, 2).translate(*(hd - dirv * 0.0))
        out.append(tag(hand, ids[fa], S(A, "skin", SKIN_SUB["hand"])))
    # меховой ворот и плащ (полководец)
    if spec.get("fur_collar"):
        pts = [(0.16 * math.sin(a), 1.47 + dy, 0.12 * math.cos(a) + dz - 0.01)
               for a in np.linspace(0, 2 * math.pi, 5)]
        fc = limb(pts, 0.05, sides=3 if lo else 4)
        out.append(tag(fc, ids["CHEST"], A.rect("fur"), flip=False))
    if spec.get("cloak"):
        cpf = [(0.2, 0.0), (0.3, -0.36), (0.40, -0.72)] if not lo else [(0.2, 0.0), (0.40, -0.72)]
        cl = lathe(cpf, 4 if lo else 5, sweep=200, start=80)
        cl.translate(0, 1.45 + dy, dz - 0.02)
        cl.P[:, 2] -= 0.12 * np.clip(-(cl.P[:, 1] - 1.45 - dy), 0, None)  # отлетает назад
        cl = two_sided(cl)
        out.append(tag(cl, ids["CHEST"], A.rect(spec["cloak"]), side=1.0, flip=False,
                       weight=lambda m: (1.45 + dy - m.P[:, 1]) / 0.72))
    return out


def human_legs(A, spec, d):
    """Ноги пехотинца: штаны под подолом, высокие сапоги с загнутым носком."""
    out = []
    lo = d < 0.8
    for s, th, sh in ((1, "THIGH_L", "SHIN_L"), (-1, "THIGH_R", "SHIN_R")):
        side = "L" if s > 0 else "R"
        hip, kn, an = v3(HUMAN_PIV["HIP_" + side]), v3(HUMAN_PIV["KNEE_" + side]), v3(HUMAN_PIV["ANKLE_" + side])
        # широкие шаровары, заправленные в сапоги
        t = limb([hip + (0.006 * s, 0.05, 0), (hip + kn) / 2 + (0.012 * s, 0, 0.012), kn + (0, 0.03, 0)],
                 [0.086, 0.088, 0.068], sides=4 if lo else 5) if not lo else \
            limb([hip + (0, 0.05, 0), kn + (0, 0.03, 0)], [0.088, 0.068], sides=4)
        out.append(tag(t, HP[th], A.rect(spec["trousers"]), flip=False))
        # сапог: икра, узкая щиколотка, раструб голенища
        if lo:
            b = limb([kn + (0, 0.02, 0.005), an + (0, 0.01, 0)], [0.066, 0.048], sides=4)
        else:
            b = limb([kn + (0, 0.02, 0.008), kn * 0.55 + an * 0.45 + (0, 0, -0.008), an + (0, 0.012, 0)],
                     [0.068, 0.06, 0.046], sides=5)
        out.append(tag(b, HP[sh], S(A, "leather", LEATHER_SUB["boot"]), flip=False))
        f = ellipsoid(0.048, 0.052, 0.125, 4, 1 if lo else 2, y_from=-0.35).translate(an[0], 0.045, an[2] + 0.045)
        toe = f.P[:, 2] > an[2] + 0.1
        f.P[toe, 1] += (f.P[toe, 2] - an[2] - 0.1) * 0.8  # загнутый носок
        f.P[:, 1] = np.maximum(f.P[:, 1], 0.0)
        out.append(tag(f, HP[sh], S(A, "leather", LEATHER_SUB["boot"])))
    # подол кафтана: две половины, каждая следует за своим бедром (передний и задний разрез);
    # левая пола запахнута поверх правой (чуть шире и заходит за середину)
    hem = spec.get("hem", 0.4)
    prof = [(0.16, 1.03), (0.19, 0.9), (0.245, 0.66), (0.305, hem)]
    if lo:
        prof = [prof[0], prof[2], prof[3]]
    for s, name, start, sweep, grow in ((1, "SKIRT_L", -10.0, 200.0, 1.018), (-1, "SKIRT_R", 180.0, 180.0, 1.0)):
        sk = lathe(prof, 3 if lo else (4 if spec.get("lean") else 5), sweep=sweep, start=start)
        sk.P[:, 0] *= grow
        sk.P[:, 2] = sk.P[:, 2] * 0.88 * grow + 0.014
        b = spec.get("bulk", 1.0)
        sk.P[:, 0] *= b
        if s < 0:  # u = 0 у переднего края у обеих половин
            sk.UV[:, 0] = 1.0 - sk.UV[:, 0]
        out.append(tag(sk, HP[name], A.rect(spec["skirt"]), side=spec.get("side_skirt", 1.0), flip=False,
                       weight=lambda m: (1.03 - m.P[:, 1]) / (1.03 - hem)))
    return out


# =====================================================================
# Оружие и предметы (в позе покоя: хват в правой кисти, ось оружия +Y)
# =====================================================================

def _w0(P, rider=False):
    return v3(P["HAND_R"])


def musket(A, part, W, d, back=False):
    """Мылтык (фитильное ружьё) ~1.5 м: ось +Y от запястья ложа к дулу; +Z — низ приклада при прицеливании."""
    out = []
    W = v3(W)
    bar = limb([W + (0, 0.1, -0.004), W + (0, 1.14, -0.004)], [0.017, 0.0135], sides=3 if d < 0.8 else (4 if back else 5))
    out.append(tag(bar, part, S(A, "metal", METAL_SUB["iron"]), metal=0.7, flip=False))
    k = 4
    secs = [(-0.34, 0.022, 0.062, 0.036), (-0.17, 0.02, 0.046, 0.024), (0.0, 0.016, 0.026, 0.008),
            (0.09, 0.02, 0.034, 0.012), (0.56, 0.016, 0.02, 0.002)]
    if d < 0.8:
        secs = [secs[0], secs[2], secs[4]]
    rings = [ring(W + (0, y, zo), rx, rz, k, phase=45.0 if k == 4 else 0.0) for y, rx, rz, zo in secs]
    st = loft(rings, cap_start=True)
    out.append(tag(st, part, S(A, "wood", WOOD_SUB["walnut"]), flip=False))
    if not back and d > 0.8:  # золотой замок и фитиль
        lk = ellipsoid(0.012, 0.035, 0.012, 4, 2).translate(W[0] + 0.02, W[1] + 0.08, W[2] + 0.01)
        out.append(tag(lk, part, S(A, "metal", METAL_SUB["gold"]), metal=1.0))
    return out


def blade(A, part, W, d, length=0.82, curve=0.07, guard=True):
    """Сабля/меч: клинок вдоль +Y, лезвие вперёд (+Z), изгиб назад."""
    W = v3(W)
    out = []
    n = 4 if d > 0.8 else 3
    ys = np.linspace(0.1, 0.1 + length, n + 1)
    rings = []
    for i, y in enumerate(ys):
        t = (y - 0.1) / length
        wdt = 0.02 * (1 - 0.65 * t ** 3) if i < n else 0.002
        rings.append(ring_axis(W + (0, y, -curve * t * t), (0, 1, 0), wdt, 0.0045, 4, ref=(0, 0, 1)))
    bl = loft(rings)
    out.append(tag(bl, part, S(A, "metal", METAL_SUB["steel"]), metal=1.0, flip=False))
    grip = limb([W + (0, -0.07, 0), W + (0, 0.1, 0)], [0.017, 0.015], sides=4)
    out.append(tag(grip, part, S(A, "leather", LEATHER_SUB["belt"]), flip=False))
    if guard:
        gd = limb([W + (0, 0.1, -0.06), W + (0, 0.1, 0.06)], 0.011, sides=4)
        out.append(tag(gd, part, S(A, "metal", METAL_SUB["gold"]), metal=1.0, flip=False))
    return out


def mace(A, part, W, d):
    W = v3(W)
    sh = limb([W + (0, -0.1, 0), W + (0, 0.5, 0)], [0.018, 0.016], sides=4)
    hd = lathe([(0.0, 0.48), (0.05, 0.5), (0.068, 0.57), (0.05, 0.64), (0.0, 0.67)], seg(6, d), normals="crease")
    hd.translate(*W)
    return [tag(sh, part, S(A, "wood", WOOD_SUB["shaft"]), flip=False),
            tag(hd, part, S(A, "metal", METAL_SUB["gold"]), metal=1.0)]


def staff(A, part, W, d):
    W = v3(W)
    path = [W + (0, -0.82, 0), W + (0, 0.7, 0), W + (0, 0.86, 0.04), W + (0, 0.9, 0.12), W + (0, 0.84, 0.17)]
    st = limb(path, [0.019, 0.017, 0.017, 0.016, 0.015], sides=4)
    return [tag(st, part, S(A, "wood", WOOD_SUB["shaft"]), flip=False)]


def lance(A, part, cloth_part, W, d):
    """Найза ~3.7 м с маленьким вымпелом (ткань — отдельная часть, развевается)."""
    W = v3(W)
    out = []
    sh = limb([W + (0, -1.3, 0), W + (0, 2.3, 0)], [0.022, 0.017], sides=4)
    out.append(tag(sh, part, S(A, "wood", WOOD_SUB["shaft"]), flip=False))
    hd = lathe([(0.02, 2.29), (0.034, 2.36), (0.0, 2.6)], 4, normals="crease").translate(W[0], W[1], W[2])
    out.append(tag(hd, part, S(A, "metal", METAL_SUB["steel"]), metal=1.0))
    # вымпел: треугольный, назад от древка
    g = grid(0.5, 0.2, 2 if d < 0.8 else 4, 1)
    g.P[:, 1] = 0.1 + (g.P[:, 1] - 0.1) * (1 - 0.8 * g.P[:, 0] / 0.5)
    g.rotate_y(90).translate(W[0], W[1] + 2.06, W[2])  # полотно вдоль −Z
    g = two_sided(g)
    out.append(tag(g, cloth_part, A.rect("pennon"), side=1.0, weight=lambda m: (W[2] - m.P[:, 2]) / 0.5))
    return out


def banner_pole(A, part, cloth_part, W, d, kind):
    """Знамя: древко в правой кисти, полотно назад (−Z), развевается в шейдере."""
    W = v3(W)
    out = []
    if kind == "kokand":
        lo, hi, cw, chh, ctop = -0.85, 2.45, 1.05, 0.82, 2.3
    else:
        lo, hi, cw, chh, ctop = -1.25, 2.85, 0.95, 0.72, 2.55
    pole = limb([W + (0, lo, 0), W + (0, hi, 0)], [0.022, 0.018], sides=seg(5, d))
    out.append(tag(pole, part, S(A, "wood", WOOD_SUB["shaft"]), flip=False))
    if kind == "kokand":  # золотой шар и навершие-полумесяц
        fin = lathe([(0.0, hi), (0.045, hi + 0.04), (0.045, hi + 0.08), (0.0, hi + 0.12), (0.012, hi + 0.13),
                     (0.0, hi + 0.3)], 4 if d < 0.8 else 5, normals="crease").translate(W[0], W[1], W[2])
        out.append(tag(fin, part, S(A, "metal", METAL_SUB["gold"]), metal=1.0))
    else:  # туг: конский хвост под навершием-трезубцем
        tug = lathe([(0.0, hi - 0.02), (0.1, hi - 0.16), (0.12, hi - 0.34), (0.06, hi - 0.46), (0.0, hi - 0.5)],
                    seg(6, d)).translate(W[0], W[1], W[2])
        out.append(tag(tug, part, A.rect("tug"), weight=lambda m: (W[1] + hi - m.P[:, 1]) / 0.5 * 0.6))
        for zx in (-0.07, 0.0, 0.07):
            pr = limb([W + (0, hi, 0) + (0, 0, zx * 0.3), W + (0, hi + 0.22 - abs(zx) * 0.8, zx)], [0.012, 0.002], sides=3)
            out.append(tag(pr, part, S(A, "metal", METAL_SUB["steel"]), metal=1.0, flip=False))
    g = grid(cw, chh, 3 if d < 0.8 else 4, 1 if d < 0.8 else 2)
    g.rotate_y(90).translate(W[0], W[1] + ctop - chh, W[2] - 0.02)  # x полотна → −Z
    g = two_sided(g)
    out.append(tag(g, cloth_part, A.rect("banner"), side=1.0, weight=lambda m: (W[2] - 0.02 - m.P[:, 2]) / cw))
    return out


def shield(A, part, center, d, r=0.27):
    """Круглый калкан на левом предплечье, лицом вперёд (+Z)."""
    c = v3(center)
    dome = lathe([(0.0, 0.07), (r, 0.0)] if d < 0.8 else [(0.0, 0.07), (r * 0.55, 0.055), (r, 0.0)], 6 if d < 0.8 else 8)
    dome.rotate_x(90).translate(*c)
    dome.UV = np.column_stack([0.5 - (dome.P[:, 0] - c[0]) / (2 * r), 0.5 - (dome.P[:, 1] - c[1]) / (2 * r)])
    back = disc(r, 6 if d < 0.8 else 8).rotate_x(-90).translate(*c)
    back.UV = np.column_stack([0.5 + (back.P[:, 0] - c[0]) / (2 * r), 0.5 - (back.P[:, 1] - c[1]) / (2 * r)])
    return [tag(dome, part, A.rect("shield"), side=0.6, flip=False),
            tag(back, part, S(A, "leather", LEATHER_SUB["belt"]), flip=False)]


def ramrod(A, part, W):
    W = v3(W)
    rr = limb([W + (0, -0.05, 0.0), W + (0, 0.85, 0.0)], 0.0065, sides=3)
    return [tag(rr, part, S(A, "metal", METAL_SUB["iron"]), metal=0.6, flip=False)]


def sack(A, part, d):
    sk = ellipsoid(0.2, 0.13, 0.14, seg(6, d), 3).rotate_z(20).translate(-0.17, 1.58, -0.05)
    return [tag(sk, part, S(A, "leather", LEATHER_SUB["felt"]))]


def flask(A, part, d):
    f = ellipsoid(0.05, 0.072, 0.028, seg(5, d), 3).rotate_z(-15).translate(-0.178, 0.895, 0.07)
    return [tag(f, part, A.rect("flask"), metal=0.6)]


# =====================================================================
# Пехотинец
# =====================================================================

def build_infantry(A, spec, d):
    parts = human_upper(A, spec, d, HUMAN_PIV, HP) + human_legs(A, spec, d)
    W = HUMAN_PIV["HAND_R"]
    wpn = spec.get("weapon")
    if wpn == "musket":
        parts += musket(A, HP["WEAPON"], W, d)
    elif wpn in ("sword", "saber"):
        parts += blade(A, HP["WEAPON"], W, d, curve=0.05 if wpn == "sword" else 0.09)
    elif wpn == "staff":
        parts += staff(A, HP["WEAPON"], W, d)
    elif wpn == "banner_kokand":
        parts += banner_pole(A, HP["WEAPON"], HP["CLOTH"], W, d, "kokand")
    item = spec.get("item")
    if item == "shield":
        parts += shield(A, HP["ITEM"], (0.262, 0.99, 0.085), d)
    elif item == "ramrod":
        parts += ramrod(A, HP["ITEM"], W)
    elif item == "sack":
        parts += sack(A, HP["ITEM"], d)
    if spec.get("flask") and d > 0.8:
        parts += flask(A, HP["PELVIS"], d)
    if spec.get("back") == "musket":
        # ружьё за спиной: наискось от правого бедра к левому плечу
        bm = Mesh.merge(musket(A, HP["CHEST"], (0, 0, 0), 0.4, back=True))
        bm.rotate_z(-32).translate(0.0, 1.12, -0.17)
        parts.append(bm)
    m = Mesh.merge(parts)
    bake_shade(m, 0.0, 1.75, low=0.62, down=0.82)
    return m


# =====================================================================
# Конь (+ всадник)
# =====================================================================

_lg = HORSE_SUB["legs"]
HORSE_SUB_X = dict(HORSE_SUB, legs_up=(_lg[0], _lg[1], _lg[2], (_lg[1] + _lg[3]) / 2),
                   legs_lo=(_lg[0], (_lg[1] + _lg[3]) / 2, _lg[2], _lg[3]))


def horse_body(A, d, coat_cell="coat0", coat_mask=1.0, mane=True):
    out = []
    H = HORSE_PIV
    hs = lambda nm: S(A, coat_cell, HORSE_SUB_X[nm])  # noqa: E731
    lo = d < 0.8
    k = 6 if lo else 8
    # профиль корпуса: круп, провис спины, холка выше, грудь вперёд; сечение уже к хребту
    sec = [(-0.99, 1.30, 0.09, 0.12), (-0.9, 1.275, 0.205, 0.26), (-0.7, 1.24, 0.27, 0.33), (-0.45, 1.205, 0.288, 0.345),
           (-0.15, 1.16, 0.3, 0.338), (0.15, 1.16, 0.302, 0.35), (0.42, 1.215, 0.27, 0.37), (0.62, 1.2, 0.215, 0.33),
           (0.76, 1.13, 0.13, 0.22)]
    if lo:
        sec = [sec[0], sec[2], sec[4], sec[6], sec[7], sec[8]]
    spine = lambda a: 1.0 - 0.1 * max(math.cos(a), 0.0) ** 3 + 0.04 * max(-math.cos(a), 0.0)  # noqa: E731
    # корпус короче (длина ≈ высоте в холке), передняя часть остаётся на месте
    rings = [ring_z((0, y, 0.62 + (z - 0.62) * 0.9), rx, ry, k, squash=spine) for z, y, rx, ry in sec]
    body = loft(rings, cap_start=True, cap_end=True)
    out.append(tag(body, RP["BODY"], hs("body"), coat=coat_mask))
    # шея с гребнем гривы
    ax = v3((0, 1.84, 0.92)) - v3((0, 1.33, 0.56))
    # сечение шеи: гребень (a=0) чуть выше, горло (a=π) округлое, бока полнее — не «доска»
    crest = lambda a: (1.0 + 0.16 * max(math.cos(a), 0.0) ** 4) * (1.0 + 0.1 * math.sin(a) ** 2)  # noqa: E731
    ns = [((0, 1.27, 0.53), 0.255, 0.165), ((0, 1.47, 0.69), 0.215, 0.145), ((0, 1.65, 0.81), 0.17, 0.12),
          ((0, 1.8, 0.9), 0.13, 0.1)]
    neck = loft([ring_axis(c, ax, rc, rs, 5 if lo else 8, squash=crest) for c, rc, rs in ([ns[0], ns[3]] if lo else ns)])
    # вес изгиба: 0 у основания (сидит в корпусе) → 1 у затылка; шея гнётся, а не поворачивается целиком
    axn = ax / np.linalg.norm(ax)
    out.append(tag(neck, RP["NECK"], hs("neck"), coat=coat_mask, flip=False,
                   weight=lambda m: (m.P - v3((0, 1.3, 0.56))) @ axn / 0.5))
    # голова: от затылка к морде
    hax = v3((0, 1.43, 1.36)) - v3((0, 1.86, 0.96))
    # голова: затылок, щёки (ганаши — шире, к челюсти), прямая переносица, морда с ноздрями
    hsec = [((0, 1.885, 0.955), 0.095, 0.078), ((0, 1.735, 1.025), 0.14, 0.1), ((0, 1.585, 1.2), 0.085, 0.07),
            ((0, 1.45, 1.335), 0.08, 0.072)]
    if d < 0.8:
        hsec = [hsec[0], hsec[1], hsec[3]]
    head = loft([ring_axis(c, hax, rc, rs, 5 if lo else 7) for c, rc, rs in hsec], cap_end=not lo)
    out.append(tag(head, RP["HEAD"], hs("head"), coat=coat_mask, flip=False))
    for s in (() if lo else (1, -1)):
        ear = limb([(0.045 * s, 1.9, 0.94), (0.06 * s, 1.99, 0.96), (0.07 * s, 2.06, 0.98)], [0.03, 0.026, 0.003],
                   sides=3)
        out.append(tag(ear, RP["HEAD"], hs("hair"), coat=coat_mask, flip=False))
    # ноги
    sides = 5 if d > 0.8 else 4
    for s, sd in ((1, "L"), (-1, "R")):
        x = 0.15 * s
        fu = limb([(x, 1.06, 0.49), (x, 0.5, 0.55)] if lo else [(x, 1.06, 0.49), (x, 0.8, 0.52), (x, 0.5, 0.55)],
                  [0.11, 0.048] if lo else [0.125, 0.08, 0.048], sides=sides)
        out.append(tag(fu, RP["FU_" + sd], hs("legs_up"), coat=coat_mask, flip=False))
        if lo:
            fl = limb([(x, 0.53, 0.55), (x, 0.13, 0.566), (x, 0.075, 0.576)], [0.045, 0.04, 0.037], sides=sides)
        else:
            fl = limb([(x, 0.53, 0.55), (x, 0.2, 0.556), (x, 0.13, 0.566), (x, 0.075, 0.576)],
                      [0.045, 0.033, 0.041, 0.037], sides=sides)
        out.append(tag(fl, RP["FL_" + sd], hs("legs_lo"), coat=coat_mask, flip=False))
        hf = lathe([(0.052, 0.0), (0.04, 0.08)], sides, normals="crease").translate(x, 0, 0.58)
        out.append(tag(hf, RP["FL_" + sd], hs("hoof"), coat=coat_mask))
        x = 0.165 * s
        hu = limb([(x * 1.06, 1.1, -0.52), (x, 0.56, -0.7)] if lo else
                  [(x * 1.06, 1.1, -0.52), (x * 1.03, 0.84, -0.61), (x, 0.56, -0.7)],
                  [0.13, 0.052] if lo else [0.155, 0.095, 0.052], sides=sides)
        out.append(tag(hu, RP["HU_" + sd], hs("legs_up"), coat=coat_mask, flip=False))
        if lo:
            hl = limb([(x, 0.59, -0.705), (x, 0.13, -0.632), (x, 0.075, -0.622)], [0.05, 0.04, 0.037], sides=sides)
        else:
            hl = limb([(x, 0.59, -0.705), (x, 0.2, -0.64), (x, 0.13, -0.632), (x, 0.075, -0.622)],
                      [0.05, 0.033, 0.041, 0.037], sides=sides)
        out.append(tag(hl, RP["HL_" + sd], hs("legs_lo"), coat=coat_mask, flip=False))
        hf = lathe([(0.052, 0.0), (0.04, 0.08)], sides, normals="crease").translate(x, 0, -0.615)
        out.append(tag(hf, RP["HL_" + sd], hs("hoof"), coat=coat_mask))
    # хвост: вес по длине — для взмаха
    tp = [(0, 1.42, -0.85), (0, 1.31, -0.95), (0, 1.05, -1.01), (0, 0.72, -0.99)]
    tl = limb(tp if not lo else [tp[0], tp[2], tp[3]], [0.05, 0.088, 0.082, 0.035] if not lo else [0.055, 0.08, 0.035],
              sides=4 if lo else 5)
    out.append(tag(tl, RP["TAIL"], hs("hair"), coat=coat_mask, flip=False, weight=lambda m: (1.43 - m.P[:, 1]) / 0.71))
    return out


def caparison_mesh(A, region, d, z0=-0.8, z1=0.62, hem=0.8, side=1.0, top_off=0.035, sub=None):
    """Попона: открытые дуги через спину, бока висят отвесно до подола."""
    nz = 6 if d > 0.8 else 4
    zs = np.linspace(z0, z1, nz)
    kk = 7 if d > 0.8 else 3
    # профиль тела по z (как в horse_body)
    tbl = np.array([(-0.99, 1.31, 0.09, 0.12), (-0.9, 1.28, 0.2, 0.26), (-0.7, 1.245, 0.268, 0.335),
                    (-0.45, 1.205, 0.285, 0.35), (-0.15, 1.165, 0.298, 0.345), (0.15, 1.165, 0.3, 0.352),
                    (0.42, 1.21, 0.272, 0.36), (0.62, 1.22, 0.218, 0.325), (0.75, 1.17, 0.13, 0.22)])
    tbl[:, 0] = 0.62 + (tbl[:, 0] - 0.62) * 0.9  # как укороченный корпус в horse_body
    secs = []
    for z in zs:
        cy = np.interp(z, tbl[:, 0], tbl[:, 1])
        rx = np.interp(z, tbl[:, 0], tbl[:, 2]) + top_off
        ry = np.interp(z, tbl[:, 0], tbl[:, 3]) + top_off
        pts = []
        for t in np.linspace(-1, 1, kk):
            th = t * math.radians(96)
            x, y = -rx * math.sin(th), cy + ry * math.cos(th)
            pts.append((x, y, z))
        # отвесный подол
        hx = pts[0][0]
        pts = [(hx * 1.02, hem, z)] + pts + [(pts[-1][0] * 1.02, hem, z)]
        secs.append(np.array(pts))
    cp = loft(secs, closed_sections=False)
    rect = A.rect(region) if sub is None else S(A, region, sub)
    return tag(cp, RP["BODY"], rect, side=side, flip=True, weight=lambda m: np.clip((1.05 - m.P[:, 1]) / 0.25, 0, 1))


def saddle(A, d, region="saddle"):
    s = ellipsoid(0.19, 0.075, 0.27, 4 if d < 0.8 else 5, 2, y_from=-0.2).translate(0, 1.565, 0.03)
    po = limb([(0, 1.6, 0.24), (0, 1.69, 0.29)], [0.06, 0.03], sides=4)
    ca = limb([(0, 1.6, -0.2), (0, 1.69, -0.25)], [0.08, 0.05], sides=4)
    return [tag(s, RP["BODY"], A.rect(region)), tag(po, RP["BODY"], A.rect(region), flip=False),
            tag(ca, RP["BODY"], A.rect(region), flip=False)]


def rider_legs(A, spec, d):
    """Ноги всадника — часть тела коня (жёстко в стременах)."""
    out = []
    for s in (1, -1):
        hip = v3((0.115 * s, 1.63, 0.05))
        kn = v3((0.30 * s, 1.43, 0.3))
        an = v3((0.31 * s, 1.07, 0.2))
        t = limb([hip, kn], [0.082, 0.064], sides=seg(5, d) if d > 0.8 else 4)
        out.append(tag(t, RP["BODY"], A.rect(spec["trousers"]), flip=False))
        # сапог и ступня одной трубкой (носок в стремени вперёд)
        b = limb([kn + (0, 0.02, 0), an + (0, 0.02, 0), an + (0.01 * s, -0.03, 0.13)], [0.062, 0.05, 0.035],
                 sides=5 if d > 0.8 else 4)
        out.append(tag(b, RP["BODY"], S(A, "leather", LEATHER_SUB["boot"]), flip=False))
    # подол кафтана всадника: две полы по бокам седла, вперёд по бёдрам
    for s, start in ((1, 0.0), (-1, 180.0)):
        sp = [(0.16, 0.0), (0.21, -0.13), (0.3, -0.34)]
        sk = lathe(sp if d > 0.8 else [sp[0], sp[2]], 4 if d > 0.8 else 3, sweep=180.0, start=start)
        if s < 0:
            sk.UV[:, 0] = 1.0 - sk.UV[:, 0]
        sk.rotate_x(-38).translate(0, 1.67, 0.045)
        sk.P[:, 0] *= spec.get("bulk", 1.0)
        out.append(tag(sk, RP["R_PELVIS"], A.rect(spec["skirt"]), side=spec.get("side_skirt", 1.0), flip=False,
                       weight=lambda m: np.clip((1.67 - m.P[:, 1]) / 0.3, 0, 1)))
    return out


def build_rider(A, spec, d):
    parts = horse_body(A, d, spec.get("coat", "coat0"), spec.get("coat_mask", 1.0))
    if spec.get("caparison"):
        cz = spec["caparison"]
        parts.append(caparison_mesh(A, cz["region"], d, cz.get("z0", -0.8), cz.get("z1", 0.62), cz.get("hem", 0.8)))
    parts += saddle(A, d)
    ids = {"PELVIS": RP["R_PELVIS"], "CHEST": RP["R_TORSO"], "HEAD": RP["R_HEAD"], "UARM_L": RP["R_UARM_L"],
           "FARM_L": RP["R_FARM_L"], "UARM_R": RP["R_UARM_R"], "FARM_R": RP["R_FARM_R"]}
    P = {k[2:]: v for k, v in HORSE_PIV.items() if k.startswith("R_")}
    parts += human_upper(A, dict(spec, rider=True), d, P, ids)
    parts += rider_legs(A, spec, d)
    W = P["HAND_R"]
    wpn = spec.get("weapon")
    if wpn == "lance":
        parts += lance(A, RP["R_WEAPON"], RP["R_CLOTH"], W, d)
    elif wpn in ("saber", "sword"):
        parts += blade(A, RP["R_WEAPON"], W, d, curve=0.1)
    elif wpn == "mace":
        parts += mace(A, RP["R_WEAPON"], W, d)
    elif wpn == "banner_kipchak":
        parts += banner_pole(A, RP["R_WEAPON"], RP["R_CLOTH"], W, d, "kipchak")
    if spec.get("item") == "shield":
        el, hd = v3(P["ELBOW_L"]), v3(P["HAND_L"])
        parts += shield(A, RP["R_ITEM"], (el + hd) / 2 + (0.0, 0.0, 0.075), d, r=0.25)
    m = Mesh.merge(parts)
    bake_shade(m, 0.0, 2.3, low=0.6, down=0.8)
    return m


def build_horse(A, d, coat_cell="coat0"):
    parts = horse_body(A, d, coat_cell, 1.0)
    # недоуздок (ремни на голове) — тёмные полосы не нужны на дальнем зуме, достаточно текстуры
    m = Mesh.merge(parts)
    bake_shade(m, 0.0, 1.6, low=0.62, down=0.78)
    return m


# =====================================================================
# Овца (курдючная)
# =====================================================================

def build_sheep(A, d):
    out = []
    ws = lambda nm: S(A, "wool0", SHEEP_SUB[nm])  # noqa: E731
    k = 10 if d > 0.8 else 6
    sec = [(-0.43, 0.6, 0.08, 0.08), (-0.34, 0.6, 0.19, 0.19), (-0.14, 0.585, 0.235, 0.225), (0.1, 0.59, 0.228, 0.22),
           (0.28, 0.61, 0.18, 0.18), (0.38, 0.64, 0.09, 0.1)]
    if d < 0.8:
        sec = [sec[0], sec[1], sec[3], sec[4], sec[5]]
    body = loft([ring_z((0, y, z), rx, ry, k) for z, y, rx, ry in sec], cap_start=True, cap_end=True)
    body.jitter(0.012, seed=3)
    out.append(tag(body, SP["BODY"], ws("body"), coat=1.0))
    hax = v3((0, 0.55, 0.6)) - v3((0, 0.68, 0.36))
    hs = [((0, 0.69, 0.35), 0.075, 0.065), ((0, 0.65, 0.46), 0.07, 0.06), ((0, 0.58, 0.56), 0.05, 0.045),
          ((0, 0.555, 0.6), 0.04, 0.035)]
    head = loft([ring_axis(c, hax, rc, rs, 7 if d > 0.8 else 4) for c, rc, rs in (hs if d > 0.8 else hs[::2] + hs[-1:])],
                cap_end=True)
    out.append(tag(head, SP["HEAD"], ws("head"), coat=1.0, flip=False))
    for s in (1, -1):  # висячие уши
        ear = two_sided(grid(0.1, 0.04, 1, 1).translate(0, -0.02, 0))
        ear.rotate_z(-35 * s if s > 0 else 180 + 35).translate(0.05 * s, 0.68, 0.42)
        out.append(tag(ear, SP["HEAD"], ws("face"), coat=1.0))
    for nm, (x, z) in (("LEG_FL", (0.1, 0.25)), ("LEG_FR", (-0.1, 0.25)), ("LEG_HL", (0.1, -0.24)),
                       ("LEG_HR", (-0.1, -0.24))):
        lg = limb([(x, 0.44, z), (x, 0.2, z + 0.01), (x, 0.0, z)] if d > 0.8 else [(x, 0.44, z), (x, 0.0, z)],
                  [0.042, 0.026, 0.022] if d > 0.8 else [0.04, 0.022], sides=5 if d > 0.8 else 3)
        out.append(tag(lg, SP[nm], ws("legs"), coat=1.0, flip=False))
    tail = ellipsoid(0.13, 0.11, 0.08, 7 if d > 0.8 else 5, 4 if d > 0.8 else 2).translate(0, 0.45, -0.43)
    tail.P[:, 1] -= 0.04 * (np.abs(tail.P[:, 0]) < 0.03) * (tail.P[:, 1] < 0.45)  # курдюк на две доли
    out.append(tag(tail, SP["TAIL"], ws("tail"), coat=1.0))
    m = Mesh.merge(out)
    bake_shade(m, 0.0, 0.8, low=0.6, down=0.8)
    return m


# =====================================================================
# Описание юнитов
# =====================================================================

KOK = KOKAND_ATLAS
KIP = KIPCHAK_ATLAS

SARBOZ = dict(torso="torso", skirt="skirt", sleeve="sleeve", trousers="trousers", hat="turban", sash="sash",
              flask=True, weapon="musket", item="ramrod")
JOOKER = dict(torso="torso", skirt="skirt", sleeve="sleeve", trousers="trousers", hat="kalpak", sash="sash",
              weapon="sword", item="shield", hem=0.46)
MALCHY = dict(torso="work_torso", skirt="work_skirt", sleeve="work_torso", trousers="trousers", hat="kalpak",
              sash="sash", side_sash=1.0, side_torso=0.0, side_skirt=0.0, side_sleeve=0.0, weapon="staff", item="sack",
              hem=0.5)

UNITS = {
    "kok_sarboz": ("infantry", KOK, SARBOZ),
    "kok_sarboz_banner": ("infantry", KOK, dict(SARBOZ, weapon="banner_kokand", item=None, flask=False, back="musket",
                                                 lean=True)),
    "kok_yuzboshi": ("rider", KOK, dict(torso="torso2", skirt="skirt2", sleeve="sleeve2", trousers="trousers",
                                         hat="turban", hat_variant=False, sash="sash", weapon="saber", coat="coat0",
                                         caparison=dict(region="saddlecloth", z0=-0.5, z1=0.38, hem=1.0))),
    "kip_sayisker": ("rider", KIP, dict(torso="torso2", side_torso=0.0, skirt="skirt", sleeve="sleeve",
                                        trousers="trousers", hat="helmet", sash="sash", weapon="lance", item="shield",
                                        caparison=dict(region="caparison"))),
    "kip_sayisker_banner": ("rider", KIP, dict(torso="torso2", side_torso=0.0, skirt="skirt", sleeve="sleeve",
                                               trousers="trousers", hat="helmet", sash="sash", weapon="banner_kipchak",
                                               item="shield", caparison=dict(region="caparison"))),
    "kip_kolbashchy": ("rider", KIP, dict(torso="torso2", side_torso=0.0, skirt="skirt", sleeve="sleeve",
                                          trousers="trousers", hat="helmet_plume", sash="sash", weapon="mace",
                                          bulk=1.1, fur_collar=True, cloak="cloak", coat="coat2", coat_mask=0.0,
                                          caparison=dict(region="cloak", hem=0.74))),
    "kip_jooker": ("infantry", KIP, JOOKER),
    "kip_malchy": ("infantry", KIP, MALCHY),
    "sheep": ("sheep", ANIMALS_ATLAS, {}),
    "horse": ("horse", ANIMALS_ATLAS, {}),
}

LOD_DETAIL = 0.5


def build(uid, d):
    kind, A, spec = UNITS[uid]
    if kind == "infantry":
        return build_infantry(A, spec, d), A
    if kind == "rider":
        return build_rider(A, spec, d), A
    if kind == "sheep":
        return build_sheep(A, d), A
    return build_horse(A, d), A


def main(argv):
    os.makedirs(OUT_MODELS, exist_ok=True)
    os.makedirs(OUT_TEX, exist_ok=True)
    if "--no-tex" not in argv:
        for fn, name in ((build_kokand, "kokand_units"), (build_kipchak, "kipchak_units"), (build_animals, "animals")):
            p = os.path.join(OUT_TEX, name + ".png")
            fn(p)
            ensure_import(p, PNG_IMPORT)
            print("атлас", os.path.relpath(p, ROOT))
    write_skeleton_include(os.path.join(ROOT, "shaders/include/crowd_skeletons.gdshaderinc"))
    only = [a for a in argv if not a.startswith("--")]
    for uid in UNITS:
        if only and uid not in only:
            continue
        for lod, d in ((0, 1.0), (1, LOD_DETAIL)):
            m, A = build(uid, d)
            name = uid + ("_lod1" if lod else "")
            p = os.path.join(OUT_MODELS, name + ".glb")
            write_glb(p, [(name, m, Material(A.name, texture_uri=A.uri, roughness=0.85))])
            ensure_import(p, GLB_IMPORT)
            lo, hi = m.bounds()
            print(f"{name:24s} {m.tris:5d} треуг. высота {hi[1]:.2f} м  ширина {hi[0] - lo[0]:.2f}  длина {hi[2] - lo[2]:.2f}")


if __name__ == "__main__":
    main(sys.argv[1:])
