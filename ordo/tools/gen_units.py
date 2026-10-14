"""Модели юнитов для толпы (ТЗ 11.3–11.6): жёсткие части + рисованные атласы.

    python3 tools/gen_units.py            # все юниты, атласы, константы скелетов
    python3 tools/gen_units.py --no-tex   # без перерисовки атласов (быстрее)
    python3 tools/gen_units.py kok_sarboz kip_jooker   # только эти юниты
    python3 tools/gen_units_preview.py --all           # быстрый предпросмотр без Godot

Пишет:
    assets/models/units/<id>.glb и <id>_lod1.glb       (ссылка на общий атлас стороны)
    assets/textures/units/{kokand_units,kipchak_units,animals,kokand_dehqon}.png
    shaders/include/crowd_skeletons.gdshaderinc        (точки вращения частей)
Работники (kok_dehqon, kip_malchy с топором, кетменём, молотом и ношей) — tools/gen_units_work.py,
этот генератор зовёт его сам.

Каждая часть — одна кость (UV2.x), см. gen_units_kit.py. Модель смотрит в +Z, ноги на y = 0
(ТЗ 11.6). Пропорции реалистичные, силуэт чуть утрирован: широкие плечи, высокие шапки, крупное
оружие, знамёна (ТЗ 11.1). Против «игрушечности»: рука растёт из линии плеч торса, рукав — одна
гладкая трубка (сгибы у плеча, локтя и колена смешивает шейдер толпы по весу UV2.y, см.
gen_units_kit.joint_weight и hp_joint_blend), кулак с большим пальцем, голова чуть крупнее натуры
с живописным лицом (брови, глазницы, усы и бороды по вариантам; развёртка head_u даёт лицу вдвое
больше пикселей), шапки сидят над бровями; конь с дугой гребня шеи, мышцами предплечья и бедра,
круглой мордой. Цвет стороны — 20–30 % силуэта (ТЗ 11.2), крупными пятнами, которые читаются
с камеры RTS: у сарбоза — камзул (торс), кулах и кушак; у жоокера — накидка, отворот калпака,
кант и обшлага; у работников — шапка, кушак, обшлага и кайма подола; у конницы — попона, вымпел,
знамя. Халаты — природных красок (икат, алача, войлок, шерсть).
"""
from __future__ import annotations

import os
import sys

sys.path.insert(0, os.path.dirname(__file__))

from gen_units_kit import (GLB_IMPORT, HORSE_PIV, HP, HUMAN_PIV, PNG_IMPORT, ROOT, RP, SHEEP_PIV, SP, Mesh,  # noqa: E402
                           bake_ao, bake_shade, drop_degenerate, ellipsoid, ensure_import, joint_weight, lathe, limb,
                           loft, ring, ring_axis, seg, tag, two_sided, v3, write_skeleton_include, np, math, grid)
from gen_units_tex import (ANIMALS_ATLAS, HAT_SPLIT, HEAD_Y, HORSE_SUB, head_u, KIPCHAK_ATLAS, KOKAND_ATLAS,  # noqa: E402
                           LEATHER_SUB, METAL_SUB, SHEEP_SUB, WOOD_SUB, build_animals, build_kipchak, build_kokand)
from glb import Material, write_glb  # noqa: E402
from meshkit import disc, ring_z  # noqa: E402

OUT_MODELS = os.path.join(ROOT, "assets/models/units")
OUT_TEX = os.path.join(ROOT, "assets/textures/units")

VAR_ROBE = 1.0   # COLOR.b: вариант по w — масть коня и халат (полоса через 512 px)
VAR_HEAD = 0.5   # COLOR.b: вариант головы — шапка и лицо


def S(A, name, frac):
    """Прямоугольник части области (frac — доли)."""
    return A.sub(name, *frac)


def _rv(spec, region):
    """Вариант одежды (COLOR.b = 1): только у областей с вариантами («torso0», «sleeve0» …) —
    постоянные (офицерский кафтан «torsoX», доспех) не сдвигаются по атласу."""
    return VAR_ROBE if spec.get("robe_var") and region and region[-1] == "0" else 0.0


def _unit(v):
    v = v3(v)
    return v / max(np.linalg.norm(v), 1e-9)


# =====================================================================
# Голова, лицо, шапки
# =====================================================================

def _head_uv(m, c, rect):
    """Развёртка головы вокруг оси: u — head_u (лицо ±45° — середина ячейки, вдвое плотнее),
    v — высота (HEAD_Y), в ячейку rect."""
    u = head_u(np.degrees(np.arctan2(m.P[:, 0] - c[0], m.P[:, 2] - c[2])))
    v = (m.P[:, 1] - c[1] - HEAD_Y[0]) / (HEAD_Y[1] - HEAD_Y[0])
    m.UV = np.column_stack([np.clip(u, 0, 1), np.clip(v, 0, 1)])
    return m


def head_mesh(A, part, c, d, hat, var=True):
    """Голова: подбородок вперёд, узкая челюсть, скулы, надбровье, затылок круглее лба; нос — гребень
    из вершин переднего столбца (без отдельного клина: он давал чёрный треугольник снизу).
    Лицо — рисованное (ячейка face, развёртка head_u)."""
    cx, cy, cz = c
    lo = d < 0.8
    k = 6 if lo else 8
    # (dy, полуширина, глубина вперёд, глубина назад, сдвиг z)
    rings = [(-0.102, 0.06, 0.08, 0.052, 0.006),     # подбородок и низ челюсти
             (-0.06, 0.083, 0.098, 0.076, 0.002),    # угол челюсти, рот
             (-0.012, 0.094, 0.106, 0.098, 0.0),     # скулы, глаза
             (0.042, 0.095, 0.094, 0.112, -0.006)]   # надбровье, виски, затылок
    if not hat:
        rings.append((0.092, 0.08, 0.066, 0.1, -0.014))
    if lo:
        rings = [rings[1], rings[3]] + rings[4:]
    secs = [np.tile([cx, cy - 0.128, cz + 0.042], (k, 1))]
    for dy, rx, rf, rb, dz in rings:
        a = np.radians(180.0) + np.linspace(0, 2 * np.pi, k, endpoint=False)
        rz = np.where(np.cos(a) > 0, rf, rb)
        pts = np.column_stack([cx + rx * np.sin(a), np.full(k, cy + dy), cz + dz + rz * np.cos(a)])
        secs.append(pts)
    # макушка: без шапки — купол, под шапкой — низкая крышка (шапка сзади выше лба, щели быть не должно)
    secs.append(np.tile([cx, cy + (0.122 if not hat else 0.07), cz - 0.01], (k, 1)))
    h = loft(secs)
    drop_degenerate(h)
    # нос и подбородок: передний столбец вперёд (кончик носа — у скул, ямка под губой — у челюсти)
    front = (np.abs(h.P[:, 0] - cx) < 1e-6) & (h.P[:, 2] > cz + 0.05)
    h.P[front & (np.abs(h.P[:, 1] - (cy - 0.012)) < 1e-6), 2] += 0.026
    h.P[front & (np.abs(h.P[:, 1] - (cy + 0.042)) < 1e-6), 2] += 0.008
    h.smooth()
    rect = A.rect("face0")
    _head_uv(h, c, (0, 0, 1, 1))
    # u по столбцам loft (шов — затылок: u = 0 и 1), угол столбца → head_u
    cols = k + 1
    ucol = head_u(-180.0 + 360.0 * np.arange(cols) / k)
    for i in range(len(secs)):
        h.UV[i * cols:(i + 1) * cols, 0] = ucol
    return [tag(h, part, rect, coat=VAR_HEAD if var else 0.0)]


HEAD_SCALE = 1.06    # голова чуть крупнее натуры: лицо и шапка читаются с камеры боя (ТЗ 11.1)
HAT_LIFT = {"turban": 0.016, "kalpak": 0.014, "doppi": 0.012, "helmet": 0.006, "helmet_plume": 0.006}


def _hat_rect(A, region, fy0, fy1):
    return S(A, region, (0, fy0, 1, fy1))


def hat_mesh(A, part, c, d, kind, var=True, region="hat0"):
    """Шапки (ТЗ 11.1: высокие силуэты). c — центр головы. Вариант (COLOR.b = 0.5) у шапки и лица общий.
    Шапка сидит над бровями (HAT_LIFT): лоб и надбровье видны — лицо читается, а не прячется под чалмой."""
    cx, cy, cz = c
    cy += HAT_LIFT.get(kind, 0.0)
    out = []
    b = VAR_HEAD if var else 0.0
    lo = d < 0.8
    if kind == "turban":
        n = 6 if lo else 8
        prof = [(0.104, 0.022), (0.143, 0.085), (0.136, 0.18), (0.088, 0.245)]
        if lo:
            prof = [prof[0], prof[1], prof[3]]
        t = lathe(prof, n, start=10.0)
        th = np.arctan2(t.P[:, 0], t.P[:, 2])
        rr = 1.0 + 0.045 * np.sin(2.0 * th + t.P[:, 1] * 18.0) * (t.P[:, 1] > 0.04)   # витки наискось
        t.P[:, 0] *= rr
        t.P[:, 2] *= rr
        t.translate(cx, cy, cz - 0.006)
        t.P[:, 1] += 0.024 * (cz - t.P[:, 2]) / 0.15                 # спереди ниже, сзади выше
        t.smooth()
        t = tag(t, part, _hat_rect(A, region, HAT_SPLIT, 1.0), coat=b)
        t.C[t.P[:, 1] < cy + 0.05, 1] = 1.0      # нижний виток — лента цвета стороны (рисунок ячейки)
        out.append(t)
        kp = [(0.096, 0.232), (0.08, 0.37), (0.0, 0.53)] if not lo else [(0.096, 0.232), (0.0, 0.53)]
        k_ = lathe(kp, 6 if not lo else 5).translate(cx, cy, cz - 0.016)
        k_.P[:, 2] -= 0.05 * np.clip(k_.P[:, 1] - cy - 0.3, 0, None)   # макушка кулаха чуть назад
        out.append(tag(k_, part, _hat_rect(A, region, 0.0, HAT_SPLIT), coat=b, side=1.0))   # кулах — цвет стороны
    elif kind == "kalpak":
        n = 6 if lo else 8   # восемь граней: шестигранный калпак крупным планом выглядел коробкой
        brim = lathe([(0.1, 0.02), (0.132, 0.118)], n, start=0.0).translate(cx, cy, cz)   # высокий отворот
        # раздвоенный отворот: спереди выше и шире расходится
        fr = np.clip((brim.P[:, 2] - cz) / 0.13, 0, None)
        brim.P[:, 1] += 0.02 * fr * (brim.P[:, 1] > cy + 0.05)
        out.append(tag(brim, part, _hat_rect(A, region, 0.74, 1.0), coat=b, side=1.0))   # отворот киноварью
        cp = [(0.106, 0.07), (0.088, 0.27), (0.0, 0.44)]   # тулья: гладкий конус (нормали скругляют грани)
        crown = lathe(cp, n, start=0.0).translate(cx, cy, cz - 0.004)
        crown.P[:, 2] -= 0.06 * np.clip(crown.P[:, 1] - cy - 0.2, 0, None)
        out.append(tag(crown, part, _hat_rect(A, region, 0.0, 0.74), coat=b))
        if not lo:   # кисточка цвета стороны на макушке
            tz = cz - 0.004 - 0.06 * 0.24
            ts = lathe([(0.0, 0.47), (0.03, 0.43), (0.018, 0.4)], 4).translate(cx, cy, tz)
            out.append(tag(ts, part, S(A, "pennon", (0, 0, 0.5, 0.4)), side=1.0))
    elif kind == "doppi":
        prof = [(0.108, 0.03), (0.112, 0.085), (0.075, 0.135), (0.0, 0.15)] if not lo else \
            [(0.108, 0.03), (0.105, 0.09), (0.0, 0.15)]
        m = lathe(prof, 6 if lo else 8, start=30.0 if lo else 22.5)
        th = np.arctan2(m.P[:, 0], m.P[:, 2])
        sq = 1.0 / np.maximum(np.abs(np.cos(th)), np.abs(np.sin(th))) ** 0.55
        m.P[:, 0] *= sq * 0.94
        m.P[:, 2] *= sq * 1.04
        m.translate(cx, cy, cz - 0.004)
        m.smooth()
        out.append(tag(m, part, A.rect(region), coat=b, side=1.0))   # дўппи — бирюза и изумруд стороны
    elif kind in ("helmet", "helmet_plume"):
        n = 6 if lo else 7
        gold = kind == "helmet_plume"
        hp = [(0.108, 0.02), (0.114, 0.1), (0.086, 0.235), (0.032, 0.33), (0.0, 0.44)]
        hm = lathe([hp[0], hp[2], hp[4]] if lo else hp, n).translate(cx, cy, cz)
        if gold:
            out.append(tag(hm, part, S(A, "metal", METAL_SUB["gold"]), metal=1.0))
        else:
            # тулья — ячейка hatx: кисть (верх 0.1), сталь с рёбрами, венец, бармица (низ)
            out.append(tag(hm, part, _hat_rect(A, "hatx", 0.1, 0.62), metal=0.8))
        # бармица: кольчужная сетка от венца до плеч, открыта спереди
        av = lathe([(0.112, 0.05), (0.15, -0.13)], 5 if lo else 6, sweep=250.0, start=55.0)
        av.translate(cx, cy, cz - 0.01)
        out.append(tag(av, part, _hat_rect(A, "hatx", 0.64, 1.0), metal=0.4, flip=False))
        if gold:
            path = [(cx, cy + 0.40, cz), (cx, cy + 0.52, cz - 0.03), (cx, cy + 0.66, cz - 0.10), (cx, cy + 0.74, cz - 0.20)]
            pl = limb([path[0], path[2], path[3]], [0.018, 0.055, 0.012], sides=3)
            out.append(tag(pl, part, A.rect("plume"), flip=False, weight=lambda m: (m.P[:, 1] - (cy + 0.4)) / 0.34))
        else:
            # кисть крашеного конского волоса на шпиле — цвет стороны виден и сверху
            ts = lathe([(0.0, 0.48), (0.032, 0.42), (0.065, 0.33)], 4 if lo else 5).translate(cx, cy, cz - 0.01)
            out.append(tag(ts, part, _hat_rect(A, "hatx", 0.0, 0.1), side=1.0, flip=False,
                           weight=lambda m: np.clip((cy + 0.48 - m.P[:, 1]) / 0.15, 0, 1)))
    return out


# =====================================================================
# Человек: тело (пехота и всадник — одна верхняя половина)
# =====================================================================

def fist(A, part, hd, el, s, d, region="hand"):
    """Кулак с большим пальцем (не «варежка»): сжатая кисть вдоль предплечья, большой палец
    спереди поверх указательного, к телу."""
    hd, el = v3(hd), v3(el)
    lo = d < 0.8
    ey = _unit(el - hd)                 # вверх по руке
    ez = _unit(v3((0, 0, 1)) - ey * ey[2])
    ex = np.cross(ey, ez)
    R = np.column_stack([ex, ey, ez])
    f = ellipsoid(0.03, 0.05, 0.043, 4 if lo else 5, 2 if lo else 3)
    # костяшки — плоский торец, ладонь чуть впалая
    f.P[:, 2] += 0.008 * np.clip(-f.P[:, 1] / 0.05, 0, 1)
    f.P[:, 0] *= 1.0 - 0.15 * np.clip(-f.P[:, 1] / 0.05, 0, 1) ** 2
    f.translate(0, -0.012, 0.004)
    f.transform(np.vstack([np.column_stack([R, hd]), [0, 0, 0, 1]]))
    f.UV = np.clip(f.UV, 0, 1)
    out = [tag(f, part, A.rect(region), flip=False)]
    if not lo:
        tp = [(-s * 0.012, 0.02, 0.032), (-s * 0.026, -0.036, 0.046)]
        tp = [hd + R @ v3(p) for p in tp]
        th = limb(tp, [0.016, 0.012], sides=3, cap_end=False)
        out.append(tag(th, part, S(A, region, (0.4, 0.2, 0.7, 0.8)), flip=False))
    return out


def cape_mesh(A, part, region, d, dy=0.0, dz=0.0, top=1.5, bottom=0.95, side=1.0, var=0.0, width=1.0):
    """Накидка-жамчы на плечах: сверху лежит на плечах у шеи, вниз расходится за спиной —
    края падают позади рук (руки не протыкают её при махе)."""
    lo = d < 0.8
    cols = 3 if lo else 5
    rows = [top, (top + bottom) / 2, bottom] if not lo else [top, bottom]
    secs = []
    for y in rows:
        t = (top - y) / (top - bottom)
        W = (0.19 + 0.08 * t) * width
        zc = -0.02 - 0.1 * t
        depth = 0.13 + 0.06 * t
        s = np.linspace(-1, 1, cols)
        x = s * W
        z = zc - depth * (1 - s * s) ** 0.7
        yy = y + 0.02 * (1 - s * s) * (1 - t)
        secs.append(np.column_stack([x, yy + dy, z + dz]))
    m = loft(secs, closed_sections=False)
    if np.mean(m.N[:, 2]) > 0:
        m.flip()
    m = two_sided(m)
    return tag(m, part, A.rect(region), side=side, coat=var, flip=False,
               weight=lambda m: np.clip((top + dy - m.P[:, 1]) / (top - bottom), 0, 1))


def human_upper(A, spec, d, P, ids):
    """Торс, голова, руки, пояс. P — точки вращения (человек или всадник), ids — номера частей."""
    out = []
    pel, ch = v3(P["PELVIS"]), v3(P["CHEST"])
    dy = pel[1] - 0.98
    dz = pel[2]
    side_t, side_sl = spec.get("side_torso", 0.0), spec.get("side_sleeve", 0.0)
    lo = d < 0.8
    k = 7 if lo else 8
    bulk = spec.get("bulk", 1.0)
    # торс: от пояса до ворота; грудь колесом, широкая линия плеч (в ней прячется верх рукава —
    # рука растёт из плеча, а не торчит рядом трубой), покатая трапеция, стойка ворота
    sec = [(0.985, 0.152, 0.116, 0.0), (1.235, 0.186, 0.136, 0.02), (1.44, 0.262, 0.118, -0.004),
           (1.515, 0.17, 0.098, -0.012), (1.585, 0.072, 0.072, 0.006)]
    if lo:
        sec = [sec[0], sec[1], sec[2], sec[4]]
    elif spec.get("chest_ring"):   # грудь и лопатки круглее (где бюджет позволяет: +16 треугольников)
        sec = [sec[0], (1.15, 0.176, 0.13, 0.016), (1.33, 0.208, 0.138, 0.016)] + sec[2:]
    sq = lambda a: 1.0 + 0.06 * math.cos(2.0 * a)  # noqa: E731
    rings = [ring((0, y + dy, z + dz), rx * bulk, rz * bulk, k, phase=180.0, squash=sq) for y, rx, rz, z in sec]
    torso = loft(rings)
    out.append(tag(torso, ids["CHEST"], A.rect(spec["torso"]), side=side_t, coat=_rv(spec, spec["torso"])))
    # голова и шапка
    hc = (0.0, 1.638 + dy, 0.012 + dz)
    hv = spec.get("hat_variant", True)
    hd_parts = head_mesh(A, ids["HEAD"], hc, d, spec["hat"] is not None, var=spec.get("face_variant", True))
    if spec["hat"]:
        hd_parts += hat_mesh(A, ids["HEAD"], hc, d, spec["hat"], hv, spec.get("hat_region", "hat0"))
    for m in hd_parts:   # крупнее вокруг центра головы, низ подбородка остаётся у ворота
        m.P = (m.P - v3(hc)) * HEAD_SCALE + v3(hc) + v3((0.0, 0.004, 0.0))
    out += hd_parts
    # кушак: закрывает шов торса и подола; концы свисают спереди сбоку
    if spec.get("sash") and not (lo and not spec.get("sash_lod1", True)):
        sash = lathe([(0.168, 0.932 + dy), (0.178, 1.088 + dy)], 6 if lo else 8)   # широкий кушак-шаль
        sash.transform(np.diag([bulk, 1, bulk * 0.9]))
        sash.translate(0, 0, dz + 0.004)
        out.append(tag(sash, ids["PELVIS"], A.rect(spec["sash"]), side=spec.get("side_sash", 1.0),
                       coat=_rv(spec, spec["sash"]), flip=False))
        if not lo and dy < 0.1 and not spec.get("lean"):
            for x0, ang, L in ((0.075, 14, 0.3), (0.13, 40, 0.24)):
                g = two_sided(grid(0.07, L, 1, 1).translate(-0.035, -L, 0))
                g.rotate_y(ang).translate(x0, 0.99 + dy, 0.125 + dz - (x0 - 0.075) * 0.6)
                out.append(tag(g, ids["PELVIS"], A.rect(spec["sash"]), side=spec.get("side_sash", 1.0),
                               coat=_rv(spec, spec["sash"]),
                               weight=lambda m, y0=0.99 + dy, L=L: (y0 - m.P[:, 1]) / L))
    # руки: рукав — одна гладкая трубка от купола плеча до локтя (купол уходит под линию плеч
    # торса); у плеча вершины смешиваются с грудью, у локтя — с предплечьем (шейдер толпы,
    # hp_joint_blend): рукав гнётся дугой, без щелей и «эполет»
    sv = spec["sleeve"]
    rvs = _rv(spec, sv)
    for s, ua, fa in ((1, "UARM_L", "FARM_L"), (-1, "UARM_R", "FARM_R")):
        side = "L" if s > 0 else "R"
        sh, el, hd = v3(P["SHOULDER_" + side]), v3(P["ELBOW_" + side]), v3(P["HAND_" + side])
        rs = 5 if lo else 6
        ud = _unit(el - sh)
        fd = _unit(hd - el)
        inw = v3((-s, 0.0, 0.0))
        if lo:
            up = limb([sh - ud * 0.034 + inw * 0.006, sh, el + ud * 0.01], [0.05, 0.068, 0.058], sides=rs)
        else:
            up = limb([sh - ud * 0.058 + inw * 0.014, sh - ud * 0.034 + inw * 0.005, sh, el + ud * 0.01],
                      [0.014, 0.052, 0.069, 0.059], sides=rs)
        up = tag(up, ids[ua], S(A, sv, (0, 0, 1, 0.5)), side=side_sl, coat=rvs, flip=False)
        joint_weight(up, sh, ud, 0.13, 0.42)        # плечо держится за торс
        joint_weight(up, el, -ud, 0.1, 0.5)         # локоть — пополам с предплечьем
        out.append(up)
        cuff = hd - fd * 0.045
        cs = spec.get("cuff_side") and not lo
        cw = 0.075 if cs else 0.0                                 # ширина обшлага
        fs = 5                                                    # предплечье и обшлаг — пять граней
        if lo:
            fo = limb([el, cuff], [0.06, 0.072], sides=fs)
        else:
            fo = limb([el - fd * 0.01, cuff - fd * cw], [0.06, 0.069], sides=fs)
        fo = tag(fo, ids[fa], S(A, sv, (0, 0.5, 1, 0.86 if cs else 1.0)), side=side_sl, coat=rvs, flip=False)
        joint_weight(fo, el, fd, 0.1, 0.5)
        out.append(fo)
        if cs:   # обшлаг цвета стороны — отворот чуть шире рукава
            cf = limb([cuff - fd * (cw + 0.004), cuff + fd * 0.006], [0.073, 0.077], sides=fs)
            out.append(tag(cf, ids[fa], S(A, sv, (0, 0.86, 1, 1)), side=1.0, coat=rvs, flip=False))
        out += fist(A, ids[fa], hd, el, s, d)
    # меховой ворот и плащ (полководец)
    if spec.get("fur_collar"):
        pts = [(0.17 * math.sin(a), 1.505 + dy, 0.125 * math.cos(a) + dz - 0.01) for a in np.linspace(0, 2 * math.pi, 5)]
        fc = limb(pts, 0.05, sides=3)
        out.append(tag(fc, ids["CHEST"], A.rect("fur"), flip=False))
    if spec.get("cloak"):
        cpf = [(0.2, 0.0), (0.3, -0.36), (0.40, -0.72)] if not lo else [(0.2, 0.0), (0.40, -0.72)]
        cl = lathe(cpf, 4, sweep=200, start=80)
        cl.translate(0, 1.45 + dy, dz - 0.02)
        cl.P[:, 2] -= 0.12 * np.clip(-(cl.P[:, 1] - 1.45 - dy), 0, None)
        cl = two_sided(cl)
        out.append(tag(cl, ids["CHEST"], A.rect(spec["cloak"]), side=1.0, flip=False,
                       weight=lambda m: (1.45 + dy - m.P[:, 1]) / 0.72))
    if spec.get("cape"):
        out.append(cape_mesh(A, ids["CHEST"], spec["cape"], d, dy, dz,
                             bottom=spec.get("cape_bottom", 0.95)))
    return out


def human_legs(A, spec, d):
    """Ноги пехотинца: штаны под подолом, высокие сапоги с загнутым носком, полы халата."""
    out = []
    lo = d < 0.8
    rvt = _rv(spec, spec["trousers"])
    for s, th, sh in ((1, "THIGH_L", "SHIN_L"), (-1, "THIGH_R", "SHIN_R")):
        side = "L" if s > 0 else "R"
        hip, kn, an = v3(HUMAN_PIV["HIP_" + side]), v3(HUMAN_PIV["KNEE_" + side]), v3(HUMAN_PIV["ANKLE_" + side])
        td, bd = _unit(kn - hip), _unit(an - kn)
        # шаровары под полами — видны только при шаге
        t = limb([hip + (0.006 * s, 0.05, 0), kn + (0, 0.01, 0)], [0.086, 0.068], sides=4)
        t = tag(t, HP[th], A.rect(spec["trousers"]), coat=rvt, flip=False)
        joint_weight(t, hip + (0, 0.05, 0), td, 0.12, 0.4)     # у пояса держится за таз
        joint_weight(t, kn, -td, 0.1, 0.5)                      # колено — пополам с голенищем
        out.append(t)
        if lo:
            b = limb([kn + (0, 0.02, 0.005), an + (0, 0.01, 0)], [0.066, 0.048], sides=4)
        else:
            # голенище одной трубкой (сгиб у колена смешивает шейдер): треугольники ушли в голову
            b = limb([kn + (0, 0.03, 0.008), an + (0, 0.012, 0)], [0.07, 0.046], sides=5)
        b = tag(b, HP[sh], S(A, "leather", LEATHER_SUB["boot"]), flip=False)
        joint_weight(b, kn, bd, 0.1, 0.5)
        out.append(b)
        f = ellipsoid(0.048, 0.052, 0.125, 4, 1 if lo else 2, y_from=-0.35).translate(an[0], 0.045, an[2] + 0.045)
        toe = f.P[:, 2] > an[2] + 0.1
        f.P[toe, 1] += (f.P[toe, 2] - an[2] - 0.1) * 0.8
        f.P[:, 1] = np.maximum(f.P[:, 1], 0.0)
        out.append(tag(f, HP[sh], S(A, "leather", LEATHER_SUB["boot"])))
    # полы халата: две половины, каждая следует за своим бедром; левая запахнута поверх правой.
    # Подол чуть волнистый — складки читаются в силуэте, а не только в текстуре.
    hem = spec.get("hem", 0.4)
    hb = spec.get("hem_side")
    prof = [(0.16, 1.03), (0.19, 0.9), (0.245, 0.66), (0.305, hem)]
    if lo:
        prof = [prof[0], prof[2], prof[3]]
    if hb:   # кайма подола цвета стороны (и в LOD1 — она нужна издали): повтор кольца, край без растяжки
        hy = hem + 0.065
        hr = 0.245 + (0.305 - 0.245) * (0.66 - hy) / (0.66 - hem)
        # в LOD1 без повтора: кайма издали — мягкий переход к подолу, зато на 12 треугольников легче
        prof = prof[:-1] + ([(hr, hy)] if lo else [(hr, hy), (hr, hy - 0.002)]) + prof[-1:]
    b = spec.get("bulk", 1.0)
    for s, name, start, sweep, grow in ((1, "SKIRT_L", -10.0, 200.0, 1.018), (-1, "SKIRT_R", 180.0, 180.0, 1.0)):
        sk = lathe(prof, 3 if lo else (4 if spec.get("lean") or hb else 5), sweep=sweep, start=start)
        th = np.arctan2(sk.P[:, 0], sk.P[:, 2])
        low = np.clip((0.75 - sk.P[:, 1]) / (0.75 - hem), 0, 1)
        wav = 1.0 + 0.05 * np.sin(th * 5.0 + s) * low
        sk.P[:, 0] *= grow * wav * b
        sk.P[:, 2] = sk.P[:, 2] * 0.88 * grow * wav + 0.014
        if s < 0:
            sk.UV[:, 0] = 1.0 - sk.UV[:, 0]
        sk.smooth()
        sk = tag(sk, HP[name], A.rect(spec["skirt"]), side=spec.get("side_skirt", 0.0), coat=_rv(spec, spec["skirt"]),
                 flip=False,
                 weight=lambda m: (1.03 - m.P[:, 1]) / (1.03 - hem))
        if hb:
            cols = len(sk.P) // len(prof)
            sk.C[np.arange(len(sk.P)) // cols >= len(prof) - 2, 1] = 1.0
        out.append(sk)
    return out


# =====================================================================
# Оружие и предметы (в позе покоя: хват в правой кисти, ось оружия +Y)
# =====================================================================

def musket(A, part, W, d, back=False):
    """Мылтык (фитильное ружьё) ~1.5 м: ось +Y от запястья ложа к дулу; +Z — низ приклада при прицеливании."""
    out = []
    W = v3(W)
    bar = limb([W + (0, 0.1, -0.004), W + (0, 1.14, -0.004)], [0.017, 0.0135], sides=3 if d < 0.8 else (4 if back else 5))
    out.append(tag(bar, part, S(A, "metal", METAL_SUB["iron"]), metal=0.7, flip=False))
    k = 4
    secs = [(-0.34, 0.022, 0.062, 0.036), (-0.17, 0.02, 0.046, 0.024), (0.0, 0.016, 0.026, 0.008),
            (0.09, 0.02, 0.034, 0.012), (0.56, 0.016, 0.02, 0.002)]
    secs = [secs[0], secs[2], secs[4]] if d < 0.8 else [secs[0], secs[1], secs[3], secs[4]]
    rings = [ring(W + (0, y, zo), rx, rz, k, phase=45.0) for y, rx, rz, zo in secs]
    st = loft(rings, cap_start=True)
    out.append(tag(st, part, S(A, "wood", WOOD_SUB["walnut"]), flip=False))
    if not back and d > 0.8:
        lk = ellipsoid(0.012, 0.035, 0.012, 3, 2).translate(W[0] + 0.02, W[1] + 0.08, W[2] + 0.01)
        out.append(tag(lk, part, S(A, "metal", METAL_SUB["gold"]), metal=1.0))
    return out


def blade(A, part, W, d, length=0.82, curve=0.07, guard=True, flat=False):
    """Сабля/меч: клинок вдоль +Y, лезвие вперёд (+Z), изгиб назад. flat — плоский двусторонний."""
    W = v3(W)
    out = []
    n = 4 if d > 0.8 else 3
    ys = np.linspace(0.1, 0.1 + length, n + 1)
    if flat:
        P = []
        for i, y in enumerate(ys):
            t = (y - 0.1) / length
            wdt = 0.021 * (1 - 0.6 * t ** 3) if i < n else 0.0015
            zc = -curve * t * t
            P += [W + (0, y, zc - wdt), W + (0, y, zc + wdt)]
        F = []
        for i in range(n):
            a = 2 * i
            F += [(a, a + 1, a + 3), (a, a + 3, a + 2)]
        UV = [(j % 2, 1 - (j // 2) / n) for j in range(len(P))]
        bl = two_sided(Mesh(P, F, None, UV))
    else:
        rings = []
        for i, y in enumerate(ys):
            t = (y - 0.1) / length
            wdt = 0.02 * (1 - 0.65 * t ** 3) if i < n else 0.002
            rings.append(ring_axis(W + (0, y, -curve * t * t), (0, 1, 0), wdt, 0.0045, 4, ref=(0, 0, 1)))
        bl = loft(rings)
    out.append(tag(bl, part, S(A, "metal", METAL_SUB["steel"]), metal=1.0, flip=False))
    grip = limb([W + (0, -0.07, 0), W + (0, 0.1, 0)], [0.017, 0.015], sides=3 if flat else 4)
    out.append(tag(grip, part, S(A, "leather", LEATHER_SUB["belt"]), flip=False))
    if guard:
        gd = limb([W + (0, 0.1, -0.06), W + (0, 0.1, 0.06)], 0.011, sides=3 if flat else 4)
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
    """Найза ~3.7 м с вымпелом (ткань — отдельная часть, развевается)."""
    W = v3(W)
    out = []
    sh = limb([W + (0, -1.3, 0), W + (0, 2.3, 0)], [0.022, 0.017], sides=4)
    out.append(tag(sh, part, S(A, "wood", WOOD_SUB["shaft"]), flip=False))
    hd = lathe([(0.02, 2.29), (0.034, 2.36), (0.0, 2.6)], 4, normals="crease").translate(W[0], W[1], W[2])
    out.append(tag(hd, part, S(A, "metal", METAL_SUB["steel"]), metal=1.0))
    g = grid(0.5, 0.2, 2 if d < 0.8 else 4, 1)
    g.P[:, 1] = 0.1 + (g.P[:, 1] - 0.1) * (1 - 0.8 * g.P[:, 0] / 0.5)
    g.rotate_y(90).translate(W[0], W[1] + 2.06, W[2])
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
    pole = limb([W + (0, lo, 0), W + (0, hi, 0)], [0.022, 0.018], sides=4)
    out.append(tag(pole, part, S(A, "wood", WOOD_SUB["shaft"]), flip=False))
    if kind == "kokand":
        fin = lathe([(0.0, hi), (0.046, hi + 0.06), (0.01, hi + 0.13), (0.0, hi + 0.3)], 4,
                    normals="crease").translate(W[0], W[1], W[2])
        out.append(tag(fin, part, S(A, "metal", METAL_SUB["gold"]), metal=1.0))
    else:
        tug = lathe([(0.0, hi - 0.02), (0.1, hi - 0.16), (0.12, hi - 0.34), (0.0, hi - 0.5)],
                    5 if d > 0.8 else 4).translate(W[0], W[1], W[2])
        out.append(tag(tug, part, A.rect("tug"), weight=lambda m: (W[1] + hi - m.P[:, 1]) / 0.5 * 0.6))
        pr = limb([W + (0, hi, 0), W + (0, hi + 0.22, 0)], [0.012, 0.002], sides=3)
        out.append(tag(pr, part, S(A, "metal", METAL_SUB["steel"]), metal=1.0, flip=False))
    g = grid(cw, chh, 3, 1 if d < 0.8 else 2)
    g.rotate_y(90).translate(W[0], W[1] + ctop - chh, W[2] - 0.02)
    g = two_sided(g)
    out.append(tag(g, cloth_part, A.rect("banner"), side=1.0, weight=lambda m: (W[2] - 0.02 - m.P[:, 2]) / cw))
    return out


def shield(A, part, center, d, r=0.27, side=0.4):
    """Круглый калкан на левом предплечье, лицом вперёд (+Z)."""
    c = v3(center)
    n = 6 if d < 0.8 else 10   # круглый край: щит — крупное пятно силуэта, восьмигранник выглядел «игрушкой»
    dome = lathe([(0.0, 0.07), (r, 0.0)] if d < 0.8 else [(0.0, 0.07), (r * 0.55, 0.055), (r, 0.0)], n)
    dome.rotate_x(90).translate(*c)
    dome.UV = np.column_stack([0.5 - (dome.P[:, 0] - c[0]) / (2 * r), 0.5 - (dome.P[:, 1] - c[1]) / (2 * r)])
    back = disc(r, n).rotate_x(-90).translate(*c)
    back.UV = np.column_stack([0.5 + (back.P[:, 0] - c[0]) / (2 * r), 0.5 - (back.P[:, 1] - c[1]) / (2 * r)])
    return [tag(dome, part, A.rect("shield"), side=side, flip=False),
            tag(back, part, S(A, "leather", LEATHER_SUB["belt"]), flip=False)]


def ramrod(A, part, W):
    W = v3(W)
    rr = limb([W + (0, -0.05, 0.0), W + (0, 0.85, 0.0)], 0.0065, sides=3)
    return [tag(rr, part, S(A, "metal", METAL_SUB["iron"]), metal=0.6, flip=False)]


def sack(A, part, d):
    sk = ellipsoid(0.2, 0.13, 0.14, seg(6, d), 3).rotate_z(20).translate(-0.17, 1.58, -0.05)
    return [tag(sk, part, S(A, "leather", LEATHER_SUB["felt"]))]


def flask(A, part, d):
    f = ellipsoid(0.05, 0.072, 0.028, 4, 2).rotate_z(-15).translate(-0.178, 0.895, 0.07)
    return [tag(f, part, A.rect("flask"), metal=0.6)]


# =====================================================================
# Пехотинец
# =====================================================================

EXCLUDE_AO_H = (HP["WEAPON"], HP["ITEM"], HP["CLOTH"], 17, 18, 19, 20)


def finish_human(parts, d=1.0):
    m = Mesh.merge(parts)
    bake_shade(m, 0.0, 1.75, low=0.62, down=0.82)
    bake_ao(m, EXCLUDE_AO_H, rays=24 if d > 0.8 else 12)
    return m


def build_infantry(A, spec, d, finish=True):
    parts = human_upper(A, spec, d, HUMAN_PIV, HP) + human_legs(A, spec, d)
    W = HUMAN_PIV["HAND_R"]
    wpn = spec.get("weapon")
    if wpn == "musket":
        parts += musket(A, HP["WEAPON"], W, d)
    elif wpn in ("sword", "saber"):
        parts += blade(A, HP["WEAPON"], W, d, curve=0.05 if wpn == "sword" else 0.09, flat=True)
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
    if spec.get("back") == "musket" and d > 0.8:
        # ружьё за спиной наискось: ствол и ложе тремя гранями (издали не видно — в LOD1 нет)
        W0 = v3((0, 0, 0))
        bar = limb([W0 + (0, 0.1, 0), W0 + (0, 1.12, 0)], [0.016, 0.013], sides=3)
        st = limb([W0 + (0, -0.34, 0.03), W0 + (0, -0.12, 0.016), W0 + (0, 0.12, 0.004)], [0.04, 0.028, 0.018], sides=3)
        bm = Mesh.merge([tag(bar, HP["CHEST"], S(A, "metal", METAL_SUB["iron"]), metal=0.7, flip=False),
                         tag(st, HP["CHEST"], S(A, "wood", WOOD_SUB["walnut"]), flip=False)])
        bm.rotate_z(-32).translate(0.0, 1.12, -0.17)
        parts.append(bm)
    if not finish:
        return parts
    return finish_human(parts, d)


# =====================================================================
# Конь (+ всадник)
# =====================================================================

_lg = HORSE_SUB["legs"]
HORSE_SUB_X = dict(HORSE_SUB, legs_up=(_lg[0], _lg[1], _lg[2], (_lg[1] + _lg[3]) / 2),
                   legs_lo=(_lg[0], (_lg[1] + _lg[3]) / 2, _lg[2], _lg[3]))

# профиль корпуса: z, высота оси, полуширина, полувысота (как в horse_body; укорочен ×0.9 к груди)
HORSE_BODY = [(-0.99, 1.31, 0.09, 0.12), (-0.88, 1.28, 0.215, 0.265), (-0.62, 1.24, 0.285, 0.335),
              (-0.3, 1.19, 0.288, 0.33), (0.08, 1.17, 0.305, 0.36), (0.42, 1.215, 0.27, 0.37),
              (0.62, 1.2, 0.215, 0.33), (0.76, 1.13, 0.13, 0.22)]


def horse_body(A, d, coat_cell="coat0", coat_mask=1.0, mane=True, ridden=False):
    """Конь. ridden — под всадником: середину корпуса закрывают попона и седло, корпус на грань проще."""
    out = []
    hs = lambda nm: S(A, coat_cell, HORSE_SUB_X[nm])  # noqa: E731
    lo = d < 0.8
    k = 6 if lo else (7 if ridden else 8)
    sec = HORSE_BODY
    if lo:
        sec = [sec[0], sec[2], sec[4], sec[5], sec[6], sec[7]]
    elif ridden:   # середину корпуса закрывают попона и седло: кольцо под ними не видно
        sec = sec[:3] + sec[4:]
    spine = lambda a: 1.0 - 0.1 * max(math.cos(a), 0.0) ** 3 + 0.04 * max(-math.cos(a), 0.0)  # noqa: E731
    rings = [ring_z((0, y, 0.62 + (z - 0.62) * 0.9), rx, ry, k, squash=spine) for z, y, rx, ry in sec]
    body = loft(rings, cap_start=True, cap_end=True)
    out.append(tag(body, RP["BODY"], hs("body"), coat=coat_mask))
    # шея: широкая у груди, гребень дугой, горло округлое
    n0, n1 = v3((0, 1.3, 0.56)), v3((0, 1.84, 0.92))
    ax = n1 - n0
    axn = ax / np.linalg.norm(ax)
    # гребень шеи дугой: у средних колец верх выпуклее (крутая «лебединая» линия, а не доска),
    # горло — уже и круглее
    def crest_k(k_):
        return lambda a: ((1.0 + k_ * max(math.cos(a), 0.0) ** 3) * (1.0 + 0.1 * math.sin(a) ** 2)
                          * (1.0 - 0.08 * max(-math.cos(a), 0.0) ** 2))
    ns = [((0, 1.27, 0.53), 0.26, 0.17, 0.12), ((0, 1.47, 0.69), 0.215, 0.145, 0.3),
          ((0, 1.65, 0.81), 0.168, 0.118, 0.3), ((0, 1.8, 0.9), 0.13, 0.098, 0.16)]
    neck = loft([ring_axis(c, ax, rc, rs, 5 if lo else 7, squash=crest_k(kk_))
                 for c, rc, rs, kk_ in ([ns[0], ns[3]] if lo else ns)])
    nw = lambda m: (m.P - n0) @ axn / 0.5  # noqa: E731
    out.append(tag(neck, RP["NECK"], hs("neck"), coat=coat_mask, flip=False, weight=nw))
    # грива — рисованные карты: стоячий гребень (силуэт с обеих сторон) и пряди, падающие на
    # правую сторону шеи; чёлка между ушами
    if mane:
        segs = 2 if lo else 4
        ts = np.linspace(0.0, 1.0, segs + 1)
        crest_pts = [v3((0, 1.43, 0.55)) * (1 - t) + v3((0, 1.97, 0.92)) * t for t in ts]

        def card(rows, fn):
            P, UV = [], []
            for t, p in zip(ts, rows):
                a, b = fn(t, p)
                P += [a, b]
                UV += [(t, 0.0), (t, 1.0)]
            F = []
            for i in range(segs):
                a = 2 * i
                F += [(a, a + 2, a + 3), (a, a + 3, a + 1)]
            return two_sided(Mesh(P, F, None, UV))

        up = card(crest_pts, lambda t, p: (p + (0, -0.03, 0.0), p + (0.0, 0.075 - 0.02 * t, -0.04)))
        out.append(tag(up, RP["NECK"], hs("mane"), coat=coat_mask, flip=False, weight=nw))
        hang = card(crest_pts, lambda t, p: (p + (-0.005, 0.01, 0.0), p + (-0.1, -0.21 + 0.07 * t, -0.03)))
        out.append(tag(hang, RP["NECK"], hs("mane"), coat=coat_mask, flip=False, weight=nw))
        if not lo:
            fl_ = two_sided(Mesh([(0.035, 1.965, 1.025), (-0.035, 1.965, 1.025), (-0.03, 1.85, 1.14), (0.03, 1.85, 1.14)],
                                 [(0, 1, 2), (0, 2, 3)], None, [(0, 0), (1, 0), (1, 1), (0, 1)]))
            out.append(tag(fl_, RP["HEAD"], hs("mane"), coat=coat_mask, flip=False))
    # голова: затылок, широкие ганаши, прямая переносица, морда с ноздрями
    h0, h1 = v3((0, 1.885, 0.955)), v3((0, 1.43, 1.345))
    hax = h1 - h0
    jowl = lambda a: 1.0 + 0.22 * max(-math.cos(a), 0.0) ** 2  # noqa: E731
    nose_ = lambda a: 1.0 - 0.12 * max(math.cos(a), 0.0) ** 2  # noqa: E731   (переносица площе, ноздри шире)
    hsec = [((0, 1.885, 0.955), 0.092, 0.075, None), ((0, 1.72, 1.04), 0.13, 0.096, jowl),
            ((0, 1.585, 1.2), 0.076, 0.064, nose_), ((0, 1.47, 1.315), 0.074, 0.07, nose_),
            ((0, 1.425, 1.36), 0.046, 0.05, None)]
    if lo:
        hsec = [hsec[0], hsec[1], hsec[3]]
    head = loft([ring_axis(c, hax, rc, rs, 5 if lo else 7, squash=sq) for c, rc, rs, sq in hsec], cap_end=True)
    out.append(tag(head, RP["HEAD"], hs("head"), coat=coat_mask, flip=False))
    for s in (() if lo else (1, -1)):
        ear = limb([(0.045 * s, 1.9, 0.93), (0.075 * s, 2.06, 0.95)], [0.03, 0.004], sides=3)
        out.append(tag(ear, RP["HEAD"], hs("ear"), coat=coat_mask, flip=False, weight=lambda m: np.full(len(m.P), 0.6)))
    # ноги: мускулистое предплечье и голень, узловатое запястье и скакательный сустав, плоская
    # (уже сбоку, глубже спереди-назад) пясть, путовый сустав, наклонная бабка, копыто
    sides = 5 if not lo else 4

    def flat_leg(m, x, k=0.8, y_top=0.62):
        """Пясть и запястье уже сбоку: сжатие по X к оси ноги ниже y_top."""
        sel = m.P[:, 1] < y_top
        m.P[sel, 0] = x + (m.P[sel, 0] - x) * k
        m.smooth()
        return m

    for s, sd in ((1, "L"), (-1, "R")):
        x = 0.15 * s
        kf = v3(HORSE_PIV["F_KNEE_" + sd])
        # предплечье: мышца у локтя (впереди и снаружи), к запястью сухое и плоское
        fu = limb([(x, 1.06, 0.49), (x, 0.53, 0.55)] if lo else
                  [(x * 0.92, 1.12, 0.45), (x, 0.9, 0.505), (x, 0.72, 0.532), (x, 0.53, 0.552)],
                  [0.11, 0.05] if lo else [0.13, 0.095, 0.068, 0.054], sides=sides)
        fu = tag(flat_leg(fu, x, 0.85), RP["FU_" + sd], hs("legs_up"), coat=coat_mask, flip=False)
        joint_weight(fu, kf, v3((0, 1, -0.07)), 0.12, 0.5)
        out.append(fu)
        fpath = [(x, 0.55, 0.552), (x, 0.4, 0.555), (x, 0.13, 0.558), (x, 0.06, 0.594)]
        frad = [0.054, 0.036, 0.044, 0.036]
        if lo:
            fpath, frad = [fpath[0], fpath[2], fpath[3]], [frad[0], frad[2], frad[3]]
        fl = tag(flat_leg(limb(fpath, frad, sides=sides), x, 0.78), RP["FL_" + sd], hs("legs_lo"), coat=coat_mask,
                 flip=False)
        joint_weight(fl, kf, v3((0, -1, 0.01)), 0.12, 0.5)
        out.append(fl)
        hf = lathe([(0.058, 0.0), (0.04, 0.078)], sides, normals="crease")
        hf.P[hf.P[:, 1] > 0.04, 2] -= 0.016
        hf.translate(x, 0, 0.602)
        out.append(tag(hf, RP["FL_" + sd], hs("hoof"), coat=coat_mask))
        x = 0.165 * s
        kh = v3(HORSE_PIV["H_HOCK_" + sd])
        # бедро и голень: круп переходит в мощную «штанину», к скакательному суставу — сухожилие
        hu = limb([(x * 1.06, 1.1, -0.52), (x, 0.56, -0.7)] if lo else
                  [(x * 0.9, 1.2, -0.46), (x, 0.98, -0.575), (x, 0.78, -0.665), (x, 0.58, -0.71)],
                  [0.13, 0.054] if lo else [0.17, 0.12, 0.078, 0.056], sides=sides)
        hu = tag(flat_leg(hu, x, 0.72, y_top=1.05), RP["HU_" + sd], hs("legs_up"), coat=coat_mask, flip=False)
        joint_weight(hu, kh, _unit(v3((0, 0.58, -0.71)) - v3((0, 0.84, -0.62))) * -1, 0.12, 0.5)
        out.append(hu)
        hpath = [(x, 0.62, -0.728), (x, 0.46, -0.69), (x, 0.13, -0.64), (x, 0.06, -0.608)]
        hrad = [0.058, 0.038, 0.044, 0.036]
        if lo:
            hpath, hrad = [hpath[0], hpath[2], hpath[3]], [hrad[0], hrad[2], hrad[3]]
        hl = limb(hpath, hrad, sides=sides)
        # пяточный бугор скакательного сустава торчит назад
        back = (hl.P[:, 2] < -0.72) & (np.abs(hl.P[:, 1] - 0.6) < 0.05)
        hl.P[back, 2] -= 0.022
        hl = tag(flat_leg(hl, x, 0.78), RP["HL_" + sd], hs("legs_lo"), coat=coat_mask, flip=False)
        joint_weight(hl, kh, v3((0, -1, 0.15)), 0.12, 0.5)
        out.append(hl)
        hf = lathe([(0.058, 0.0), (0.04, 0.078)], sides, normals="crease")
        hf.P[hf.P[:, 1] > 0.04, 2] -= 0.016
        hf.translate(x, 0, -0.594)
        out.append(tag(hf, RP["HL_" + sd], hs("hoof"), coat=coat_mask))
    # хвост: короткая репица и две скрещённые карты волоса (объём с любого ракурса)
    root, tip = v3((0, 1.42, -0.85)), v3((0, 0.7, -1.0))
    dock = limb([root + (0, 0.02, 0.03), root + (0, -0.12, -0.08)], [0.05, 0.04], sides=4)
    tw = lambda m: np.clip((1.43 - m.P[:, 1]) / 0.73, 0, 1)  # noqa: E731
    out.append(tag(dock, RP["TAIL"], hs("tail"), coat=coat_mask, flip=False, weight=tw))
    rows = 3 if (lo or ridden) else 4
    pts = [v3((0, 1.36, -0.92)), v3((0, 1.2, -1.0)), v3((0, 0.98, -1.03)), v3((0, 0.7, -1.0))]
    wid = [0.06, 0.13, 0.15, 0.08]
    if lo or ridden:
        pts, wid = [pts[0], pts[2], pts[3]], [wid[0], wid[2], wid[3]]
    for axis in (v3((1, 0, 0)), _unit(v3((0, 0.25, -1)))):
        P, UV = [], []
        for i, (p, w_) in enumerate(zip(pts, wid)):
            P += [p - axis * w_ * 0.5, p + axis * w_ * 0.5]
            UV += [(0.0, i / (rows - 1)), (1.0, i / (rows - 1))]
        F = []
        for i in range(rows - 1):
            a = 2 * i
            F += [(a, a + 1, a + 3), (a, a + 3, a + 2)]
        card = two_sided(Mesh(P, F, None, UV))
        out.append(tag(card, RP["TAIL"], hs("tail"), coat=coat_mask, flip=False, weight=tw))
    del tip
    return out


def caparison_mesh(A, region, d, z0=-0.8, z1=0.62, hem=0.8, side=1.0, top_off=0.035, sub=None):
    """Попона: открытые дуги через спину, бока висят отвесно до подола."""
    nz = 5 if d > 0.8 else 3
    zs = np.linspace(z0, z1, nz)
    kk = 7 if d > 0.8 else 3
    tbl = np.array(HORSE_BODY, dtype=float)
    tbl[:, 0] = 0.62 + (tbl[:, 0] - 0.62) * 0.9
    secs = []
    for z in zs:
        cy = np.interp(z, tbl[:, 0], tbl[:, 1])
        rx = np.interp(z, tbl[:, 0], tbl[:, 2]) + top_off
        ry = np.interp(z, tbl[:, 0], tbl[:, 3]) + top_off
        pts = []
        for t in np.linspace(-1, 1, kk):
            th = t * math.radians(96)
            pts.append((-rx * math.sin(th), cy + ry * math.cos(th), z))
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
        t = limb([hip, kn], [0.082, 0.064], sides=4)
        out.append(tag(t, RP["BODY"], A.rect(spec["trousers"]), coat=_rv(spec, spec["trousers"]), flip=False))
        b = limb([kn + (0, 0.02, 0), an + (0, 0.02, 0), an + (0.01 * s, -0.03, 0.13)], [0.062, 0.05, 0.035],
                 sides=4)
        out.append(tag(b, RP["BODY"], S(A, "leather", LEATHER_SUB["boot"]), flip=False))
    for s, start in ((1, 0.0), (-1, 180.0)):
        sp = [(0.16, 0.0), (0.21, -0.13), (0.3, -0.34)]
        sk = lathe(sp if d > 0.8 else [sp[0], sp[2]], 4 if d > 0.8 else 3, sweep=180.0, start=start)
        if s < 0:
            sk.UV[:, 0] = 1.0 - sk.UV[:, 0]
        sk.rotate_x(-38).translate(0, 1.67, 0.045)
        sk.P[:, 0] *= spec.get("bulk", 1.0)
        skv = _rv(spec, spec["skirt"])
        out.append(tag(sk, RP["R_PELVIS"], A.rect(spec["skirt"]), side=spec.get("side_skirt", 0.0), coat=skv, flip=False,
                       weight=lambda m: np.clip((1.67 - m.P[:, 1]) / 0.3, 0, 1)))
    return out


EXCLUDE_AO_R = (RP["R_WEAPON"], RP["R_ITEM"], RP["R_CLOTH"], RP["TAIL"])


def build_rider(A, spec, d):
    parts = horse_body(A, d, spec.get("coat", "coat0"), spec.get("coat_mask", 1.0), ridden=True)
    cap = (0, 0)
    if spec.get("caparison"):
        cz = spec["caparison"]
        n0 = sum(len(p.P) for p in parts)
        cm = caparison_mesh(A, cz["region"], d, cz.get("z0", -0.8), cz.get("z1", 0.62), cz.get("hem", 0.8))
        parts.append(cm)
        cap = (n0, n0 + len(cm.P))
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
        parts += blade(A, RP["R_WEAPON"], W, d, curve=0.1, flat=True)
    elif wpn == "mace":
        parts += mace(A, RP["R_WEAPON"], W, d)
    elif wpn == "banner_kipchak":
        parts += banner_pole(A, RP["R_WEAPON"], RP["R_CLOTH"], W, d, "kipchak")
    if spec.get("item") == "shield":
        el, hd = v3(P["ELBOW_L"]), v3(P["HAND_L"])
        parts += shield(A, RP["R_ITEM"], (el + hd) / 2 + (0.0, 0.0, 0.075), d, r=0.25)
    m = Mesh.merge(parts)
    bake_shade(m, 0.0, 2.3, low=0.6, down=0.8)
    before = m.C[cap[0]:cap[1], 0].copy()
    bake_ao(m, EXCLUDE_AO_R, rays=24 if d > 0.8 else 12)
    # попона — крупные треугольники: полная тень от ноги всадника ложилась на них треугольными пятнами
    m.C[cap[0]:cap[1], 0] = before + (m.C[cap[0]:cap[1], 0] - before) * 0.35
    return m


def build_horse(A, d, coat_cell="coat0"):
    m = Mesh.merge(horse_body(A, d, coat_cell, 1.0))
    bake_shade(m, 0.0, 1.6, low=0.62, down=0.78)
    bake_ao(m, (RP["TAIL"],), rays=24 if d > 0.8 else 12)
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
    for s in (1, -1):
        ear = two_sided(grid(0.1, 0.04, 1, 1).translate(0, -0.02, 0))
        ear.rotate_z(-35 * s if s > 0 else 180 + 35).translate(0.05 * s, 0.68, 0.42)
        out.append(tag(ear, SP["HEAD"], ws("face"), coat=1.0))
    for nm, (x, z) in (("LEG_FL", (0.1, 0.25)), ("LEG_FR", (-0.1, 0.25)), ("LEG_HL", (0.1, -0.24)),
                       ("LEG_HR", (-0.1, -0.24))):
        lg = limb([(x, 0.44, z), (x, 0.2, z + 0.01), (x, 0.0, z)] if d > 0.8 else [(x, 0.44, z), (x, 0.0, z)],
                  [0.042, 0.026, 0.022] if d > 0.8 else [0.04, 0.022], sides=5 if d > 0.8 else 3)
        out.append(tag(lg, SP[nm], ws("legs"), coat=1.0, flip=False))
    tail = ellipsoid(0.13, 0.11, 0.08, 7 if d > 0.8 else 5, 4 if d > 0.8 else 2).translate(0, 0.45, -0.43)
    tail.P[:, 1] -= 0.04 * (np.abs(tail.P[:, 0]) < 0.03) * (tail.P[:, 1] < 0.45)
    out.append(tag(tail, SP["TAIL"], ws("tail"), coat=1.0))
    m = Mesh.merge(out)
    bake_shade(m, 0.0, 0.8, low=0.6, down=0.8)
    return m


# =====================================================================
# Описание юнитов
# =====================================================================

KOK = KOKAND_ATLAS
KIP = KIPCHAK_ATLAS

ROBE = dict(torso="torso0", skirt="skirt0", sleeve="sleeve0", trousers="trousers0", sash="sash0", robe_var=True)
# сарбоз: камзул цвета стороны (торс) поверх халата природной краски — пятно стороны на плечах и спине
SARBOZ = dict(ROBE, hat="turban", flask=True, weapon="musket", item="ramrod", hem=0.4, side_torso=1.0, chest_ring=True)
JOOKER = dict(ROBE, hat="kalpak", weapon="sword", item="shield", hem=0.46, cape="cloak", chest_ring=True)
MALCHY = dict(ROBE, hat="kalpak", weapon="staff", item="sack", hem=0.5, cuff_side=True, hem_side=True)

UNITS = {
    "kok_sarboz": ("infantry", KOK, SARBOZ),
    "kok_sarboz_banner": ("infantry", KOK, dict(SARBOZ, weapon="banner_kokand", item=None, flask=False, back="musket",
                                                 lean=True)),
    "kok_yuzboshi": ("rider", KOK, dict(ROBE, torso="torsoX", skirt="skirtX", sleeve="sleeveX", robe_var=True,
                                         hat="turban", hat_region="hatx", hat_variant=False, weapon="saber",
                                         coat="coat0", cuff_side=True,
                                         caparison=dict(region="saddlecloth", z0=-0.66, z1=0.46, hem=0.92))),
    "kip_sayisker": ("rider", KIP, dict(ROBE, torso="torsoX", skirt="skirtX", hat="helmet", weapon="lance",
                                        item="shield", caparison=dict(region="caparison", hem=0.86))),
    "kip_sayisker_banner": ("rider", KIP, dict(ROBE, torso="torsoX", skirt="skirtX", hat="helmet",
                                               weapon="banner_kipchak", item="shield",
                                               caparison=dict(region="caparison", hem=0.86))),
    "kip_kolbashchy": ("rider", KIP, dict(ROBE, torso="torsoX", skirt="skirtX", sleeve="sleeveX", hat="helmet_plume",
                                          weapon="mace", bulk=1.1, fur_collar=True, cloak="saddlecloth", coat="coat2",
                                          coat_mask=0.0, caparison=dict(region="saddlecloth", hem=0.78))),
    "kip_jooker": ("infantry", KIP, JOOKER),
    "kip_malchy": ("work", KIP, MALCHY),
    "kok_dehqon": ("work", None, {}),
    "sheep": ("sheep", ANIMALS_ATLAS, {}),
    "horse": ("horse", ANIMALS_ATLAS, {}),
}

LOD_DETAIL = 0.5


def build(uid, d):
    kind, A, spec = UNITS[uid]
    if kind == "work":
        import gen_units_work as W   # работники с инструментами: kip_malchy, kok_dehqon
        return W.build_dehqon(d) if uid == "kok_dehqon" else W.build_malchy(d)
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
    only = [a for a in argv if not a.startswith("--")]
    if "--no-tex" not in argv:
        import gen_units_work as W
        for fn, name in ((build_kokand, "kokand_units"), (build_kipchak, "kipchak_units"), (build_animals, "animals"),
                         (W.build_dehqon_atlas, "kokand_dehqon")):
            p = os.path.join(OUT_TEX, name + ".png")
            fn(p)
            ensure_import(p, PNG_IMPORT)
            print("атлас", os.path.relpath(p, ROOT))
    write_skeleton_include(os.path.join(ROOT, "shaders/include/crowd_skeletons.gdshaderinc"))
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
