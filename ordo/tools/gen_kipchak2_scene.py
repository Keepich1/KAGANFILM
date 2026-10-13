"""Сцены-обёртки построек и месторождений → scenes/kipchak2/*.tscn.

Корень — KipchakBuilding (scenes/kipchak2/kipchak_building.gd) или ResourceDeposit
(resource_deposit.gd); метаданные kind, footprint (Vector2, м), side; метки — Marker3D в узле
«Markers» (договор с Кокандом): Slot_N (гарнизон башни, +Z метки — наружу), WorkSpot_N (где
стоят работники), DropOff (куда несут добычу), Spawn (где выходят обученные), Door (вход),
Smoke_N (дым), Pass_In / Pass_Out (проход ворот изнутри / снаружи), Ladder (низ лестницы башни),
Banner (верх древка вымпела).
"""
from __future__ import annotations

import math
import os

import numpy as np

import gen_kipchak2_build as B
import gen_kipchak2_fort as F
import meshkit as K

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
OUT = os.path.join(ROOT, "scenes/kipchak2")
BUILDING = "res://scenes/kipchak2/kipchak_building.gd"
DEPOSIT = "res://scenes/kipchak2/resource_deposit.gd"


def xform(pos, yaw=0.0):
    M = K.rot("y", yaw)
    v = list(M.flatten()) + list(pos)
    return "Transform3D(" + ", ".join(f"{x:.6g}" for x in v) + ")"


def facing(pos, target):
    """Поворот метки лицом (её +Z) к точке target."""
    d = np.asarray(target, float) - np.asarray(pos, float)
    return math.degrees(math.atan2(d[0], d[2]))


def write_scene(name, script, props, meta, markers):
    lines = ["[gd_scene load_steps=2 format=3]", "", f'[ext_resource type="Script" path="{script}" id="1"]', ""]
    root = "".join(p.capitalize() for p in name.split("_"))
    lines.append(f'[node name="{root}" type="Node3D"]')
    lines.append('script = ExtResource("1")')
    for k, v in props.items():
        lines.append(f"{k} = {v}")
    for k, v in meta.items():
        lines.append(f"metadata/{k} = {v}")
    lines.append("")
    if markers:
        lines.append('[node name="Markers" type="Node3D" parent="."]')
        lines.append("")
        for mname, pos, yaw in markers:
            lines.append(f'[node name="{mname}" type="Marker3D" parent="Markers"]')
            lines.append(f"transform = {xform(pos, yaw)}")
            lines.append("")
    path = os.path.join(OUT, name + ".tscn")
    os.makedirs(OUT, exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))
    print("  ", os.path.relpath(path, ROOT), len(markers), "меток")


def v2(x, z):
    return f"Vector2({x:g}, {z:g})"


def build_all():
    kip = '"kipchak"'
    # кен: дым из алачыка, куда несут руду (двуколка, корзины), где стоят у жилы (сзади)
    ax, az = -1.75, -1.35
    write_scene("ken", BUILDING, {"kind": '"ken"'}, {"kind": '"ken"', "footprint": v2(8, 8), "side": kip}, [
        ("Smoke_1", (ax, 3.15, az), 0.0),
        ("Door", (ax + 1.6 * math.sin(math.radians(25)), 0.0, az + 1.6 * math.cos(math.radians(25))), 25.0),
        ("DropOff", (0.9, 0.0, 2.9), 180.0),
        ("Banner", (-3.25, 4.2, 2.95), 0.0),
        ("WorkSpot_1", (1.0, 0.0, -1.4), facing((1.0, 0, -1.4), (1.75, 0, -2.35))),
        ("WorkSpot_2", (2.7, 0.0, -1.3), facing((2.7, 0, -1.3), (1.75, 0, -2.35))),
        ("WorkSpot_3", (-0.3, 0.0, 1.0), facing((-0.3, 0, 1.0), (0.05, 0, 2.35))),
    ])
    jy = B.JOOKER_YURT
    spec = B.jooker_spec(0)
    write_scene("jooker", BUILDING, {"kind": '"jooker"'}, {"kind": '"jooker"', "footprint": v2(12, 10), "side": kip}, [
        ("Door", (jy[0], 0.0, jy[1] + spec.R + 0.3), 0.0),
        ("Spawn", (jy[0], 0.0, jy[1] + spec.R + 1.4), 0.0),
        ("Banner", (-0.45, 6.6, 3.25), 0.0),
        ("Smoke_1", (jy[0], spec.top_y + 0.2, jy[1]), 0.0),
    ])
    ks = B.kurultai_yurt_spec(0)
    write_scene("kurultai", BUILDING, {"kind": '"kurultai"'},
                {"kind": '"kurultai"', "footprint": v2(14, 14), "side": kip},
                [("Door", (0.0, 0.0, 3.1), 0.0), ("Spawn", (0.0, 0.0, 4.6), 0.0),
                 ("Banner", (0.0, B.PAV_PEAK + 1.4, 0.0), 0.0)] +
                [(f"Smoke_{i + 1}", (x, ks.top_y + 0.2, z), 0.0) for i, (x, z) in enumerate(B.KUR_YURTS)])
    slots = [(f"Slot_{i + 1}", (x, y, z), yaw) for i, (x, y, z, yaw) in enumerate(F.munara_slots())]
    write_scene("munara", BUILDING, {"kind": '"munara"'}, {"kind": '"munara"', "footprint": v2(5, 5), "side": kip,
                                                           "platform_height": f"{F.MUN_FLOOR:g}"},
                slots + [("Ladder", (0.0, 0.0, -(F.MUN_BASE + 0.95)), 0.0),
                         ("Banner", (0.0, F.MUN_FLOOR + 2.05 + 1.7 + 2.1, 0.0), 0.0)])
    write_scene("munara_arba", BUILDING, {"kind": '"munara_arba"'},
                {"kind": '"munara_arba"', "footprint": v2(2.4, 7.6), "side": kip}, [])
    write_scene("chep", BUILDING, {"kind": '"chep"'}, {"kind": '"chep"', "footprint": v2(3.4, 1.2), "side": kip,
                                                       "pitch": f"{F.CHEP_PITCH:g}"}, [])
    write_scene("darbaza", BUILDING, {"kind": '"darbaza"'},
                {"kind": '"darbaza"', "footprint": v2(6.4, 2.4), "side": kip, "passage_width": f"{F.GATE_PASS:g}"}, [
                    ("Pass_In", (0.0, 0.0, -1.8), 180.0), ("Pass_Out", (0.0, 0.0, 1.8), 0.0)])
    # месторождения: места работников по кругу лицом к породе
    for kind, rx, rz, n in (("stone", 3.9, 3.4, 6), ("gold", 3.6, 3.3, 6)):
        spots = []
        for i in range(n):
            a = math.radians(360 * i / n + 20)
            p = (rx * math.sin(a), 0.0, rz * math.cos(a))
            spots.append((f"WorkSpot_{i + 1}", p, facing(p, (0, 0, 0))))
        write_scene(f"deposit_{kind}", DEPOSIT, {"kind": f'"{kind}"'},
                    {"kind": f'"deposit_{kind}"', "footprint": v2(2 * rx, 2 * rz), "side": '"neutral"',
                     "amount": "4000" if kind == "stone" else "3000"}, spots)


if __name__ == "__main__":
    build_all()
