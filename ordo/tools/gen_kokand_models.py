"""Сборка моделей Коканда в glb: каждая модель + <имя>_lod1, <имя>_site (стройка),
<имя>_ruin (руины), у каждой — своя облегчённая версия (ТЗ 11.5, 11.6).

Все модели ссылаются на один атлас (Material.texture_uri) — один материал на объект;
второй материал того же атласа — вырез по альфе: «cloth» (знамя, навес: двусторонний,
в сцене — shaders/cloth.gdshader), «cutout» (колосья и хлопок поля).

Узлы с осью вращения (створки ворот Door_L/Door_R, колесо мельницы Wheel) получают
перенос узла (translation) — начало узла на петле или на оси; створки собраны под
пустым узлом «Door» (договор с воротами кыпчаков: darbaza и darvoza устроены одинаково).
glb.py не умеет иерархию и переносы, поэтому правим JSON уже записанного glb (patch_glb).
"""
from __future__ import annotations

import json
import os
import struct

import numpy as np

from glb import Material, read_glb_stats, write_glb
from meshkit import Mesh

ATLAS_URI = "../../textures/kokand/atlas.png"
MAT = {
    "opaque": Material("kokand", texture_uri=ATLAS_URI, roughness=0.9),
    "cutout": Material("kokand_cutout", texture_uri=ATLAS_URI, roughness=1.0, alpha="MASK", alpha_cutoff=0.5,
                       double_sided=True),
    "cloth": Material("kokand_cloth", texture_uri=ATLAS_URI, roughness=0.95, double_sided=True, alpha="MASK",
                      alpha_cutoff=0.5),
}


class Model:
    """Результат генератора: узлы glb и правки иерархии.

    nodes — [(имя, Mesh, вид материала)]; pivots — {имя: (x, y, z)} перенос узла (меш узла
    в его локальных координатах); groups — {родитель: [дети]} пустые узлы-родители.
    """

    def __init__(self, nodes=None, pivots=None, groups=None):
        self.nodes = list(nodes or [])
        self.pivots = dict(pivots or {})
        self.groups = dict(groups or {})

    def add(self, name, mesh, kind="opaque", pivot=None):
        if mesh is None or not len(mesh.F):
            return self
        self.nodes.append((name, mesh, kind))
        if pivot is not None:
            self.pivots[name] = tuple(float(v) for v in pivot)
        return self

    @property
    def tris(self):
        return sum(m.tris for _, m, _ in self.nodes)


def patch_glb(path, pivots=None, groups=None):
    """Переносы узлов и пустые узлы-родители в уже записанном glb (BIN не меняется)."""
    if not pivots and not groups:
        return
    with open(path, "rb") as f:
        data = f.read()
    jlen = struct.unpack_from("<I", data, 12)[0]
    g = json.loads(data[20:20 + jlen])
    rest = data[20 + jlen:]
    nodes = g["nodes"]
    index = {n["name"]: i for i, n in enumerate(nodes)}
    for name, t in (pivots or {}).items():
        if name in index:
            nodes[index[name]]["translation"] = list(t)
    roots = list(g["scenes"][0]["nodes"])
    for parent, kids in (groups or {}).items():
        ids = [index[k] for k in kids if k in index]
        if not ids:
            continue
        nodes.append({"name": parent, "children": ids})
        roots = [r for r in roots if r not in ids] + [len(nodes) - 1]
    g["scenes"][0]["nodes"] = roots
    js = json.dumps(g, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    js += b" " * ((4 - len(js) % 4) % 4)
    total = 12 + 8 + len(js) + len(rest)
    with open(path, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, total))
        f.write(struct.pack("<II", len(js), 0x4E4F534A))
        f.write(js)
        f.write(rest)


def write_model(out_dir, name, model: Model):
    for node_name, m, _ in model.nodes:
        if not m.has_color:
            m.C[:] = 1.0
            m.has_color = True
        if node_name not in model.pivots:
            # ничего ниже земли (обломки руин, повёрнутые куски): ТЗ 11.6
            m.P[:, 1] = np.maximum(m.P[:, 1], -0.03)
    gl_nodes = [(n, m, MAT[k]) for n, m, k in model.nodes if m is not None and m.tris]
    path = os.path.join(out_dir, name + ".glb")
    write_glb(path, gl_nodes)
    patch_glb(path, model.pivots, model.groups)
    return path, model.tris


def jobs():
    import gen_kokand_fort as FO
    import gen_kokand_build as BU
    import gen_kokand_field as FI
    out = {}
    import gen_kokand_bonus as BO
    for mod in (FO, BU, FI, BO):
        out.update(mod.JOBS)
    return out


def build_all(out_dir, only=None):
    """JOBS: имя → {"": fn(lod), "_site": fn(lod), "_ruin": fn(lod), ...}; каждая fn → Model."""
    rows = []
    for name, variants in jobs().items():
        if only and name not in only:
            continue
        for suffix, fn in variants.items():
            full = name + suffix
            t0 = None
            for lod in (0, 1):
                model = fn(lod)
                path, t = write_model(out_dir, full if lod == 0 else full + "_lod1", model)
                if lod == 0:
                    t0 = t
                    st = read_glb_stats(path)
                    print(f"  {full:16s} {t:6d} треуг.  размер {st['size']}  мин.Y {st['min'][1]}")
                else:
                    print(f"  {full + '_lod1':16s} {t:6d} треуг.  ({t / max(t0, 1):.0%} от LOD0)")
                rows.append((full if lod == 0 else full + "_lod1", t))
    return rows


def merged(parts) -> Mesh:
    return Mesh.merge([p for p in parts if p is not None])
