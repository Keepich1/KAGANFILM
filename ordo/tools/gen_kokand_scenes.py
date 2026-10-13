"""Сцены-обёртки scenes/kokand/<kind>.tscn: KokandBuilding + модель + метки.

Каждая обёртка: корень Node3D со скриптом scripts/kokand/kokand_building.gd (kind, footprint,
метаданные footprint/kind/side), дочерний «Model» (glb готового здания — для редактора;
скрипт подменяет его по состоянию built/site/ruin и добавляет LOD1) и «Markers» (Marker3D).
Метки берутся из SCENES модулей gen_kokand_fort / gen_kokand_build / gen_kokand_field.
"""
from __future__ import annotations

import math
import os


def _scenes():
    import gen_kokand_build as BU
    import gen_kokand_field as FI
    import gen_kokand_fort as FO
    out = {}
    import gen_kokand_bonus as BO
    for mod in (FO, BU, FI, BO):
        out.update(getattr(mod, "SCENES", {}))
    return out


def _xf(pos, yaw=0.0):
    c, s = math.cos(math.radians(yaw)), math.sin(math.radians(yaw))
    v = [c, 0, s, 0, 1, 0, -s, 0, c] + list(pos)
    return "Transform3D(" + ", ".join(f"{x:.6g}" for x in v) + ")"


def _val(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return f"{v:g}"
    return f'"{v}"'


def build_all(out_dir):
    os.makedirs(out_dir, exist_ok=True)
    for kind, spec in _scenes().items():
        model = spec.get("model", kind)
        fx, fz = spec["footprint"]
        lines = ["[gd_scene load_steps=3 format=3]", "",
                 '[ext_resource type="Script" path="res://scripts/kokand/kokand_building.gd" id="1"]',
                 f'[ext_resource type="PackedScene" path="res://assets/models/kokand/{model}.glb" id="2"]', "",
                 f'[node name="{spec["node"]}" type="Node3D"]', 'script = ExtResource("1")', f'kind = "{kind}"',
                 f"footprint = Vector2({fx:g}, {fz:g})"]
        for k, v in spec.get("props", {}).items():
            lines.append(f"{k} = {_val(v)}")
        lines += [f"metadata/footprint = Vector2({fx:g}, {fz:g})", f'metadata/kind = "{kind}"',
                  'metadata/side = "kokand"']
        for k, v in spec.get("meta", {}).items():
            lines.append(f"metadata/{k} = {_val(v)}")
        lines += ["",
                  '[node name="Model" parent="." instance=ExtResource("2")]', "",
                  '[node name="Markers" type="Node3D" parent="."]', ""]
        for m in spec.get("markers", []):
            name, pos = m[0], m[1]
            meta = dict(m[2]) if len(m) > 2 else {}
            yaw = meta.pop("yaw", 0.0) if meta else 0.0
            lines.append(f'[node name="{name}" type="Marker3D" parent="Markers"]')
            lines.append(f"transform = {_xf(pos, yaw)}")
            for k, v in (meta or {}).items():
                lines.append(f"metadata/{k} = {_val(v)}")
            lines.append("")
        path = os.path.join(out_dir, kind + ".tscn")
        with open(path, "w", encoding="utf-8") as f:
            f.write("\n".join(lines))
        print("  ", os.path.relpath(path), len(spec.get("markers", [])), "меток")
