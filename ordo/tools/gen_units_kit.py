"""Общее для генераторов юнитов: скелеты (точки вращения), разметка частей, запись.

Юнит — меш из жёстких частей (ТЗ 11.5, CONTRACT §7):
    UV2.x — номер части (кость толпы), UV2.y — вес вторичного движения
            (ткань знамени, подол, хвост: 0 у крепления → 1 на свободном краю).
    COLOR_0 — маски для шейдера толпы:
        r — нарисованная тень (множитель 0..1),
        g — цвет стороны (не дрожит по варианту, держит узнаваемость),
        b — масть / вариант (смещение по атласу на variant_du по w),
        a — металл (золото, сталь: блик).

Точки вращения частей — константы шейдера: write_skeleton_include() пишет
shaders/include/crowd_skeletons.gdshaderinc из таблиц ниже.
Оси: +Z — вперёд (лицо), +X — левая сторона юнита, Y — вверх (CONTRACT §2).
"""
from __future__ import annotations

import math
import os

import numpy as np

from meshkit import Mesh, loft, tube, ellipsoid, grid, ring
from meshkit import lathe as _lathe_raw

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), ".."))

# ---------------------------------------------------------------- скелеты

# Человек стоя (пехота). Части: номер → имя (для шейдера: H_<ИМЯ>)
HUMAN_PARTS = ["ROOT", "PELVIS", "CHEST", "HEAD", "UARM_L", "FARM_L", "UARM_R", "FARM_R",
               "THIGH_L", "SHIN_L", "THIGH_R", "SHIN_R", "WEAPON", "ITEM", "CLOTH", "SKIRT_L", "SKIRT_R",
               # инструменты работников (tools/gen_units_work.py): видна та, что нужна работе
               "TOOL_AXE", "TOOL_HOE", "TOOL_HAMMER", "TOOL_LOAD"]
HUMAN_PIV = {
    "PELVIS": (0.0, 0.98, 0.0),
    "CHEST": (0.0, 1.06, 0.0),
    "HEAD": (0.0, 1.53, 0.0),
    "SHOULDER_L": (0.205, 1.43, -0.01), "ELBOW_L": (0.245, 1.15, -0.035), "HAND_L": (0.262, 0.87, 0.01),
    "SHOULDER_R": (-0.205, 1.43, -0.01), "ELBOW_R": (-0.245, 1.15, -0.035), "HAND_R": (-0.262, 0.87, 0.01),
    "HIP_L": (0.10, 0.93, 0.0), "KNEE_L": (0.10, 0.51, 0.025), "ANKLE_L": (0.10, 0.085, 0.0),
    "HIP_R": (-0.10, 0.93, 0.0), "KNEE_R": (-0.10, 0.51, 0.025), "ANKLE_R": (-0.10, 0.085, 0.0),
    "SKIRT_L": (0.06, 0.97, 0.0), "SKIRT_R": (-0.06, 0.97, 0.0),
}

# Конь (+ всадник). Ноги коня — две кости: верх от лопатки/тазобедренного сустава,
# низ от запястья/скакательного сустава до копыта.
RIDER_PARTS = ["ROOT", "BODY", "NECK", "HEAD", "FU_L", "FL_L", "FU_R", "FL_R",
               "HU_L", "HL_L", "HU_R", "HL_R", "TAIL",
               "R_PELVIS", "R_TORSO", "R_HEAD", "R_UARM_L", "R_FARM_L", "R_UARM_R", "R_FARM_R",
               "R_WEAPON", "R_ITEM", "R_CLOTH"]
RIDER_OFF = np.array([0.0, 0.64, 0.02])   # сдвиг верхней половины человека в седло
HORSE_PIV = {
    "BODY": (0.0, 1.17, -0.02),
    "NECK": (0.0, 1.40, 0.56),
    "HEAD": (0.0, 1.86, 0.95),
    "F_TOP_L": (0.15, 1.22, 0.50), "F_KNEE_L": (0.15, 0.50, 0.55), "F_HOOF_L": (0.15, 0.0, 0.575),
    "F_TOP_R": (-0.15, 1.22, 0.50), "F_KNEE_R": (-0.15, 0.50, 0.55), "F_HOOF_R": (-0.15, 0.0, 0.575),
    "H_TOP_L": (0.17, 1.25, -0.54), "H_HOCK_L": (0.165, 0.56, -0.70), "H_HOOF_L": (0.165, 0.0, -0.62),
    "H_TOP_R": (-0.17, 1.25, -0.54), "H_HOCK_R": (-0.165, 0.56, -0.70), "H_HOOF_R": (-0.165, 0.0, -0.62),
    "TAIL": (0.0, 1.42, -0.83),
}
for _k in ("PELVIS", "CHEST", "HEAD", "SHOULDER_L", "ELBOW_L", "HAND_L", "SHOULDER_R", "ELBOW_R", "HAND_R"):
    HORSE_PIV["R_" + _k] = tuple(np.array(HUMAN_PIV[_k]) + RIDER_OFF)

SHEEP_PARTS = ["ROOT", "BODY", "HEAD", "LEG_FL", "LEG_FR", "LEG_HL", "LEG_HR", "TAIL"]
SHEEP_PIV = {
    "BODY": (0.0, 0.56, 0.0),
    "HEAD": (0.0, 0.66, 0.36),
    "LEG_FL": (0.10, 0.40, 0.25), "LEG_FR": (-0.10, 0.40, 0.25),
    "LEG_HL": (0.10, 0.40, -0.24), "LEG_HR": (-0.10, 0.40, -0.24),
    "TAIL": (0.0, 0.50, -0.40),
}

# ID частей по имени
HP = {n: i for i, n in enumerate(HUMAN_PARTS)}
RP = {n: i for i, n in enumerate(RIDER_PARTS)}
SP = {n: i for i, n in enumerate(SHEEP_PARTS)}


def v3(p):
    return np.asarray(p, dtype=np.float64)


# ---------------------------------------------------------------- геометрия

def ring_axis(center, axis, rc, rs, k=8, ref=(0.0, 1.0, 0.0), phase=0.0, squash=None):
    """Кольцо k точек вокруг оси axis (для loft вдоль произвольной оси).
    rc — радиус вдоль ref (проекция ref на плоскость кольца), rs — поперёк.
    Порядок точек как у meshkit.ring: нормали loft смотрят наружу."""
    d = v3(axis) / np.linalg.norm(axis)
    ec = v3(ref) - d * np.dot(ref, d)
    ec /= np.linalg.norm(ec)
    es = np.cross(d, ec)
    a = np.radians(phase) + np.linspace(0, 2 * np.pi, k, endpoint=False)
    f = np.ones(k) if squash is None else np.array([squash(t) for t in a])
    return v3(center)[None] + (rc * f * np.cos(a))[:, None] * ec[None] + (rs * f * np.sin(a))[:, None] * es[None]


def lathe(profile, *args, **kw) -> Mesh:
    """meshkit.lathe с наружными гранями при любом направлении профиля.
    (У meshkit.lathe профиль сверху вниз даёт грани внутрь — их отсекает cull_back.)"""
    m = _lathe_raw(profile, *args, **kw)
    p = np.asarray(profile, dtype=np.float64)
    if p[-1, 1] < p[0, 1]:
        m.flip()
    return m


def limb(path, radii, sides=6, cap_end=False):
    """Трубка конечности с нормированной развёрткой: u по кругу, v 0..1 по длине."""
    path = v3(path)
    L = float(np.sum(np.linalg.norm(np.diff(path, axis=0), axis=1)))
    m = tube(path, radii, sides=sides, caps=False, uv_len=1.0 / max(L, 1e-6), roll=180.0)
    if cap_end:
        r_end = np.broadcast_to(radii, (len(path),))[-1]
        d = path[-1] - path[-2]
        d /= np.linalg.norm(d)
        cap = ellipsoid(r_end, r_end, r_end, sides, 2, y_from=0.0, y_to=1.0).align(path[-1], path[-1] + d)
        cap.UV[:, 1] = 1.0
        m = Mesh.merge([m, cap])
    return m


def seg(base, d):
    """Число сегментов по детализации d (1 — LOD0, ~0.5 — LOD1)."""
    return max(3, int(round(base * d)))


def two_sided(m: Mesh) -> Mesh:
    """Двусторонняя ткань: копия с обратными гранями (шейдер толпы режет задние грани)."""
    b = m.copy()
    b.flip()
    return Mesh.merge([m, b])


# ---------------------------------------------------------------- атлас

class Atlas:
    """Разметка атласа: имя области → прямоугольник в пикселях (x0, y0, w, h)."""

    def __init__(self, name, w, h, regions):
        self.name, self.w, self.h, self.regions = name, w, h, regions

    def rect(self, region, inset=4):
        x, y, w, h = self.regions[region]
        return ((x + inset) / self.w, (y + inset) / self.h, (x + w - inset) / self.w, (y + h - inset) / self.h)

    def sub(self, region, fx0, fy0, fx1, fy1, inset=3):
        """Часть области (доли 0..1 от её прямоугольника)."""
        x, y, w, h = self.regions[region]
        return ((x + fx0 * w + inset) / self.w, (y + fy0 * h + inset) / self.h,
                (x + fx1 * w - inset) / self.w, (y + fy1 * h - inset) / self.h)

    @property
    def uri(self):
        return f"../../textures/units/{self.name}.png"


def tag(m: Mesh, part, rect, shade=1.0, side=0.0, coat=0.0, metal=0.0, flip=True, weight=None) -> Mesh:
    """Помечает часть: номер кости, область атласа, маски цвета.
    flip=True — верх картинки = верх детали (для lathe/loft снизу вверх)."""
    u0, v0, u1, v1 = rect
    m.UV = np.clip(m.UV, 0.0, 1.0)
    m.map_uv((u0, v1, u1, v0) if flip else (u0, v0, u1, v1))
    m.set_part(part)
    if weight is not None:
        m.UV2[:, 1] = np.clip(weight(m), 0.0, 1.0)
    m.set_color((shade, side, coat, metal))
    return m


def bake_shade(m: Mesh, y0, y1, low=0.72, down=0.85, parts=None):
    """Нарисованная тень в цвете вершин: низ темнее, грани вниз темнее (ТЗ 11.1)."""
    t = np.clip((m.P[:, 1] - y0) / max(y1 - y0, 1e-6), 0, 1)
    t = t * t * (3 - 2 * t)
    k = low + (1 - low) * t
    k *= 1.0 - (1.0 - down) * np.clip(-m.N[:, 1], 0, 1)
    sel = np.ones(len(m.P), bool) if parts is None else np.isin(np.round(m.UV2[:, 0]).astype(int), parts)
    m.C[sel, 0] *= k[sel]
    return m


def bake_ao(m: Mesh, exclude_parts=(), rays=24, dist=0.26, strength=0.6, floor=0.45, seed=7):
    """Нарисованная тень у стыков и в складках (ТЗ 11.1: свет и тень частично в цвете):
    доля лучей полусферы вокруг нормали, которые упираются в соседние части в позе покоя.
    Множитель ложится в COLOR.r (как bake_shade). exclude_parts — части, которые не затеняют
    (оружие, знамя, инструменты — они двигаются и уходят от тела)."""
    if not len(m.F):
        return m
    part_f = np.round(m.UV2[m.F[:, 0], 0]).astype(int)
    F = m.F[~np.isin(part_f, list(exclude_parts))]
    v0 = m.P[F[:, 0]]
    e1 = m.P[F[:, 1]] - v0
    e2 = m.P[F[:, 2]] - v0
    # косинусное распределение направлений (одна и та же сетка лучей для всех вершин)
    k = np.arange(rays) + 0.5
    u1 = k / rays
    phi = k * 2.399963229728653 + seed
    loc = np.column_stack([np.sqrt(u1) * np.cos(phi), np.sqrt(u1) * np.sin(phi), np.sqrt(1 - u1)])
    N = m.N / np.maximum(np.linalg.norm(m.N, axis=1, keepdims=True), 1e-9)
    a = np.where(np.abs(N[:, 1:2]) < 0.9, np.array([[0.0, 1.0, 0.0]]), np.array([[1.0, 0.0, 0.0]]))
    t1 = np.cross(a, N)
    t1 /= np.maximum(np.linalg.norm(t1, axis=1, keepdims=True), 1e-9)
    t2 = np.cross(N, t1)
    occ = np.zeros(len(m.P))
    chunk = max(1, 24000 // max(len(F), 1))
    for s in range(0, len(m.P), chunk):
        sl = slice(s, s + chunk)
        D = (loc[None, :, 0:1] * t1[sl, None] + loc[None, :, 1:2] * t2[sl, None] + loc[None, :, 2:3] * N[sl, None])
        D = D.reshape(-1, 3)
        O = np.repeat(m.P[sl] + N[sl] * 0.006, rays, axis=0)
        # Мёллер — Трумбор: лучи × треугольники
        pv = np.cross(D[:, None], e2[None])
        det = np.einsum("rtk,tk->rt", pv, e1)
        inv = 1.0 / np.where(np.abs(det) < 1e-12, 1e-12, det)
        tv = O[:, None] - v0[None]
        u = np.einsum("rtk,rtk->rt", tv, pv) * inv
        qv = np.cross(tv, e1[None])
        v = np.einsum("rk,rtk->rt", D, qv) * inv
        t = np.einsum("rtk,tk->rt", qv, e2) * inv
        hit = (np.abs(det) > 1e-12) & (u >= 0) & (v >= 0) & (u + v <= 1) & (t > 1e-4) & (t < dist)
        w = np.where(hit, 1.0 - t / dist, 0.0).max(axis=1)
        occ[sl] = w.reshape(-1, rays).mean(axis=1)
    m.C[:, 0] *= np.clip(1.0 - strength * occ, floor, 1.0)
    return m


def joint_weight(m: Mesh, joint, axis, radius=0.12, peak=0.5):
    """Вес смешивания с соседней костью у сустава (плечо, локоть, колено, запястье коня):
    peak у самого сустава → 0 через radius вдоль кости. axis — направление кости ОТ сустава
    (у плеча — к локтю, у локтя для плеча — назад к плечу, для предплечья — к кисти).
    Считается по оси, а не по расстоянию до точки: всё кольцо у сустава получает один вес,
    и кольца соседних костей сходятся без щели. Пишется в UV2.y; кого смешивать — решает
    шейдер толпы (crowd_human / crowd_horse: ближе к какому суставу вершина)."""
    a = v3(axis) / max(np.linalg.norm(axis), 1e-9)
    t = (m.P - v3(joint)[None]) @ a
    x = np.clip(1.0 - np.maximum(t, 0.0) / radius, 0.0, 1.0)
    m.UV2[:, 1] = np.maximum(m.UV2[:, 1], peak * x * x * (3.0 - 2.0 * x))
    return m


def drop_degenerate(m: Mesh) -> Mesh:
    n = np.cross(m.P[m.F[:, 1]] - m.P[m.F[:, 0]], m.P[m.F[:, 2]] - m.P[m.F[:, 0]])
    m.F = m.F[np.linalg.norm(n, axis=1) > 1e-10]
    return m


# ---------------------------------------------------------------- запись

GLB_IMPORT = """[remap]

importer="scene"
importer_version=1
type="PackedScene"

[params]

meshes/ensure_tangents=false
meshes/generate_lods=false
meshes/create_shadow_meshes=false
meshes/light_baking=0
meshes/force_disable_compression=true
animation/import=false
gltf/embedded_image_handling=0
"""

PNG_IMPORT = """[remap]

importer="texture"
type="CompressedTexture2D"

[params]

compress/mode=2
compress/high_quality=true
mipmaps/generate=true
detect_3d/compress_to=0
"""


def ensure_import(path, text):
    """Настройки импорта Godot: без авто-LOD и теневых мешей (они ломают номер части в UV2)."""
    imp = path + ".import"
    if os.path.exists(imp):
        with open(imp, encoding="utf-8") as f:
            cur = f.read()
        need = [ln for ln in text.splitlines() if "=" in ln and ln.split("=")[0] in
                ("meshes/generate_lods", "meshes/create_shadow_meshes", "compress/mode", "mipmaps/generate",
                 "meshes/force_disable_compression")]
        if all(ln in cur for ln in need):
            return
    with open(imp, "w", encoding="utf-8") as f:
        f.write(text)


def _const_name(prefix, n):
    return f"{prefix}_{n}"


def write_skeleton_include(path):
    """Константы скелетов для шейдера толпы (генерируется, руками не править)."""
    out = ["// Скелеты толпы: номера частей и точки вращения (ГЕНЕРИРУЕТСЯ tools/gen_units.py, не править).",
           "// Оси: +Z вперёд, +X — левая сторона юнита, Y вверх; метры, поза покоя.", ""]

    def block(title, parts, prefix, piv):
        out.append(f"// --- {title}")
        for i, n in enumerate(parts):
            out.append(f"const int {prefix}_{n} = {i};")
        for k, p in piv.items():
            out.append(f"const vec3 {prefix}P_{k} = vec3({p[0]:.4f}, {p[1]:.4f}, {p[2]:.4f});")
        out.append("")

    block("человек (skeleton 0)", HUMAN_PARTS, "H", HUMAN_PIV)
    block("конь и всадник (skeleton 1), конь без всадника (skeleton 3)", RIDER_PARTS, "R", HORSE_PIV)
    block("овца (skeleton 2)", SHEEP_PARTS, "S", SHEEP_PIV)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(out))


def smoothstep(a, b, x):
    t = np.clip((np.asarray(x, float) - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


def lerp(a, b, t):
    return v3(a) + (v3(b) - v3(a)) * t


__all__ = ["bake_ao", "joint_weight", "drop_degenerate", "HUMAN_PARTS", "HUMAN_PIV", "RIDER_PARTS", "HORSE_PIV", "SHEEP_PARTS", "SHEEP_PIV", "HP", "RP", "SP",
           "RIDER_OFF", "ring_axis", "limb", "seg", "two_sided", "Atlas", "tag", "bake_shade", "ensure_import",
           "write_skeleton_include", "GLB_IMPORT", "PNG_IMPORT", "v3", "smoothstep", "lerp", "math", "np",
           "Mesh", "loft", "lathe", "tube", "ellipsoid", "grid", "ring"]
