"""Раскладка лагеря кыпчаков → scenes/camp/camp.tscn (мировые координаты, CONTRACT §3).

Хан ордосу в (−60, 0, 20), 10 боз үй кольцом 31–44 м (вход в лагерь — на юго-восток,
к полю боя), туг у входа в ставку, короо (−115, 65), жылкы (−25, 90), арбы, костры,
казан, поленницы, кошмы, сёдла, тропы (Decal). Высоту ставит camp.gd (Terrain.height_at).

Двери юрт смотрят примерно на юго-восток: поворот вокруг Y на 45° ± 20°
(локальный +Z модели → направление (sin, cos) в плане).
"""
from __future__ import annotations

import math
import os

import numpy as np

import meshkit as K

C = np.array([-60.0, 0.0, 20.0])  # центр ставки
SEED = 20260412


def bearing(deg, r):
    a = math.radians(deg)
    return C + np.array([r * math.sin(a), 0.0, r * math.cos(a)])


def xform(pos, yaw=0.0, tilt_x=0.0, tilt_z=0.0, scale=1.0):
    M = K.rot("y", yaw) @ K.rot("x", tilt_x) @ K.rot("z", tilt_z) * scale
    v = list(M.flatten()) + list(pos)
    return "Transform3D(" + ", ".join(f"{x:.6g}" for x in v) + ")"


def build(out_path):
    rs = np.random.default_rng(SEED)
    res = {}      # путь → id
    nodes = []    # строки узлов

    def ext(path, typ="PackedScene"):
        if path not in res:
            res[path] = (f"{len(res) + 1}", typ)
        return res[path][0]

    used = set()

    def node(name, parent, typ=None, inst=None, xf=None, props=None):
        key = (parent, name)
        assert key not in used, f"повтор имени узла {key}"
        used.add(key)
        head = f'[node name="{name}"'
        if typ:
            head += f' type="{typ}"'
        head += f' parent="{parent}"' if parent is not None else ""
        if inst:
            head += f' instance=ExtResource("{ext(inst)}")'
        head += "]"
        lines = [head]
        if xf:
            lines.append(f"transform = {xf}")
        for k, v in (props or {}).items():
            lines.append(f"{k} = {v}")
        nodes.append("\n".join(lines) + "\n")

    script = ext("res://scripts/camp/camp.gd", "Script")
    area = ext("res://scripts/camp/camp_area.gd", "Script")
    M = "res://assets/models/kipchak/"
    node("Camp", None, "Node3D", props={"script": f'ExtResource("{script}")'})
    node("Buildings", ".", "Node3D")
    node("Props", ".", "Node3D")
    node("Fires", ".", "Node3D")
    node("Ground", ".", "Node3D")
    node("Markers", ".", "Node3D")

    # ---- ставка хана
    door = np.array([math.sin(math.radians(45)), 0, math.cos(math.radians(45))])
    side = np.array([door[2], 0, -door[0]])  # вправо от входа (к северо-востоку)
    node("Ordo", "Buildings", inst=M + "ordo.glb", xf=xform(C, 45),
         props={"metadata/footprint": "7.5", "metadata/kind": '"ordo"'})
    tug_pos = C + door * 10.5 + side * 3.2
    node("Tug", "Buildings", inst=M + "tug.glb", xf=xform(tug_pos, 20), props={"metadata/footprint": "1.0"})

    # ---- кольцо из 10 боз үй: вход в лагерь — сектор вокруг 45° (юго-восток)
    angles = [78, 108, 139, 170, 202, 233, 264, 296, 328, 359]
    radii = [36, 33, 41, 38, 43, 35, 40, 34, 42, 37]
    tints = ['Color(1, 0.985, 0.95, 1)', 'Color(0.97, 0.95, 0.9, 1)', 'Color(1, 1, 1, 1)',
             'Color(0.94, 0.92, 0.88, 1)', 'Color(1, 0.97, 0.93, 1)', 'Color(0.96, 0.95, 0.93, 1)']
    yurts = []
    for i, (a, r) in enumerate(zip(angles, radii)):
        a2 = a + rs.uniform(-5, 5)
        p = bearing(a2, r + rs.uniform(-2, 2))
        yaw = 45 + rs.uniform(-20, 20)
        sc = rs.uniform(0.93, 1.06)
        node(f"Boz_{i + 1}", "Buildings", inst=M + "boz.glb",
             xf=xform(p, yaw, rs.uniform(-1.0, 1.0), rs.uniform(-1.0, 1.0), sc),
             props={"metadata/footprint": f"{3.6 * sc:.2f}", "metadata/kind": '"boz"',
                    "metadata/tint": tints[i % len(tints)]})
        yurts.append((p, yaw, sc))

    # ---- загоны
    koroo = np.array([-115.0, 0, 65.0])
    k_yaw = math.degrees(math.atan2(C[0] - koroo[0], C[2] - koroo[2]))
    node("Koroo", "Buildings", inst=M + "koroo.glb", xf=xform(koroo, k_yaw), props={"metadata/footprint": "7.5"})
    jylky = np.array([-25.0, 0, 90.0])
    j_yaw = math.degrees(math.atan2(C[0] - jylky[0], C[2] - jylky[2]))
    node("Jylky", "Buildings", inst=M + "jylky.glb", xf=xform(jylky, j_yaw), props={"metadata/footprint": "8.5"})

    # ---- костры: у ставки (общий) и у трёх юрт
    def front_of(i, dist, lateral=0.0):
        p, yaw, sc = yurts[i]
        d = np.array([math.sin(math.radians(yaw)), 0, math.cos(math.radians(yaw))])
        s = np.array([d[2], 0, -d[0]])
        return p + d * (3.5 * sc + dist) + s * lateral

    fires = [C + door * 15.0 - side * 2.5, front_of(1, 3.4, 1.0), front_of(4, 5.5, 1.0), front_of(7, 5.0, 2.0),
             front_of(6, 6.0, -1.0)]
    for i, f in enumerate(fires):
        node(f"Fire_{i + 1}", "Fires", inst="res://scenes/camp/campfire.tscn", xf=xform(f, rs.uniform(0, 360)),
             props=dict({"light_energy": "3.2" if i == 0 else "2.4", "light_range": "11.0" if i == 0 else "8.5"},
                        **({"under_pot": "true"} if i == 1 else {})))
    # казан над вторым костром, без своего кострища (огонь уже есть)
    node("Kazan", "Props", inst=M + "kazan.glb", xf=xform(fires[1], 15))

    # ---- хозяйство у каждой юрты: поленница, кошмы, сёдла, сено, арба
    def beside(i, side_sign, lateral=0.0, back=0.0):
        p, yaw, sc = yurts[i]
        d = np.array([math.sin(math.radians(yaw)), 0, math.cos(math.radians(yaw))])
        sd = np.array([d[2], 0, -d[0]]) * side_sign
        return p + sd * (4.7 * sc + lateral) - d * back, yaw

    household = {
        0: [("woodpile", 1, 0.3, 0.5)],
        1: [("woodpile", -1, 0.3, 0.8)],
        2: [("felt_rolls", -1, 0.6, 1.0), ("hay", 0, 0.0, 5.6)],
        3: [("saddle_rack", -1, 0.4, -0.8), ("woodpile", 1, 0.3, 0.6)],
        4: [("felt_rolls", 1, 0.6, 0.8)],
        5: [("arba", 1, 2.2, 1.5), ("felt_rolls", -1, 0.6, 0.9)],
        6: [("woodpile", 1, 0.3, 0.5)],
        7: [("hay", 0, 0.0, 5.6)],
        8: [("saddle_rack", 1, 0.4, -0.6), ("felt_rolls", -1, 0.6, 1.0)],
        9: [("woodpile", -1, 0.3, 0.6)],
    }
    names = {"woodpile": "Woodpile", "felt_rolls": "FeltRolls", "saddle_rack": "SaddleRack", "hay": "Hay",
             "arba": "Arba"}
    count = {"arba": 0}
    spots = {k: [] for k in names}
    for i, items in household.items():
        for kind, sgn, lat, back in items:
            if sgn == 0:  # за юртой
                p, yaw, sc = yurts[i]
                d = np.array([math.sin(math.radians(yaw)), 0, math.cos(math.radians(yaw))])
                pos = p - d * (3.5 * sc + back * 0.5)
            else:
                pos, yaw = beside(i, sgn, lat, back)
            count[kind] = count.get(kind, 0) + 1
            yaw_k = {"woodpile": 90, "felt_rolls": 0, "saddle_rack": 90, "hay": 0, "arba": 180}[kind]
            sc_k = 0.55 if kind == "hay" else 1.0
            node(f"{names[kind]}_{count[kind]}", "Props", inst=M + kind + ".glb",
                 xf=xform(pos, yaw + yaw_k + rs.uniform(-15, 15), scale=sc_k))
            spots[kind].append(pos)
    wp, fr = spots["woodpile"], spots["felt_rolls"]
    # арбы: одна гружёная у западного края (готова к көчу), вторая у конного двора
    node("Arba_Koch", "Props", inst=M + "arba.glb", xf=xform(bearing(250, 53), 160))
    node("Arba_Jylky", "Props", inst=M + "arba.glb", xf=xform(jylky + np.array([-12.0, 0, -4.0]), 75))
    node("Hay_Koroo", "Props", inst=M + "hay.glb", xf=xform(koroo + np.array([10.5, 0, -4.0]), 30))
    node("Hay_Jylky", "Props", inst=M + "hay.glb", xf=xform(jylky + np.array([10.0, 0, 3.0]), 80))
    node("SaddleRack_Jylky", "Props", inst=M + "saddle_rack.glb", xf=xform(jylky + np.array([-4.0, 0, -9.5]), j_yaw + 5))
    node("SaddleRack_Ordo", "Props", inst=M + "saddle_rack.glb", xf=xform(C + door * 8.5 - side * 6.0, 45 + 70))

    # ---- тропы и вытоптанная земля (Decal: проекция сверху, не красит стены)
    def decal(name, a, b, width, tex="path"):
        a, b = np.asarray(a, float), np.asarray(b, float)
        mid = (a + b) / 2
        d = b - a
        L = float(np.linalg.norm(d))
        yaw = math.degrees(math.atan2(d[0], d[2]))
        size = f"Vector3({width:.2f}, 3.0, {L:.2f})" if tex == "path" else f"Vector3({width:.2f}, 3.0, {width:.2f})"
        node(name, "Ground", "Decal", xf=xform(mid, yaw),
             props={"size": size,
                    "texture_albedo": f'ExtResource("{ext(f"res://assets/textures/kipchak/{tex}_decal.png", "Texture2D")}")',
                    "albedo_mix": ("0.45" if width > 3 else "0.38") if tex == "path" else "0.55",
                    "modulate": "Color(0.8, 0.78, 0.76, 1)" if tex == "path" else "Color(0.86, 0.84, 0.8, 1)",
                    "upper_fade": "0.3", "lower_fade": "0.3", "normal_fade": "0.5",
                    "cull_mask": "1"})

    def path(name, pts, width):
        pts = [np.asarray(p, float) for p in pts]
        for i in range(len(pts) - 1):
            a, b = pts[i], pts[i + 1]
            d = (b - a) / np.linalg.norm(b - a)
            decal(f"{name}_{i + 1}", a - d * width * 0.4, b + d * width * 0.4, width * rs.uniform(0.9, 1.1))

    gate_e = bearing(45, 50)
    path("Path_Entrance", [C + door * 9.0, C + door * 22 + side * 2.0, C + door * 36 - side * 1.0, gate_e,
                           gate_e + door * 14 + side * 3.0], 4.6)
    kd = (koroo - C) / np.linalg.norm(koroo - C)
    kp = np.array([kd[2], 0, -kd[0]])
    path("Path_Koroo", [C + kd * 10, C + kd * 24 + kp * 3.0, C + kd * 40 - kp * 2.0, koroo - kd * 7.0], 3.4)
    jd = (jylky - C) / np.linalg.norm(jylky - C)
    jp = np.array([jd[2], 0, -jd[0]])
    path("Path_Jylky", [C + door * 12.0, C + jd * 30 - jp * 4.0, C + jd * 50 + jp * 2.0, jylky - jd * 6.0], 3.4)
    decal("Trample_Ordo", C + door * 13.0, C + door * 13.0, 26.0, tex="trample")
    # земля загонов: вытоптанные пятна декалями (свет как у земли мира)
    decal("Trample_Koroo", koroo, koroo, 16.0, tex="trample")
    decal("Trample_Koroo_2", koroo + np.array([1.5, 0, -1.0]), koroo + np.array([1.5, 0, -1.0]), 11.0, tex="trample")
    decal("Trample_Jylky", jylky, jylky, 18.0, tex="trample")
    decal("Trample_Jylky_2", jylky + np.array([-2.0, 0, 1.0]), jylky + np.array([-2.0, 0, 1.0]), 12.0, tex="trample")
    for i, f in enumerate(fires[1:]):
        decal(f"Trample_Fire_{i + 2}", f, f, 7.0, tex="trample")
    # у каждой юрты — вытоптанное пятно у двери; тропинки к ставке только у половины юрт,
    # изогнутые, разной ширины, не доходят до центра (не «спицы колеса» на виде сверху)
    for i in range(len(yurts)):
        door_p = front_of(i, 1.5)
        decal(f"Trample_Boz_{i + 1}", door_p, door_p, 9.0 * rs.uniform(0.9, 1.15), tex="trample")
        to_c = C - door_p
        dist = float(np.linalg.norm(to_c))
        to_c /= dist
        perp = np.array([to_c[2], 0, -to_c[0]])
        bend = rs.uniform(-4, 4)
        width = rs.uniform(1.2, 2.4)
        if i % 2 == 1:
            continue
        p1 = door_p + to_c * dist * 0.35 + perp * bend
        p2 = door_p + to_c * dist * 0.62 + perp * bend * 0.4
        path(f"Path_Boz_{i + 1}", [door_p + to_c * 3.0, p1, p2, C + (door_p - C) / dist * 16.0], width)

    # ---- метки для интеграции
    node("SheepPen", "Markers", "Marker3D", xf=xform(koroo, k_yaw),
         props={"script": f'ExtResource("{area}")', "size": "Vector2(12, 12)"})
    node("HorsePen", "Markers", "Marker3D", xf=xform(jylky, j_yaw),
         props={"script": f'ExtResource("{area}")', "size": "Vector2(14, 10)"})
    node("BannerPos", "Markers", "Marker3D", xf=xform(tug_pos, 20))
    node("CampCenter", "Markers", "Marker3D", xf=xform(C, 45))
    node("OrdoDoor", "Markers", "Marker3D", xf=xform(C + door * 8.2, 45))
    for i, f in enumerate(fires):
        node(f"Fire_{i + 1}", "Markers", "Marker3D", xf=xform(f))
    perp = np.array([math.cos(math.radians(45)), 0, -math.sin(math.radians(45))])
    guards = [gate_e + perp * 4.5, gate_e - perp * 4.5, C + door * 11.0 + side * 6.0, C + door * 11.0 - side * 5.5]
    for i, g in enumerate(guards):
        node(f"GuardPost_{i + 1}", "Markers", "Marker3D", xf=xform(g, 45))
    works = [(wp[0], 1.4), (wp[1], 1.4), (wp[2], 1.4), (fires[1], 1.6), (fr[0], 1.2), (fr[1], 1.2),
             (koroo + np.array([10.0, 0, -2.5]), 1.0)]
    for i, (p, off) in enumerate(works):
        node(f"WorkSpot_{i + 1}", "Markers", "Marker3D", xf=xform(p + np.array([off, 0, off * 0.6])))

    head = f"[gd_scene load_steps={len(res) + 1} format=3]\n\n"
    exts = "".join(f'[ext_resource type="{typ}" path="{p}" id="{i}"]\n' for p, (i, typ) in res.items())
    text = head + exts + "\n" + "\n".join(nodes)
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    with open(out_path, "w", encoding="utf-8") as f:
        f.write(text)
    print("  ", out_path, len(nodes), "узлов")
