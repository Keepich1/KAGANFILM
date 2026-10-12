"""Укрепления кыпчаков (ТЗ 6, 11.6): жыгач чеп (частокол), дарбаза (ворота), күзөт мунарасы
(сторожевая башня) и мунара, свёрнутая в арбу.

JOBS: имя → функция(lod) → узлы [(имя, Mesh, вид[, начало узла])], groups (родители узлов).
У каждого — стройка <имя>_site и руины <имя>_ruin (руины звена и ворот — пролом: завал,
через который можно пройти).

Соглашения: метры, Y вверх, фасад (сторона врага) в +Z, начало — центр основания.
Звено частокола вытянуто по X (3.4 × 1.2), соседние звенья заходят друг на друга на 0.4 м
(шаг 3.0 м): брёвна стоят через 1/3 м и продолжаются у соседа ровно с тем же шагом,
вал сходит на нет только на последних 0.2 м — стык без щели и без провала.
"""
from __future__ import annotations

import math

import numpy as np

import gen_camp_kit as G
import gen_camp_props as P
import gen_camp_yurt as Y
import meshkit as K
from gen_kipchak2_kit import (char, felt_sheet, felt_wrap, finish, lashing, local, log_post, q, scorch,
                              stake_line)
from meshkit import Mesh

CHEP_PITCH = 3.0          # шаг звеньев частокола (3.4 м длина − 0.4 м нахлёст)
CHEP_LOGS = 9             # брёвен на шаг
CHEP_H = 2.75             # высота бревна до затёса


# ================================================================ вал

def berm(x0, x1, width, height, lod=0, taper=0.2, region="earth", z0=0.0):
    """Земляной вал вдоль X: поперёк — горб, на концах сходит на нет за taper метров."""
    zs = [-1.0, -0.5, 0.0, 0.5, 1.0] if lod == 0 else [-1.0, 0.0, 1.0]
    hs = {-1.0: 0.0, -0.5: 0.72, 0.0: 1.0, 0.5: 0.72, 1.0: 0.0}
    xs = [x0, x0 + taper, x1 - taper, x1]
    P_, UV, F = [], [], []
    cols = len(zs)
    for i, x in enumerate(xs):
        k = 0.0 if i in (0, 3) else 1.0
        for j, s in enumerate(zs):
            P_.append((x, height * hs[s] * k - 0.03, z0 + s * width / 2))
            UV.append((0.22 + 0.56 * (x - x0) / (x1 - x0), 0.3 + 0.4 * (s + 1) / 2))
    for i in range(len(xs) - 1):
        for j in range(cols - 1):
            a = i * cols + j
            b = a + cols
            F += [(a, a + 1, b + 1), (a, b + 1, b)]
    m = Mesh(P_, F, None, UV)
    if m.N[:, 1].mean() < 0:
        m.flip()
    m.smooth()
    G.to_region(m, region)
    return G.shade(m, lambda p: 0.5 + 0.3 * np.clip(p[:, 1] / max(height, 1e-6), 0, 1))


# ================================================================ частокол

def _chep_logs(lod, seed=5, h_scale=1.0, xs=None):
    rs = np.random.default_rng(seed)
    out = []
    step = CHEP_PITCH / CHEP_LOGS
    xs = [(k - (CHEP_LOGS - 1) / 2) * step for k in range(CHEP_LOGS)] if xs is None else xs
    for k, x in enumerate(xs):
        r = 0.15 + rs.uniform(-0.015, 0.015)
        h = (CHEP_H + rs.uniform(-0.18, 0.2)) * h_scale
        z = rs.uniform(-0.035, 0.035)
        lean = (rs.uniform(-0.04, 0.04), rs.uniform(-0.05, 0.03))
        out.append((x, z, h, r, lean))
    return out


def chep(lod=0):
    """Жыгач чеп: 9 заострённых брёвен в валу, две связи-жерди с внутренней стороны (−Z),
    киноварные войлочные обмотки на трёх брёвнах (цвет стороны виден сверху)."""
    sides = q(lod, 6, 4)
    parts = [berm(-1.7, 1.7, 1.2, 0.34, lod)]
    for k, (x, z, h, r, lean) in enumerate(_chep_logs(lod)):
        parts.append(G.ground_ao(log_post(x, z, h, r, sides, tip=0.42, seed=k, lean=lean, sink=0.1, simple_tip=True),
                                  0.6, 0.3))
        if lod == 0 and k in (1, 4, 7):
            parts.append(felt_wrap((x + lean[0] * 0.85, h - 0.42, z + lean[1] * 0.85), r, 0.26, 5))
    for y in ((0.95, 2.05) if lod == 0 else (1.5,)):
        parts.append(G.pole((-1.56, y, -0.2), (1.56, y + 0.02, -0.21), 0.065, sides=q(lod, 5, 3), region="pole"))
    return [("Chep", finish(parts), "opaque")]


def chep_site(lod=0):
    """Стройка звена: насыпан вал, вкопаны три бревна, остальные лежат штабелем; разметка."""
    rs = np.random.default_rng(15)
    parts = [berm(-1.7, 1.7, 1.2, 0.22, lod)]
    logs = _chep_logs(lod, h_scale=0.38)
    for k, (x, z, h, r, lean) in enumerate(logs[:3]):
        parts.append(log_post(x, z, h, r, q(lod, 6, 4), tip=0.0, seed=k, sink=0.1))
    for i in range(q(lod, 5, 3)):
        y = 0.17 + (i // 3) * 0.28
        z = -0.9 - (i % 3) * 0.3 + (i // 3) * 0.15
        parts.append(P.log((-1.2 + rs.uniform(-0.1, 0.1), y, z), (1.4 + rs.uniform(-0.1, 0.1), y, z + rs.uniform(-0.05, 0.05)),
                           0.15, lod))
    parts.append(stake_line([(-1.5, 0.75), (1.5, 0.75)], 0.4, lod, closed=False))
    return [("ChepSite", G.ground_ao(finish(parts), 0.3, 0.3), "opaque")]


def chep_ruin(lod=0):
    """Пролом: вал растащен, от брёвен — обломанные пни, два бревна упали наружу поперёк,
    комья земли. Низко — через пролом проходят."""
    rs = np.random.default_rng(25)
    parts = [berm(-1.7, -0.6, 1.2, 0.3, lod, taper=0.2), berm(0.7, 1.7, 1.2, 0.26, lod, taper=0.2)]
    logs = _chep_logs(lod)
    for k in (0, 1, 2, 7, 8):
        x, z, h, r, lean = logs[k]
        hh = rs.uniform(0.35, 0.95) if k not in (0, 8) else rs.uniform(1.6, 2.4)
        st = log_post(x, z, hh, r, q(lod, 6, 4), tip=0.12, seed=k + 40, sink=0.1, simple_tip=True)
        parts.append(char(st, 0.55, top_y=hh, soft=0.5))
    for (a, b) in (((-0.4, 0.12, 0.2), (0.3, 0.13, 2.6)), ((0.5, 0.11, 0.1), (-0.6, 0.12, 2.3))):
        parts.append(char(P.log(a, b, 0.15, lod), 0.6))
    for i in range(q(lod, 4, 2)):
        x, z = rs.uniform(-0.9, 0.9), rs.uniform(-0.5, 1.2)
        parts.append(G.lump(rs.uniform(0.2, 0.35), rs.uniform(0.1, 0.18), rs.uniform(0.18, 0.3), q(lod, 5, 4), 2,
                            "stones" if i % 2 else "earth", seed=200 + i, amount=0.2).translate(x, 0, z))
    return [("ChepRuin", G.ground_ao(finish(parts), 0.3, 0.3), "opaque")]


# ================================================================ дарбаза

GATE_W = 6.4
GATE_PASS = 2.8          # ширина прохода
LEAF_H = 2.9


def _bastion(sx, lod, seed, h_scale=1.0, tips=True, rows=(0.55, -0.55)):
    """Боковой бастион ворот из заострённых брёвен: передний и задний ряд, боковые стенки."""
    rs = np.random.default_rng(seed)
    x_in, x_out = GATE_PASS / 2 + 0.05, GATE_W / 2 - 0.15
    parts = []
    step = 0.33
    n = int(round((x_out - x_in) / step)) + 1
    xs = np.linspace(x_in, x_out, n)
    for zi, z in enumerate(rows):
        for i, x in enumerate(xs):
            h = (3.55 + rs.uniform(-0.12, 0.15) + (0.25 if zi == 0 else 0.0)) * h_scale
            r = 0.16 + rs.uniform(-0.012, 0.012)
            parts.append(G.ground_ao(log_post(sx * x, z, h, r, q(lod, 6, 4), tip=0.45 if tips else 0.0,
                                              seed=seed + zi * 31 + i, lean=(0, rs.uniform(-0.03, 0.03)),
                                              simple_tip=lod > 0), 0.6, 0.3))
    # торцевые стенки (поперёк, по краям)
    for x in (x_in, x_out):
        for z in np.linspace(rows[0] - 0.33, rows[1] + 0.33, 2):
            h = (3.4 + rs.uniform(-0.1, 0.1)) * h_scale
            parts.append(log_post(sx * x, z, h, 0.15, q(lod, 6, 4), tip=0.4 if tips else 0.0, seed=seed + int(z * 100)))
    return parts


def darbaza(lod=0):
    """Дарбаза: два бастиона из заострённых брёвен, над проходом — две балки и помост с
    плетнёвым бруствером, две створки из досок (узел «Door»: Door_L, Door_R с началом в петле),
    щиты с конскими кистями, киноварная кошма над проходом, вымпелы на шестах бастионов."""
    parts = [berm(-GATE_W / 2 - 0.1, -GATE_PASS / 2 + 0.25, 2.2, 0.36, lod),
             berm(GATE_PASS / 2 - 0.25, GATE_W / 2 + 0.1, 2.2, 0.36, lod)]
    for sx in (-1, 1):
        parts += _bastion(sx, lod, 100 + (sx > 0) * 50)
    # мощные столбы проёма (вереи) и балки над проходом
    hp = GATE_PASS / 2
    for sx in (-1, 1):
        for z in (0.55, -0.55):
            parts.append(G.ground_ao(log_post(sx * hp, z, 3.9, 0.2, q(lod, 7, 5), tip=0.0, seed=7 + int(z * 10)), 0.6, 0.3))
    for z, y in ((0.62, 3.25), (-0.62, 3.2)):
        parts.append(P.log((-hp - 0.5, y, z), (hp + 0.5, y + 0.02, z), 0.17, lod))
    # помост над проходом и плетнёвый бруствер спереди
    deck = G.box(GATE_PASS + 0.9, 0.12, 1.35, {"top": "planks", "front": "wood", "back": "wood"})
    parts.append(deck.translate(0, 3.38, 0))
    if lod == 0:
        for z in (0.68,):
            parts.append(P.wattle_panel((-hp - 0.3, 3.45, z), (hp + 0.3, 3.45, z), 0.85, lod))
    else:
        parts.append(G.quad((-hp - 0.3, 3.45, 0.72), (hp + 0.3, 3.45, 0.72), (hp + 0.3, 4.3, 0.72), (-hp - 0.3, 4.3, 0.72),
                            "wattle", uvs=((0, 1), (1.0, 1), (1.0, 0), (0, 0))))
    # киноварная кошма над проходом (свисает с бруствера наружу)
    parts.append(G.quad((-0.75, 2.62, 0.83), (0.75, 2.62, 0.83), (0.75, 3.62, 0.8), (-0.75, 3.62, 0.8), "saddlecloth"))
    # щиты с кистями на бастионах
    for sx in (-1, 1):
        x = sx * (GATE_W / 2 + GATE_PASS / 2) / 2
        sh = Y.shield(0.36, lod).translate(x, 2.25, 0.73)
        parts.append(sh)
        for dx in ((-0.17, 0.17) if lod == 0 else (0.0,)):
            parts.append(Y.tassel(0.5, 0.06, lod).translate(x + dx, 2.0, 0.78))
        parts.append(felt_wrap((sx * hp, 3.0, 0.55), 0.2, 0.3, q(lod, 7, 5)))
    # шесты вымпелов на бастионах
    pole_x = GATE_W / 2 - 0.55
    pen_nodes = []
    for sx, nm in ((-1, "Pennant_L"), (1, "Pennant_R")):
        base = np.array([sx * pole_x, 3.1, -0.0])
        top = base + np.array([0, 2.9, 0])
        parts.append(G.pole(base, top, 0.05, 0.035, sides=q(lod, 5, 4), region="pole"))
        parts.append(G.to_region(K.ellipsoid(0.07, 0.06, 0.07, 6, 3).translate(*top), "brass"))
        pen = P.pennant(1.9, 0.6, q(lod, 10, 5), q(lod, 2, 1)).translate(0.04, top[1] - 0.72, 0)
        origin = (base[0], 0.0, base[2])
        pen_nodes.append((nm, G.white(local(pen.translate(base[0], 0, base[2]), origin)), "cloth", origin))
    # створки: доски вертикально, две поперечины и раскос, железные полосы; начало — петля
    leaves = []
    for sx, nm in ((-1, "Door_L"), (1, "Door_R")):
        lw = GATE_PASS / 2 - 0.08
        hinge = np.array([sx * (hp - 0.02), 0.0, 0.42])
        leaf = _leaf(lw, LEAF_H, lod, sx)
        leaves.append((nm, finish([leaf]), "opaque", tuple(hinge)))
    nodes = [("Darbaza", finish(parts), "opaque")] + leaves + pen_nodes
    return nodes, {"Door": ["Door_L", "Door_R"]}


def _leaf(w, h, lod, sx):
    """Створка в осях петли: от петли (x=0) к середине прохода (x = −sx·w), лицо в +Z."""
    parts = []
    face = G.box(w, h, 0.09, {"front": ("planks", True), "back": ("planks", True), "top": "wood",
                               "left": "wood", "right": "wood"})
    face.translate(-sx * w / 2, 0.06, 0.0)
    parts.append(face)
    for y in ((0.45, h - 0.5) if lod == 0 else (h * 0.5,)):
        bar = G.box(w - 0.06, 0.14, 0.07, {"front": ("bark", True), "top": "bark", "bottom": "bark"})
        parts.append(bar.translate(-sx * w / 2, y, 0.075))
    if lod == 0:
        # раскос
        a = np.array([-sx * 0.1, 0.55, 0.1])
        b = np.array([-sx * (w - 0.1), h - 0.55, 0.1])
        parts.append(G.pole(a, b, 0.05, sides=4, region="bark"))
        # железные полосы-петли и латунные гвозди
        for y in (0.5, h - 0.45):
            st = G.box(0.5, 0.07, 0.02, {"front": "iron", "top": "iron"})
            parts.append(st.translate(-sx * 0.25, y + 0.03, 0.12))
        ring = K.lathe([(0.07, 0.0), (0.085, 0.02), (0.07, 0.04)], 6, 1.0).rotate_x(90).translate(-sx * (w - 0.25), h * 0.48, 0.07)
        parts.append(G.to_region(ring, "brass"))
    return G.shade(Mesh.merge(parts), lambda p: 0.8 + 0.2 * np.clip(p[:, 1] / h, 0, 1))


def darbaza_site(lod=0):
    """Стройка ворот: насыпан вал, вкопаны вереи и угловые брёвна (~1.5 м), створки сколочены
    и лежат, балка и брёвна штабелем."""
    rs = np.random.default_rng(61)
    parts = [berm(-GATE_W / 2 - 0.1, -GATE_PASS / 2 + 0.25, 2.2, 0.24, lod),
             berm(GATE_PASS / 2 - 0.25, GATE_W / 2 + 0.1, 2.2, 0.24, lod)]
    hp = GATE_PASS / 2
    for sx in (-1, 1):
        for z in (0.55, -0.55):
            parts.append(log_post(sx * hp, z, 1.9, 0.2, q(lod, 7, 5), tip=0.0, seed=3))
            parts.append(log_post(sx * (GATE_W / 2 - 0.2), z, 1.25 + rs.uniform(-0.1, 0.2), 0.16, q(lod, 6, 4), tip=0.0,
                                  seed=5 + int(z * 10)))
    leaf = _leaf(hp - 0.08, LEAF_H, lod, 1)
    parts.append(leaf.rotate_x(-90).translate(-0.6, 0.1, -1.3))
    for i in range(q(lod, 6, 3)):
        y = 0.17 + (i // 3) * 0.3
        x = 1.6 + (i % 3) * 0.32
        parts.append(P.log((x, y, -1.4 + rs.uniform(-0.1, 0.1)), (x + rs.uniform(-0.1, 0.1), y, 1.6), 0.16, lod))
    parts.append(P.log((-3.0, 0.17, 1.4), (0.4, 0.18, 1.5), 0.17, lod))
    parts.append(stake_line([(-3.2, 1.2), (-hp, 1.2), (-hp, -1.2), (-3.2, -1.2)], 0.4, lod))
    parts.append(stake_line([(3.2, 1.2), (hp, 1.2), (hp, -1.2), (3.2, -1.2)], 0.4, lod))
    return [("DarbazaSite", G.ground_ao(finish(parts), 0.3, 0.3), "opaque")]


def darbaza_ruin(lod=0):
    """Разбитые ворота: бастионы обломаны до пней, балка рухнула в проход, створка лежит,
    вторая повисла наискось; гарь. Проход завален низко — пройти можно."""
    rs = np.random.default_rng(71)
    parts = [berm(-GATE_W / 2 - 0.1, -GATE_PASS / 2 + 0.25, 2.2, 0.3, lod),
             berm(GATE_PASS / 2 - 0.25, GATE_W / 2 + 0.1, 2.2, 0.3, lod)]
    hp = GATE_PASS / 2
    for sx in (-1, 1):
        x_in, x_out = hp + 0.05, GATE_W / 2 - 0.15
        for zi, z in enumerate((0.55, -0.55)):
            for i, x in enumerate(np.linspace(x_in, x_out, 6)):
                if rs.random() < 0.25:
                    continue
                hh = rs.uniform(0.3, 1.5) if zi == 0 else rs.uniform(0.6, 2.4)
                st = log_post(sx * x, z, hh, 0.16, q(lod, 6, 4), tip=0.1, seed=300 + i + zi * 10 + (sx > 0) * 50, sink=0.1)
                parts.append(char(st, 0.5, top_y=hh, soft=0.6))
        parts.append(char(log_post(sx * hp, -0.55, 2.2 + 0.4 * sx, 0.2, q(lod, 7, 5), tip=0.1, seed=11), 0.55, top_y=2.6))
    # рухнувшая балка поперёк прохода
    parts.append(char(P.log((-hp - 0.6, 0.18, 0.4), (hp + 0.3, 0.55, -0.5), 0.17, lod), 0.5))
    # створки: одна лежит, вторая сорвана наискось
    lf = _leaf(hp - 0.08, LEAF_H, lod, -1)
    parts.append(scorch(lf.rotate_x(-88).translate(0.35, 0.1, 1.2), 3, 0.45))
    lf2 = _leaf(hp - 0.08, LEAF_H, lod, 1)
    parts.append(scorch(lf2.rotate_z(-62).rotate_y(18).translate(hp - 0.1, 0.15, -0.3), 4, 0.45))
    # брёвна раскатились наружу
    for i in range(q(lod, 4, 2)):
        x = rs.uniform(-3.0, 3.0)
        parts.append(char(P.log((x, 0.15, 1.0), (x + rs.uniform(-1.2, 1.2), 0.15, 3.2), 0.16, lod), 0.55))
    for i in range(q(lod, 6, 3)):
        x, z = rs.uniform(-1.2, 1.2), rs.uniform(-0.8, 1.6)
        parts.append(G.lump(rs.uniform(0.2, 0.32), rs.uniform(0.1, 0.18), rs.uniform(0.18, 0.3), q(lod, 6, 4), 2,
                            "stones", seed=400 + i, amount=0.2).translate(x, 0, z))
    return [("DarbazaRuin", G.ground_ao(finish(parts), 0.3, 0.3), "opaque")]


# ================================================================ мунара

MUN_FLOOR = 7.0           # верх настила площадки (ТЗ 11.6: площадка на 7 м)
MUN_BASE = 1.95           # полуширина основания по столбам
MUN_TOP = 1.62            # полуширина у площадки (столбы сходятся внутрь)
MUN_HALF = 2.15           # полуширина настила


def _post_xz(sx, sz, y):
    t = np.clip(y / MUN_FLOOR, 0, 1.3)
    hw = MUN_BASE + (MUN_TOP - MUN_BASE) * t
    return sx * hw, sz * hw


def munara(lod=0):
    """Күзөт мунарасы: четыре столба-бревна, сходящиеся к площадке на 7 м, раскосы крест-накрест
    в два яруса, обвязка, настил из досок, плетнёвый бруствер с киноварной кошмой и щитами,
    войлочная шатровая крыша с киноварным свесом, лестница спереди (+Z), вымпел на макушке
    (узел «Pennant», древко в начале координат — вымпел разворачивается по ветру)."""
    rs = np.random.default_rng(81)
    parts = []
    sides = q(lod, 7, 5)
    Ht = 9.25
    corners = [(-1, -1), (1, -1), (1, 1), (-1, 1)]
    for i, (sx, sz) in enumerate(corners):
        x0, z0 = _post_xz(sx, sz, 0)
        x1, z1 = _post_xz(sx, sz, Ht)
        parts.append(G.ground_ao(G.pole((x0, -0.1, z0), (x1, Ht, z1), 0.19, 0.15, sides=sides, region="bark"), 0.8, 0.35))
        cap = G.disc_uv(0.15, sides, "logend")
        parts.append(cap.translate(x1, Ht, z1))
        # камни у подножия
        for k in range(q(lod, 3, 1)):
            a = rs.uniform(0, 2 * math.pi)
            st = G.lump(rs.uniform(0.2, 0.3), rs.uniform(0.12, 0.2), rs.uniform(0.18, 0.28), q(lod, 6, 4), 2, "stones",
                        seed=i * 10 + k, amount=0.2)
            parts.append(G.ground_ao(st.translate(x0 + 0.3 * math.sin(a), 0, z0 + 0.3 * math.cos(a)), 0.2, 0.35))
    # обвязка (горизонтальные брёвна) и раскосы
    rings = (0.55, 3.7, MUN_FLOOR - 0.25) if lod == 0 else (3.7, MUN_FLOOR - 0.25)
    for y in rings:
        for i in range(4):
            a, b = corners[i], corners[(i + 1) % 4]
            pa = _post_xz(*a, y)
            pb = _post_xz(*b, y)
            parts.append(G.pole((pa[0], y, pa[1]), (pb[0], y, pb[1]), 0.1, sides=q(lod, 5, 4), region="bark"))
    tiers = ((0.55, 3.7), (3.7, MUN_FLOOR - 0.25))
    for y0, y1 in tiers:
        for i in range(4):
            a, b = corners[i], corners[(i + 1) % 4]
            for (c0, y_a), (c1, y_b) in (((a, y0), (b, y1)), ((b, y0), (a, y1))) if lod == 0 else (((a, y0), (b, y1)),):
                pa = _post_xz(*c0, y_a)
                pb = _post_xz(*c1, y_b)
                parts.append(G.pole((pa[0], y_a, pa[1]), (pb[0], y_b, pb[1]), 0.065, sides=q(lod, 4, 3), region="pole"))
    # настил и балки под ним
    floor = G.box(MUN_HALF * 2, 0.16, MUN_HALF * 2, {"top": "planks", "bottom": "planks", "front": "wood",
                                                      "back": "wood", "left": "wood", "right": "wood"})
    parts.append(floor.translate(0, MUN_FLOOR - 0.16, 0))
    # бруствер: плетень по периметру (спереди проём для лестницы), сверху жердь
    hh = 1.05
    edge = MUN_HALF - 0.06
    sides_def = [((-edge, edge), (edge, edge)), ((edge, edge), (edge, -edge)), ((edge, -edge), (-edge, -edge)),
                 ((-edge, -edge), (-edge, edge))]
    for i, (a, b) in enumerate(sides_def):
        pa = np.array([a[0], MUN_FLOOR, a[1]])
        pb = np.array([b[0], MUN_FLOOR, b[1]])
        if i == 2:   # сзади (−Z) — проём лестницы посередине
            mid1 = pa + (pb - pa) * 0.38
            mid2 = pa + (pb - pa) * 0.62
            segs = [(pa, mid1), (mid2, pb)]
        else:
            segs = [(pa, pb)]
        for s0, s1 in segs:
            if lod == 0:
                parts.append(P.wattle_panel(s0, s1, hh, lod))
            else:
                n = np.cross(s1 - s0, [0, 1, 0])
                n = n / np.linalg.norm(n) * 0.0
                parts.append(G.quad(s0, s1, s1 + [0, hh, 0], s0 + [0, hh, 0], "wattle",
                                    uvs=((0, 1), (np.linalg.norm(s1 - s0) / 3, 1), (np.linalg.norm(s1 - s0) / 3, 0), (0, 0)),
                                    two_sided=True))
        parts.append(G.pole(pa + [0, hh + 0.04, 0], pb + [0, hh + 0.04, 0], 0.055, sides=q(lod, 5, 3), region="pole"))
    # киноварные кошмы по брустверу (с трёх сторон) и щиты спереди
    for i, (a, b) in enumerate([sides_def[0], sides_def[1], sides_def[3]]):
        pa = np.array([a[0], MUN_FLOOR, a[1]])
        pb = np.array([b[0], MUN_FLOOR, b[1]])
        mid = (pa + pb) / 2
        d = (pb - pa) / np.linalg.norm(pb - pa)
        out = np.array([-d[2], 0, d[0]]) * 0.09
        c0 = mid - d * 0.55 + out
        c1 = mid + d * 0.55 + out
        parts.append(G.quad(c0 + [0, 0.05, 0], c1 + [0, 0.05, 0], c1 + [0, 1.0, 0], c0 + [0, 1.0, 0], "saddlecloth"))
    for x in (-1.45, 1.45):
        parts.append(Y.shield(0.3, lod).translate(x, MUN_FLOOR + 0.55, edge + 0.12))
    # крыша: четырёхскатный войлочный шатёр (квадратный — сверху не спутать с юртой),
    # свес с киноварным поясом, верёвки по рёбрам
    roof_y = MUN_FLOOR + 2.05
    R_roof = (MUN_HALF + 0.45) * math.sqrt(2.0)
    eave = K.lathe([(R_roof, roof_y - 0.42), (R_roof * 0.97, roof_y)], 4, 1.0, start=45, normals="crease").flat()
    eave.UV[:, 1] = 1.0 - eave.UV[:, 1]
    G.to_region(eave, "eave_ordo")
    eave_in = K.lathe([(R_roof * 0.97, roof_y), (R_roof, roof_y - 0.42)], 4, 1.0, start=45).flat()
    G.to_region(eave_in, "felt_grey")
    top_y = roof_y + 1.75
    cone = K.lathe([(R_roof * 0.97, roof_y), (R_roof * 0.5, roof_y + 1.02), (0.12, top_y)], 4, 1.0, start=45,
                   normals="crease").flat()
    cone.UV[:, 1] = 1.0 - cone.UV[:, 1]
    G.to_region(cone, "felt_white")
    G.shade(cone, lambda p: 0.78 + 0.25 * np.clip((p[:, 1] - roof_y) / 1.75, 0, 1))
    under = K.lathe([(0.12, top_y - 0.1), (R_roof * 0.97, roof_y - 0.02)], 4, 1.0, start=45).flat()
    G.to_region(under, "felt_grey")
    parts += [eave, G.shade(eave_in, lambda p: np.full(len(p), 0.55)), cone, G.shade(under, lambda p: np.full(len(p), 0.5))]
    if lod == 0:
        for k in range(4):
            a = math.radians(45 + 90 * k)
            d = np.array([math.sin(a), 0, math.cos(a)])
            pts = [d * R_roof * 0.98 + (0, roof_y + 0.02, 0), d * R_roof * 0.5 + (0, roof_y + 1.06, 0),
                   d * 0.15 + (0, top_y - 0.02, 0)]
            parts.append(G.path_tube(pts, 0.035, sides=3, region="rope", tile_len=3.0))
    # лестница с внутренней стороны (−Z): от земли к проёму бруствера
    lz0, lz1 = -(MUN_BASE + 0.75), -(MUN_HALF - 0.05)
    rails = []
    for sx in (-0.32, 0.32):
        rails.append(G.pole((sx, -0.05, lz0), (sx, MUN_FLOOR + 0.9, lz1), 0.045, sides=q(lod, 4, 3), region="pole"))
    parts += rails
    n_r = q(lod, 17, 9)
    for k in range(1, n_r):
        t = k / n_r
        y = -0.05 + t * (MUN_FLOOR - 0.05)
        z = lz0 + (lz1 - lz0) * t
        parts.append(G.pole((-0.33, y, z - 0.02), (0.33, y, z - 0.02), 0.03, sides=3, region="wood"))
    # частокол под башней по линии стены (X): башня ставится на стену вместо двух звеньев
    parts.append(berm(-2.85, 2.85, 1.2, 0.34, lod))
    step = CHEP_PITCH / CHEP_LOGS
    xs = [(k - 8) * step for k in range(17)]
    for k, (x, z, h, r, lean) in enumerate(_chep_logs(lod, seed=33, xs=xs)):
        parts.append(G.ground_ao(log_post(x, z, h, r, q(lod, 6, 4), tip=0.42, seed=k + 60, lean=lean, sink=0.1,
                                          simple_tip=True), 0.6, 0.3))
    # латунное яблоко и вымпел на макушке (древко — по оси Y модели)
    top_pole = top_y - 0.05
    parts.append(G.pole((0, top_pole - 0.2, 0), (0, top_pole + 2.1, 0), 0.045, 0.03, sides=q(lod, 5, 4), region="pole"))
    parts.append(G.to_region(K.ellipsoid(0.08, 0.07, 0.08, 6, 3).translate(0, top_pole + 2.12, 0), "brass"))
    pen = P.pennant(2.3, 0.72, q(lod, 12, 6), q(lod, 2, 1)).translate(0.04, top_pole + 2.05 - 0.72 - 0.12, 0)
    return [("Munara", finish(parts), "opaque"), ("Pennant", G.white(pen), "cloth")]


def munara_slots():
    """Метки гарнизона (Slot_1..6) на площадке: (x, y, z, поворот лицом наружу, градусы)."""
    y = MUN_FLOOR
    e = MUN_HALF - 0.55
    return [(-0.95, y, e, 0.0), (0.95, y, e, 0.0), (e, y, 0.0, 90.0), (-e, y, 0.0, -90.0),
            (-0.8, y, -e, 180.0), (0.8, y, -e, 180.0)]


def munara_site(lod=0):
    """Стройка башни (~35% высоты): вкопаны четыре столба до первой обвязки, нижние раскосы,
    приставлена лестница; брёвна, доски и плетни сложены рядом."""
    rs = np.random.default_rng(91)
    parts = []
    corners = [(-1, -1), (1, -1), (1, 1), (-1, 1)]
    for i, (sx, sz) in enumerate(corners):
        x0, z0 = _post_xz(sx, sz, 0)
        hh = 3.35 + rs.uniform(-0.15, 0.2)
        x1, z1 = _post_xz(sx, sz, hh)
        parts.append(G.ground_ao(G.pole((x0, -0.1, z0), (x1, hh, z1), 0.19, 0.17, sides=q(lod, 7, 5), region="bark"), 0.8, 0.35))
        parts.append(G.disc_uv(0.17, q(lod, 7, 5), "logend").translate(x1, hh, z1))
    for i in range(4):
        a, b = corners[i], corners[(i + 1) % 4]
        pa, pb = _post_xz(*a, 0.55), _post_xz(*b, 0.55)
        parts.append(G.pole((pa[0], 0.55, pa[1]), (pb[0], 0.55, pb[1]), 0.1, sides=q(lod, 5, 4), region="bark"))
        if i % 2 == 0:
            pa, pb = _post_xz(*a, 0.55), _post_xz(*b, 3.1)
            parts.append(G.pole((pa[0], 0.55, pa[1]), (pb[0], 3.1, pb[1]), 0.065, sides=q(lod, 4, 3), region="pole"))
    # приставленная лестница
    for sx in (-0.32, 0.32):
        parts.append(G.pole((sx, -0.05, -3.4), (sx, 3.3, -2.0), 0.045, sides=q(lod, 4, 3), region="pole"))
    for k in range(1, q(lod, 8, 4)):
        t = k / q(lod, 8, 4)
        parts.append(G.pole((-0.33, -0.05 + t * 3.35, -3.4 + t * 1.4), (0.33, -0.05 + t * 3.35, -3.4 + t * 1.4), 0.03,
                            sides=3, region="wood"))
    # штабель брёвен, доски, плетни
    for i in range(q(lod, 6, 3)):
        y = 0.18 + (i // 3) * 0.32
        x = 3.0 + (i % 3) * 0.34
        parts.append(P.log((x, y, -2.6), (x + rs.uniform(-0.1, 0.1), y, 2.4), 0.17, lod))
    planks = G.box(1.0, 0.36, 3.0, {"top": "planks", "front": "wood", "back": "wood", "left": ("planks", True),
                                     "right": ("planks", True)})
    parts.append(planks.rotate_y(8).translate(-3.2, 0, 0.2))
    for k in range(q(lod, 2, 1)):
        parts.append(P.wattle_panel((-3.3 + k * 0.15, 0.0, -2.0 - k * 0.12), (-1.0 + k * 0.15, 0.0, -2.2 - k * 0.12), 1.0,
                                    lod, lean=0.35))
    parts.append(stake_line([(-2.5, 2.5), (2.5, 2.5), (2.5, -2.5), (-2.5, -2.5)], 0.4, lod))
    return [("MunaraSite", G.ground_ao(finish(parts), 0.3, 0.3), "opaque")]


def munara_ruin(lod=0):
    """Рухнувшая башня: столбы обломаны (пни 1–2.5 м), один столб лежит, настил съехал
    наискось на землю, войлок крыши тлеет в стороне, раскиданные доски и брёвна."""
    rs = np.random.default_rng(101)
    parts = []
    corners = [(-1, -1), (1, -1), (1, 1), (-1, 1)]
    for i, (sx, sz) in enumerate(corners):
        x0, z0 = _post_xz(sx, sz, 0)
        if i == 2:
            # упавший столб наружу
            parts.append(char(P.log((x0, 0.2, z0), (x0 + 5.6, 0.25, z0 + 3.2), 0.18, lod), 0.5))
            parts.append(char(log_post(x0, z0, 0.6, 0.19, q(lod, 7, 5), tip=0.15, seed=7), 0.5, top_y=0.6))
            continue
        hh = rs.uniform(1.1, 2.6)
        st = log_post(x0, z0, hh, 0.19, q(lod, 7, 5), tip=0.25, seed=30 + i, lean=(sx * 0.1, sz * 0.08))
        parts.append(char(st, 0.45, top_y=hh, soft=1.0))
    # настил съехал: одним краем на земле, другим на обломке
    floor = G.box(MUN_HALF * 1.7, 0.16, MUN_HALF * 1.8, {"top": "planks", "bottom": "planks", "front": "wood",
                                                         "back": "wood", "left": "wood", "right": "wood"})
    parts.append(scorch(floor.rotate_x(-24).rotate_y(12).translate(0.3, 0.75, -0.3), 5, 0.45, 1.2))
    # кусок шатра и обломки бруствера
    parts.append(scorch(felt_sheet(-2.8, 1.6, 1.4, 1.1, 0.35, "felt_white", q(lod, 8, 6), 9, 20), 9, 0.4))
    parts.append(char(P.wattle_panel((1.2, 0.0, 2.6), (3.4, 0.0, 2.2), 0.9, lod, lean=-0.6), 0.5))
    for i in range(q(lod, 7, 3)):
        a = rs.uniform(0, 2 * math.pi)
        r0 = rs.uniform(1.2, 3.4)
        p0 = np.array([r0 * math.sin(a), 0.1, r0 * math.cos(a)])
        p1 = p0 + np.array([rs.uniform(-1.6, 1.6), 0.02, rs.uniform(-1.6, 1.6)])
        parts.append(char(G.pole(p0, p1, rs.uniform(0.05, 0.12), sides=q(lod, 5, 3), region="bark"), 0.55))
    return [("MunaraRuin", G.ground_ao(finish(parts), 0.3, 0.3), "opaque")]


# ================================================================ мунара в арбе

def munara_arba(lod=0):
    """Мунара, свёрнутая в арбу (көч): на арбе вдоль — связка брёвен-столбов (торчат назад),
    сверху доски настила, свёрнутый войлок шатра с киноварным поясом, плетни бруствера
    торчком у бортов, лестница поверх; всё перетянуто верёвками. Оглобли в +Z."""
    parts = []
    R = 0.85
    bed_y = 1.0
    L, W = 2.6, 1.5
    zc = -0.15
    for sx in (-1, 1):
        parts.append(P.wheel(R, lod).translate(sx * (W / 2 + 0.2), R, zc))
    parts.append(G.pole((-(W / 2 + 0.3), R, zc), (W / 2 + 0.3, R, zc), 0.06, sides=q(lod, 6, 4), region="walnut"))
    bed = G.box(W, 0.1, L, {"top": "planks", "front": "wood", "back": "wood", "left": "wood", "right": "wood"})
    parts.append(bed.translate(0, bed_y, zc))
    for sx in (-1, 1):
        for z in ((-L / 2 + 0.08, L / 2 - 0.08) if lod else (-L / 2 + 0.08, 0.0, L / 2 - 0.08)):
            parts.append(G.pole((sx * W / 2, bed_y, zc + z), (sx * W / 2, bed_y + 0.5, zc + z), 0.03, sides=q(lod, 4, 3),
                                region="pole"))
    front = zc + L / 2
    for sx in (-1, 1):
        parts.append(G.pole((sx * 0.5, bed_y - 0.02, zc - L / 2 + 0.3), (sx * 0.36, 0.08, front + 1.9), 0.055, 0.04,
                            sides=q(lod, 5, 4), region="pole"))
    parts.append(G.pole((-0.47, bed_y - 0.25, front + 0.45), (0.47, bed_y - 0.25, front + 0.45), 0.035, sides=4,
                        region="pole"))
    top = bed_y + 0.1
    # связка столбов: 4 бревна (по 2 в ряд, 2 ряда), торчат назад
    rs = np.random.default_rng(111)
    for i, (x, y) in enumerate(((-0.42, 0.19), (0.42, 0.19), (-0.21, 0.52), (0.21, 0.52))):
        a = (x, top + y, zc + L / 2 + 0.25)
        b = (x * 1.05, top + y + rs.uniform(-0.02, 0.04), zc - L / 2 - 2.6 - rs.uniform(0, 0.5))
        parts.append(P.log(a, b, 0.17, lod))
    # доски настила стопкой поверх
    planks = G.box(1.2, 0.22, 2.4, {"top": "planks", "front": "wood", "back": "wood", "left": ("planks", True),
                                     "right": ("planks", True)})
    parts.append(planks.translate(0, top + 0.72, zc - 0.1))
    # свёрнутый войлок шатра (рулон поперёк, киноварный пояс)
    parts.append(P.felt_roll(1.6, 0.3, "koshma", lod).translate(0, top + 1.24, zc + 0.35))
    parts.append(P.felt_roll(1.5, 0.26, "felt_white", lod).translate(0, top + 1.2, zc - 0.45))
    # плетни бруствера торчком у бортов
    for sx in (-1, 1):
        parts.append(P.wattle_panel((sx * (W / 2 + 0.06), bed_y + 0.1, zc - 1.1), (sx * (W / 2 + 0.06), bed_y + 0.1, zc + 1.0),
                                    0.9, lod))
    # лестница поверх (вдоль, торчит назад)
    for sx in (-0.3, 0.3):
        parts.append(G.pole((sx, top + 1.56, zc + 1.1), (sx, top + 1.5, zc - 3.6), 0.04, sides=q(lod, 4, 3), region="pole"))
    for k in range(q(lod, 10, 4)):
        z = zc + 0.9 - k * (4.4 / q(lod, 10, 4))
        parts.append(G.pole((-0.31, top + 1.56, z), (0.31, top + 1.56, z), 0.025, sides=3, region="wood"))
    # латунное яблоко с вымпелом-древком вдоль поклажи
    parts.append(G.pole((0.55, top + 0.95, zc + 1.2), (0.55, top + 0.9, zc - 3.2), 0.035, sides=q(lod, 4, 3), region="pole"))
    for z in (-0.75, 0.6):
        path = [(-W / 2 - 0.02, bed_y + 0.45, zc + z), (-0.62, top + 1.4, zc + z), (0.0, top + 1.62, zc + z),
                (0.62, top + 1.4, zc + z), (W / 2 + 0.02, bed_y + 0.45, zc + z)]
        parts.append(G.path_tube(path, 0.022, sides=q(lod, 4, 3), region="rope", tile_len=4.0))
    return [("MunaraArba", finish(parts), "opaque")]


JOBS = {
    "chep": chep, "chep_site": chep_site, "chep_ruin": chep_ruin,
    "darbaza": darbaza, "darbaza_site": darbaza_site, "darbaza_ruin": darbaza_ruin,
    "munara": munara, "munara_site": munara_site, "munara_ruin": munara_ruin,
    "munara_arba": munara_arba,
}
