"""Деревья и камни мира: тополь (терек), ива (тал), арча, карагач, валуны.

    python3 tools/gen_world_models.py

Кроны — пучки рисованных карточек листвы с вырезом по альфе; нормали карточек
смотрят от центра кроны, поэтому крона затеняется мягко, как один объём (живописно),
а силуэт остаётся рваным. Альфа цвета вершины — сила качания на ветру (0 у земли).
Цвет вершины rgb — нарисованная тень внутри и снизу кроны.
Общий атлас: assets/textures/world/trees.png (ссылкой из всех glb).
У каждой модели есть _lod1 (~45% треугольников).
"""
from __future__ import annotations

import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, ".."))
sys.path.insert(0, HERE)

from glb import Material, write_glb, read_glb_stats  # noqa: E402
from meshkit import Mesh, ellipsoid, grid, tube  # noqa: E402
from paint import fbm  # noqa: E402
from palette import rgb8  # noqa: E402

OUT_MODELS = os.path.join(ROOT, "assets/models/world")
OUT_TEX = os.path.join(ROOT, "assets/textures/world")
ATLAS = 1024
# Области атласа (u0, v0, u1, v1) в долях; v растёт вниз, как в картинке
R_BROAD = (0.0, 0.0, 0.5, 0.5)
R_WILLOW = (0.5, 0.0, 1.0, 0.5)
R_JUNIPER = (0.0, 0.5, 0.5, 1.0)
R_BARK = (0.5, 0.5, 0.75, 1.0)
R_BROAD2 = (0.75, 0.5, 1.0, 0.75)
R_JBARK = (0.75, 0.75, 1.0, 1.0)


# =====================================================================
# Атлас
# =====================================================================

class Card:
    """Холст карточки: цвет + альфа, рисуем мазками-листьями (суперсэмплинг ×2)."""

    def __init__(self, w, h, seed):
        self.w, self.h, self.ss = w, h, 2
        self.col = Image.new("RGB", (w * 2, h * 2), (40, 50, 30))
        self.alpha = Image.new("L", (w * 2, h * 2), 0)
        self.dc = ImageDraw.Draw(self.col)
        self.da = ImageDraw.Draw(self.alpha)
        self.rs = np.random.default_rng(seed)

    def leaf(self, x, y, length, width, angle, color, a=255):
        s = self.ss
        ca, sa = math.cos(angle), math.sin(angle)
        pts = []
        for t in np.linspace(0, 2 * np.pi, 10, endpoint=False):
            lx, ly = math.cos(t) * length * 0.5, math.sin(t) * width * 0.5 * (1.0 - 0.35 * math.cos(t))
            pts.append(((x + lx * ca - ly * sa) * s, (y + lx * sa + ly * ca) * s))
        self.dc.polygon(pts, fill=tuple(int(np.clip(c, 0, 255)) for c in color))
        self.da.polygon(pts, fill=a)

    def image(self):
        col = self.col.resize((self.w, self.h), Image.LANCZOS)
        al = self.alpha.filter(ImageFilter.GaussianBlur(0.6)).resize((self.w, self.h), Image.LANCZOS)
        out = col.convert("RGBA")
        out.putalpha(al)
        return out


def _pal(colors):
    return [np.array(rgb8(c), float) for c in colors]


def broad_cluster(w, h, seed, palette, n_sub=5, leaves=3000, leaf=(12, 20), spread=0.62):
    """Гроздь листвы: несколько подгроздей, листья-мазки, светлее сверху-слева."""
    c = Card(w, h, seed)
    rs = c.rs
    cols = _pal(palette)
    subs = [(w * 0.5 + rs.normal(0, w * 0.1), h * 0.5 + rs.normal(0, h * 0.09), rs.uniform(0.6, 1.0))
            for _ in range(n_sub)]
    for i in range(leaves):
        sx, sy, sr = subs[rs.integers(len(subs))]
        r = min(abs(rs.normal(0, 0.8)), 1.6) ** 0.7 * w * spread * 0.5 * sr
        a = rs.uniform(0, 2 * np.pi)
        x, y = sx + math.cos(a) * r, sy + math.sin(a) * r * 0.9
        if not (6 < x < w - 6 and 6 < y < h - 6):
            continue
        # свет: верх-лево светлее, низ и центр темнее (нарисованный объём)
        lit = np.clip(0.5 - (x - w * 0.5) / w * 0.6 - (y - h * 0.5) / h * 0.9 + rs.normal(0, 0.18), 0, 1)
        depth = i / leaves                     # поздние листья — поверх, светлее
        k = int(np.clip(lit * (len(cols) - 1) * (0.6 + 0.6 * depth) + rs.normal(0, 0.5), 0, len(cols) - 1))
        col = cols[k] * rs.uniform(0.9, 1.08)
        ln = rs.uniform(*leaf)
        c.leaf(x, y, ln, ln * rs.uniform(0.45, 0.65), a + rs.normal(0, 0.6) + 1.2, col)
    return c.image()


def willow_strands(w, h, seed, palette, strands=34):
    """Ива: свисающие пряди узких листьев от верхнего края."""
    c = Card(w, h, seed)
    rs = c.rs
    cols = _pal(palette)
    for s in range(strands):
        x0 = rs.uniform(w * 0.08, w * 0.92)
        L = rs.uniform(h * 0.55, h * 0.95)
        sway = rs.normal(0, w * 0.04)
        n = int(L / 7)
        for i in range(n):
            t = i / max(n - 1, 1)
            x = x0 + sway * t * t + math.sin(t * 5 + s) * 3
            y = 4 + t * L
            for side in (-1, 1):
                if rs.random() < 0.85:
                    ang = math.pi / 2 + side * rs.uniform(0.25, 0.6)
                    lit = np.clip(0.75 - t * 0.6 + rs.normal(0, 0.15), 0, 1)
                    col = cols[int(lit * (len(cols) - 1) + 0.5)] * rs.uniform(0.92, 1.06)
                    ln = rs.uniform(12, 20) * (1 - 0.3 * t)
                    c.leaf(x + side * 3, y, ln, ln * 0.22, ang, col)
    return c.image()


def juniper_clump(w, h, seed, palette):
    """Арча: плотные чешуйчатые комки, тёмная сине-зелёная хвоя, светлые кончики."""
    c = Card(w, h, seed)
    rs = c.rs
    cols = _pal(palette)
    subs = [(w * 0.5 + rs.normal(0, w * 0.09), h * 0.5 + rs.normal(0, h * 0.08), rs.uniform(0.6, 1.0)) for _ in range(6)]
    for i in range(5200):
        sx, sy, sr = subs[rs.integers(len(subs))]
        r = min(abs(rs.normal(0, 0.8)), 1.5) ** 0.6 * w * 0.24 * sr
        a = rs.uniform(0, 2 * np.pi)
        x, y = sx + math.cos(a) * r, sy + math.sin(a) * r * 0.8
        if not (5 < x < w - 5 and 5 < y < h - 5):
            continue
        lit = np.clip(0.55 - (y - h * 0.5) / h * 1.1 - (x - w * 0.5) / w * 0.4 + rs.normal(0, 0.2), 0, 1)
        k = int(np.clip(lit * (len(cols) - 1) * (0.5 + 0.7 * i / 5200) + 0.3, 0, len(cols) - 1))
        ln = rs.uniform(8, 13)
        c.leaf(x, y, ln, ln * 0.7, a, cols[k] * rs.uniform(0.9, 1.08))
    return c.image()


def bark(w, h, seed, palette, horizontal_bands=False):
    """Кора: вертикальные мазки, тёмные борозды, тёплый свет с одной стороны."""
    rs = np.random.default_rng(seed)
    img = Image.new("RGB", (w * 2, h * 2), rgb8(palette[1]))
    d = ImageDraw.Draw(img)
    cols = [rgb8(p) for p in palette]
    for _ in range(900):
        x, y = rs.uniform(0, w * 2), rs.uniform(-40, h * 2)
        L = rs.uniform(30, 120)
        wd = rs.uniform(3, 9)
        lit = x / (w * 2)
        k = int(np.clip(lit * (len(cols) - 1) + rs.normal(0, 0.8), 0, len(cols) - 1))
        d.line([(x, y), (x + rs.normal(0, 4), y + L)], fill=cols[k], width=int(wd))
    for _ in range(140):
        x, y = rs.uniform(0, w * 2), rs.uniform(-40, h * 2)
        d.line([(x, y), (x + rs.normal(0, 3), y + rs.uniform(40, 160))], fill=rgb8("#241a14"), width=2)
    if horizontal_bands:
        for _ in range(40):
            y = rs.uniform(0, h * 2)
            d.line([(0, y), (w * 2, y + rs.normal(0, 3))], fill=rgb8("#3a2c22"), width=2)
    out = img.resize((w, h), Image.LANCZOS).convert("RGBA")
    return out


def build_atlas():
    A = Image.new("RGBA", (ATLAS, ATLAS), (0, 0, 0, 0))
    half, q = ATLAS // 2, ATLAS // 4
    poplar_pal = ["#2e3a22", "#3e4c2a", "#55642f", "#6f7c3a", "#8d944a", "#a9a65a"]
    A.paste(broad_cluster(half, half, 1, poplar_pal), (0, 0))
    A.paste(willow_strands(half, half, 2, ["#45523c", "#5d6c4f", "#7a8a68", "#97a483", "#b4bb9a"]), (half, 0))
    A.paste(juniper_clump(half, half, 3, ["#1e2a24", "#283a30", "#34493b", "#45604a", "#5f7a5c"]), (0, half))
    A.paste(bark(q, half, 4, ["#2c241e", "#4a3c30", "#6a5846", "#857160"]), (half, half))
    A.paste(broad_cluster(q, q, 5, poplar_pal, n_sub=3, leaves=900, leaf=(7, 11), spread=0.62), (half + q, half))
    A.paste(bark(q, q, 6, ["#3a2219", "#5a3424", "#7a4a32", "#956048"], horizontal_bands=False), (half + q, half + q))
    os.makedirs(OUT_TEX, exist_ok=True)
    A.save(os.path.join(OUT_TEX, "trees.png"), optimize=True)
    print("   trees.png")


# =====================================================================
# Геометрия
# =====================================================================

def _rect_uv(m: Mesh, rect):
    """UV карточки grid() (0..1, y вверх) → область атласа (v вниз)."""
    u0, v0, u1, v1 = rect
    m.UV = np.column_stack([u0 + m.UV[:, 0] * (u1 - u0), v0 + (1.0 - m.UV[:, 1]) * (v1 - v0)])
    return m


def card(w, h, rect, center, crown_c, crown_r, rs, face=None, sway=1.0, hang=False):
    """Карточка листвы в точке center. Нормали — от центра кроны (мягкий объём)."""
    m = grid(w, h, 1, 1).translate(-w / 2, 0 if hang else -h / 2, 0)
    if hang:
        m.translate(0, -h, 0)               # свисает вниз от точки крепления
    _rect_uv(m, rect)
    yaw = rs.uniform(0, 360) if face is None else face
    m.rotate_z(rs.normal(0, 25) if not hang else rs.normal(0, 6))
    m.rotate_x(rs.uniform(-35, 35) if not hang else rs.uniform(-10, 10))
    m.rotate_y(yaw)
    m.translate(*center)
    d = (m.P - np.asarray(crown_c)) / np.asarray(crown_r)
    n = d / np.maximum(np.linalg.norm(d, axis=1, keepdims=True), 1e-6)
    n[:, 1] += 0.25
    m.N = n / np.linalg.norm(n, axis=1, keepdims=True)
    # нарисованная тень: внутри и снизу кроны темнее
    outer = np.clip(np.linalg.norm(d, axis=1), 0, 1.2)
    up = np.clip((m.P[:, 1] - (crown_c[1] - crown_r[1])) / (2 * crown_r[1]), 0, 1)
    ao = np.clip(0.42 + 0.38 * outer + 0.3 * up, 0.35, 1.08)
    sw = np.clip(sway * (0.55 + 0.45 * outer), 0, 1)
    m.C = np.column_stack([ao, ao, ao, sw])
    m.has_color = True
    return m


def trunk(path, r0, r1, sides, rect, sway_top=0.25):
    rs_ = np.linspace(r0, r1, len(path))
    m = tube(path, rs_, sides=sides, uv_len=0.25)
    u0, v0, u1, v1 = rect
    vv = m.UV[:, 1] / max(m.UV[:, 1].max(), 1e-6)
    m.UV = np.column_stack([u0 + m.UV[:, 0] * (u1 - u0), v1 - vv * (v1 - v0)])
    hgt = np.asarray(path)[:, 1]
    h = (m.P[:, 1] - hgt.min()) / max(np.ptp(hgt), 1e-6)
    ao = 0.55 + 0.45 * np.clip(h * 1.5, 0, 1)
    m.C = np.column_stack([ao, ao, ao, np.clip(h, 0, 1) ** 2 * sway_top])
    m.has_color = True
    return m


def _bent_path(base, top, n, bend, rs, wobble=0.15):
    pts = []
    for i in range(n):
        t = i / (n - 1)
        p = np.asarray(base, float) * (1 - t) + np.asarray(top, float) * t
        p[0] += bend[0] * math.sin(t * math.pi) + rs.normal(0, wobble) * t
        p[2] += bend[1] * math.sin(t * math.pi) + rs.normal(0, wobble) * t
        pts.append(p)
    return np.array(pts)


def poplar(seed, lod=0):
    """Терек (пирамидальный тополь): высокая веретенообразная крона, 18–22 м."""
    rs = np.random.default_rng(seed)
    H = 19.0
    parts = [trunk(_bent_path((0, 0, 0), (0, H * 0.82, 0), 7, (0.2, 0.1), rs), 0.32, 0.08, 7 if lod == 0 else 5, R_BARK)]
    cc, cr = (0.0, H * 0.55, 0.0), (2.4, H * 0.45, 2.4)
    n = 110 if lod == 0 else 48
    size = (2.6, 2.9) if lod == 0 else (3.6, 4.0)
    for i in range(n):
        t = rs.uniform(0.0, 1.0) ** 0.9
        y = 2.2 + t * (H - 2.4)
        prof = math.sin(math.pi * min(t * 1.15, 1.0)) ** 0.75 * (1.0 - 0.35 * t)
        rad = 2.3 * prof * rs.uniform(0.45, 1.0)
        a = rs.uniform(0, 2 * np.pi)
        p = (math.cos(a) * rad, y, math.sin(a) * rad)
        s = rs.uniform(*size) * (0.6 + 0.5 * prof)
        rect = R_BROAD if rs.random() < 0.8 else R_BROAD2
        parts.append(card(s, s, rect, p, cc, cr, rs, face=math.degrees(-a) + 90 + rs.normal(0, 40), sway=0.4 + 0.6 * t))
    return Mesh.merge(parts)


def elm(seed, lod=0):
    """Карагач: толстый ствол, круглая густая крона ~12 м."""
    rs = np.random.default_rng(seed)
    parts = [trunk(_bent_path((0, 0, 0), (0.3, 6.0, 0.2), 6, (0.3, 0.2), rs), 0.55, 0.28, 8 if lod == 0 else 5, R_BARK, 0.1)]
    for k in range(4):
        a = k * math.pi / 2 + rs.normal(0, 0.3)
        tip = (math.cos(a) * 3.0, 9.0 + rs.normal(0, 0.8), math.sin(a) * 3.0)
        parts.append(trunk(_bent_path((0.3, 5.5, 0.2), tip, 4, (0, 0), rs), 0.26, 0.08, 5 if lod == 0 else 4, R_BARK, 0.3))
    cc, cr = (0.0, 8.8, 0.0), (5.6, 4.2, 5.6)
    n = 130 if lod == 0 else 56
    for i in range(n):
        d = rs.normal(0, 1, 3)
        d /= np.linalg.norm(d)
        r = rs.uniform(0.55, 1.0)
        p = np.array(cc) + d * np.array(cr) * r
        p[1] = max(p[1], 5.0)
        s = rs.uniform(2.6, 3.3) * (1.4 if lod else 1.0)
        parts.append(card(s, s, R_BROAD if rs.random() < 0.7 else R_BROAD2, p, cc, cr, rs,
                          face=math.degrees(-math.atan2(d[2], d[0])) + 90 + rs.normal(0, 35), sway=0.5 + 0.5 * r))
    return Mesh.merge(parts)


def willow(seed, lod=0):
    """Ива (тал): наклонённый к воде ствол, три толстые ветви, свисающие пряди. Наклон — в +X."""
    rs = np.random.default_rng(seed)
    base_top = np.array([1.6, 3.2, 0.2])
    parts = [trunk(_bent_path((0, 0, 0), base_top, 5, (0.3, 0.0), rs), 0.5, 0.36, 8 if lod == 0 else 5, R_BARK, 0.05)]
    tips = []
    for k in range(3):
        a = rs.uniform(-0.9, 0.9) + (k - 1) * 0.9
        tip = base_top + np.array([math.cos(a) * 3.2 + 1.0, rs.uniform(3.0, 4.5), math.sin(a) * 3.2])
        tips.append(tip)
        parts.append(trunk(_bent_path(base_top, tip, 4, (0.2, 0.0), rs), 0.3, 0.1, 6 if lod == 0 else 4, R_BARK, 0.25))
    cc = (2.6, 6.2, 0.0)
    cr = (5.2, 3.6, 5.2)
    n = 120 if lod == 0 else 52
    for i in range(n):
        d = rs.normal(0, 1, 3)
        d[1] = abs(d[1]) * 0.8 + 0.1
        d /= np.linalg.norm(d)
        r = rs.uniform(0.6, 1.0)
        p = np.array(cc) + d * np.array(cr) * r
        hang = rs.random() < 0.4 and d[1] < 0.75
        if hang:
            w, h = rs.uniform(2.0, 2.8), rs.uniform(2.4, 3.6)
            parts.append(card(w, h, R_WILLOW, p + np.array([0, 0.8, 0]), cc, cr, rs,
                              face=math.degrees(-math.atan2(d[2], d[0])) + 90, sway=0.9, hang=True))
        else:
            s = rs.uniform(2.2, 3.0)
            parts.append(card(s, s, R_BROAD2, p, cc, cr, rs, sway=0.7))
    return Mesh.merge(parts)


def juniper(seed, lod=0):
    """Арча: кривой красноватый ствол, плотные тёмные комки хвои, крона прижата ветром."""
    rs = np.random.default_rng(seed)
    H = rs.uniform(4.5, 6.5)
    lean = rs.uniform(0.4, 1.2)
    parts = [trunk(_bent_path((0, 0, 0), (lean, H * 0.7, 0.2), 6, (0.4, 0.3), rs, 0.25), 0.3, 0.1, 6 if lod == 0 else 4, R_JBARK, 0.08)]
    clumps = []
    for k in range(rs.integers(3, 5)):
        t = k / 3.0
        clumps.append((np.array([lean * t + rs.normal(0, 0.6), 1.4 + t * (H - 2.2), rs.normal(0, 0.6)]),
                       np.array([rs.uniform(1.2, 1.9) * (1.1 - 0.35 * t), rs.uniform(0.9, 1.4), rs.uniform(1.2, 1.9) * (1.1 - 0.35 * t)])))
    cc = (lean * 0.5, H * 0.55, 0.0)
    cr = (2.2, H * 0.5, 2.2)
    n = 70 if lod == 0 else 30
    for i in range(n):
        c0, r0 = clumps[rs.integers(len(clumps))]
        d = rs.normal(0, 1, 3)
        d /= np.linalg.norm(d)
        p = c0 + d * r0 * rs.uniform(0.4, 1.0)
        s = rs.uniform(1.4, 2.0) * (1.4 if lod else 1.0)
        parts.append(card(s, s * 0.85, R_JUNIPER, p, cc, cr, rs, sway=0.35))
    return Mesh.merge(parts)


def boulder(seed, lod=0):
    """Валун: неровный эллипсоид с плоским низом, свет и тень нарисованы в цвете вершин."""
    rs = np.random.default_rng(seed)
    sx, sy, sz = rs.uniform(0.9, 1.3), rs.uniform(0.55, 0.85), rs.uniform(0.8, 1.2)
    m = ellipsoid(sx, sy, sz, 14 if lod == 0 else 8, 9 if lod == 0 else 5, y_from=-0.35, y_to=1.0)
    d = m.P / np.array([sx, sy, sz])
    # бугры и сколы: шум по направлению + «срезанные» грани (не кубики — мягкие плоскости)
    nz = fbm(64, 64, 16, 3, seed=seed)
    th = (np.arctan2(d[:, 2], d[:, 0]) / (2 * np.pi) + 0.5) * 63
    ph = (d[:, 1] * 0.5 + 0.5) * 63
    bump = nz[ph.astype(int).clip(0, 63), th.astype(int).clip(0, 63)]
    m.P = m.P * (0.82 + 0.3 * bump)[:, None]
    for _ in range(3):
        pn = rs.normal(0, 1, 3)
        pn[1] = abs(pn[1]) + 0.3
        pn /= np.linalg.norm(pn)
        off = rs.uniform(0.55, 0.75) * np.array([sx, sy, sz]).mean()
        dist = m.P @ pn - off
        m.P = m.P - np.maximum(dist, 0)[:, None] * pn[None] * 0.85
    m.P[:, 1] -= m.P[:, 1].min() + 0.12 * sy           # чуть утоплен в землю
    m = m.smooth()
    # нарисованный свет: верх тёплый и светлый, низ тёмный и холодный
    h = (m.P[:, 1] - m.P[:, 1].min()) / max(np.ptp(m.P[:, 1]), 1e-6)
    top = np.clip(m.N[:, 1], 0, 1)
    v = 0.5 + 0.35 * h + 0.2 * top
    m.C = np.column_stack([v * 1.04, v, v * 0.94, np.ones(len(v))])
    m.has_color = True
    # развёртка: сбоку по окружности, масштаб ~ размеру камня
    ang = np.arctan2(m.P[:, 2], m.P[:, 0])
    m.UV = np.column_stack([ang / np.pi * 0.6, -m.P[:, 1] * 0.35])
    return m


def main():
    print("атлас деревьев…")
    build_atlas()
    tree_mat = Material("trees", texture_uri="../../textures/world/trees.png", alpha="MASK", alpha_cutoff=0.5,
                        double_sided=True, roughness=0.95)
    rock_mat = Material("rock", texture_uri="../../textures/world/ground_rock.png", roughness=0.95)
    models = {
        "poplar": lambda lod: poplar(11, lod),
        "elm": lambda lod: elm(12, lod),
        "willow": lambda lod: willow(13, lod),
        "juniper": lambda lod: juniper(14, lod),
    }
    for name, fn in models.items():
        for lod in (0, 1):
            path = os.path.join(OUT_MODELS, f"{name}{'_lod1' if lod else ''}.glb")
            write_glb(path, [(name, fn(lod), tree_mat)])
            st = read_glb_stats(path)
            print(f"   {os.path.basename(path)}: {st['triangles']} треуг., размер {st['size']}")
    for k in range(4):
        for lod in (0, 1):
            path = os.path.join(OUT_MODELS, f"rock_{k}{'_lod1' if lod else ''}.glb")
            write_glb(path, [(f"rock_{k}", boulder(40 + k, lod), rock_mat)])
            st = read_glb_stats(path)
            print(f"   {os.path.basename(path)}: {st['triangles']} треуг., размер {st['size']}")


if __name__ == "__main__":
    main()
