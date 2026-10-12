"""Запись моделей в .glb (glTF 2.0, двоичный) без сторонних библиотек.

Соглашения ТЗ 11.6: метры, Y вверх, фасад в +Z, начало координат в центре
основания на уровне земли. Текстуры встраиваются в файл (PNG).

    from glb import write_glb, Material
    mat = Material("kipchak", texture="../assets/textures/kipchak_atlas.png")
    write_glb("boz.glb", [("boz", mesh, mat)])

Узел — кортеж (имя, Mesh или список (Mesh, Material), Material или None).
Несколько мешей с одним материалом сливаются в один примитив.

Общий атлас стороны лучше подключать ссылкой, а не встраивать в каждый файл:
    Material("kipchak", texture_uri="../../textures/kipchak/atlas.png")
Godot при импорте возьмёт уже импортированную текстуру проекта (одна на все модели).
"""
from __future__ import annotations

import io
import json
import os
import struct
from dataclasses import dataclass, field

import numpy as np


@dataclass
class Material:
    name: str
    texture: str | bytes | None = None      # путь к PNG или байты PNG — встроить в glb
    texture_uri: str | None = None          # или ссылка на общий атлас стороны (путь от glb)
    color: tuple = (1.0, 1.0, 1.0, 1.0)     # baseColorFactor
    metallic: float = 0.0
    roughness: float = 0.9
    double_sided: bool = False
    alpha: str = "OPAQUE"                   # OPAQUE | MASK | BLEND
    alpha_cutoff: float = 0.5
    extras: dict = field(default_factory=dict)


class _Builder:
    def __init__(self):
        self.bin = bytearray()
        self.views = []
        self.accessors = []

    def _align(self):
        while len(self.bin) % 4:
            self.bin.append(0)

    def view(self, data: bytes, target=None):
        self._align()
        off = len(self.bin)
        self.bin += data
        v = {"buffer": 0, "byteOffset": off, "byteLength": len(data)}
        if target:
            v["target"] = target
        self.views.append(v)
        return len(self.views) - 1

    def accessor(self, arr: np.ndarray, kind: str, target=None, minmax=False, normalized=False):
        arr = np.ascontiguousarray(arr)
        ctype = {np.dtype(np.float32): 5126, np.dtype(np.uint16): 5123,
                 np.dtype(np.uint32): 5125, np.dtype(np.uint8): 5121}[arr.dtype]
        count = arr.shape[0] if kind != "SCALAR" else arr.size
        acc = {"bufferView": self.view(arr.tobytes(), target), "componentType": ctype,
               "count": int(count), "type": kind}
        if normalized:
            acc["normalized"] = True
        if minmax:
            acc["min"] = [float(x) for x in arr.min(axis=0)]
            acc["max"] = [float(x) for x in arr.max(axis=0)]
        self.accessors.append(acc)
        return len(self.accessors) - 1


def _png_bytes(tex) -> bytes:
    if isinstance(tex, (bytes, bytearray)):
        return bytes(tex)
    if hasattr(tex, "save"):  # PIL.Image
        buf = io.BytesIO()
        tex.save(buf, format="PNG")
        return buf.getvalue()
    with open(tex, "rb") as f:
        return f.read()


def write_glb(path: str, nodes, extras: dict | None = None):
    """Записывает .glb. nodes: список (имя, меш(и), материал)."""
    b = _Builder()
    materials, mat_index = [], {}
    images, textures = [], []
    gl_nodes, gl_meshes = [], []

    def material_id(m: Material | None):
        if m is None:
            m = Material("default")
        if m.name in mat_index:
            return mat_index[m.name]
        pbr = {"baseColorFactor": list(m.color), "metallicFactor": m.metallic,
               "roughnessFactor": m.roughness}
        if m.texture_uri is not None:
            # общий атлас: Godot возьмёт уже импортированную текстуру проекта
            images.append({"uri": m.texture_uri, "name": m.name})
            textures.append({"source": len(images) - 1, "sampler": 0})
            pbr["baseColorTexture"] = {"index": len(textures) - 1}
        elif m.texture is not None:
            img = b.view(_png_bytes(m.texture))
            images.append({"bufferView": img, "mimeType": "image/png", "name": m.name})
            textures.append({"source": len(images) - 1, "sampler": 0})
            pbr["baseColorTexture"] = {"index": len(textures) - 1}
        gm = {"name": m.name, "pbrMetallicRoughness": pbr, "doubleSided": m.double_sided,
              "alphaMode": m.alpha}
        if m.alpha == "MASK":
            gm["alphaCutoff"] = m.alpha_cutoff
        if m.extras:
            gm["extras"] = m.extras
        materials.append(gm)
        mat_index[m.name] = len(materials) - 1
        return mat_index[m.name]

    for entry in nodes:
        name, meshes, mat = entry[0], entry[1], entry[2] if len(entry) > 2 else None
        if not isinstance(meshes, (list, tuple)):
            meshes = [(meshes, mat)]
        groups = {}
        for item in meshes:
            m, mm = (item if isinstance(item, tuple) else (item, mat))
            key = mm.name if mm else "default"
            groups.setdefault(key, (mm, []))[1].append(m)
        prims = []
        for key, (mm, ms) in groups.items():
            from meshkit import Mesh  # локальный импорт, чтобы glb.py работал отдельно
            m = Mesh.merge(ms)
            if len(m.F) == 0:
                continue
            attrs = {
                "POSITION": b.accessor(m.P.astype(np.float32), "VEC3", 34962, minmax=True),
                "NORMAL": b.accessor(_unit(m.N).astype(np.float32), "VEC3", 34962),
                "TEXCOORD_0": b.accessor(m.UV.astype(np.float32), "VEC2", 34962),
            }
            if m.has_uv2:
                attrs["TEXCOORD_1"] = b.accessor(m.UV2.astype(np.float32), "VEC2", 34962)
            if m.has_color:
                attrs["COLOR_0"] = b.accessor(m.C.astype(np.float32), "VEC4", 34962)
            idx = m.F.astype(np.uint32 if len(m.P) > 65535 else np.uint16).reshape(-1)
            prims.append({"attributes": attrs,
                          "indices": b.accessor(idx, "SCALAR", 34963),
                          "material": material_id(mm), "mode": 4})
        gl_meshes.append({"name": name, "primitives": prims})
        gl_nodes.append({"name": name, "mesh": len(gl_meshes) - 1})

    gltf = {
        "asset": {"version": "2.0", "generator": "ordo/tools/glb.py"},
        "scene": 0,
        "scenes": [{"name": os.path.splitext(os.path.basename(path))[0],
                    "nodes": list(range(len(gl_nodes)))}],
        "nodes": gl_nodes,
        "meshes": gl_meshes,
        "accessors": b.accessors,
        "bufferViews": b.views,
        "buffers": [{"byteLength": 0}],
    }
    if materials:
        gltf["materials"] = materials
    if images:
        gltf["images"] = images
        gltf["textures"] = textures
        # Повтор по обеим осям, мип-карты, линейная фильтрация
        gltf["samplers"] = [{"magFilter": 9729, "minFilter": 9987, "wrapS": 10497, "wrapT": 10497}]
    if extras:
        gltf["scenes"][0]["extras"] = extras

    b._align()
    gltf["buffers"][0]["byteLength"] = len(b.bin)
    js = json.dumps(gltf, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    js += b" " * ((4 - len(js) % 4) % 4)
    total = 12 + 8 + len(js) + 8 + len(b.bin)
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    with open(path, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, total))
        f.write(struct.pack("<II", len(js), 0x4E4F534A))
        f.write(js)
        f.write(struct.pack("<II", len(b.bin), 0x004E4942))
        f.write(bytes(b.bin))
    return total


def read_glb_stats(path: str) -> dict:
    """Число треугольников, вершин, материалов и габариты — для проверки бюджетов (ТЗ 11.5)."""
    with open(path, "rb") as f:
        data = f.read()
    jlen = struct.unpack_from("<I", data, 12)[0]
    g = json.loads(data[20:20 + jlen])
    tris = verts = 0
    lo, hi = np.full(3, np.inf), np.full(3, -np.inf)
    for mesh in g.get("meshes", []):
        for p in mesh["primitives"]:
            tris += g["accessors"][p["indices"]]["count"] // 3
            pa = g["accessors"][p["attributes"]["POSITION"]]
            verts += pa["count"]
            lo = np.minimum(lo, pa["min"])
            hi = np.maximum(hi, pa["max"])
    return {"triangles": tris, "vertices": verts, "materials": len(g.get("materials", [])),
            "min": lo.round(3).tolist(), "max": hi.round(3).tolist(),
            "size": (hi - lo).round(3).tolist()}


def _unit(n):
    l = np.linalg.norm(n, axis=1, keepdims=True)
    l[l == 0] = 1
    return n / l


if __name__ == "__main__":
    import sys
    for p in sys.argv[1:]:
        print(p, read_glb_stats(p))
