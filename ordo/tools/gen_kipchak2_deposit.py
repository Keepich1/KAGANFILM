"""Месторождения камня и золота (ТЗ 5.1, 11.2): различимы по силуэту без подписей.

    deposit_stone_d0/d1/d2(_lod1).glb — светлый известняк: уступы карьера с плоскими
        стёсанными гранями, тёсаные блоки и щебень вокруг. Чем меньше осталось, тем ниже
        выход породы и больше плоский пол карьера.
    deposit_gold_d0/d1/d2(_lod1).glb — тёмный сланец острыми гребнями наискось, по нему жилы
        кварца с золотом (светятся тёплым), охристые отвалы с блёстками. Выше и темнее камня.

Стадии: _d0 — полное, _d1 — половина, _d2 — почти выработано. Основание одно на все стадии
(в плане ~8×7 м камень, ~7×6 м золото), начало координат — центр основания.

Рисованные бесшовные плитки (тот же paint.py): assets/textures/world/deposit_*.png.
Шейдер scenes/kipchak2/deposit.gdshader кладёт их трипланарно в осях модели (без растяжек
на скалах), маски — в вершинах:
    UV2.x — стёсанная/свежая грань (камень) или кварц (золото),
    UV2.y — плотность жил (золото),
    COLOR.rgb — нарисованный свет (верх светлее, низ и тень темнее), COLOR.a — отвал/земля.
Без своего шейдера модель тоже выглядит прилично: материал glb — плитка породы, UV — проекция.
"""
from __future__ import annotations

import math
import os

import numpy as np
from PIL import Image

import gen_camp_brush as B
import meshkit as K
from gen_units_kit import GLB_IMPORT, PNG_IMPORT, ensure_import
from glb import Material, read_glb_stats, write_glb
from meshkit import Mesh
from paint import Canvas, fbm

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
OUT_TEX = os.path.join(ROOT, "assets/textures/world")
OUT_MODELS = os.path.join(ROOT, "assets/models/world")
TEX = 512


# ================================================================ текстуры

def _save(c: Canvas, name, alpha=None):
    img = c.image()
    if alpha is not None:
        a = Image.fromarray((np.clip(alpha, 0, 1) * 255).astype(np.uint8), "L").resize(img.size, Image.LANCZOS)
        img = img.convert("RGBA")
        img.putalpha(a)
    os.makedirs(OUT_TEX, exist_ok=True)
    p = os.path.join(OUT_TEX, name)
    img.save(p, optimize=True)
    ensure_import(p, PNG_IMPORT)
    print("  ", name)


def _strata(c: Canvas, n, cols, width=(2, 5), alpha=(0.25, 0.5), wav=6.0, seed=0, slope=0.0):
    """Слои напластования: волнистые линии через всю плитку (бесшовно по x)."""
    rs = np.random.default_rng(seed)
    for i in range(n):
        y0 = rs.uniform(0, c.h)
        ph = rs.uniform(0, 6.28)
        amp = rs.uniform(2, wav)
        xs = np.linspace(0, c.w, 40)
        pts = [(x, y0 + slope * x + amp * math.sin(x / c.w * 2 * math.pi * 2 + ph)) for x in xs]
        c.line(pts, rs.uniform(*width), cols[i % len(cols)], rs.uniform(*alpha), wobble=1.2, seed=seed + i)


def tex_stone_face():
    """Выветренный известняк: тёплый серый, холодные тени мазком, слои, лишайник."""
    c = Canvas(TEX, TEX, base="#8e877a", seed=501)
    c.underpaint(["#7c766b", "#8e877a", "#9c9484", "#857e70", "#a39a86"], cell=120, seed=501)
    B.mottle(c, 70, 0.08, 3, seed=502)
    c.strokes(900, ["#a8a090", "#777064", "#938b7c", "#6c665c", "#b0a690"], length=(18, 48), width=(6, 14), angle=-12,
              angle_jitter=30, alpha=(0.18, 0.4), bristles=4, curve=0.25)
    _strata(c, 9, ["#625c52", "#b5ad9a", "#6f685c"], width=(2.5, 6), seed=503)
    c.strokes(260, ["#5b6a72", "#4e5a62"], length=(14, 36), width=(6, 12), angle=-15, angle_jitter=25,
              alpha=(0.08, 0.18), bristles=2)                    # холодная тень мазком
    c.strokes(220, ["#8a8a52", "#9c9258", "#a49a64", "#7c7a4c"], length=(4, 10), width=(3, 7), angle=0,
              angle_jitter=180, alpha=(0.35, 0.7), bristles=0, curve=0.6)   # лишайник
    c.strokes(160, ["#c8a070", "#b88e5e"], length=(4, 9), width=(2, 4), angle=0, angle_jitter=180,
              alpha=(0.2, 0.45), bristles=0)                      # охристые пятна
    c.grain(0.03)
    _save(c, "deposit_stone_face.png")


def tex_stone_cut():
    """Свежая стёсанная грань: светлый кремовый камень, ряды следов кирки, линия клиньев."""
    c = Canvas(TEX, TEX, base="#b8ae98", seed=511)
    c.underpaint(["#a89e88", "#b8ae98", "#c6bca4", "#b1a690"], cell=110, seed=511)
    c.strokes(500, ["#cfc5ad", "#a0957f", "#bdb39b"], length=(20, 60), width=(8, 16), angle=0, angle_jitter=8,
              alpha=(0.15, 0.32), bristles=5, curve=0.05)
    rs = np.random.default_rng(512)
    rows = 9
    for j in range(rows):                                         # ряды следов кирки
        y = (j + 0.5) * TEX / rows
        for i in range(30):
            x = rs.uniform(0, TEX)
            L = rs.uniform(8, 16)
            a = math.radians(rs.uniform(55, 70))
            pts = [(x, y + rs.uniform(-8, 8)), (x + math.cos(a) * L, y + math.sin(a) * L)]
            c.line(pts, 2.2, "#857a66", 0.55, wobble=0.3, seed=j * 100 + i)
            c.line([(p[0] - 1.5, p[1] - 1.0) for p in pts], 1.2, "#ddd3bb", 0.5, wobble=0.3, seed=j * 100 + i + 50)
        c.line([(0, y + TEX / rows / 2), (TEX, y + TEX / rows / 2)], 1.6, "#9a8f7a", 0.35, wobble=1.0, seed=j)
    for k in range(6):                                            # гнёзда клиньев
        x = (k + 0.5) * TEX / 6
        c.ellipse(x, TEX * 0.12, 5, 9, "#5e5548", 0.8)
        c.ellipse(x - 1, TEX * 0.12 - 3, 2.5, 3, "#3e372e", 0.8)
    c.strokes(120, ["#e6dcc4"], length=(6, 16), width=(2, 4), angle=-30, angle_jitter=20, alpha=(0.3, 0.6),
              bristles=0)
    c.grain(0.025)
    _save(c, "deposit_stone_cut.png")


def tex_spoil(name="deposit_spoil.png", gold=False):
    """Отвал: охристая земля, щебень, у золота — блёстки."""
    c = Canvas(TEX, TEX, base="#6a5c46", seed=521 + gold)
    c.underpaint(["#5c4e3a", "#6a5c46", "#786850", "#524636", "#827258"], cell=90, seed=521 + gold)
    c.strokes(1400, ["#786850", "#524636", "#8a785a", "#605240"], length=(8, 22), width=(4, 10), angle=0,
              angle_jitter=180, alpha=(0.2, 0.45), bristles=3, curve=0.4)
    rs = np.random.default_rng(523 + gold)
    for _ in range(420):                                          # щебень: камешки со светлым верхом
        x, y = rs.uniform(0, TEX), rs.uniform(0, TEX)
        r = rs.uniform(2, 6)
        col = ["#7a7466", "#8e877a", "#5d574e", "#a39a86"][rs.integers(4)]
        c.ellipse(x + 1, y + 1.5, r, r * 0.75, "#3a2e1e", 0.5)
        c.ellipse(x, y, r, r * 0.75, col, 0.95)
        c.ellipse(x - r * 0.3, y - r * 0.3, r * 0.4, r * 0.3, "#d0c6b0", 0.6)
    if gold:
        for _ in range(160):
            x, y = rs.uniform(0, TEX), rs.uniform(0, TEX)
            c.ellipse(x, y, rs.uniform(1.2, 2.6), rs.uniform(1.0, 2.0), ["#f2c45a", "#ffe08a", "#d49a30"][rs.integers(3)], 0.95)
    c.grain(0.03)
    _save(c, name)


def tex_gold_rock():
    """Тёмный сланец: сизо-лиловые плоскости сколов (короткие угловатые мазки в разные стороны,
    не «волокна дерева»), чёрные трещины, ржавые потёки, слюдяные блёстки."""
    c = Canvas(TEX, TEX, base="#3c3a42", seed=531)
    c.underpaint(["#2e2c34", "#3c3a42", "#4a4650", "#363238", "#46404a"], cell=90, seed=531)
    B.mottle(c, 50, 0.14, 3, seed=532)
    rs = np.random.default_rng(533)
    for _ in range(420):                                          # плоскости сколов: многоугольники
        x, y = rs.uniform(0, TEX), rs.uniform(0, TEX)
        r = rs.uniform(8, 26)
        k = int(rs.integers(3, 6))
        a0 = rs.uniform(0, 6.28)
        pts = [(x + r * rs.uniform(0.6, 1.0) * math.cos(a0 + j * 6.28 / k), y + r * rs.uniform(0.5, 1.0) * math.sin(a0 + j * 6.28 / k))
               for j in range(k)]
        col = ["#4e4a56", "#2a2830", "#585260", "#3a3640", "#5e5660"][rs.integers(5)]
        c.polygon(pts, col, rs.uniform(0.25, 0.55), wobble=1.0, seed=int(x * 7 + y))
    c.strokes(260, ["#1e1c22", "#26242a"], length=(10, 34), width=(1.2, 2.4), angle=-35, angle_jitter=50,
              alpha=(0.4, 0.75), bristles=0, curve=0.4)               # трещины
    c.strokes(140, ["#7a4426", "#8e5430", "#64381e"], length=(8, 30), width=(4, 9), angle=90, angle_jitter=15,
              alpha=(0.15, 0.32), bristles=2)                     # ржавые потёки
    c.strokes(220, ["#9a94a6", "#b2aabc"], length=(2, 5), width=(1.2, 2.5), angle=0, angle_jitter=180,
              alpha=(0.3, 0.6), bristles=0)                       # слюда
    c.grain(0.03)
    _save(c, "deposit_gold_rock.png")


def tex_quartz():
    """Кварц жилы: молочно-белый с голубой тенью и золотыми зёрнами (стёсанные куски золотой жилы)."""
    c = Canvas(TEX, TEX, base="#d8d2c6", seed=541)
    c.underpaint(["#c8c2b6", "#d8d2c6", "#e6e0d4", "#b8b4b0"], cell=90, seed=541)
    c.strokes(600, ["#f0ece2", "#a8a8b0", "#cfc8b8"], length=(14, 40), width=(6, 14), angle=20, angle_jitter=40,
              alpha=(0.2, 0.45), bristles=4, curve=0.3)
    rs = np.random.default_rng(542)
    for _ in range(140):
        x, y = rs.uniform(0, TEX), rs.uniform(0, TEX)
        r = rs.uniform(2, 7)
        c.ellipse(x + 1, y + 1, r, r * 0.7, "#7a5a20", 0.6)
        c.ellipse(x, y, r, r * 0.7, ["#e8b448", "#f6d276", "#c88e2a"][rs.integers(3)], 0.95)
    c.grain(0.02)
    _save(c, "deposit_gold_quartz.png")


def tex_gold_vein():
    """Сеть жил (RGBA): альфа — где жила; цвет — кварц по краю, золото в середине."""
    c = Canvas(TEX, TEX, base="#e8c060", seed=551)
    c.underpaint(["#d8a440", "#f0c860", "#ffe08a", "#c89032"], cell=40, seed=551)
    c.strokes(400, ["#fff0b0", "#b07a20", "#ffd870"], length=(6, 18), width=(2, 5), angle=0, angle_jitter=180,
              alpha=(0.4, 0.8), bristles=1)
    W = TEX * c.ss
    yy, xx = np.mgrid[0:W, 0:W] / c.ss
    n1 = fbm(W, W, 140 * c.ss, 4, seed=552)
    n2 = fbm(W, W, 70 * c.ss, 3, seed=553)
    # гребни шума — ветвистые жилы (бесшовно: шум бесшовный)
    n3 = fbm(W, W, 220 * c.ss, 2, seed=554)
    v1 = np.clip(1 - np.abs(n1 - 0.5) / 0.022, 0, 1)
    v2 = np.clip(1 - np.abs(n2 - 0.5) / 0.012, 0, 1) * 0.6 * (n3 > 0.62)
    vein = np.clip(np.maximum(v1 * (0.35 + 0.65 * (n3 > 0.35)), v2) * 1.5, 0, 1)
    # край жилы — тонкая кварцевая кайма, середина — золото
    edge = np.clip(vein * 3.0, 0, 1) - np.clip((vein - 0.3) * 3.0, 0, 1)
    img = np.asarray(c.img, dtype=np.float64)
    quartz = np.array([214, 204, 182], float)
    img = img * (1 - edge[..., None] * 0.55) + quartz * edge[..., None] * 0.55
    c._blend(img)
    alpha = np.asarray(Image.fromarray((np.clip(vein, 0, 1) * 255).astype(np.uint8)).resize((TEX, TEX), Image.LANCZOS),
                       float) / 255
    _save(c, "deposit_gold_vein.png", alpha=alpha)


def tex_stone_vein():
    """Кальцитовые прожилки известняка (RGBA): тонкие светлые, редкие."""
    c = Canvas(TEX, TEX, base="#e4dccb", seed=561)
    c.underpaint(["#d8d0be", "#ece4d2"], cell=40, seed=561)
    W = TEX * c.ss
    n1 = fbm(W, W, 160 * c.ss, 4, seed=562)
    vein = np.clip(1 - np.abs(n1 - 0.5) / 0.012, 0, 1) * 0.7
    alpha = np.asarray(Image.fromarray((vein * 255).astype(np.uint8)).resize((TEX, TEX), Image.LANCZOS), float) / 255
    _save(c, "deposit_stone_vein.png", alpha=alpha)


def build_textures():
    tex_stone_face()
    tex_stone_cut()
    tex_stone_vein()
    tex_spoil("deposit_spoil.png", gold=False)
    tex_spoil("deposit_gold_spoil.png", gold=True)
    tex_gold_rock()
    tex_quartz()
    tex_gold_vein()


# ================================================================ геометрия

class Piece:
    """Кусок породы: треугольники с масками (cut — грань стёсана/кварц, vein, spoil)."""

    def __init__(self, P, F, N, cut, vein, spoil, light):
        self.P, self.F, self.N = P, F, N
        self.cut, self.vein, self.spoil, self.light = cut, vein, spoil, light


def _noise3(P, seed, scale, amp):
    rs = np.random.default_rng(seed)
    out = np.zeros(len(P))
    for o in range(3):
        k = rs.normal(0, 1, (3, 3))
        ph = rs.uniform(0, 6.28, 3)
        f = scale * (2 ** o)
        for j in range(3):
            out += amp / (2 ** o) * np.sin(P @ k[j] * f + ph[j]) / 3
    return out


def chunk(center, radii, seed, lod=0, tilt=(0.0, 0.0, 0.0), noise=0.14, cuts=(), sink=0.35, seg=None, jag=0.0,
          vein=0.0, spoil=0.0):
    """Скальный выступ: эллипсоид с неровностью; cuts — плоскости (нормаль, точка): всё, что за
    плоскостью, стёсано на неё — плоская грань (маска cut). jag — острые рёбра сланца."""
    rx, ry, rz = radii
    su, sv = seg or ((12, 7) if lod == 0 else (8, 5))
    m = K.ellipsoid(1.0, 1.0, 1.0, su, sv, y_from=-sink, y_to=1.0)
    d = m.P.copy()
    n = _noise3(d, seed, 1.6, noise)
    if jag:
        n += jag * np.abs(np.sin(np.arctan2(d[:, 0], d[:, 2]) * 3 + seed)) * np.clip(d[:, 1], 0, 1)
    m.P = d * (1 + n)[:, None] * np.array([rx, ry, rz])
    for ax, ang in zip("xyz", tilt):
        if ang:
            m.rotate(ax, ang)
    m.translate(*center)
    m.P[:, 1] = np.maximum(m.P[:, 1], -0.04)
    on = np.zeros(len(m.P), bool)
    on_mask = np.zeros(len(m.P))
    for c in cuts:
        nrm, pt = np.asarray(c[0], float), np.asarray(c[1], float)
        mval = c[2] if len(c) > 2 else 1.0
        nrm /= np.linalg.norm(nrm)
        dist = (m.P - pt) @ nrm
        out = dist > 0
        m.P[out] -= dist[out, None] * nrm[None]
        hit = np.abs((m.P - pt) @ nrm) < 1e-3
        on |= hit
        on_mask[hit] = np.maximum(on_mask[hit], mval)
    # треугольники: плоские (стёсанные или сколы) — с нормалью плоскости; остальные — сглаженные
    F = m.F
    tri_cut = on[F].all(axis=1)
    m.smooth()
    P = m.P[F.reshape(-1)]
    N = m.N[F.reshape(-1)].copy()
    fn = np.cross(P[1::3] - P[0::3], P[2::3] - P[0::3])
    fn /= np.maximum(np.linalg.norm(fn, axis=1, keepdims=True), 1e-9)
    cut = np.repeat(tri_cut.astype(float) * on_mask[F].min(axis=1), 3)
    N[np.repeat(tri_cut, 3)] = np.repeat(fn[tri_cut], 3, axis=0)
    Fo = np.arange(len(P)).reshape(-1, 3)
    vein_m = np.full(len(P), vein)
    spoil_m = np.full(len(P), spoil)
    return Piece(P, Fo, N, cut, vein_m, spoil_m, None)


def block(center, size, yaw=0.0, tilt=0.0, seed=0, cut=0.55, spoil=0.0, lod=0):
    """Тёсаный блок: грубо обтёсанный брус со скруглёнными рёбрами и сколами (не «кубик»)."""
    sx, sy, sz = size
    rs = np.random.default_rng(seed + 900)
    m = K.ellipsoid(1.0, 1.0, 1.0, 8 if lod == 0 else 6, 4 if lod == 0 else 3, y_from=-0.05, y_to=1.0)
    d = m.P.copy()
    k = np.max(np.abs(d), axis=1, keepdims=True) ** 0.72
    d = d / np.maximum(k, 1e-6)
    d *= 1 + rs.normal(0, 0.06, d.shape)
    d[:, 1] *= 1 + 0.12 * np.sin(d[:, 0] * 3 + seed) * (d[:, 1] > 0.5)
    m.P = np.column_stack([d[:, 0] * sx / 2, np.maximum(d[:, 1], 0) * sy, d[:, 2] * sz / 2])
    m.rotate_z(tilt).rotate_y(yaw).translate(*center)
    m.smooth()
    n = len(m.P)
    return Piece(m.P[m.F.reshape(-1)], np.arange(m.tris * 3).reshape(-1, 3), m.N[m.F.reshape(-1)],
                 np.full(m.tris * 3, cut), np.zeros(m.tris * 3), np.full(m.tris * 3, spoil), None) if n else None


def heap(center, rx, ry, rz, seed, lod=0, spoil=1.0, vein=0.0):
    """Отвал/щебень: пологий конус осыпи с неровным краем (не «каравай»)."""
    su = 12 if lod == 0 else 8
    prof = [(1.0, -0.12), (0.82, 0.2), (0.5, 0.62), (0.18, 0.92), (0.0, 1.0)] if lod == 0 else \
        [(1.0, -0.12), (0.6, 0.55), (0.0, 1.0)]
    m = K.lathe(prof, su, 1.0)
    d = m.P.copy()
    n = _noise3(d * np.array([1, 0.3, 1]), seed, 1.4, 0.22)
    m.P = d * np.column_stack([1 + n, 1 + 0.6 * n, 1 + n]) * np.array([rx, ry, rz])
    m.translate(*center)
    m.P[:, 1] = np.maximum(m.P[:, 1], -0.04)
    m.smooth()
    F = m.F
    P = m.P[F.reshape(-1)]
    N = m.N[F.reshape(-1)]
    k = len(P)
    return Piece(P, np.arange(k).reshape(-1, 3), N, np.zeros(k), np.full(k, vein), np.full(k, spoil), None)


SCALE = 1.22   # месторождение — ориентир на карте: крупнее юрты (ТЗ 11.2)


def assemble(pieces, kind, height):
    """Куски → Mesh: нарисованный свет в цвете, маски в UV2 и альфе, проекция UV для glb."""
    pieces = [p for p in pieces if p is not None]
    P = np.vstack([p.P for p in pieces]) * SCALE
    P[:, 1] = np.maximum(P[:, 1], -0.045)
    N = np.vstack([p.N for p in pieces])
    F = []
    off = 0
    for p in pieces:
        F.append(p.F + off)
        off += len(p.P)
    F = np.vstack(F)
    cut = np.concatenate([p.cut for p in pieces])
    vein = np.concatenate([p.vein for p in pieces])
    spoil = np.concatenate([p.spoil for p in pieces])
    h = np.clip(P[:, 1] / max(height * SCALE, 1e-6), 0, 1)
    top = np.clip(N[:, 1], 0, 1)
    if kind == "stone":
        v = 0.6 + 0.32 * h + 0.16 * top
    else:
        v = 0.62 + 0.3 * h + 0.14 * top
    v *= 1.0 - 0.3 * np.clip(1 - P[:, 1] / 0.35, 0, 1) ** 1.5      # контактная тень у земли
    C = np.column_stack([v * 1.03, v, v * 0.96, spoil])
    UV = np.column_stack([(P[:, 0] + P[:, 2]) * 0.45, -P[:, 1] * 0.45 + P[:, 2] * 0.1])
    UV2 = np.column_stack([cut, vein])
    m = Mesh(P, F, N, UV, UV2, C)
    m.has_uv2 = True
    m.has_color = True
    return m


# ---------------------------------------------------------------- камень

def stone(stage, lod=0):
    """Известняк пластами: уступы карьера (отвесные стёсанные грани спереди, плоские площадки
    сверху), ровные штабеля тёсаных блоков, щебень. stage 0 — полный, 1 — срезан наполовину,
    2 — остался пол карьера."""
    rs = np.random.default_rng(600 + stage)
    pcs = []
    # пласты снизу вверх: центр, радиусы, отступ отвесной грани карьера спереди
    layers = [((0.0, 0.0, -0.3), (3.5, 0.95, 2.7), 1.15),
              ((-0.35, 0.8, -0.65), (2.95, 0.85, 2.25), 0.6),
              ((-0.55, 1.55, -0.95), (2.35, 0.8, 1.75), 0.15),
              ((-0.3, 2.25, -1.15), (1.6, 0.7, 1.25), -0.35)]
    keep = [4, 2, 1][stage]
    for i, (c, r, zf) in enumerate(layers[:keep]):
        top = c[1] + r[1] * (0.62 if not (stage == 2) else 0.35)
        cuts = [((0.0, 0.0, 1.0), (0, 0, zf - 0.35 * stage), 1.0),        # отвесная стенка карьера
                ((0.04, 1.0, 0.02), (0, top, 0), 0.0)]                   # площадка уступа
        frs = np.random.default_rng(40 + i)
        for f in range(4):                                              # сколы по бокам
            a = frs.uniform(math.pi * 0.35, math.pi * 1.65)
            nrm = np.array([math.sin(a), frs.uniform(-0.15, 0.35), math.cos(a)])
            nrm /= np.linalg.norm(nrm)
            cuts.append((nrm, np.asarray(c) + nrm * np.array([r[0], 0.0, r[2]]) * frs.uniform(0.66, 0.8), 0.0))
        if stage >= 1 and i == keep - 1:
            cuts.append(((1.0, 0.0, 0.25), (1.3 - 0.4 * stage, 0, 0), 1.0))   # выработка сбоку
        pcs.append(chunk(c, r, 11 + i, lod, noise=0.09, cuts=cuts, sink=0.6))
    # тёсаные блоки: ровный ряд и штабель перед карьером (продукт работы)
    rows = [[(-1.5, 2.15), (-0.45, 2.25), (0.6, 2.1)],
            [(-1.6, 2.1), (-0.55, 2.2), (0.5, 2.15), (1.55, 2.3), (-1.05, 3.05)],
            [(-1.2, 1.4), (-0.15, 1.5), (0.9, 1.4), (-0.7, 2.35), (0.35, 2.4)]][stage]
    for i, (x, z) in enumerate(rows):
        pcs.append(block((x, 0.0, z), (0.95, 0.5, 0.62), rs.uniform(-8, 8), 0, seed=i, lod=lod))
    if stage >= 1:
        for i, (x, y, z) in enumerate(((2.7, 0.0, 1.3), (2.75, 0.0, 2.0), (2.72, 0.5, 1.65))):
            pcs.append(block((x, y, z), (0.9, 0.48, 0.6), 88 + rs.uniform(-5, 5), 0, seed=20 + i, lod=lod))
    # щебень и каменная пыль у стенки
    pcs.append(heap((0.5, 0.0, 1.35 - 0.3 * stage), 1.9 + 0.3 * stage, 0.22, 0.75, 31, lod, spoil=0.6))
    for i in range([5, 7, 8][stage] if lod == 0 else 3):
        a = rs.uniform(-1.4, 1.4)
        rr = rs.uniform(2.9, 3.8)
        pcs.append(chunk((rr * math.sin(a), 0.0, rr * math.cos(a) * 0.8), (rs.uniform(0.18, 0.32),) * 2 + (0.24,),
                         40 + i, lod, noise=0.2, seg=(6, 3) if lod == 0 else (5, 2), sink=0.3,
                         cuts=[((0.2, 1, 0.1), (rr * math.sin(a), 0.12, 0), 1.0)]))
    return assemble(pcs, "stone", 3.0)


# ---------------------------------------------------------------- золото

def gold(stage, lod=0):
    """Тёмный сланец: наклонные плиты-гребни (сланцеватость в одну сторону), сколы, жилы кварца
    с золотом, охристые отвалы. stage 0 — острые гребни, 1 — обломаны, 2 — пни в отвалах."""
    rs = np.random.default_rng(700 + stage)
    pcs = []
    k = [1.0, 0.56, 0.26][stage]
    # плиты наклонены к +X (одна сланцеватость), выше в середине
    fins = [((-1.9, 0.0, -0.4), (0.55, 2.3, 1.45), (0, 8, 24), 0.6),
            ((-0.8, 0.0, -0.75), (0.6, 3.5, 1.7), (0, -6, 22), 1.0),
            ((0.35, 0.0, -0.35), (0.55, 3.0, 1.55), (0, 10, 26), 0.95),
            ((1.45, 0.0, -0.1), (0.5, 2.2, 1.3), (0, -4, 24), 0.7),
            ((-0.3, 0.0, -1.95), (0.5, 2.4, 1.1), (0, 18, 20), 0.55),
            ((2.3, 0.0, 0.7), (0.45, 1.4, 0.9), (0, 2, 26), 0.5)]
    for i, (c, r, t, v) in enumerate(fins):
        cuts = []
        frs = np.random.default_rng(130 + i)
        for f in range(3):                    # сколы: плоские грани без кварца — угловатые гребни
            a = frs.uniform(0, 2 * math.pi)
            nrm = np.array([math.sin(a), frs.uniform(0.0, 0.6), math.cos(a)])
            nrm /= np.linalg.norm(nrm)
            cuts.append((nrm, np.asarray(c, float) + nrm * np.array([r[0], r[1] * 0.45, r[2]]) * 0.62
                         + (0, r[1] * 0.4, 0), 0.0))
        if stage >= 1:                        # обломанный верх — свежий скол той же породы
            cuts.append(((0.15 * (i % 2 * 2 - 1), 1, 0.1), (c[0], r[1] * k * 0.95 + 0.25, c[2]), 0.0))
        pcs.append(chunk(c, r, 80 + i, lod, tilt=t, noise=0.1, jag=0.1 if stage == 0 else 0.05, cuts=cuts, vein=v))
    # основание-холм: пологое, тёмное
    pcs.append(chunk((0.0, 0.0, 0.0), (3.1, 0.7 * max(k, 0.6), 2.6), 90, lod, noise=0.14, vein=0.4,
                     cuts=[((0.2, 1, 0.1), (0, 0.55 * max(k, 0.6), 0), 0.0)]))
    # куски кварца с золотом у подножия
    for i in range([3, 4, 4][stage] if lod == 0 else 2):
        a = rs.uniform(-1.3, 1.3)
        rr = rs.uniform(2.2, 3.0)
        p = (rr * math.sin(a), 0.0, rr * math.cos(a))
        pcs.append(chunk(p, (0.3, 0.26, 0.24), 100 + i, lod, noise=0.25, seg=(6, 3) if lod == 0 else (5, 2),
                         sink=0.25, vein=0.7, cuts=[((rs.normal(0, 1), 1, rs.normal(0, 1)), (p[0], 0.16, p[2]), 1.0)]))
        pcs[-1].cut[:] = 1.0
    # отвалы: пологие охристые, растут с выработкой
    heaps = [[((1.5, 0.0, 2.6), 1.5, 0.32, 1.0)],
             [((1.5, 0.0, 2.6), 1.7, 0.42, 1.1), ((-2.0, 0.0, 2.3), 1.3, 0.34, 0.9)],
             [((1.4, 0.0, 2.4), 1.9, 0.5, 1.3), ((-1.9, 0.0, 2.1), 1.5, 0.42, 1.1), ((0.2, 0.0, -2.4), 1.7, 0.38, 1.0)]][stage]
    for i, (c, rx, ry, rz) in enumerate(heaps):
        pcs.append(heap(c, rx, ry, rz, 110 + i, lod, spoil=1.0))
    return assemble(pcs, "gold", 3.6)


# ================================================================ запись

def build_models():
    mats = {"stone": Material("deposit_stone", texture_uri="../../textures/world/deposit_stone_face.png", roughness=0.95),
            "gold": Material("deposit_gold", texture_uri="../../textures/world/deposit_gold_rock.png", roughness=0.9)}
    fns = {"stone": stone, "gold": gold}
    for kind in ("stone", "gold"):
        for st in range(3):
            t0 = None
            for lod in (0, 1):
                m = fns[kind](st, lod)
                name = f"deposit_{kind}_d{st}" + ("_lod1" if lod else "")
                path = os.path.join(OUT_MODELS, name + ".glb")
                write_glb(path, [("Deposit", m, mats[kind])])
                ensure_import(path, GLB_IMPORT)
                s = read_glb_stats(path)
                extra = f"({m.tris / max(t0, 1):.0%} от LOD0)" if lod else f"размер {s['size']}"
                print(f"   {name:24s} {m.tris:5d} треуг.  {extra}")
                if lod == 0:
                    t0 = m.tris


def build_all():
    build_textures()
    build_models()


if __name__ == "__main__":
    build_all()
