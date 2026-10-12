"""Сборка моделей лагеря в glb: каждая модель + облегчённая <имя>_lod1.glb (ТЗ 11.5, 11.6).

Все модели ссылаются на один атлас (Material.texture_uri) — один материал на объект;
у вымпела и навеса второй материал того же атласа: вырез по альфе, двусторонний
(в сцене его заменяет shaders/cloth.gdshader).
"""
from __future__ import annotations

import os

from glb import Material, read_glb_stats, write_glb
from meshkit import Mesh

ATLAS_URI = "../../textures/kipchak/atlas.png"
MAT = {
    "opaque": Material("kipchak", texture_uri=ATLAS_URI, roughness=0.9),
    "cutout": Material("kipchak_cutout", texture_uri=ATLAS_URI, roughness=1.0, alpha="MASK", alpha_cutoff=0.5),
    "cloth": Material("kipchak_cloth", texture_uri=ATLAS_URI, roughness=0.95, double_sided=True, alpha="MASK",
                      alpha_cutoff=0.5),
}


def write_model(out_dir, name, nodes):
    """nodes: [(имя узла, Mesh, "opaque" | "cloth"), ...]"""
    gl_nodes = [(n, m, MAT[k]) for n, m, k in nodes if m is not None and m.tris]
    path = os.path.join(out_dir, name + ".glb")
    write_glb(path, gl_nodes)
    return path, sum(m.tris for _, m, _ in gl_nodes)


def build_all(out_dir, only=None):
    import gen_camp_yurt as Y
    import gen_camp_props as P
    jobs = {
        "boz": lambda lod: Y.build(Y.boz_spec(lod)),
        "ordo": lambda lod: Y.build(Y.ordo_spec(lod)),
    }
    jobs.update(P.JOBS)
    for name, fn in jobs.items():
        if only and name not in only:
            continue
        t0 = None
        for lod in (0, 1):
            nodes = fn(lod)
            path, t = write_model(out_dir, name if lod == 0 else name + "_lod1", nodes)
            if lod == 0:
                t0 = t
                st = read_glb_stats(path)
                print(f"  {name:12s} {t:6d} треуг.  размер {st['size']}  мин.Y {st['min'][1]}")
            else:
                print(f"  {name + '_lod1':12s} {t:6d} треуг.  ({t / max(t0, 1):.0%} от LOD0)")
