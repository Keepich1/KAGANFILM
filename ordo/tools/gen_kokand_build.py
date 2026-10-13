"""Здания Коканда (ТЗ 5.2, 11.6): урда, уй, тегирмон, омбор, казарма, отхона, тўпхона —
с облегчёнными версиями, стройкой (_site) и руинами (_ruin).

Фасад и вход — в +Z, начало координат — центр основания на уровне земли, размеры в плане
по ТЗ 11.6. Метки (дверь, места работы, дым, появление нанятых) — в SCENES, их ставит
обёртка scenes/kokand/<kind>.tscn.
"""
from __future__ import annotations

import math

import numpy as np

import gen_kokand_fort as FO
import gen_kokand_kit as G
import gen_kokand_parts as PT
import gen_kokand_ruins as R
import meshkit as K
from gen_kokand_atlas import PORTAL, arch_curve
from gen_kokand_models import Model
from meshkit import Mesh

q = PT.q


def _finish(m: Mesh, seed=0, grime=0.06) -> Mesh:
    return G.grime(m, grime, seed=seed) if grime else m


# ================================================================ урда — ставка хана

URDA = dict(T=7.6, TR=1.4, WALL_H=4.7, WALL_T=0.9, HALL=(-7.0, 7.0, -7.9, -2.0), HALL_H=6.0, DOME_R=2.9,
            IWAN_Z=1.2, IWAN_H=5.0)


def urda(lod=0):
    """Урда 18×18: дворец-цитадель. Стены с изразцовым поясом и скруглёнными зубцами, круглые
    угловые башни с бирюзовыми куполами, высокий портал-пештак с нишей и резной дверью
    (рисунок «portal» совпадает с аркой), зал с большим бирюзовым куполом и золотым навершием,
    айван на резных ореховых колоннах, двор с хаузом, знамя на портале. Её видно как центр."""
    U = URDA
    T, TR, WH, WT = U["T"], U["TR"], U["WALL_H"], U["WALL_T"]
    parts = []
    wall_kw = dict(region="brick", plinth=0.8, band=(WH - 0.4, WH), merlons=(1.0, 0.5, 0.62, 0.36), lod=lod)
    zo = 9.0 - WT / 2    # ось внешних стен
    # передняя стена: два куска по бокам портала; задняя и боковые — от башни до башни
    parts.append(FO_place(PT.wall_run(-T + TR * 0.7, -3.6, WT, WH, **wall_kw), 0.0, zo))
    parts.append(FO_place(PT.wall_run(3.6, T - TR * 0.7, WT, WH, **wall_kw), 0.0, zo))
    parts.append(FO_place(PT.wall_run(-T + TR * 0.7, T - TR * 0.7, WT, WH, **wall_kw), 180.0, -zo))
    parts.append(FO_place(PT.wall_run(-T + TR * 0.7, T - TR * 0.7, WT, WH, **wall_kw), 90.0, zo, rot_axis="x"))
    parts.append(FO_place(PT.wall_run(-T + TR * 0.7, T - TR * 0.7, WT, WH, **wall_kw), -90.0, -zo, rot_axis="x"))
    # угловые башни
    for sx in (-1, 1):
        for sz in (-1, 1):
            tw = PT.round_tower(TR, 6.0, plinth=0.8, band=(5.6, 6.0), merlons=7, cupola=True, lod=lod,
                                seed=int(sx * 3 + sz * 5 + 10))
            parts.append(tw.translate(sx * T, 0, sz * T))
    parts.append(_portal(lod))
    hall = _hall(lod)
    parts.append(hall)
    # айван перед залом
    parts.append(PT.iwan(-6.0, 6.0, U["HALL"][3], U["IWAN_Z"], U["IWAN_H"], 6, lod))
    # боковые худжры вдоль стен двора
    for sx in (-1, 1):
        x0, x1 = (6.25, 8.0) if sx > 0 else (-8.0, -6.25)
        blk = PT.clay_block(x0, x1, -1.8, 7.2, 3.6, region="clay", footing=0.3, over=(0.0, 0.0, 0.0, 0.0), lod=lod,
                            sides=("left",) if sx > 0 else ("right",), beam_side=None)
        parts.append(blk)
        face_x = x0 if sx > 0 else x1
        for k, zz in enumerate((-0.6, 1.6, 3.8, 6.0)):
            item = PT.door(0.95, 2.0) if k % 2 == 0 else PT.window(0.9, 0.9, 1.0)
            parts.append(item.rotate_y(-90 * sx).translate(face_x, 0, zz))
    # двор: мощение и хауз
    court = PT.ground_patch(-6.2, 6.2, U["IWAN_Z"], 7.2, "brick", y=0.02, shade_k=0.6, tile=(1.6, 0.8))
    parts.append(_hauz(lod))
    body = Mesh.merge(parts)
    model = Model().add("Urda", body)
    model.add("Ground", court)
    model.add("Water", _hauz_water())
    pole, flag = FO.banner_pole((0.0, PORTAL["h"], 7.75), 4.2, 2.6, 1.7, lod)
    model.add("Pole", pole)
    model.add("Banner", flag, "cloth")
    for k, sx in enumerate((-1, 1)):
        p2, f2 = FO.banner_pole((sx * T, 6.0 + 0.55 + 0.75 * 1.35 + 0.5, -T), 2.2, 1.4, 0.95, lod, finial=False)
        model.add(f"Pole_{k + 2}", p2)
        model.add(f"Banner_{k + 2}", f2, "cloth")
    return model


def FO_place(m: Mesh, yaw, offset, rot_axis="z"):
    """Стена, построенная вдоль X, поворачивается на yaw и сдвигается на offset по своей нормали."""
    m.rotate_y(yaw)
    if rot_axis == "z":
        return m.translate(0, 0, offset)
    return m.translate(offset, 0, 0)


def _portal(lod=0):
    """Пештак: лицевая грань с проёмом арки (рисунок «portal»), ниша со стрельчатым бирюзовым
    сводом, резная дверь и решётка над ней, бока и зад кирпичом, гульдасты по углам."""
    P = PORTAL
    W, H, aw, hs, ha = P["w"], P["h"], P["aw"], P["hs"], P["ha"]
    zf, zb, zn = 9.0, 7.2, 7.95     # лицо, зад, дно ниши
    parts = []
    curve = arch_curve(aw, hs, ha, q(lod, 16, 8))
    bottom = [(-W / 2, 0.0), (-aw - 1e-3, 0.0)] + [(x, y) for x, y in curve] + [(aw + 1e-3, 0.0), (W / 2, 0.0)]
    front = G.face((0, 0, zf), (1, 0, 0), (0, 1, 0), -W / 2, W / 2, "portal", (W, H), 0.0, H, bottom=bottom,
                   off=(W / 2, 0.0))
    parts.append(G.shade(front, 1.0))
    # бока и зад пештака
    for s, reg in (("left", "brick"), ("right", "brick")):
        parts.append(G.box_face(s, -W / 2, W / 2, zb, zf, 0, 0.8, "plinth", tile=(3.2, None), v_span=(0, 0.8)))
        parts.append(G.box_face(s, -W / 2, W / 2, zb, zf, 0.8, H - 0.6, reg))
        parts.append(G.box_face(s, -W / 2, W / 2, zb, zf, H - 0.6, H, "tileband", tile=(3.2, None)))
    parts.append(G.box_face("back", -W / 2, W / 2, zb, zf, 0, H - 0.6, "brick"))
    parts.append(G.box_face("back", -W / 2, W / 2, zb, zf, H - 0.6, H, "tileband", tile=(3.2, None)))
    parts.append(G.box_face("top", -W / 2, W / 2, zb, zf, 0, H, "brick"))
    # ниша: стены, свод, дно с дверью
    for sx in (-1, 1):
        side = "right" if sx < 0 else "left"   # стена ниши смотрит внутрь проёма
        x = sx * aw
        parts.append(G.box_face(side, x if sx > 0 else -W, W if sx > 0 else x, zn, zf, 0, hs, "clay"))
    vz = FO.vault(curve, zn, zf, "dome_tile")
    parts.append(G.shade(vz, 0.9))
    back = G.face((0, 0, zn), (1, 0, 0), (0, 1, 0), -aw, aw, "clay", None, 0.0, ha, top=[(x, y) for x, y in curve])
    parts.append(G.shade(back, 1.15))
    parts.append(PT.door(2.0, 3.3, step=True).translate(0, 0, zn))
    parts.append(PT.window(1.8, 1.1, 3.6).translate(0, 0, zn))
    # мелкие зубцы по верху лица
    for i in range(8):
        x = -W / 2 + 0.45 + i * (W - 0.9) / 7
        parts.append(G.merlon(0.4, 0.5, 0.28, "brick", arc_seg=q(lod, 4, 2), back=False, seed=90 + i)
                     .translate(x, H, zf - 0.28))
    m = Mesh.merge(parts)
    G.wall_light(m, H, base=0.74, top=1.04)
    gs = [PT.guldasta(sx * (W / 2 - 0.3), zf - 0.3, H + 1.0, 0.36, lod) for sx in (-1, 1)]
    return Mesh.merge([m] + gs)


def _hall(lod=0):
    U = URDA
    x0, x1, z0, z1 = U["HALL"]
    h = U["HALL_H"]
    blk = PT.brick_block(x0, x1, z0, z1, h, plinth=0.6, band=(h - 0.8, h - 0.4), lod=lod, parapet=0.4)
    parts = [blk]
    # фасад под айваном: дверь и окна
    parts.append(PT.door(1.8, 3.0, step=False).translate(0, 0.35, z1))
    for x in (-4.2, -2.1, 2.1, 4.2):
        parts.append(PT.window(1.0, 1.4, 1.3).translate(x, 0, z1))
    # барабан и купол
    cx, cz = 0.0, (z0 + z1) / 2
    R0 = U["DOME_R"]
    tiles, seg = (6, 4) if lod == 0 else (4, 3)
    drum = [G.lathe_bands([(R0, h), (R0, h + 1.1)], "brick", tiles, seg, tile_h=1.6),
            G.ring_band(R0 + 0.04, R0 + 0.04, h + 1.1, h + 1.5, "band2", tiles, seg)]
    prof = [(R0 + 0.12, 0.0), (R0 + 0.2, 0.55), (R0 + 0.05, 1.35), (R0 * 0.85, 2.2), (R0 * 0.6, 2.95),
            (R0 * 0.32, 3.45), (0.12, 3.75), (0.0, 3.8)]
    if lod:
        prof = [prof[0], prof[2], prof[3], prof[4], prof[5], prof[7]]
    dome = G.dome(prof, "dome_tile", tiles, seg).translate(0, h + 1.5, 0)
    # окна барабана
    wins = []
    for k in range(8 if lod == 0 else 4):
        a = 360.0 * (k + 0.5) / (8 if lod == 0 else 4)
        wins.append(PT.window(0.6, 0.7, h + 0.25, frame=False).translate(0, 0, R0 + 0.01).rotate_y(a))
    # навершие: шар, стержень, полумесяц
    alem = [K.lathe([(0.12, 0.0), (0.2, 0.15), (0.12, 0.3), (0.05, 0.35), (0.14, 0.5), (0.05, 0.65), (0.03, 1.1)],
                    q(lod, 8, 5), 1.0)]
    G.to_region(alem[0], "bronze")
    if lod == 0:
        a = np.linspace(math.radians(200), math.radians(-20), 9)
        pts = [(0.28 * math.cos(t), 1.4 + 0.28 * math.sin(t), 0.0) for t in a]
        alem.append(G.path_tube(pts, 0.04, sides=4, region="bronze", tile_len=1.0))
    alem_m = Mesh.merge(alem).translate(0, h + 1.5 + 3.75, 0)
    dm = Mesh.merge(drum + [dome] + wins + [alem_m]).translate(cx, 0, cz)
    G.grime(dm, 0.05, seed=3)
    parts.append(dm)
    return Mesh.merge(parts)


def _hauz(lod=0):
    """Хауз: каменный бортик вокруг воды посреди двора."""
    x0, x1, z0, z1 = -1.7, 1.7, 3.2, 5.8
    t, h = 0.3, 0.32
    parts = []
    for s, (a0, a1, b0, b1) in (("front", (x0, x1, z1 - t, z1)), ("back", (x0, x1, z0, z0 + t)),
                                 ("left", (x0, x0 + t, z0, z1)), ("right", (x1 - t, x1, z0, z1))):
        parts.append(G.box_face(s, a0, a1, b0, b1, 0, h, "plinth", tile=(3.2, None), v_span=(0, 0.8)))
        inner = {"front": "back", "back": "front", "left": "right", "right": "left"}[s]
        parts.append(G.box_face(inner, a0, a1, b0, b1, 0.1, h, "stones", tile=(1.6, 1.6)))
        parts.append(G.box_face("top", a0, a1, b0, b1, 0, h, "stones", tile=(1.6, 1.6)))
    return Mesh.merge(parts)


def _hauz_water():
    m = G.quad((-1.4, 0.18, 5.5), (1.4, 0.18, 5.5), (1.4, 0.18, 3.5), (-1.4, 0.18, 3.5), "water",
               uvs=((0, 1), (1, 1), (1, 0.4), (0, 0.4)))
    return G.shade(m, 0.85)


def urda_walls():
    T = URDA["T"]
    return [R.Wall((-T, 8.55), (-3.6, 8.55), 4.7, 0.9, "brick"), R.Wall((3.6, 8.55), (T, 8.55), 4.7, 0.9, "brick"),
            R.Wall((T, -8.55), (-T, -8.55), 4.7, 0.9, "brick"), R.Wall((8.55, T), (8.55, -T), 4.7, 0.9, "brick"),
            R.Wall((-8.55, -T), (-8.55, T), 4.7, 0.9, "brick"),
            R.Wall((-3.6, 7.6), (3.6, 7.6), 9.6, 1.6, "brick"),
            R.Wall((-7.0, -2.2), (7.0, -2.2), 6.0, 0.7, "brick"), R.Wall((-7.0, -7.7), (7.0, -7.7), 6.0, 0.7, "brick")]


def urda_site(lod=0):
    T = URDA["T"]
    m = R.site(urda_walls(), lod, seed=101, frac=0.32, scaff=[5, 6, 2],
               round_walls=[(sx * T, sz * T, URDA["TR"], 6.0, "brick") for sx in (-1, 1) for sz in (-1, 1)],
               stacks=[("bricks", -3.0, 3.5, 10), ("bricks", -1.5, 4.2, -5), ("bricks", 2.5, 3.8, 20),
                       ("logs", 3.5, 0.5, 90), ("sacks", -4.5, 1.0, 0), ("stones", 0.5, 1.0, 0),
                       ("ladder", -2.0, 6.2, 0), ("ladder", 4.0, -1.4, 180)])
    return Model().add("Site", m)


def urda_ruin(lod=0):
    T = URDA["T"]
    m = R.ruin(urda_walls(), lod, seed=103, frac=(0.15, 0.45),
               round_walls=[(sx * T, sz * T, URDA["TR"], 6.0, "brick") for sx in (-1, 1) for sz in (-1, 1)],
               roofs=[(-6.0, -2.0, 6.0, 1.2, 5.0)], piles=[(0.0, -5.0, 3.2, 2.4, 1.6), (-4.0, 4.5, 1.6, 1.2, 0.6)],
               beams=6)
    # обломки купола: бирюзовые черепки поверх кучи
    shards = []
    rs = np.random.default_rng(104)
    for i in range(10 if lod == 0 else 4):
        a = rs.uniform(0, 2 * math.pi)
        r = rs.uniform(0.5, 2.8)
        s = rs.uniform(0.35, 0.7)
        sh = G.box(s, 0.12, s * 0.8, {"top": "dome_tile", "front": "brick", "back": "brick", "left": "brick",
                                      "right": "brick"})
        y = max(0.0, 1.4 * (1 - (r / 3.2) ** 2))
        sh.rotate_y(rs.uniform(0, 360)).rotate_x(rs.uniform(-20, 20)).translate(math.cos(a) * r, y, -5.0 + math.sin(a) * r * 0.75)
        shards.append(sh)
    sm = G.shade(Mesh.merge(shards), 0.75)
    return Model().add("Ruin", Mesh.merge([m, sm]))


# ================================================================ уй — дом

def uy(lod=0):
    """Дом 8×8: глиняный дом с плоской крышей и выпусками балок, айван на резных колоннах,
    резная дверь и окно-панжара, дворовая стена из пахсы с воротами под навесиком.
    Варианты двора (узлы Var_1..Var_3; обёртка показывает один): 1 — тандыр и дрова,
    2 — суфа с ковром и виноградный навес, 3 — балахана на крыше и мешки."""
    parts = []
    hx0, hx1, hz0, hz1, hh = -3.8, 3.8, -3.8, -0.8, 3.0
    parts.append(PT.clay_block(hx0, hx1, hz0, hz1, hh, region="clay", footing=0.35, over=(0.35, 0.12, 0.2, 0.2),
                               lod=lod, chimney=(-2.6, -3.0)))
    # лестница на крышу
    parts.append(R.ladder((-3.45, 0.0, -0.35), (-3.45, hh + 0.55, -0.75), 0.45, lod))
    # айван: продолжение крыши вперёд на колоннах
    ax0, ax1, az1 = -0.6, 3.75, 1.0
    for x in ((ax0 + 0.25, (ax0 + ax1) / 2, ax1 - 0.25) if lod == 0 else (ax0 + 0.25, ax1 - 0.25)):
        parts.append(PT.ustun(2.62, lod).translate(x, 0.35, az1 - 0.25))
    parts.append(G.beam((ax0, 2.92, az1 - 0.25), (ax1, 2.92, az1 - 0.25), 0.22, 0.2, "walnut"))
    parts.append(PT.roof_slab(ax0, ax1 + 0.2, -0.45, az1 + 0.15, hh, 0.26, sides=("front", "right"), lod=lod,
                              under=True, ceiling="ceiling"))
    fl = Mesh.merge([G.box_face("top", ax0, ax1, hz1, az1, 0, 0.35, "clay"),
                     G.box_face("front", ax0, ax1, hz1, az1, 0, 0.35, "plinth", tile=(3.2, None), v_span=(0, 0.8)),
                     G.box_face("left", ax0, ax1, hz1, az1, 0, 0.35, "plinth", tile=(3.2, None), v_span=(0, 0.8))])
    parts.append(G.shade(fl, 0.85))
    parts.append(PT.door(1.1, 2.05).translate(1.6, 0.35, hz1))
    parts.append(PT.window(0.9, 0.9, 1.25).translate(0.1, 0, hz1))
    parts.append(PT.window(0.8, 0.8, 1.2).translate(-2.3, 0, hz1))
    # дворовая стена и ворота
    yw = [((-3.9, -0.8), (-3.9, 3.9)), ((3.9, 3.9), (3.9, -0.8)), ((-3.9, 3.9), (-2.45, 3.9)), ((-0.95, 3.9), (3.9, 3.9))]
    for a, b in yw:
        parts.append(PT.yard_wall(a, b, 1.9, 0.32, lod=lod))
    parts.append(PT.gate_canopy(-1.7, 3.9, 1.5, 2.25, lod))
    house = Mesh.merge(parts)
    G.grime(house, 0.06, seed=7)
    ground = PT.ground_patch(-3.74, 3.74, -0.8, 3.74, "earth", shade_k=0.62)
    model = Model().add("Uy", house)
    model.add("Ground", ground)
    # варианты двора
    v1 = [PT.tandyr(lod).translate(2.6, 0, 2.6), R.log_pile(-2.8, 1.2, 90, n=3, L=1.6, r=0.1, lod=lod, seed=3),
          PT.jug(2.0, 3.35, 1.0, lod)]
    model.add("Var_1", Mesh.merge(v1))
    v2 = [PT.carpet_supa(1.9, 2.4, 2.0, 1.4, 0.45), PT.pergola(0.6, 3.4, 1.4, 3.5, 2.3, lod),
          PT.jug(-2.9, 0.0, 1.1, lod), PT.jug(-2.6, 0.2, 0.8, lod)]
    model.add("Var_2", Mesh.merge(v2))
    bal = PT.clay_block(-3.5, -1.2, -3.6, -1.3, 1.9, region="clay", footing=0.0, over=(0.25, 0.1, 0.1, 0.1),
                        lod=lod).translate(0, hh + 0.26, 0)
    bal_win = PT.window(0.9, 0.8, 0.5, frame=True).translate(-2.35, hh + 0.26, -1.3)
    v3 = [bal, bal_win, R.sack_pile(2.4, 2.6, 30, n=5 if lod == 0 else 3, seed=5, lod=lod),
          PT.hay_lump(2.6, -2.6, 0.7, seed=9, lod=lod, y=hh + 0.26)]
    model.add("Var_3", Mesh.merge(v3))
    return model


def uy_walls():
    return [R.Wall((-3.8, -0.8), (3.8, -0.8), 3.0, 0.4, "clay"), R.Wall((3.8, -3.8), (-3.8, -3.8), 3.0, 0.4, "clay"),
            R.Wall((-3.8, -3.8), (-3.8, -0.8), 3.0, 0.4, "clay"), R.Wall((3.8, -0.8), (3.8, -3.8), 3.0, 0.4, "clay"),
            R.Wall((-3.9, 3.9), (3.9, 3.9), 1.9, 0.32, "pakhsa")]


def uy_site(lod=0):
    m = R.site(uy_walls(), lod, seed=111, frac=0.4, scaff=[0],
               stacks=[("logs", 1.5, 2.4, 0), ("bricks", -2.0, 2.2, 10), ("ladder", -1.0, 0.0, 180)])
    return Model().add("Site", m)


def uy_ruin(lod=0):
    m = R.ruin(uy_walls(), lod, seed=113, frac=(0.2, 0.55), roofs=[(-3.8, -3.8, 3.8, -0.8, 3.0)], beams=4)
    return Model().add("Ruin", m)


# ================================================================ тегирмон — мельница

def tegirmon(lod=0):
    """Водяная мельница 9×9: глиняный дом с плоской крышей и надстройкой, арык вдоль +X с
    деревянным лотком, колесо (узел «Wheel», начало на оси, вращается вокруг X), мешки зерна,
    жернова у стены."""
    parts = []
    parts.append(PT.clay_block(-4.2, 2.3, -3.6, 2.4, 3.7, region="clay", footing=0.4, over=(0.35, 0.15, 0.2, 0.2),
                               lod=lod, chimney=(-3.4, 1.4)))
    parts.append(PT.clay_block(-3.4, -1.4, -3.0, -1.0, 1.4, region="clay", footing=0.0, over=(0.2, 0.1, 0.1, 0.1),
                               lod=lod).translate(0, 3.96, 0))
    parts.append(PT.door(1.3, 2.2).translate(-1.2, 0, 2.4))
    parts.append(PT.window(0.8, 0.8, 1.4).translate(1.0, 0, 2.4))
    # арык с берегами и деревянным лотком
    cx0, cx1 = 2.75, 4.15
    bank = []
    for x0, x1 in ((2.4, cx0), (cx1, 4.5)):
        bank.append(G.box_face("top", x0, x1, -4.5, 4.5, 0, 0.3, "earth"))
        bank.append(G.box_face("front", x0, x1, -4.5, 4.5, 0, 0.3, "earth"))
        bank.append(G.box_face("back", x0, x1, -4.5, 4.5, 0, 0.3, "earth"))
    bank.append(G.box_face("right", 2.4, cx0, -4.5, 4.5, 0.08, 0.3, "planks", tile=(2.0, None), v_span=(0, 0.8)))
    bank.append(G.box_face("left", cx1, 4.5, -4.5, 4.5, 0.08, 0.3, "planks", tile=(2.0, None), v_span=(0, 0.8)))
    bank.append(G.box_face("right", cx1, 4.5, -4.5, 4.5, 0.0, 0.3, "earth"))
    parts.append(G.shade(Mesh.merge(bank), 0.8))
    water = G.face((0, 0.1, 0), (1, 0, 0), (0, 0, -1), cx0, cx1, "water", (1.4, 4.5), -4.5, 4.5)
    # лоток над колесом: доски на козлах
    if lod == 0:
        for z in (-3.6, -2.8):
            for x in (cx0 - 0.05, cx1 + 0.05):
                parts.append(G.pole((x, 0.0, z), (x, 0.75, z), 0.05, sides=4, region="bark"))
    parts.append(G.box(1.3, 0.08, 1.8, {"top": "planks", "front": "planks", "left": "planks", "right": "planks",
                                        "bottom": "planks"}).translate(3.45, 0.72, -3.4))
    # жернова у стены и мешки
    for k, (x, z) in enumerate(((-2.0, 2.75), (-0.2, 2.8))):
        st = K.cylinder(0.6, 0.6, 0.22, q(lod, 12, 8), caps=True)
        st.UV = np.column_stack([0.5 + st.P[:, 0] * 0.6, 0.5 + st.P[:, 2] * 0.6 + st.P[:, 1]])
        G.to_region(st, "stones")
        parts.append(st.rotate_x(78 + k * 4).translate(x, 0.6, z))
    parts.append(R.sack_pile(-3.4, 3.4, 15, n=6 if lod == 0 else 3, seed=21, lod=lod))
    parts.append(R.sack_pile(0.9, 3.5, -20, n=4 if lod == 0 else 2, seed=22, lod=lod))
    house = Mesh.merge(parts)
    G.grime(house, 0.06, seed=11)
    model = Model().add("Tegirmon", house)
    model.add("Water", G.shade(water, 0.85))
    # колесо: ось вдоль X, начало узла — на оси
    wh = PT.wheel(1.85, 0.55, lod, spokes=8, paddles=q(lod, 16, 8), region="wood")
    axle = G.pole((-1.25, 0, 0), (0.45, 0, 0), 0.09, sides=q(lod, 6, 4), region="walnut")
    model.add("Wheel", G.shade(Mesh.merge([wh, axle]), 0.9), pivot=(3.45, 1.95, -0.6))
    return model


def tegirmon_walls():
    return [R.Wall((-4.2, 2.4), (2.3, 2.4), 3.7, 0.5, "clay"), R.Wall((2.3, -3.6), (-4.2, -3.6), 3.7, 0.5, "clay"),
            R.Wall((-4.2, -3.6), (-4.2, 2.4), 3.7, 0.5, "clay"), R.Wall((2.3, 2.4), (2.3, -3.6), 3.7, 0.5, "clay")]


def tegirmon_site(lod=0):
    m = R.site(tegirmon_walls(), lod, seed=121, frac=0.38, scaff=[0],
               stacks=[("logs", 3.0, 3.0, 0), ("stones", -3.2, 3.6, 0), ("ladder", 0.0, -4.2, 0)])
    # колесо ещё лежит на земле
    wh = PT.wheel(1.85, 0.55, lod, spokes=8, paddles=0).rotate_z(90).translate(3.2, 0.3, 1.0)
    return Model().add("Site", Mesh.merge([m, wh]))


def tegirmon_ruin(lod=0):
    m = R.ruin(tegirmon_walls(), lod, seed=123, frac=(0.2, 0.5), roofs=[(-4.2, -3.6, 2.3, 2.4, 3.7)], beams=4)
    wh = PT.wheel(1.85, 0.55, lod, spokes=8, paddles=8).rotate_z(70).translate(3.4, 0.6, -0.6)
    G.shade(wh, 0.45)
    return Model().add("Ruin", Mesh.merge([m, wh]))


# ================================================================ омбор — склад

def ombor(lod=0):
    """Склад 9×9: тяжёлые пахсовые стены с наклоном и контрфорсами, плоская крыша, широкие
    ворота под балкой, у входа брёвна, камень, мешки и весы-тарози."""
    parts = []
    x0, x1, z0, z1, h = -4.0, 4.0, -4.2, 1.4, 4.2
    walls = Mesh.merge([G.box_face(s, x0, x1, z0, z1, 0, h, "pakhsa") for s in ("front", "back", "left", "right")])
    G.taper(walls, 0, (z0 + z1) / 2, 0.22, 0, h)
    G.wall_light(walls, h, base=0.72, top=1.04)
    parts.append(walls)
    parts.append(PT.roof_slab(x0 + 0.1, x1 - 0.1, z0 + 0.1, z1 - 0.1, h, 0.3, lod=lod, beam_side="front",
                              under=False))
    # контрфорсы по углам (наклонные)
    for sx in (-1, 1):
        for zz in (z0 + 0.5, z1 - 0.5):
            bt = G.box(0.9, 3.0, 1.0, {"front": "pakhsa", "back": "pakhsa", "left": "pakhsa", "right": "pakhsa",
                                       "top": "pakhsa"})
            G.taper(bt, 0, 0, 0.3, 0, 3.0)
            parts.append(bt.translate(sx * (4.0 + 0.2), 0, zz))
    # ворота: две створки под тяжёлой балкой
    gw, gh = 3.0, 2.9
    for sx, mir in ((-1, False), (1, True)):
        uvs = ((1, 1), (0, 1), (0, 0), (1, 0)) if mir else ((0, 1), (1, 1), (1, 0), (0, 0))
        xa, xb = (-gw / 2, 0.0) if sx < 0 else (0.0, gw / 2)
        parts.append(G.quad((xa, 0.05, z1 + 0.04), (xb, 0.05, z1 + 0.04), (xb, gh, z1 + 0.04), (xa, gh, z1 + 0.04),
                            "gate", uvs=uvs))
    parts.append(G.beam((-gw / 2 - 0.5, gh + 0.15, z1 + 0.15), (gw / 2 + 0.5, gh + 0.15, z1 + 0.15), 0.3, 0.3,
                        "walnut"))
    for sx in (-1, 1):
        parts.append(G.box(0.25, gh, 0.25, {"front": "walnut", "left": "walnut", "right": "walnut"})
                     .translate(sx * (gw / 2 + 0.12), 0, z1 + 0.12))
    # отдушины под крышей
    for x in (-2.6, 2.6):
        parts.append(G.shade(G.quad((x - 0.35, 3.3, z1 + 0.02), (x + 0.35, 3.3, z1 + 0.02), (x + 0.35, 3.55, z1 + 0.02),
                                    (x - 0.35, 3.55, z1 + 0.02), "panjara"), 0.6))
    # у входа: брёвна, камень, мешки, тарози
    parts.append(R.log_pile(-2.7, 3.0, 90, n=6, L=3.0, r=0.14, lod=lod, seed=31))
    parts.append(R.stone_pile(2.9, 3.2, 0.85, n=8, seed=32, lod=lod))
    parts.append(R.sack_pile(1.0, 2.4, -10, n=5 if lod == 0 else 3, seed=33, lod=lod))
    if lod == 0:
        tz = 3.6
        for k in range(3):
            a = math.radians(k * 120 + 20)
            parts.append(G.pole((0.6 + 0.8 * math.cos(a), 0, tz + 0.8 * math.sin(a)), (0.6, 2.4, tz), 0.04, sides=4,
                                region="pole"))
        parts.append(G.pole((-0.2, 2.2, tz), (1.4, 2.2, tz), 0.035, sides=4, region="walnut"))
        parts.append(G.path_tube([(-0.1, 2.2, tz), (-0.1, 1.5, tz)], 0.01, 3, "rope"))
        parts.append(G.path_tube([(1.3, 2.2, tz), (1.3, 1.6, tz)], 0.01, 3, "rope"))
    m = Mesh.merge(parts)
    G.grime(m, 0.06, seed=13)
    ground = PT.ground_patch(-4.4, 4.4, 1.4, 4.4, "earth", shade_k=0.6)
    return Model().add("Ombor", m).add("Ground", ground)


def ombor_walls():
    return [R.Wall((-4.0, 1.4), (4.0, 1.4), 4.2, 0.8, "pakhsa"), R.Wall((4.0, -4.2), (-4.0, -4.2), 4.2, 0.8, "pakhsa"),
            R.Wall((-4.0, -4.2), (-4.0, 1.4), 4.2, 0.8, "pakhsa"), R.Wall((4.0, 1.4), (4.0, -4.2), 4.2, 0.8, "pakhsa")]


def ombor_site(lod=0):
    m = R.site(ombor_walls(), lod, seed=131, frac=0.35, scaff=[0, 3],
               stacks=[("logs", -2.5, 3.2, 90), ("stones", 2.8, 3.4, 0), ("sacks", 0.4, 3.0, 0)])
    return Model().add("Site", m)


def ombor_ruin(lod=0):
    m = R.ruin(ombor_walls(), lod, seed=133, frac=(0.25, 0.6), roofs=[(-4.0, -4.2, 4.0, 1.4, 4.2)], beams=5)
    return Model().add("Ruin", m)


# ================================================================ казарма

def kazarma(lod=0):
    """Казарма 16×12: кирпичное здание с изразцовым поясом и зубцами по фасаду, длинный айван
    на семи резных колоннах, двор за кирпичной оградой с воротами-пилонами, стойки с оружием,
    знамя."""
    parts = []
    parts.append(PT.brick_block(-7.8, 7.8, -5.9, -2.6, 4.6, plinth=0.6, band=(3.7, 4.1), lod=lod, parapet=0.45,
                                merlon_side="front"))
    parts.append(PT.iwan(-7.4, 7.4, -2.6, 0.2, 4.0, 7, lod))
    for k, x in enumerate((-5.5, -3.3, -1.1, 1.1, 3.3, 5.5)):
        item = PT.door(1.1, 2.2, step=False) if k in (1, 4) else PT.window(1.0, 1.2, 1.2)
        parts.append(item.translate(x, 0.35 if k in (1, 4) else 0.0, -2.6))
    parts.append(PT.door(1.4, 2.5, step=False).translate(0.0, 0.35, -2.6))
    # ограда двора: кирпич на цоколе, пояс, ворота-пилоны
    kw = dict(region="brick", plinth=0.5, band=(1.85, 2.15), merlons=(1.1, 0.42, 0.5, 0.28), lod=lod)
    parts.append(PT.run_between((7.85, 5.85), (7.85, -2.6), 0.35, 2.15, **kw))
    parts.append(PT.run_between((-7.85, -2.6), (-7.85, 5.85), 0.35, 2.15, **kw))
    parts.append(PT.run_between((-7.85, 5.85), (-1.9, 5.85), 0.35, 2.15, **kw))
    parts.append(PT.run_between((1.9, 5.85), (7.85, 5.85), 0.35, 2.15, **kw))
    for sx in (-1, 1):
        pil = PT.brick_block(-0.45, 0.45, -0.45, 0.45, 3.1, plinth=0.5, band=(2.5, 2.8), lod=lod)
        parts.append(pil.translate(sx * 1.9, 0, 5.85))
        parts.append(FO.cupola(sx * 1.9, 5.85, 3.1, 0.38, lod, drum_h=0.25))
    parts.append(PT.weapon_rack(7, lod, seed=1).translate(-4.6, 0, 2.6))
    parts.append(PT.weapon_rack(7, lod, seed=2).rotate_y(180).translate(4.6, 0, 2.6))
    if lod == 0:
        # чучело для учения: столб, перекладина, соломенный ком
        parts.append(G.pole((0, 0, 3.0), (0, 1.9, 3.0), 0.06, sides=5, region="bark"))
        parts.append(G.pole((-0.5, 1.5, 3.0), (0.5, 1.5, 3.0), 0.04, sides=4, region="bark"))
        parts.append(G.lump(0.28, 0.4, 0.22, 6, 3, "hay", seed=4).translate(0, 1.3, 3.0))
        parts.append(PT.barrel(0.3, 0.8, lod).translate(6.6, 0, 4.9))
        parts.append(PT.barrel(0.28, 0.75, lod).translate(6.0, 0, 5.2))
    m = Mesh.merge(parts)
    G.grime(m, 0.05, seed=17)
    ground = PT.ground_patch(-7.65, 7.65, 0.2, 5.65, "earth", shade_k=0.6)
    model = Model().add("Kazarma", m).add("Ground", ground)
    pole, flag = FO.banner_pole((-6.9, 0.0, 4.6), 7.2, 2.4, 1.6, lod)
    model.add("Pole", pole)
    model.add("Banner", flag, "cloth")
    return model


def kazarma_walls():
    return [R.Wall((-7.8, -2.6), (7.8, -2.6), 4.6, 0.6, "brick"), R.Wall((7.8, -5.9), (-7.8, -5.9), 4.6, 0.6, "brick"),
            R.Wall((-7.8, -5.9), (-7.8, -2.6), 4.6, 0.6, "brick"), R.Wall((7.8, -2.6), (7.8, -5.9), 4.6, 0.6, "brick"),
            R.Wall((-7.85, 5.85), (-1.9, 5.85), 2.15, 0.35, "brick"), R.Wall((1.9, 5.85), (7.85, 5.85), 2.15, 0.35, "brick"),
            R.Wall((7.85, 5.85), (7.85, -2.6), 2.15, 0.35, "brick"), R.Wall((-7.85, -2.6), (-7.85, 5.85), 2.15, 0.35, "brick")]


def kazarma_site(lod=0):
    m = R.site(kazarma_walls(), lod, seed=141, frac=0.35, scaff=[0, 1],
               stacks=[("bricks", -4.0, 2.0, 0), ("bricks", -2.5, 2.4, 15), ("bricks", 3.0, 2.0, -10),
                       ("logs", 4.5, 3.6, 0), ("ladder", 0.0, -2.0, 180), ("stones", -5.5, 4.0, 0)])
    return Model().add("Site", m)


def kazarma_ruin(lod=0):
    m = R.ruin(kazarma_walls(), lod, seed=143, frac=(0.18, 0.5), roofs=[(-7.4, -2.6, 0.0, 0.2, 4.0),
                                                                         (0.5, -5.9, 7.8, -2.6, 4.6)], beams=6)
    return Model().add("Ruin", m)


# ================================================================ отхона — конюшня

def otxona(lod=0):
    """Конюшня 16×12: длинный навес-стойла (задняя стена из пахсы, односкатная земляная крыша
    на столбах), перегородки и кормушки, сено на крыше, двор за жердевой оградой,
    коновязь, каменная колода с водой, копны сена."""
    parts = []
    x0, x1, zb, zf = -7.8, 7.8, -5.9, -1.4
    hb, hf = 3.5, 3.0
    # задняя и боковые стены
    parts.append(G.box_face("front", x0, x1, zb, zb + 0.5, 0, hb, "pakhsa"))
    parts.append(G.box_face("back", x0, x1, zb, zb + 0.5, 0, hb, "pakhsa"))
    for s, x in (("left", x0), ("right", x1)):
        side = G.box_face(s, x0, x1, zb, zf, 0, hb, "pakhsa",
                          top=[(zb if s == "left" else -zf, hb if s == "left" else hf),
                               (zf if s == "left" else -zb, hf if s == "left" else hb)])
        parts.append(side)
        if s == "left":
            parts.append(G.box_face("right", x0, x0 + 0.4, zb, zf, 0, hf, "pakhsa"))
        else:
            parts.append(G.box_face("left", x1 - 0.4, x1, zb, zf, 0, hf, "pakhsa"))
    walls = Mesh.merge(parts)
    G.wall_light(walls, hb, base=0.72, top=1.03)
    parts = [walls]
    # односкатная крыша: от задней стены вниз к переднему ряду столбов
    yb, yf = hb + 0.05, hf + 0.05
    Vr = np.array([0.0, yf - yb, (zf + 0.4) - (zb - 0.2)])
    Lr = float(np.linalg.norm(Vr))
    top = G.face((0, yb + 0.25, zb - 0.2), (-1, 0, 0), Vr / Lr, -(x1 + 0.2), -(x0 - 0.2), "roof", None, 0, Lr)
    under = G.face((0, yb, zb - 0.2), (1, 0, 0), Vr / Lr, x0 - 0.2, x1 + 0.2, "planks", None, 0, Lr)
    parts.append(G.shade(top, 0.78))
    parts.append(G.shade(under, 0.7))
    parts.append(G.box_face("front", x0 - 0.2, x1 + 0.2, zb, zf + 0.4, yf, yf + 0.25, "wood", tile=(2.0, None),
                            v_span=(yf, yf + 2.0)))
    # столбы и балка по фасаду
    for x in np.linspace(x0 + 0.3, x1 - 0.3, 7):
        parts.append(G.pole((x, 0, zf + 0.1), (x, yf, zf + 0.1), 0.1, 0.09, q(lod, 6, 4), "bark"))
    parts.append(G.beam((x0, yf - 0.1, zf + 0.1), (x1, yf - 0.1, zf + 0.1), 0.22, 0.2, "walnut"))
    # перегородки стойл и кормушки
    for x in np.linspace(x0 + 2.6, x1 - 2.6, 5):
        pt = G.quad((x, 0.0, zb + 0.5), (x, 0.0, zf - 0.6), (x, 1.4, zf - 0.6), (x, 1.4, zb + 0.5), "planks",
                    uvs=((0, 1), (1, 1), (1, 0.3), (0, 0.3)), two_sided=True)
        parts.append(G.shade(pt, 0.8))
    if lod == 0:
        for x in np.linspace(x0 + 1.3, x1 - 1.3, 6):
            parts.append(G.box(1.4, 0.4, 0.5, {"front": "planks", "top": "hay", "left": "planks", "right": "planks"})
                         .translate(x, 0.55, zb + 0.8))
    # сено на крыше
    for k, (x, s) in enumerate(((-5.0, 1.3), (-2.4, 1.0), (4.6, 1.2))):
        z = -4.2
        y = yb + (yf - yb) * ((z - (zb - 0.2)) / ((zf + 0.4) - (zb - 0.2))) + 0.15
        parts.append(PT.hay_lump(x, z, s, seed=40 + k, lod=lod, y=y))
    # двор: жердевая ограда, коновязь, колода, копны
    fence = []
    pts = [(-7.9, -1.2), (-7.9, 5.9), (-2.0, 5.9)], [(2.0, 5.9), (7.9, 5.9), (7.9, -1.2)]
    for poly in pts:
        for i in range(len(poly) - 1):
            a, b = np.array(poly[i]), np.array(poly[i + 1])
            L = np.linalg.norm(b - a)
            n = max(1, int(L / q(lod, 2.0, 4.0)))
            for k in range(n + 1):
                p = a + (b - a) * k / n
                fence.append(G.pole((p[0], 0, p[1]), (p[0], 1.45, p[1]), 0.07, 0.06, q(lod, 5, 4), "bark"))
            for y in ((0.6, 1.25) if lod == 0 else (1.0,)):
                fence.append(G.pole((a[0], y, a[1]), (b[0], y, b[1]), 0.045, sides=q(lod, 5, 3), region="pole"))
    parts.append(G.ground_ao(Mesh.merge(fence), 0.4, 0.3))
    parts.append(PT.hitching_rail(4.5, lod).translate(-3.0, 0, 2.2))
    tr, water = PT.trough(2.0, lod)
    parts.append(tr.translate(4.2, 0, 2.6))
    parts.append(PT.hay_lump(6.2, 4.6, 0.9, seed=51, lod=lod))
    parts.append(PT.hay_lump(5.0, 5.0, 0.6, seed=52, lod=lod))
    # сбруйная и кладовая для ячменя в углу двора, выпуски балок навеса
    parts.append(PT.clay_block(-7.6, -4.4, 2.8, 5.7, 2.8, region="clay", footing=0.3, over=(0.3, 0.1, 0.1, 0.1),
                               lod=lod, sides=("front", "back", "right"), chimney=None))
    parts.append(PT.door(0.9, 1.9).rotate_y(90).translate(-4.4, 0, 4.1))
    parts.append(R.sack_pile(-3.6, 5.0, 10, n=4 if lod == 0 else 2, seed=53, lod=lod))
    if lod == 0:
        for x in np.linspace(x0 + 0.3, x1 - 0.3, 13):
            parts.append(G.pole((x, yf + 0.08, zf - 0.3), (x, yf + 0.04, zf + 0.6), 0.07, 0.07, 5, "pole", caps=True))
        for k, x in enumerate((-1.4, 0.2)):
            # сёдла с чепраками на коновязи
            sd = G.box(0.6, 0.3, 0.75, {"front": "carpet", "back": "carpet", "top": "carpet", "left": "walnut",
                                        "right": "walnut"})
            parts.append(sd.translate(x, 1.05, 2.2))
    if lod == 0:
        parts.append(G.shade(G.quad((-4.4, 1.08, 2.25), (-3.4, 1.08, 2.25), (-3.4, 0.45, 2.3), (-4.4, 0.45, 2.3),
                                    "carpet", two_sided=True), 0.9))
    m = Mesh.merge(parts)
    G.grime(m, 0.05, seed=19)
    ground = PT.ground_patch(-7.8, 7.8, -1.4, 5.8, "earth", shade_k=0.58)
    model = Model().add("Otxona", m).add("Ground", ground)
    model.add("Water", G.shade(water.translate(4.2, 0, 2.6), 0.85))
    return model


def otxona_walls():
    return [R.Wall((7.8, -5.65), (-7.8, -5.65), 3.5, 0.5, "pakhsa"), R.Wall((-7.6, -5.9), (-7.6, -1.4), 3.2, 0.4, "pakhsa"),
            R.Wall((7.6, -1.4), (7.6, -5.9), 3.2, 0.4, "pakhsa")]


def otxona_site(lod=0):
    m = R.site(otxona_walls(), lod, seed=151, frac=0.4, scaff=[0],
               stacks=[("logs", -3.0, 1.5, 0), ("logs", 2.0, 1.5, 0), ("ladder", 5.0, -1.0, 180)])
    parts = [m]
    for x in np.linspace(-7.5, 7.5, 7):
        parts.append(G.pole((x, 0, -1.3), (x, 1.6 + 0.4 * math.sin(x), -1.3), 0.1, 0.09, 5, "bark"))
    return Model().add("Site", Mesh.merge(parts))


def otxona_ruin(lod=0):
    m = R.ruin(otxona_walls(), lod, seed=153, frac=(0.2, 0.55), roofs=[(-7.8, -5.9, 7.8, -1.4, 3.2)], beams=8)
    hay = PT.hay_lump(2.0, 1.0, 0.8, seed=60, lod=lod)
    G.shade(hay, 0.35)
    return Model().add("Ruin", Mesh.merge([m, hay]))


# ================================================================ тўпхона — пушечный двор

def topxona(lod=0):
    """Пушечный двор 14×12: кирпичная мастерская с широкой аркой (внутри жар горна), высокая
    кирпичная труба (дым — метка Smoke_1), плавильная печь под куполом, пушка на лафете,
    пирамиды ядер, бочки пороха, ворот-тренога, низкая ограда с поясом."""
    parts = []
    x0, x1, z0, z1, h = -6.8, 1.2, -5.9, -1.0, 5.0
    blk = PT.brick_block(x0, x1, z0, z1, h, plinth=0.6, band=(4.1, 4.5), lod=lod, parapet=0.4,
                         sides=("back", "left", "right"))
    parts.append(blk)
    # фасад с широкой аркой
    aw, sp, ap = 1.7, 2.5, 3.7
    curve = arch_curve(aw, sp, ap, q(lod, 12, 6))
    cxa = -2.8
    bottom = [(x0, 0.0), (cxa - aw - 1e-3, 0.0)] + [(x + cxa, y) for x, y in curve] + [(cxa + aw + 1e-3, 0.0), (x1, 0.0)]
    fr = [G.face((0, 0, z1), (1, 0, 0), (0, 1, 0), x0, x1, "brick", None, 0.6, 4.1, bottom=[(x, max(y, 0.6))
                                                                                         for x, y in bottom],
                 off=(0, -0.6)),
          G.face((0, 0, z1 + 0.03), (1, 0, 0), (0, 1, 0), x0, x1, "tileband", (3.2, None), 4.1, 4.5),
          G.face((0, 0, z1), (1, 0, 0), (0, 1, 0), x0, x1, "brick", None, 4.5, h + 0.4)]
    for xa, xb in ((x0, cxa - aw), (cxa + aw, x1)):
        fr.append(G.face((0, 0, z1 + 0.04), (1, 0, 0), (0, 1, 0), xa, xb, "plinth", (3.2, None), 0.0, 0.6))
    frm = Mesh.merge(fr)
    G.wall_light(frm, h, base=0.74, top=1.04)
    parts.append(frm)
    parts.append(FO.arch_ribbon(curve, 0.25, z1 + 0.03, "band2", out=1, lod=lod).translate(cxa, 0, 0))
    # ниша мастерской: стены, свод, тёмная глубина, горн с жаром
    zn = z1 - 2.2
    for sx in (-1, 1):
        side = "right" if sx < 0 else "left"
        x = cxa + sx * aw
        parts.append(G.shade(G.box_face(side, x if sx > 0 else x - 1, x + 1 if sx > 0 else x, zn, z1, 0, sp, "brick"), 0.55))
    parts.append(G.shade(FO.vault(curve, zn, z1).translate(cxa, 0, 0), 0.5))
    back = G.face((0, 0, zn), (1, 0, 0), (0, 1, 0), cxa - aw, cxa + aw, "brick", None, 0.0, ap,
                  top=[(x + cxa, y) for x, y in curve])
    parts.append(G.shade(back, 0.4))
    forge = G.box(1.6, 0.9, 0.9, {"front": "brick", "top": "stones", "left": "brick", "right": "brick"})
    parts.append(G.shade(forge.translate(cxa, 0, zn + 0.45), 0.55))
    anvil = G.box(0.5, 0.45, 0.3, {"front": "iron", "top": "iron", "left": "iron", "right": "iron", "back": "iron"})
    parts.append(anvil.translate(cxa + 1.0, 0, z1 - 0.8))
    # труба
    chx, chz = -5.6, -4.8
    ch = G.box(1.3, 6.0, 1.3, {"front": "brick", "back": "brick", "left": "brick", "right": "brick"})
    G.taper(ch, 0, 0, 0.22, 0, 6.0)
    chb = G.box(1.04, 0.35, 1.04, {"front": "tileband", "back": "tileband", "left": "tileband", "right": "tileband"})
    chtop = G.box(1.1, 0.3, 1.1, {"front": "brick", "back": "brick", "left": "brick", "right": "brick", "top": "embers"})
    chm = Mesh.merge([ch, chb.translate(0, 4.6, 0), G.shade(chtop, 0.5).translate(0, 6.0, 0)])
    G.wall_light(chm, 6.3, base=0.85, top=1.0)
    G.shade(chm, lambda P: 1.0 - 0.45 * np.clip((P[:, 1] - 5.0) / 1.3, 0, 1))   # копоть у устья
    parts.append(chm.translate(chx, h, chz))
    # плавильная печь под кирпичным куполом
    fx, fz = 3.6, -3.7
    seg = q(lod, 4, 3)
    furn = [G.lathe_bands([(2.0, 0.0), (2.0, 0.6)], "plinth", 3, seg, v_span=(0, 0.8)),
            G.lathe_bands([(1.9, 0.6), (1.85, 1.9)], "brick", 3, seg, tile_h=1.6),
            G.dome([(1.85, 0.0), (1.8, 0.6), (1.45, 1.35), (0.8, 1.85), (0.0, 2.0)], "brick", 3, seg)
            .translate(0, 1.9, 0)]
    furn.append(G.lathe_bands([(0.35, 3.75), (0.3, 4.6)], "brick", 2, 3, tile_h=1.6))
    fm = Mesh.merge(furn)
    G.wall_light(fm, 4.6, base=0.74, top=1.0)
    G.grime(fm, 0.1, seed=5)
    parts.append(fm.translate(fx, 0, fz))
    # устье печи
    mouth = arch_curve(0.45, 0.5, 0.95, 6)
    mm = G.face((0, 0, 0), (1, 0, 0), (0, 1, 0), -0.45, 0.45, "brick", (0.9, 0.95), 0.0, 0.95,
                top=[(x, y) for x, y in mouth], off=(0.45, 0.0))
    G.shade(mm, 0.3)
    parts.append(mm.translate(fx, 0, fz + 1.93))
    # двор: пушка, ядра, бочки, тренога
    parts.append(PT.cannon(lod).rotate_y(20).translate(-1.6, 0, 2.8))
    parts.append(PT.ball_pyramid(3 if lod == 0 else 2, 0.13, lod).translate(1.2, 0, 3.8))
    parts.append(PT.ball_pyramid(3 if lod == 0 else 2, 0.13, lod).translate(-4.8, 0, 1.6))
    parts.append(PT.barrel(0.32, 0.85, lod).translate(4.6, 0, 1.2))
    parts.append(PT.barrel(0.3, 0.8, lod).translate(5.3, 0, 1.6))
    if lod == 0:
        parts.append(PT.barrel(0.3, 0.8, lod).rotate_z(90).translate(4.8, 0.3, 2.3))
        for k in range(3):
            a = math.radians(k * 120)
            parts.append(G.pole((5.6 + 1.0 * math.cos(a), 0, -0.4 + 1.0 * math.sin(a)), (5.6, 3.2, -0.4), 0.06, sides=4,
                                region="bark"))
        parts.append(G.path_tube([(5.6, 3.2, -0.4), (5.6, 1.2, -0.4)], 0.02, 3, "iron", tile_len=2.0))
        # куча угля
        coal = G.lump(1.1, 0.5, 0.8, 8, 3, "iron", seed=7, amount=0.25)
        parts.append(G.shade(coal, 0.6).translate(-5.6, 0, 3.6))
    # низкая ограда с поясом
    kw = dict(region="brick", plinth=0.45, band=(1.3, 1.6), merlons=None, lod=lod)
    parts.append(PT.run_between((6.9, 5.85), (6.9, -5.9), 0.35, 1.6, **kw))
    parts.append(PT.run_between((-6.9, -1.0), (-6.9, 5.85), 0.35, 1.6, **kw))
    parts.append(PT.run_between((-6.9, 5.85), (-1.8, 5.85), 0.35, 1.6, **kw))
    parts.append(PT.run_between((1.8, 5.85), (6.9, 5.85), 0.35, 1.6, **kw))
    m = Mesh.merge(parts)
    G.grime(m, 0.05, seed=23)
    ground = PT.ground_patch(-6.7, 6.7, -1.0, 5.65, "earth", shade_k=0.55)
    model = Model().add("Topxona", m).add("Ground", ground)
    emb = G.quad((cxa - 0.55, 0.92, zn + 0.92), (cxa + 0.55, 0.92, zn + 0.92), (cxa + 0.55, 0.92, zn + 0.1),
                 (cxa - 0.55, 0.92, zn + 0.1), "embers")
    emb2 = G.face((0, 0, 0.02), (1, 0, 0), (0, 1, 0), -0.38, 0.38, "embers", (0.76, 0.8), 0.05, 0.85,
                  top=[(x, y - 0.06) for x, y in arch_curve(0.38, 0.45, 0.85, 6)], off=(0.38, -0.05))
    model.add("Embers", Mesh.merge([emb, emb2.translate(fx, 0, fz + 1.93)]))
    pole, flag = FO.banner_pole((0.4, h + 0.4, -2.0), 3.4, 2.0, 1.35, lod)
    model.add("Pole", pole)
    model.add("Banner", flag, "cloth")
    return model


def topxona_walls():
    return [R.Wall((-6.8, -1.0), (1.2, -1.0), 5.0, 0.6, "brick"), R.Wall((1.2, -5.9), (-6.8, -5.9), 5.0, 0.6, "brick"),
            R.Wall((-6.8, -5.9), (-6.8, -1.0), 5.0, 0.6, "brick"), R.Wall((1.2, -1.0), (1.2, -5.9), 5.0, 0.6, "brick"),
            R.Wall((6.9, 5.85), (6.9, -5.9), 1.6, 0.35, "brick"), R.Wall((-6.9, 5.85), (-1.8, 5.85), 1.6, 0.35, "brick"),
            R.Wall((1.8, 5.85), (6.9, 5.85), 1.6, 0.35, "brick")]


def topxona_site(lod=0):
    m = R.site(topxona_walls(), lod, seed=161, frac=0.33, scaff=[0],
               round_walls=[(3.6, -3.7, 1.9, 3.9, "brick")],
               stacks=[("bricks", -3.0, 2.0, 0), ("bricks", -1.6, 2.5, 20), ("logs", 3.5, 2.8, 0), ("ladder", -5.5, -0.6, 180)])
    return Model().add("Site", m)


def topxona_ruin(lod=0):
    m = R.ruin(topxona_walls(), lod, seed=163, frac=(0.2, 0.5), roofs=[(-6.8, -5.9, 1.2, -1.0, 5.0)],
               round_walls=[(3.6, -3.7, 1.9, 3.9, "brick")], beams=5)
    can = PT.cannon(lod).rotate_z(25).rotate_y(-30).translate(-1.0, 0.3, 2.6)
    G.shade(can, 0.5)
    # обломок трубы
    ch = G.box(1.2, 2.8, 1.2, {"front": "brick", "back": "brick", "left": "brick", "right": "brick", "top": "rubble"})
    ch.rotate_z(84).translate(-3.2, 0.6, -6.6)
    G.shade(ch, 0.6)
    return Model().add("Ruin", Mesh.merge([m, can, ch]))


# ================================================================ сцены и задания

SCENES = {
    "urda": {"node": "Urda", "footprint": (18, 18),
             "markers": [("Door", (0.0, 0.0, 10.4)), ("Spawn", (3.5, 0.0, 12.5)), ("Banner", (0.0, PORTAL["h"] + 4.2, 7.75)),
                         ("WorkSpot_1", (-4.0, 0.0, 10.6)), ("WorkSpot_2", (4.0, 0.0, 10.6)),
                         ("Smoke_1", (7.1, 3.9, 5.6), {"amount": 8}),
                         ("Fire_1", (0.0, 1.5, -5.0)), ("Fire_2", (-4.5, 1.0, 4.0), {"amount": 14}),
                         ("Fire_3", (5.0, 1.0, -1.0), {"amount": 14})]},
    "uy": {"node": "Uy", "footprint": (8, 8),
           "markers": [("Door", (-1.7, 0.0, 4.6)), ("Smoke_1", (2.6, 1.5, 2.6), {"amount": 6, "variant": 1}),
                       ("Fire_1", (0.0, 1.0, -2.0))]},
    "tegirmon": {"node": "Tegirmon", "footprint": (9, 9),
                 "markers": [("Door", (-1.2, 0.0, 3.4)), ("WorkSpot_1", (-2.6, 0.0, 3.6)), ("WorkSpot_2", (0.2, 0.0, 3.8)),
                             ("Fire_1", (-1.0, 1.0, -0.6))]},
    "ombor": {"node": "Ombor", "footprint": (9, 9),
              "markers": [("Door", (0.0, 0.0, 2.6)), ("WorkSpot_1", (-1.2, 0.0, 2.4)), ("WorkSpot_2", (1.4, 0.0, 3.4)),
                          ("Fire_1", (0.0, 1.2, -1.5))]},
    "kazarma": {"node": "Kazarma", "footprint": (16, 12),
                "markers": [("Door", (0.0, 0.0, 6.6)), ("Spawn", (0.0, 0.0, 7.6)), ("Banner", (-6.9, 7.2, 4.6)),
                            ("Fire_1", (-3.0, 1.2, -4.0)), ("Fire_2", (4.0, 1.0, -4.2), {"amount": 14})]},
    "otxona": {"node": "Otxona", "footprint": (16, 12),
               "markers": [("Door", (0.0, 0.0, 6.6)), ("Spawn", (0.0, 0.0, 7.8)), ("WorkSpot_1", (-1.0, 0.0, 2.8)),
                           ("Fire_1", (-2.0, 1.0, -3.5)), ("Fire_2", (3.5, 1.0, -3.5), {"amount": 14})]},
    "topxona": {"node": "Topxona", "footprint": (14, 12),
                "markers": [("Door", (0.0, 0.0, 6.6)), ("Spawn", (0.0, 0.0, 7.8)), ("WorkSpot_1", (-2.8, 0.0, -0.4)),
                            ("WorkSpot_2", (2.4, 0.0, -1.0)),
                            ("Smoke_1", (-5.6, 11.4, -4.8), {"amount": 22, "dark": True}),
                            ("Smoke_2", (3.6, 4.7, -3.7), {"amount": 10, "dark": True}),
                            ("Fire_1", (-2.5, 1.2, -3.4)), ("Fire_2", (3.6, 1.0, -3.7), {"amount": 14})]},
}

JOBS = {
    "urda": {"": urda, "_site": urda_site, "_ruin": urda_ruin},
    "uy": {"": uy, "_site": uy_site, "_ruin": uy_ruin},
    "tegirmon": {"": tegirmon, "_site": tegirmon_site, "_ruin": tegirmon_ruin},
    "ombor": {"": ombor, "_site": ombor_site, "_ruin": ombor_ruin},
    "kazarma": {"": kazarma, "_site": kazarma_site, "_ruin": kazarma_ruin},
    "otxona": {"": otxona, "_site": otxona_site, "_ruin": otxona_ruin},
    "topxona": {"": topxona, "_site": topxona_site, "_ruin": topxona_ruin},
}
