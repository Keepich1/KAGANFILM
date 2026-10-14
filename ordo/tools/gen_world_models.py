"""Деревья и камни мира: тополь (терек), ива (тал), арча, карагач, валуны.

    python3 tools/gen_world_models.py            # атлас деревьев, деревья и камни
    python3 tools/gen_world_models.py --trees    # только деревья (атлас + glb)
    python3 tools/gen_world_models.py --atlas    # только атлас (проверить рисунок)

Кроны (ТЗ 11.1: рисованные, с видимыми мазками, без «игрушечности» и «мозаики»):
  * крона собрана из гроздей (лопастей), грозди — из карточек, которые шейдер листвы
    (assets/models/world/foliage.gdshader) разворачивает к камере: карточка никогда не видна
    ребром, все карточки параллельны экрану и не режут друг друга — силуэт кроны всегда
    пушистый, без «кубиков» и полос пересечений;
  * карточка — нарисованная гроздь: тёмная подложка, средний тон, светлая шапка, блики;
    край — из отдельных листьев-мазков (рваный, «кистевой»). Свет в рисунке — только сверху
    (небо): солнце, тень и контровой свет кладёт шейдер по настоящему солнцу;
  * альфа атласа — поле расстояния до края грозди (0,5 — край): край чёткий вблизи (без
    ступенек текселей) и не рассыпается вдали; по альфе шейдер находит тонкий край грозди —
    там листва просвечивает против низкого солнца;
  * нормаль карточки — от центра кроны и своей грозди; шейдер добавляет «купол» внутри
    карточки — каждая гроздь лепится светом и тенью отдельно, крона остаётся одним объёмом.

Виды (ТЗ 8, CONTRACT §3):
  терек  — пирамидальный тополь: высокая узкая колонна ~19,5 м из длинных «языков пламени»
           (карточки втрое выше ширины, гладкий профиль — не стопка шаров), ветви круто вверх,
           светлая кора с тёмными чечевичками, серебристая изнанка листьев;
  тал    — плакучая ива у воды: короткий наклонный ствол, дуги ветвей, невысокий купол и
           «каскады» прядей по краю купола — прядь дугой уходит наружу и свисает почти до
           земли; длина каскадов волной, с просветами — «колокол», а не «занавеска»;
  арча   — можжевельник склонов: толстый кривой красноватый ствол винтом с отводком, ветви-
           локти, плоские тёмные сизо-зелёные комки хвои, прижатые ветром к +X, сухой сук;
  карагач — густая круглая крона-«шар» на прямом толстом стволе, ветви видны снизу в просветах.

Данные вершины (договор с foliage.gdshader):
  COLOR.rgb — нарисованная тень (глубина в кроне, низ темнее); COLOR.a — сила изгиба на ветру
              (одна для ствола и листвы на той же высоте — крона не отрывается от ствола);
  UV2 = (ox + 20·тип, oy) — смещение угла карточки от её центра (м) в плоскости покоя;
        тип 1 — гроздь (разворот к камере), 3 — «масса» (так же, но купол карточки слабый:
        карточки лопасти светятся вместе), 2 — каскад прядей ивы (разворот вокруг вертикали,
        центр — точка крепления сверху; рисунок — дуга к +u, на левой для камеры стороне кроны
        шейдер зеркалит карточку); кора и ветви — UV2 = (0, 0);
  NORMAL карточки — одна на четыре угла; по ней шейдер находит плоскость покоя
        (right = up × n, up' = n × right): центр = VERTEX − right·ox − up'·oy.
Без шейдера листвы (Painterly.apply) карточки стоят в покое — смотрят наружу от грозди.

Общий атлас 2048²: assets/textures/world/trees.png (ссылкой из всех glb).
У каждой модели есть _lod1 (~45 % треугольников): те же грозди, меньше и крупнее карточки.
"""
from __future__ import annotations

import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, ".."))
sys.path.insert(0, HERE)

from glb import Material, write_glb, read_glb_stats  # noqa: E402
from meshkit import Mesh, ellipsoid, tube  # noqa: E402
from paint import Canvas, fbm  # noqa: E402
from palette import rgb8  # noqa: E402

OUT_MODELS = os.path.join(ROOT, "assets/models/world")
OUT_TEX = os.path.join(ROOT, "assets/textures/world")
ATLAS = 2048
SS = 2                       # суперсэмплинг рисунка
UP = np.array([0.0, 1.0, 0.0])

# Области атласа в пикселях (x, y, ширина, высота); v растёт вниз, как в картинке
REG = {
    "elm": [(0, 0, 512, 512), (512, 0, 512, 512), (1024, 0, 512, 512), (1536, 0, 512, 512)],
    "poplar": [(0, 512, 256, 512), (256, 512, 256, 512), (512, 512, 256, 512), (768, 512, 256, 512)],
    "strand": [(1024, 512, 256, 512), (1280, 512, 256, 512), (1536, 512, 256, 512), (1792, 512, 256, 512)],
    "juniper": [(0, 1024, 512, 256), (512, 1024, 512, 256), (0, 1280, 512, 256), (512, 1280, 512, 256)],
    "willow": [(1024, 1024, 512, 512), (1536, 1024, 512, 512)],
    "elm_edge": [(1024, 1536, 512, 512), (1536, 1536, 512, 512)],
    "bark_elm": (0, 1536, 256, 512),
    "bark_willow": (256, 1536, 256, 512),
    "bark_poplar": (512, 1536, 256, 512),
    "bark_juniper": (768, 1536, 256, 512),
}

# Палитры листвы: от глубокой тени (холодной) к бликам (тёплым). Солнце и контровой свет
# добавит шейдер; world_scatter умножает на тон вида (~0,6–0,8).
PAL = {
    "elm": ["#13201a", "#1b2c20", "#263c26", "#35502d", "#4a6634", "#667c3d", "#8b9549", "#adb05c"],
    "poplar": ["#121c18", "#1a281f", "#253727", "#33492e", "#456036", "#5f7542", "#7f8b52", "#9fa266"],
    "poplar_silver": ["#7d8a80", "#94a096", "#aab3a4"],
    "willow": ["#18231a", "#223121", "#304428", "#42582f", "#596f37", "#738540", "#919c4f", "#adb162"],
    "willow_silver": ["#87917b", "#9ea78e"],
    "juniper": ["#0b1513", "#111d19", "#182a23", "#21362d", "#2d473a", "#3f5a4b", "#58715f", "#748a77"],
}


# =====================================================================
# Рисунок: гроздь листьев-мазков с полем расстояния в альфе
# =====================================================================

def _box_blur(a, r):
    """Размытие окном 2r+1 по обеим осям (через накопленные суммы), края — повтор."""
    if r < 1:
        return a
    p = np.pad(a, [(r + 1, r)] + [(0, 0)] * (a.ndim - 1), mode="edge")
    c = np.cumsum(p, axis=0)
    a = (c[2 * r + 1:] - c[:-2 * r - 1]) / (2 * r + 1)
    p = np.pad(a, [(0, 0), (r + 1, r)] + [(0, 0)] * (a.ndim - 2), mode="edge")
    c = np.cumsum(p, axis=1)
    return (c[:, 2 * r + 1:] - c[:, :-2 * r - 1]) / (2 * r + 1)


def _chamfer(mask, maxd):
    """Расстояние (в пикселях, фаска 1/√2) от каждого пикселя до ближайшего пикселя mask."""
    d = np.where(mask, 0.0, maxd + 1.0).astype(np.float32)
    s2 = np.float32(math.sqrt(2.0))
    for _ in range(int(maxd) + 1):
        p = np.pad(d, 1, mode="edge")
        d = np.minimum.reduce([d, p[:-2, 1:-1] + 1, p[2:, 1:-1] + 1, p[1:-1, :-2] + 1, p[1:-1, 2:] + 1,
                               p[:-2, :-2] + s2, p[:-2, 2:] + s2, p[2:, :-2] + s2, p[2:, 2:] + s2])
    return np.minimum(d, maxd)


class Tile:
    """Холст одной области атласа: цвет + маска (суперсэмплинг SS)."""

    def __init__(self, w, h, seed):
        self.w, self.h = w, h
        self.col = Image.new("RGB", (w * SS, h * SS), (0, 0, 0))
        self.msk = Image.new("L", (w * SS, h * SS), 0)
        self.dc = ImageDraw.Draw(self.col)
        self.dg = ImageDraw.Draw(self.col, "RGBA")       # полупрозрачные лессировки
        self.dm = ImageDraw.Draw(self.msk)
        self.rs = np.random.default_rng(seed)

    def glaze(self, x, y, L, W, ang, color, alpha, bristles=5):
        """Лессировка: широкий полупрозрачный мазок с щетиной (маску не меняет)."""
        rs = self.rs
        k = 9
        s = np.linspace(-0.5, 0.5, k)
        bend = rs.normal(0, 0.25) * L
        ca, sa = math.cos(ang), math.sin(ang)
        cx = x + ca * s * L - sa * bend * (s * s - 0.25)
        cy = y + sa * s * L + ca * bend * (s * s - 0.25)
        wp = W * (1 - 0.6 * np.clip(s + 0.5, 0, 1) ** 1.5) * (0.6 + 0.4 * np.sin(np.pi * (s + 0.5)) ** 0.4)
        left = [((cx[i] - sa * wp[i] / 2) * SS, (cy[i] + ca * wp[i] / 2) * SS) for i in range(k)]
        right = [((cx[i] + sa * wp[i] / 2) * SS, (cy[i] - ca * wp[i] / 2) * SS) for i in range(k)][::-1]
        fill = tuple(int(np.clip(c, 0, 255)) for c in color) + (int(alpha * 255),)
        self.dg.polygon(left + right, fill=fill)
        for _ in range(bristles):
            o = rs.uniform(-0.42, 0.42)
            sh = rs.uniform(0.85, 1.15)
            bc = tuple(int(np.clip(c * sh, 0, 255)) for c in color) + (int(alpha * 255 * 0.7),)
            pts = [((cx[i] - sa * wp[i] * o) * SS, (cy[i] + ca * wp[i] * o) * SS) for i in range(k - 1)]
            self.dg.line(pts, fill=bc, width=max(1, int(W * SS * 0.07)))

    def poly(self, pts, color, mask=True):
        p = [(float(x) * SS, float(y) * SS) for x, y in pts]
        self.dc.polygon(p, fill=tuple(int(np.clip(c, 0, 255)) for c in color))
        if mask:
            self.dm.polygon(p, fill=255)

    def leaf(self, x, y, L, W, ang, color, asym=0.25, bend=0.0, mask=True):
        """Лист-мазок: заострённый с обеих сторон, шире у основания."""
        k = 7
        s = np.linspace(-1.0, 1.0, k)
        half = 0.5 * W * np.clip(1.0 - s * s, 0.0, 1.0) ** 0.7 * (1.0 - asym * s)
        ax = s * L * 0.5
        off = bend * L * 0.5 * (s * s - 1.0)             # изгиб мазка
        left = np.column_stack([ax, off + half])
        right = np.column_stack([ax, off - half])[::-1]
        pts = np.vstack([left, right[1:-1]])
        ca, sa = math.cos(ang), math.sin(ang)
        R = np.array([[ca, -sa], [sa, ca]])
        pts = pts @ R.T + np.array([x, y])
        self.poly(pts, color, mask)

    def blob(self, cx, cy, rx, ry, color, noise=0.2, n=56, mask=True):
        """Неровное пятно (подложка грозди)."""
        rs = self.rs
        ph = rs.uniform(0, 6.28, 3)
        t = np.linspace(0, 2 * np.pi, n, endpoint=False)
        k = 1.0 + noise * (0.5 * np.sin(3 * t + ph[0]) + 0.3 * np.sin(5 * t + ph[1]) + 0.2 * np.sin(9 * t + ph[2]))
        pts = np.column_stack([cx + np.cos(t) * rx * k, cy + np.sin(t) * ry * k])
        self.poly(pts, color, mask)

    def finish(self, spread=14.0):
        """RGBA области: цвет (снаружи грозди — продолжение её цвета) + альфа-поле расстояния."""
        col = np.asarray(self.col, dtype=np.float32)
        m = np.asarray(self.msk) > 127
        sp = spread * SS
        d_out = _chamfer(m, sp)
        d_in = _chamfer(~m, sp)
        sdf = np.where(m, d_in - 0.5, -(d_out - 0.5))
        alpha = np.clip(0.5 + sdf / (2.0 * sp), 0.0, 1.0)
        # цвет за краем — продолжение цвета грозди (иначе мип-уровни дают тёмную кайму)
        w = m.astype(np.float32)
        out = col.copy()
        filled = m.copy()
        for r in (2, 4, 8, 16, 32, 64, 128):
            a = _box_blur(col * w[..., None], r)
            b = _box_blur(w, r)
            ok = (b > 1e-4) & ~filled
            out[ok] = a[ok] / b[ok][:, None]
            filled |= ok
        if (~filled).any():
            out[~filled] = col[m].mean(axis=0) if m.any() else 0
        rgb = Image.fromarray(np.clip(out, 0, 255).astype(np.uint8)).resize((self.w, self.h), Image.LANCZOS)
        al = Image.fromarray((alpha * 255 + 0.5).astype(np.uint8)).resize((self.w, self.h), Image.BOX)
        img = rgb.convert("RGBA")
        img.putalpha(al)
        return img


def _pal(names):
    return [np.array(rgb8(c), float) for c in names]


def _shade(pal, v):
    """Цвет палитры по светлоте v 0..1 — мягкие ступени, как у живописца (массы, а не шум)."""
    t = np.clip(v, 0.0, 0.999) * (len(pal) - 1)
    i = int(t)
    f = t - i
    f = f * f * (3 - 2 * f)
    return pal[i] * (1 - f) + pal[min(i + 1, len(pal) - 1)] * f


def _height(w, h, lobes):
    """Гроздь как объединение полусфер-лопастей (cx, cy, rx, ry, z) в пикселях: высота,
    нормаль (x вправо, y вверх, z к зрителю), затенение складок между лопастями."""
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32) + 0.5
    H = np.full((h, w), -1.0, np.float32)
    for (cx, cy, rx, ry, z) in lobes:
        q = 1.0 - ((xx - cx) / rx) ** 2 - ((yy - cy) / ry) ** 2
        hk = np.where(q > 0, z + min(rx, ry) * np.sqrt(np.clip(q, 0, 1)), -1.0)
        H = np.maximum(H, hk)
    return _field(w, h, H)


def _height_tongues(w, h, tongues):
    """Языки пламени (перо тополя): у языка гладкий профиль — узкий заострённый верх, шире
    всего на трети высоты, низ сходится мягко; высота поперёк — цилиндр (свет ложится
    вертикальной полосой вдоль гребня, без «ступенек» шаров). tongues — (ось x, верх y,
    низ y, полуширина, наклон верха по x, z)."""
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32) + 0.5
    H = np.full((h, w), -1.0, np.float32)
    for (cx, ytop, ybot, hw, lean, z) in tongues:
        t = np.clip((ybot - yy) / (ybot - ytop), 0.0, 1.0)          # 0 — низ, 1 — верх
        k = 0.34
        prof = np.where(t < k, (t / k) ** 0.55, ((1.0 - t) / (1.0 - k)) ** 0.85) * hw
        prof = np.where((yy < ytop) | (yy > ybot), 0.0, prof)
        ax = cx + lean * t * t
        q = 1.0 - ((xx - ax) / np.maximum(prof, 1e-3)) ** 2
        hk = np.where((q > 0) & (prof > 1.0), z + prof * np.sqrt(np.clip(q, 0, 1)), -1.0)
        H = np.maximum(H, hk)
    return _field(w, h, H)


def _field(w, h, H):
    inside = H > 0
    Hs = np.where(inside, H, 0.0).astype(np.float32)
    gy, gx = np.gradient(_box_blur(Hs, 3))
    n = np.dstack([-gx, gy, np.ones_like(gx)])
    n /= np.linalg.norm(n, axis=2, keepdims=True)
    k = max(4, int(min(w, h) * 0.05))
    occ = np.clip((_box_blur(Hs, k) - Hs) / k, 0, 1)
    return H, n, occ, inside, gx, gy


def paint_clump(t: Tile, lobes, pal, leaves, leaf_len, leaf_w, light=(0.0, 0.8, 0.6),
                droop=0.2, upward=0.0, edge_bias=1.6, asym=0.3, bend=0.25, silver=None, silver_p=0.0,
                top_light=0.14, k_lit=0.32, v0=0.36, k_occ=0.5, noise=0.06, steps=5, glaze=1.0, sparkle=0.035,
                axis=None, tufts=0, field=None, sub_glaze=None):
    """Гроздь листьев-мазков. Свет внутри грозди нарисован по её форме (лопасти как шары,
    свет сверху и чуть спереди — небо, солнце кладёт шейдер), складки темнее. Светлота
    листа сведена к нескольким ступеням (steps) — листья складываются в живописные массы,
    а не в мозаику. Затем светлые и тёмные лессировки крупной кистью, сверху — редкие блики.
    axis — направление листьев (радианы, y вниз), если задано (перья тополя)."""
    rs = t.rs
    L3 = np.array(light, float)
    L3 /= np.linalg.norm(L3)
    P = _pal(pal)
    S = _pal(silver) if silver else None
    H, N, occ, inside, gx, gy = field if field is not None else _height(t.w, t.h, lobes)
    lit = np.clip(N @ L3, -1, 1)
    Hmax = max(float(H.max()), 1.0)
    # 1) тёмная подложка: гроздь чуть меньше силуэта — просветы внутри тёмные
    for (cx, cy, rx, ry, z) in lobes:
        t.blob(cx, cy, rx * 0.82, ry * 0.82, P[0] * 0.5 + P[1] * 0.5, noise=0.18)
    if not lobes:                                       # поле задано готовым (языки тополя)
        core = Image.fromarray(((H > Hmax * 0.18) * 255).astype(np.uint8)).resize(
            (t.w * SS, t.h * SS), Image.BILINEAR).point(lambda q: 255 if q > 127 else 0)
        t.col.paste(tuple(int(c) for c in P[0] * 0.5 + P[1] * 0.5), mask=core)
        t.msk.paste(255, mask=core)
    # 2) листья: гуще у края (рваный силуэт), направление — наружу по склону грозди
    ys, xs = np.nonzero(inside)
    hn = H[ys, xs] / Hmax
    wgt = 0.3 + (1.0 - hn) ** edge_bias
    wgt /= wgt.sum()
    pick = rs.choice(len(xs), size=leaves, p=wgt)
    items = []
    for i in pick:
        yi, xi = int(ys[i]), int(xs[i])
        x = xi + rs.uniform(0, 1)
        y = yi + rs.uniform(0, 1)
        ox, oy = -float(gx[yi, xi]), -float(gy[yi, xi])
        g = math.hypot(ox, oy)
        a_out = math.atan2(oy, ox) if g > 0.05 else rs.uniform(0, 2 * np.pi)
        edge = 1.0 - float(hn[i])
        if axis is not None:
            ang = axis + rs.normal(0, 0.35) + math.sin(a_out) * 0.0 + (math.cos(a_out) * 0.5 * edge)
        else:
            dx = math.cos(a_out) * (0.3 + edge) + rs.normal(0, 0.5)
            dy = math.sin(a_out) * (0.3 + edge) + rs.normal(0, 0.5) + droop - upward
            ang = math.atan2(dy, dx)
        Ln = rs.uniform(*leaf_len) * (0.85 + 0.35 * edge)
        Wd = Ln * rs.uniform(*leaf_w)
        tipx, tipy = x + math.cos(ang) * Ln * 0.5, y + math.sin(ang) * Ln * 0.5
        if not (12 < tipx < t.w - 12 and 12 < tipy < t.h - 12):
            continue
        gtop = 0.5 - y / t.h
        v = v0 + k_lit * float(lit[yi, xi]) + top_light * gtop - k_occ * float(occ[yi, xi])
        if steps:
            v = 0.45 * v + 0.55 * (round(v * steps) / steps)        # массы: ступени светлоты
        v += rs.normal(0, noise)
        items.append((v, x, y, Ln, Wd, ang))
    # 2б) вихры: веточки листьев выбиваются за край грозди — силуэт рваный, «кистевой»,
    #     а не круглый шарик
    edge_idx = np.nonzero(hn < 0.12)[0]
    margin = 17
    for _ in range(tufts if len(edge_idx) else 0):
        i = edge_idx[rs.integers(len(edge_idx))]
        yi, xi = int(ys[i]), int(xs[i])
        ox, oy = -float(gx[yi, xi]), -float(gy[yi, xi])
        a_out = math.atan2(oy, ox) if math.hypot(ox, oy) > 0.02 else rs.uniform(0, 2 * np.pi)
        dx, dy = math.cos(a_out), math.sin(a_out) + droop * 0.5
        if axis is not None:
            dx, dy = dx * 0.55 + math.cos(axis), dy * 0.55 + math.sin(axis)
        else:
            dy -= upward * 0.6
        a = math.atan2(dy, dx)
        reach = rs.uniform(1.0, 2.0) * leaf_len[1]
        gtop = 0.5 - yi / t.h
        vb = v0 + k_lit * float(lit[yi, xi]) + top_light * gtop + rs.normal(0, 0.05)
        for j in range(int(rs.integers(4, 9))):
            f = rs.uniform(0.15, 1.0)
            px = xi + math.cos(a) * reach * f + rs.normal(0, leaf_len[0] * 0.25)
            py = yi + math.sin(a) * reach * f + rs.normal(0, leaf_len[0] * 0.25)
            Ln = rs.uniform(*leaf_len) * (1.0 - 0.3 * f)
            ang = a + rs.normal(0, 0.55)
            ex, ey = abs(math.cos(ang)) * Ln * 0.5, abs(math.sin(ang)) * Ln * 0.5
            if not (margin + ex < px < t.w - margin - ex and margin + ey < py < t.h - margin - ey):
                continue
            items.append((vb + rs.normal(0, noise), px, py, Ln, Ln * rs.uniform(*leaf_w), ang))
    items.sort(key=lambda q: q[0])
    for (v, x, y, Ln, Wd, ang) in items:
        col = _shade(P, v) * rs.uniform(0.97, 1.03)
        if S is not None and rs.random() < silver_p * (0.3 + np.clip(v, 0, 1)):
            col = 0.45 * col + 0.55 * S[rs.integers(len(S))] * (0.5 + 0.5 * np.clip(v, 0, 1))
        t.leaf(x, y, Ln, Wd, ang, col, asym=asym, bend=rs.normal(0, bend))
    # 3) лессировки: светлая — по освещённой шапке каждой лопасти (мазки по форме),
    #    тёмная — по низу и в складках
    if glaze > 0:
        for (cx, cy, rx, ry, z) in lobes:
            r = min(rx, ry)
            for _ in range(int(rs.integers(2, 5) * glaze)):
                a = math.radians(rs.uniform(225, 315))          # верх (y вниз)
                px = cx + math.cos(a) * rx * rs.uniform(0.25, 0.6)
                py = cy + math.sin(a) * ry * rs.uniform(0.25, 0.6)
                t.glaze(px, py, r * rs.uniform(0.6, 1.0), r * rs.uniform(0.18, 0.3),
                        a + math.pi / 2 + rs.normal(0, 0.2), _shade(P, 0.82 + rs.uniform(-0.05, 0.12)),
                        rs.uniform(0.12, 0.24))
            for _ in range(int(rs.integers(1, 4) * glaze)):
                a = math.radians(rs.uniform(40, 140))           # низ
                px = cx + math.cos(a) * rx * rs.uniform(0.35, 0.7)
                py = cy + math.sin(a) * ry * rs.uniform(0.35, 0.7)
                t.glaze(px, py, r * rs.uniform(0.7, 1.1), r * rs.uniform(0.2, 0.35),
                        a + math.pi / 2 + rs.normal(0, 0.2), _shade(P, 0.06 + rs.uniform(0, 0.1)),
                        rs.uniform(0.14, 0.26), bristles=2)
    # 4) блики: редкие светлые листья на самой освещённой части
    best = [q for q in items if q[0] > 0.72]
    for _ in range(min(int(leaves * sparkle), len(best))):
        v, x, y, Ln, Wd, ang = best[rs.integers(len(best))]
        for _k in range(int(rs.integers(2, 5))):        # блик — пучок из нескольких мазков
            t.leaf(x + rs.normal(0, Ln * 0.35), y + rs.normal(0, Ln * 0.25), Ln * 0.7, Wd * 0.7,
                   ang + rs.normal(0, 0.3), _shade(P, 0.93) * rs.uniform(0.98, 1.04), asym=asym, mask=False)


def _lobes_cloud(w, h, rs, n, r_main, spread, squash=1.0, cy=0.52):
    """Неровная гроздь: главная лопасть и n лопастей разного размера вокруг; лопасти не
    по кругу («цветок»), а со случайным шагом, сверху крупнее (шапка), снизу мельче."""
    cx, cy = w * 0.5, h * cy
    out = [(cx + rs.normal(0, w * 0.02), cy, r_main, r_main * squash, r_main * 0.25)]
    a0 = rs.uniform(0, 2 * np.pi)
    angs = np.sort(a0 + np.cumsum(rs.uniform(0.6, 1.5, n)))
    for a in angs:
        up = -math.sin(a)                                   # 1 — вверху (y вниз)
        d = spread * rs.uniform(0.55, 1.05) * (1.0 + 0.15 * up)
        r = r_main * rs.uniform(0.45, 0.78) * (0.85 + 0.25 * max(up, 0))
        z = rs.uniform(-0.1, 0.35) * r_main
        x, y = cx + math.cos(a) * d, cy + math.sin(a) * d * squash
        r = min(r, x - 10, w - 10 - x, (y - 10) / squash, (h - 10 - y) / squash)
        if r > r_main * 0.25:
            out.append((x, y, r, r * squash, z))
    return out


def elm_clump(w, h, seed, edge=False):
    """Карагач: плотная округлая гроздь; листья-мазки крупные (живописные массы, а не
    «мозаика» мелких точек), светлота сведена к трём-четырём ступеням; «краевые» грозди
    рваные — вихры веточек за край."""
    t = Tile(w, h, seed)
    rs = t.rs
    if edge:
        lobes = _lobes_cloud(w, h, rs, 4, w * 0.2, w * 0.17)
        paint_clump(t, lobes, PAL["elm"], 1500, (26, 42), (0.5, 0.62), edge_bias=2.2, droop=0.3, tufts=34,
                    sparkle=0.012, glaze=0.7, k_occ=0.6, k_lit=0.24, v0=0.4)
    else:
        lobes = _lobes_cloud(w, h, rs, 6, w * 0.23, w * 0.2)
        paint_clump(t, lobes, PAL["elm"], 1900, (30, 48), (0.5, 0.62), edge_bias=1.6, droop=0.25, tufts=22,
                    sparkle=0.012, glaze=0.7, k_occ=0.6, k_lit=0.24, v0=0.4)
    return t.finish(spread=14)


def poplar_feather(w, h, seed):
    """Терек: одно вытянутое вверх «перо» — 3–4 узких языка пламени, сходящихся к острой
    макушке. Профиль языка гладкий (не стопка шаров): свет по гребню языка вертикальной
    полосой, между языками тёмные борозды; листья-мазки тянутся вверх, по краю — рваные
    вихры, редкое серебро изнанки (белый тополь)."""
    t = Tile(w, h, seed)
    rs = t.rs
    tongues = [(w * 0.5 + rs.normal(0, w * 0.02), h * 0.05, h * 0.97, w * 0.27, rs.normal(0, w * 0.03), 0.16 * w)]
    for side in (-1, 1):                                  # боковые языки ниже и короче
        top = h * rs.uniform(0.2, 0.34)
        tongues.append((w * (0.5 + side * rs.uniform(0.15, 0.2)), top, h * rs.uniform(0.86, 0.96),
                        w * rs.uniform(0.17, 0.21), side * w * rs.uniform(-0.06, 0.02), 0.06 * w))
    if rs.random() < 0.7:                                 # невысокий язык сзади-сбоку
        side = rs.choice([-1, 1])
        tongues.append((w * (0.5 + side * 0.26), h * rs.uniform(0.45, 0.6), h * 0.95, w * 0.14,
                        side * w * 0.03, 0.0))
    field = _height_tongues(w, h, tongues)
    paint_clump(t, [], PAL["poplar"], 2300, (15, 24), (0.34, 0.46), light=(-0.35, 0.45, 0.82),
                edge_bias=1.5, asym=0.45, bend=0.12, silver=PAL["poplar_silver"], silver_p=0.03,
                top_light=0.22, k_lit=0.85, v0=-0.04, k_occ=0.9, axis=-math.pi / 2, glaze=0.0, tufts=16,
                field=field, sparkle=0.0)
    # лессировки вдоль языков: светлый гребень слева-сверху
    P = _pal(PAL["poplar"])
    for (cx, ytop, ybot, hw, lean, z) in tongues:
        for _ in range(3):
            f = rs.uniform(0.1, 0.55)
            y = ytop + (ybot - ytop) * f
            t.glaze(cx - hw * 0.3 + lean * (1 - f) ** 2, y, (ybot - ytop) * rs.uniform(0.25, 0.4), hw * 0.35,
                    -math.pi / 2 + rs.normal(0, 0.05), _shade(P, 0.86), rs.uniform(0.08, 0.14), bristles=0)
    return t.finish(spread=12)


def willow_clump(w, h, seed):
    """Тал, верх кроны: узкие свисающие листья, гроздь чуть вытянута вниз."""
    t = Tile(w, h, seed)
    rs = t.rs
    lobes = _lobes_cloud(w, h, rs, 5, w * 0.22, w * 0.22, squash=0.85, cy=0.46)
    paint_clump(t, lobes, PAL["willow"], 3200, (28, 44), (0.15, 0.22), droop=1.1, edge_bias=1.8,
                asym=0.15, bend=0.35, silver=PAL["willow_silver"], silver_p=0.05, tufts=16)
    return t.finish(spread=12)


def juniper_pad(w, h, seed):
    """Арча: плоский комок плотной чешуйчатой хвои — неровный верх из нескольких бугров
    разной высоты, сизые светлые кончики сверху, почти чёрный низ; веточки торчат вверх и
    вбок (силуэт рваный, а не «стриженая изгородь»)."""
    t = Tile(w, h, seed)
    rs = t.rs
    lobes = []
    n = int(rs.integers(4, 6))
    for i in range(n):
        f = i / (n - 1)
        x = w * (0.16 + 0.68 * f) + rs.normal(0, w * 0.03)
        rx = w * rs.uniform(0.11, 0.17) * (1.15 - 0.4 * abs(f - 0.5))
        ry = h * rs.uniform(0.18, 0.3) * (1.3 - 0.8 * abs(f - 0.5))
        rx = min(rx, x - 14, w - 14 - x)
        lobes.append((x, h * 0.62 - ry * 0.35 + rs.normal(0, h * 0.05), rx, ry, rs.uniform(0, 0.3) * ry))
    lobes.append((w * 0.5, h * 0.68, w * 0.32, h * 0.17, 0.0))
    paint_clump(t, lobes, PAL["juniper"], 2000, (15, 25), (0.45, 0.7), light=(0.0, 0.9, 0.4),
                droop=0.0, upward=0.45, edge_bias=1.9, asym=0.15, bend=0.4, top_light=0.36, k_lit=0.55,
                v0=0.22, k_occ=0.8, noise=0.05, tufts=40, sparkle=0.012)
    return t.finish(spread=10)


def willow_strands(w, h, seed):
    """Тал: «каскад» прядей. Наверху — узел листвы (ветвь под куполом), из него пряди дугой
    уходят наружу (к +x; шейдер зеркалит карточку на левой стороне кроны, поэтому дуги всегда
    расходятся от ствола) и свисают почти отвесно. Пряди пучками (2–3) разной длины: между
    пучками просветы, низ рваный, а не «занавеска». Дальние пряди тёмные, ближние — светлее,
    верх пряди в тени купола, низ и кончики ловят свет; наружный край светлее."""
    t = Tile(w, h, seed)
    rs = t.rs
    P = _pal(PAL["willow"])
    S = _pal(PAL["willow_silver"])
    strands = []
    nb = int(rs.integers(2, 4))
    for g in range(nb):
        gx = w * (0.12 + 0.3 * g / max(nb - 1, 1)) + rs.normal(0, w * 0.03)
        reach_g = min(w * rs.uniform(0.08, 0.36), w * 0.78 - gx)
        len_g = h * rs.uniform(0.55, 0.95)
        lay_g = rs.uniform(0.0, 1.0)
        for j in range(int(rs.integers(3, 6))):
            strands.append((float(np.clip(lay_g + rs.normal(0, 0.2), 0, 1)), gx + rs.normal(0, w * 0.04),
                            h * rs.uniform(0.02, 0.09), reach_g * rs.uniform(0.75, 1.25),
                            len_g * rs.uniform(0.72, 1.05)))
    strands.sort(key=lambda q: q[0])
    margin = 14
    # узел наверху: тёмная гроздь коротких листьев прячет начало прядей
    for _ in range(110):
        r = math.sqrt(rs.random())
        a = rs.uniform(0, 2 * np.pi)
        x = w * (0.3 + 0.2 * r * math.cos(a))
        y = h * (0.055 + 0.04 * r * math.sin(a))
        ang = math.pi / 2 + rs.normal(0.3, 0.5)
        Ln = rs.uniform(20, 30)
        t.leaf(x, y, Ln, Ln * rs.uniform(0.22, 0.3), ang, _shade(P, rs.uniform(0.1, 0.32)), asym=0.1,
               bend=rs.normal(0, 0.3))
    for (layer, x0, y0, reach, L) in strands:
        n = max(int(L / 7), 8)
        sway = rs.normal(0, w * 0.035)
        ph = rs.uniform(0, 6.28)
        pts = []
        for i in range(n):
            sl = i / (n - 1)
            a = min(sl / 0.32, 1.0)
            x = x0 + reach * (1.0 - (1.0 - a) ** 2) + sway * sl * sl + math.sin(sl * 5 + ph) * 2.5
            y = y0 + L * sl - h * 0.03 * math.sin(math.pi * a)
            # к краю карточки прядь не прижимается (иначе у каскада прямой вертикальный бок)
            lim = w - margin - 18
            if x > lim - 20:
                x = lim - 20 * math.exp(-(x - lim + 20) / 20)
            pts.append((max(float(x), margin + 18), y))
        for i in range(n - 1):                             # тёмный прутик
            (xa, ya), (xb, yb) = pts[i], pts[i + 1]
            wd = 1.5 * (1 - 0.6 * i / n)
            t.poly([(xa - wd, ya), (xa + wd, ya), (xb + wd * 0.9, yb), (xb - wd * 0.9, yb)],
                   _shade(P, 0.16 + 0.14 * layer))
        for i in range(1, n):
            sl = i / (n - 1)
            x, y = pts[i]
            (xp, yp) = pts[i - 1]
            dir_a = math.atan2(y - yp, x - xp)              # направление пряди
            for side in (-1, 1):
                if rs.random() > 0.9:
                    continue
                ang = dir_a + side * rs.uniform(0.25, 0.6)
                out = (x - x0) / max(reach, 1.0)            # наружная часть дуги светлее
                v = (0.24 + 0.3 * layer + 0.3 * sl ** 0.7 * (0.45 + 0.55 * layer) + 0.08 * (side > 0)
                     + 0.06 * min(out, 1.0) + rs.normal(0, 0.05))
                v = 0.5 * v + 0.5 * round(v * 5) / 5
                col = _shade(P, v) * rs.uniform(0.97, 1.03)
                if rs.random() < 0.06 * (0.5 + layer):
                    col = S[rs.integers(len(S))] * (0.6 + 0.3 * layer)
                Ln = rs.uniform(22, 32) * (1 - 0.35 * sl)
                lx = x + math.cos(ang) * Ln * 0.42
                ly = y + math.sin(ang) * Ln * 0.42
                if not (margin < lx < w - margin and ly < h - margin):
                    continue
                t.leaf(lx, ly, Ln, Ln * rs.uniform(0.2, 0.27), ang, col, asym=0.1, bend=rs.normal(0, 0.3))
    return t.finish(spread=10)


# ---------------------------------------------------------------- кора

def bark(w, h, seed, kind):
    """Кора (бесшовная по окружности): мазки вдоль ствола, борозды, у комля темнее.
    Свет не нарисован — его кладёт живописный свет шейдера по настоящему солнцу."""
    if kind == "poplar":
        c = Canvas(w, h, base="#8c8f80", seed=seed, tile=True)
        c.underpaint(["#7e8274", "#8f9283", "#a2a493", "#878a7b"], cell=48, octaves=3)
        c.strokes(500, ["#9b9e8e", "#a9ab9a", "#858878", "#b4b4a2"], length=(30, 90), width=(5, 12), angle=90,
                  angle_jitter=4, alpha=(0.25, 0.55), bristles=4, curve=0.1)
        rs = np.random.default_rng(seed + 1)
        for _ in range(70):                              # ромбы-чечевички (белый тополь)
            x, y = rs.uniform(0, w), rs.uniform(0, h * 0.85)
            rx, ry = rs.uniform(4, 10), rs.uniform(3, 6)
            c.polygon([(x, y - ry), (x + rx, y), (x, y + ry), (x - rx, y)], "#3d3d36", alpha=rs.uniform(0.6, 0.9),
                      wobble=0.8, seed=int(x * 13 + y))
        for _ in range(60):                              # горизонтальные штрихи
            x, y = rs.uniform(0, w), rs.uniform(0, h)
            c.line([(x, y), (x + rs.uniform(8, 22), y + rs.normal(0, 1))], 1.6, "#5a5a50", alpha=0.5, wobble=0.4,
                   seed=int(x + y * 7))
        # комель старый: тёмный, в бороздах
        m = np.zeros((h * SS, w * SS))
        m[int(h * SS * 0.78):] = 1.0
        m = _box_blur(m, 20 * SS)
        c.underpaint(["#4e4c43", "#5d5a50", "#46443c"], cell=40, mask=m)
        c.strokes(220, ["#2f2d28", "#3a3832", "#6a675c"], length=(30, 80), width=(3, 7), angle=90, angle_jitter=6,
                  alpha=(0.4, 0.8), bristles=2, region=(0, h * 0.8, w, h))
    elif kind == "juniper":
        c = Canvas(w, h, base="#5e3424", seed=seed, tile=True)
        c.underpaint(["#4e2a1d", "#633826", "#74432c", "#5a3122"], cell=40, octaves=3)
        # волокнистые ленты, закрученные по стволу
        c.strokes(900, ["#7c4a32", "#8e583c", "#5a2f20", "#6d3c29", "#9b6a4c"], length=(50, 140), width=(3, 8),
                  angle=78, angle_jitter=5, alpha=(0.35, 0.8), bristles=3, curve=0.15, taper=0.3)
        c.strokes(260, ["#2a1710", "#331c13"], length=(60, 160), width=(1.5, 3), angle=78, angle_jitter=4,
                  alpha=(0.5, 0.9), bristles=1, curve=0.12)
        # серебристые выветренные полосы и сухой верх (верхняя четверть — сухие сучья)
        c.strokes(140, ["#8c857a", "#9e978a", "#7a746a"], length=(40, 120), width=(3, 7), angle=78,
                  angle_jitter=5, alpha=(0.3, 0.65), bristles=3, region=(0, h * 0.25, w, h))
        m = np.zeros((h * SS, w * SS))
        m[: int(h * SS * 0.25)] = 1.0
        c.underpaint(["#8a8478", "#9c968a", "#a9a395", "#7c766b"], cell=30, mask=m)
        c.strokes(160, ["#6b665d", "#b4ae9f", "#5a554d"], length=(30, 90), width=(1.5, 4), angle=80, angle_jitter=5,
                  alpha=(0.35, 0.7), bristles=2, region=(0, 0, w, h * 0.25))
    else:
        dark = kind == "elm"
        base = "#3d342c" if dark else "#4c4135"
        c = Canvas(w, h, base=base, seed=seed, tile=True)
        c.underpaint(["#352d26", base, "#4a3f35", "#40362d"] if dark else ["#433829", base, "#5b4d3d", "#4a3e31"],
                     cell=44, octaves=3)
        # гребни коры (светлее) и борозды между ними
        c.strokes(700, ["#55493d", "#62554a", "#4b4037", "#6e6255"] if dark else ["#64553f", "#73624b", "#5a4c3b",
                                                                                 "#82705a"],
                  length=(40, 120), width=(5, 11), angle=lambda x, y: 90 + 9 * math.sin(y * 0.05 + x * 0.08),
                  angle_jitter=6, alpha=(0.35, 0.75), bristles=4, curve=0.2)
        c.strokes(300, ["#1c1814", "#231d18", "#2a221c"], length=(50, 150), width=(1.5, 3.5),
                  angle=lambda x, y: 90 + 12 * math.sin(y * 0.04 + x * 0.1), angle_jitter=5, alpha=(0.55, 0.9),
                  bristles=1, curve=0.25)
        c.strokes(120, ["#7d7064", "#8a7d70"] if dark else ["#937f66", "#a08b70"], length=(14, 40), width=(2, 4),
                  angle=90, angle_jitter=8, alpha=(0.25, 0.5), bristles=2)
    # у комля темнее и холоднее (земля, тень травы)
    c.gradient("#ffffff", "#8c8a8a", strength=0.35)
    c.grain(0.03)
    return c.image().convert("RGBA")


def build_atlas():
    A = Image.new("RGBA", (ATLAS, ATLAS), (0, 0, 0, 0))

    def put(img, reg):
        A.paste(img, (reg[0], reg[1]))

    for i, reg in enumerate(REG["elm"]):
        put(elm_clump(reg[2], reg[3], 100 + i), reg)
    for i, reg in enumerate(REG["elm_edge"]):
        put(elm_clump(reg[2], reg[3], 110 + i, edge=True), reg)
    for i, reg in enumerate(REG["poplar"]):
        put(poplar_feather(reg[2], reg[3], 120 + i), reg)
    for i, reg in enumerate(REG["strand"]):
        put(willow_strands(reg[2], reg[3], 130 + i), reg)
    for i, reg in enumerate(REG["juniper"]):
        put(juniper_pad(reg[2], reg[3], 140 + i), reg)
    for i, reg in enumerate(REG["willow"]):
        put(willow_clump(reg[2], reg[3], 150 + i), reg)
    for k, kind in enumerate(["elm", "willow", "poplar", "juniper"]):
        reg = REG["bark_" + kind]
        put(bark(reg[2], reg[3], 160 + k, kind), reg)
    os.makedirs(OUT_TEX, exist_ok=True)
    A.save(os.path.join(OUT_TEX, "trees.png"), optimize=True)
    print("   trees.png")


# =====================================================================
# Геометрия
# =====================================================================

def _unit(v):
    v = np.asarray(v, float)
    n = np.linalg.norm(v)
    return v / n if n > 1e-9 else np.array([0.0, 1.0, 0.0])


def _uv(reg):
    x, y, w, h = reg
    e = 1.0                                          # отступ в пиксель от соседей
    return ((x + e) / ATLAS, (y + e) / ATLAS, (x + w - e) / ATLAS, (y + h - e) / ATLAS)


class Tree:
    """Части одного дерева: кора (трубки) и карточки листвы."""

    def __init__(self, seed, height):
        self.rs = np.random.default_rng(seed)
        self.H = height
        self.parts: list[Mesh] = []
        self.cards = 0

    def bend_w(self, y):
        """Сила изгиба на ветру по высоте (одна для ствола и листвы)."""
        return float(np.clip(y / self.H, 0.0, 1.0) ** 1.6)

    def card(self, center, n, w, h, reg, ao, kind=1, roll=0.0, mirror=None):
        c = np.asarray(center, float)
        n = _unit(n)
        if kind == 2:
            n = _unit([n[0], 0.0, n[2]])             # прядь: плоскость покоя вертикальна
        r = np.cross(UP, n)
        r = np.array([1.0, 0.0, 0.0]) if np.linalg.norm(r) < 1e-3 else r / np.linalg.norm(r)
        u = np.cross(n, r)
        if kind == 2:
            cor = np.array([[-w / 2, -h], [w / 2, -h], [w / 2, 0.0], [-w / 2, 0.0]])
        else:
            cor = np.array([[-w / 2, -h / 2], [w / 2, -h / 2], [w / 2, h / 2], [-w / 2, h / 2]])
            if roll:
                ca, sa = math.cos(roll), math.sin(roll)
                cor = cor @ np.array([[ca, sa], [-sa, ca]])
        P = c + cor[:, :1] * r + cor[:, 1:] * u
        u0, v0, u1, v1 = _uv(reg)
        if mirror if mirror is not None else self.rs.random() < 0.5:
            u0, u1 = u1, u0
        UVs = np.array([[u0, v1], [u1, v1], [u1, v0], [u0, v0]])
        UV2 = cor.copy()
        UV2[:, 0] += 20.0 * kind
        ao = float(np.clip(ao, 0.2, 1.1))
        C = np.tile([ao, ao, ao, self.bend_w(c[1])], (4, 1))
        m = Mesh(P, [[0, 1, 2], [0, 2, 3]], np.tile(n, (4, 1)), UVs, UV2, C)
        self.parts.append(m)
        self.cards += 1

    def wood(self, path, radii, sides, reg, ao_base=0.6, ao_top=1.0, v_from=0.0, v_to=1.0, v_pow=1.0):
        """Ствол или ветвь: трубка, развёртка коры от комля (низ области) вверх."""
        path = np.asarray(path, float)
        m = tube(path, radii, sides=sides, uv_len=1.0)
        L = np.r_[0, np.cumsum(np.linalg.norm(np.diff(path, axis=0), axis=1))]
        cols = sides + 1
        s = np.repeat(L / max(L[-1], 1e-6), cols)
        u0, v0, u1, v1 = _uv(reg)
        vv = v_from + (v_to - v_from) * s ** v_pow
        m.UV = np.column_stack([u0 + m.UV[:, 0] * (u1 - u0), v1 - vv * (v1 - v0)])
        ao = ao_base + (ao_top - ao_base) * np.clip(s, 0, 1)
        m.C = np.column_stack([ao, ao, ao, [self.bend_w(y) for y in m.P[:, 1]]])
        m.has_color = True
        m.UV2 = np.zeros((len(m.P), 2))
        m.has_uv2 = True
        self.parts.append(m)
        return m

    def mesh(self) -> Mesh:
        m = Mesh.merge(self.parts)
        # рамка видимости: карточка, развёрнутая к камере, выходит за свою позу покоя на полдиагонали —
        # добавляем вырожденный (нулевой площади) треугольник по углам такой рамки, чтобы движок
        # не отсекал крону раньше времени
        lo, hi = m.P.min(axis=0), m.P.max(axis=0)
        k = np.floor(m.UV2[:, 0] / 20.0 + 0.5)
        o = m.UV2[:, 0] - 20.0 * k
        half = np.where(k > 0.5, np.hypot(o, m.UV2[:, 1]), 0.0)
        if half.max() > 0:
            ctr = m.P.copy()
            lo = np.minimum(lo, (ctr - half[:, None]).min(axis=0))
            hi = np.maximum(hi, (ctr + half[:, None]).max(axis=0))
        lo[1] = 0.0
        pad = Mesh(np.array([lo, hi, (lo + hi) * 0.5]), [[0, 1, 2]], np.tile([0.0, 1.0, 0.0], (3, 1)),
                   np.zeros((3, 2)), np.zeros((3, 2)), np.tile([1.0, 1.0, 1.0, 0.0], (3, 1)))
        m = Mesh.merge([m, pad])
        m.P[:, 1] = np.maximum(m.P[:, 1], 0.0)        # кольцо наклонного ствола не уходит под землю
        return m


def _curve(pts, n):
    """Гладкая кривая (Катмулл — Ром) через опорные точки, n точек."""
    P = np.asarray(pts, float)
    P = np.vstack([2 * P[0] - P[1], P, 2 * P[-1] - P[-2]])
    out = []
    segs = len(P) - 3
    for i in range(n):
        t = i / (n - 1) * segs
        k = min(int(t), segs - 1)
        f = t - k
        p0, p1, p2, p3 = P[k], P[k + 1], P[k + 2], P[k + 3]
        out.append(0.5 * ((2 * p1) + (-p0 + p2) * f + (2 * p0 - 5 * p1 + 4 * p2 - p3) * f * f
                          + (-p0 + 3 * p1 - 3 * p2 + p3) * f ** 3))
    return np.array(out)


def _flare(n, r0, r1, flare=0.5, power=5.0):
    """Радиусы ствола: сужение к верху и расширение у комля."""
    t = np.linspace(0, 1, n)
    return (r0 + (r1 - r0) * t) * (1.0 + flare * (1 - t) ** power)


def _ao_in_crown(p, cc, cr, k_depth=0.5, k_bottom=0.3):
    d = np.linalg.norm((np.asarray(p) - cc) / cr)
    depth = 1.0 - np.clip(d, 0, 1)
    hb = np.clip((p[1] - (cc[1] - cr[1])) / (2 * cr[1]), 0, 1)
    return (1.0 - k_depth * depth) * (1.0 - k_bottom * (1 - hb))


def _rand_dir(rs, around=None, min_dot=-1.0):
    for _ in range(64):
        d = rs.normal(0, 1, 3)
        d /= np.linalg.norm(d)
        if around is None or np.dot(d, around) >= min_dot:
            return d
    return np.asarray(around, float)


# ---------------------------------------------------------------- общие части кроны

def _mass(T, lc, lr, n, size, regs, cc, cr, k_lobe=0.65, ao_mul=1.0, spread=(0.3, 0.92), out_bias=-0.35,
          roll=0.5, aspect=1.0, up_bias=0.0, kind=1, regs_edge=None):
    """Масса листвы (лопасть кроны): n карточек внутри эллипсоида lc ± lr. Нормаль карточки —
    от центра лопасти (k_lobe) и от центра кроны: каждая лопасть лепится солнцем как один
    крупный объём (светлая сторона, тень, тёплая полоса между ними), а не россыпь шариков.
    kind 3 — «масса» (шейдер ослабляет купол карточки); regs_edge — рваные грозди для карточек
    на наружной стороне кроны (силуэт)."""
    rs = T.rs
    lc = np.asarray(lc, float)
    lr = np.asarray(lr, float)
    n_l = _unit((lc - cc) / cr)
    for _ in range(n):
        d = _rand_dir(rs, n_l, out_bias)
        if up_bias:
            d = _unit(d + np.array([0.0, up_bias, 0.0]))
        p = lc + d * lr * rs.uniform(*spread)
        nn = _unit(k_lobe * _unit((p - lc) / lr) + (1.0 - k_lobe) * _unit((p - cc) / cr))
        sz = rs.uniform(*size)
        ao = _ao_in_crown(p, cc, cr) * ao_mul * (0.9 + 0.1 * np.dot(d, n_l))
        rg = regs
        if regs_edge is not None and np.dot(_unit((p - cc) / cr), n_l) > 0.2 and \
                np.linalg.norm((p - cc) / cr) > 0.75:
            rg = regs_edge
        T.card(p, nn, sz, sz * aspect, rg[rs.integers(len(rg))], ao, roll=rs.normal(0, roll), kind=kind)


# ---------------------------------------------------------------- карагач

def elm(seed, lod=0):
    """Карагач: прямой толстый ствол до развилки на ~3,4 м, 5–6 толстых ветвей, густая круглая
    крона ~9,5 м из десяти крупных лопастей (как у карагача в кишлаке — «шар» на стволе);
    снизу между лопастями видны ветви. Карточки крупные и их немного на лопасть — крона
    читается крупными массами света и тени, а не россыпью мелких шариков."""
    T = Tree(seed, 12.0)
    rs = T.rs
    fork = np.array([0.22, 3.4, 0.12])
    path = _curve([(0, 0, 0), (0.08, 1.2, 0.04), (0.16, 2.4, 0.08), fork], 6 if lod == 0 else 4)
    T.wood(path, _flare(len(path), 0.46, 0.34, 0.6, 6), 8 if lod == 0 else 6, REG["bark_elm"], 0.55, 0.8, 0, 0.55)
    cc = np.array([0.25, 7.6, 0.12])
    cr = np.array([4.5, 3.6, 4.5])
    lobes = [(cc + np.array([0.15, 0.55 * cr[1], -0.1]), np.array([2.7, 2.0, 2.7]))]
    a0 = rs.uniform(0, 2 * np.pi)
    for k in range(5):                                   # верхнее кольцо
        a = a0 + k * 2 * np.pi / 5 + rs.normal(0, 0.2)
        e = math.radians(rs.uniform(12, 28))
        d = np.array([math.cos(a) * math.cos(e), math.sin(e), math.sin(a) * math.cos(e)])
        r = rs.uniform(2.3, 2.7)
        lobes.append((cc + d * cr * rs.uniform(0.56, 0.66), np.array([r, r * 0.85, r])))
    for k in range(4):                                   # нижнее кольцо — между лопастями просветы
        a = a0 + (k + 0.5) * 2 * np.pi / 4 + rs.normal(0, 0.25)
        e = math.radians(rs.uniform(-30, -16))
        d = np.array([math.cos(a) * math.cos(e), math.sin(e), math.sin(a) * math.cos(e)])
        r = rs.uniform(2.0, 2.3)
        lobes.append((cc + d * cr * rs.uniform(0.58, 0.68), np.array([r, r * 0.78, r])))
    # ветви: от развилки к лопастям — толстые к нижним и боковым (видны под кроной)
    limbs = [6, 7, 8, 9, 2] if lod else [6, 7, 8, 9, 1, 2, 3, 4, 5]
    for j, li in enumerate(limbs):
        c, lr = lobes[li]
        tip = c - _unit(c - cc) * lr[0] * 0.35
        mid = fork + (tip - fork) * 0.5 + np.array([0, 0.4, 0]) + rs.normal(0, 0.25, 3)
        n = 4 if lod == 0 else 3
        r0 = 0.21 if j < 4 else 0.13
        T.wood(_curve([fork + rs.normal(0, 0.08, 3), mid, tip], n), np.linspace(r0, 0.05, n),
               5 if lod == 0 else 4, REG["bark_elm"], 0.7, 0.55, 0.5, 1.0)
    n_card = 11 if lod == 0 else 6
    size = (2.4, 3.1) if lod == 0 else (3.0, 3.8)
    for i, (c, lr) in enumerate(lobes):
        _mass(T, c, lr, n_card + (2 if i == 0 and lod == 0 else 0), size, REG["elm"], cc, cr,
              spread=(0.25, 0.85), kind=3, regs_edge=REG["elm_edge"] + REG["elm"][:2])
    for _ in range(3 if lod == 0 else 2):                # тёмное ядро кроны — не просвечивает насквозь
        p = cc + rs.normal(0, 1, 3) * cr * 0.18
        T.card(p, _rand_dir(rs), 4.2, 4.2, REG["elm"][rs.integers(4)], 0.35, roll=rs.uniform(-1, 1), kind=3)
    return T.mesh()


# ---------------------------------------------------------------- тополь

def _poplar_r(t):
    """Радиус колонны тополя по доле высоты кроны t (0 — низ кроны, 1 — макушка): низ кроны
    скруглён, шире всего на трети высоты, к макушке колонна сходится в узкое «пламя»."""
    return 1.3 * math.sin(math.pi * min(1.0, 0.16 + t * 0.92)) ** 0.5 * (1.0 - 0.35 * t) + 0.12


def poplar(seed, lod=0):
    """Терек (пирамидальный тополь): высокая узкая колонна ≈ 3,4 м на 19,5 м. Крона — длинные
    узкие «языки пламени» (карточки втрое выше ширины) по спирали с большим перекрытием по
    высоте — одна колонна в вертикальных мазках, а не стопка шаров; к макушке языки мельче и
    сходятся в острый шпиль. Ветви круто вверх вдоль ствола — видны в просветах низа кроны.
    Нормали — горизонтально от оси: колонна делится на светлую и теневую стороны."""
    H = 19.5
    T = Tree(seed, H)
    rs = T.rs
    top = np.array([0.12, H * 0.9, 0.08])
    path = _curve([(0, 0, 0), (0.04, 3.0, 0.02), (0.1, 9.0, 0.05), top], 8 if lod == 0 else 5)
    T.wood(path, _flare(len(path), 0.34, 0.05, 0.5, 6), 6 if lod == 0 else 5, REG["bark_poplar"], 0.6, 0.45,
           0, 1.0, 0.6)
    y0 = 2.1                                             # низ кроны
    nb = 7 if lod == 0 else 3
    for k in range(nb):                                  # ветви круто вверх — видны в нижних просветах
        y = y0 + 0.1 + k * 0.55 + rs.uniform(0, 0.35)
        a = k * 2.4 + rs.normal(0, 0.3)
        d = np.array([math.cos(a), 0, math.sin(a)])
        base = np.array([0.04 * y / 3, y, 0.0])
        L = rs.uniform(3.5, 5.0)
        tip = base + d * rs.uniform(0.6, 0.9) + np.array([0, L, 0])
        mid = base + d * 0.5 + np.array([0, L * 0.45, 0])
        T.wood(_curve([base, mid, tip], 3), np.linspace(0.1, 0.035, 3), 4, REG["bark_poplar"], 0.55, 0.5, 0.2, 0.6)
    hc = H - y0
    n_out = 100 if lod == 0 else 42
    for k in range(n_out):
        tt = float(np.clip((k + rs.uniform(0, 1)) / n_out, 0, 1))
        R = _poplar_r(tt)
        w = rs.uniform(1.25, 1.6) * (0.55 + 0.45 * R / 1.3) * (1.3 if lod else 1.0)
        hh = w * rs.uniform(2.5, 3.0)
        # центр карточки: нижние не опускаются ниже низа кроны, верхние не выше макушки
        y = y0 + hh * 0.42 + tt * (hc - hh * 0.42 - hh * 0.45)
        a = k * 2.39996 + rs.normal(0, 0.35)
        d = np.array([math.cos(a), 0.0, math.sin(a)])
        rr = R * rs.uniform(0.25, 0.75)
        if rs.random() < 0.08 and 0.15 < tt < 0.75:      # вихры: выбиваются из колонны
            rr = R * rs.uniform(0.85, 1.0)
        p = np.array([0.08 * tt, y, 0.05 * tt]) + d * rr
        nn = _unit(d + np.array([0, 0.1 + max(0.0, tt - 0.8) * 2.5, 0]))
        ao = (0.74 + 0.3 * tt) * (0.78 + 0.28 * rr / max(R, 1e-3)) * (0.82 + 0.18 * min(1.0, (y - y0) / 4))
        T.card(p, nn, w, hh, REG["poplar"][rs.integers(4)], ao, roll=rs.normal(0, 0.05))
    n_core = 6 if lod == 0 else 3
    for k in range(n_core):                              # тёмная сердцевина колонны
        tt = (k + 0.5) / n_core * 0.85
        y = y0 + 1.5 + tt * (hc - 3.0)
        R = _poplar_r(tt)
        T.card((0.08 * tt + rs.normal(0, 0.1), y, 0.05 * tt + rs.normal(0, 0.1)), _rand_dir(rs), 1.5 * R + 0.2,
               (hc / n_core) * 1.9, REG["poplar"][rs.integers(4)], 0.42, roll=rs.normal(0, 0.05))
    return T.mesh()


# ---------------------------------------------------------------- ива

def willow(seed, lod=0):
    """Тал (плакучая ива): короткий наклонный (в +X, к воде) ствол, дуги ветвей, невысокий
    купол и «каскады» прядей по всему краю купола: прядь дугой уходит наружу и свисает почти
    до земли. Каскады разной длины (низ «колокола» волной, с просветами), внутренние темнее —
    не «занавеска»."""
    T = Tree(seed, 9.5)
    rs = T.rs
    top = np.array([1.3, 2.7, 0.1])
    path = _curve([(0, 0, 0), (0.45, 1.05, 0.02), (0.92, 2.0, 0.06), top], 5 if lod == 0 else 4)
    T.wood(path, _flare(len(path), 0.5, 0.36, 0.55, 5), 8 if lod == 0 else 6, REG["bark_willow"], 0.55, 0.8, 0, 0.4)
    cc = np.array([1.9, 6.5, 0.0])
    cr = np.array([4.0, 2.3, 4.0])
    nl = 5 if lod == 0 else 3
    a0 = rs.uniform(0, 2 * np.pi)
    for k in range(nl):                                  # дуги ветвей: вверх, наружу и вниз
        a = a0 + k * 2 * np.pi / nl + rs.normal(0, 0.25)
        d = np.array([math.cos(a), 0, math.sin(a)])
        p1 = top + d * 0.6 + np.array([0.25, 1.6, 0])
        p2 = cc + d * cr[0] * 0.5 + np.array([0, 1.3, 0])
        p3 = cc + d * cr[0] * 0.92 + np.array([0, -0.2, 0])
        n = 5 if lod == 0 else 4
        T.wood(_curve([top, p1, p2, p3], n), np.linspace(0.26, 0.05, n), 5 if lod == 0 else 4, REG["bark_willow"],
               0.75, 0.6, 0.4, 1.0)
    # купол: невысокие лопасти сверху (короткие свисающие листья)
    lobes = [(cc + np.array([0.0, cr[1] * 0.42, 0.0]), np.array([2.3, 1.2, 2.3]))]
    for k in range(5):
        a = a0 + k * 2 * np.pi / 5 + rs.normal(0, 0.25)
        d = np.array([math.cos(a), 0.0, math.sin(a)])
        lobes.append((cc + d * cr * 0.5 + np.array([0, cr[1] * 0.15, 0]), np.array([2.0, 1.2, 2.0])))
    for (c, lr) in lobes:
        _mass(T, c, lr, 6 if lod == 0 else 3, (2.0, 2.6) if lod == 0 else (2.6, 3.3), REG["willow"], cc, cr,
              k_lobe=0.5, out_bias=-0.2, up_bias=0.3, kind=3)
    # каскады: наружный слой по всему краю купола и внутренний (темнее) ближе к стволу.
    # Длина каскада зависит от азимута плавно (низ «колокола» волной) и от случая (рваный край)
    ph = rs.uniform(0, 6.28, 2)
    for layer, count, rr, ao, el in ((0, 40 if lod == 0 else 17, (0.86, 1.04), 1.0, (-12, 48)),
                                    (1, 12 if lod == 0 else 5, (0.42, 0.66), 0.5, (0, 35))):
        for j in range(count):
            a = a0 + (j + rs.uniform(-0.35, 0.35)) * 2 * np.pi / count
            e = math.radians(rs.uniform(*el))
            d = np.array([math.cos(a) * math.cos(e), math.sin(e), math.sin(a) * math.cos(e)])
            p = cc + d * cr * rs.uniform(*rr)
            hem = 1.3 + 0.8 * math.sin(2 * a + ph[0]) + 0.5 * math.sin(3 * a + ph[1]) + rs.uniform(-0.5, 0.9)
            h = float(np.clip(p[1] + 0.3 - hem, 2.4, 7.0))
            w = rs.uniform(2.0, 2.7) * (1.15 if lod else 1.0)
            T.card(p + np.array([0, 0.3, 0]), [d[0], 0, d[2]], w, h, REG["strand"][rs.integers(4)],
                   ao * rs.uniform(0.9, 1.05) * (0.85 + 0.15 * math.sin(e + 0.4)), kind=2, mirror=False)
    return T.mesh()


# ---------------------------------------------------------------- арча

def juniper(seed, lod=0):
    """Арча: старое кривое дерево склонов. Толстый красноватый ствол винтом, у комля отводок,
    ветви-локти; неровная тёмная сизо-зелёная крона из плотных плоских комков хвои, прижатая
    ветром к одной стороне (+X), с просветами, где виден ствол; сухой серебристый сук.
    Высота 6–7 м."""
    rs0 = np.random.default_rng(seed)
    H = float(rs0.uniform(6.0, 7.0))
    T = Tree(seed, H)
    rs = T.rs
    lean = np.array([rs.uniform(0.9, 1.4), 0, rs.uniform(-0.3, 0.3)])
    pts = [np.zeros(3)]
    tw = rs.uniform(0, 6.28)
    for i in range(1, 6):
        t = i / 5
        wob = np.array([math.cos(tw + t * 4.6), 0, math.sin(tw + t * 4.6)]) * 0.5 * math.sin(t * math.pi)
        pts.append(lean * t ** 1.3 + wob + np.array([0, H * 0.68 * t, 0]))
    trunk = _curve(pts, 7 if lod == 0 else 5)
    T.wood(trunk, _flare(len(trunk), 0.36, 0.1, 0.9, 4), 7 if lod == 0 else 5, REG["bark_juniper"], 0.5, 0.85,
           0.0, 0.75)
    if lod == 0:                                         # второй, тонкий ствол-отводок
        b0 = trunk[1] * 0.5
        a = tw + 2.0
        d = np.array([math.cos(a), 0, math.sin(a)])
        s2 = _curve([b0, b0 + d * 0.6 + np.array([0, 1.3, 0]), b0 + d * 1.0 + np.array([0, 2.6, 0]) + lean * 0.3], 4)
        T.wood(s2, np.linspace(0.16, 0.06, 4), 5, REG["bark_juniper"], 0.5, 0.8, 0.0, 0.6)
    clumps = []
    nlimb = 5
    a0 = rs.uniform(0, 2 * np.pi)
    for k in range(nlimb):
        t = 0.3 + 0.55 * k / max(nlimb - 1, 1)
        i = min(int(t * (len(trunk) - 1)), len(trunk) - 2)
        base = trunk[i]
        a = a0 + k * 2.3 + rs.normal(0, 0.3)
        d = np.array([math.cos(a), 0, math.sin(a)])
        d = _unit(d + np.array([0.45, 0, 0]))            # крона прижата ветром к +X
        L = rs.uniform(1.4, 2.2) * (1.15 - 0.3 * t)
        mid = base + d * L * 0.45 + np.array([0, 0.5, 0]) + rs.normal(0, 0.15, 3)  # «локоть»
        tip = base + d * L + np.array([0, rs.uniform(0.2, 0.6), 0]) + lean * 0.2
        n = 4 if lod == 0 else 2
        T.wood(_curve([base, mid, tip], n), np.linspace(0.14, 0.05, n), 5 if lod == 0 else 3, REG["bark_juniper"],
               0.6, 0.8, 0.0, 0.75)
        r = rs.uniform(1.1, 1.45) * (1.1 - 0.25 * t)
        clumps.append((tip + np.array([0, 0.25, 0]), np.array([r, r * rs.uniform(0.4, 0.5), r])))
    clumps.append((trunk[-1] + np.array([0.2, 0.2, 0]), np.array([1.3, 0.7, 1.2])))
    if lod == 0:                                         # сухой серебристый сук
        b = trunk[len(trunk) - 3]
        a = a0 + 1.2
        d = np.array([math.cos(a), 0, math.sin(a)])
        T.wood(_curve([b, b + d * 0.7 + np.array([0, 0.8, 0]), b + d * 1.1 + np.array([0, 1.8, 0])], 3),
               np.linspace(0.08, 0.025, 3), 3, REG["bark_juniper"], 1.0, 1.0, 0.8, 0.98)
    cc = np.mean([p for p, _ in clumps], axis=0)
    cr = np.array([2.4, H * 0.38, 2.4])
    for (c, r) in clumps:
        _mass(T, c, r, 11 if lod == 0 else 7, (1.5, 2.0) if lod == 0 else (1.75, 2.3), REG["juniper"], cc, cr,
              k_lobe=0.7, ao_mul=0.95, spread=(0.15, 0.8), out_bias=-0.2, roll=0.25, aspect=0.55, up_bias=0.0)
    return T.mesh()


# ---------------------------------------------------------------- валуны (без изменений)

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
    m.P[:, 1] -= m.P[:, 1].min()                        # основание на земле (утапливает расстановка)
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
    args = set(sys.argv[1:])
    if "--models" not in args:
        print("атлас деревьев…")
        build_atlas()
    if "--atlas" in args:
        return
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
    if "--trees" in args or "--models" in args:
        return
    for k in range(4):
        for lod in (0, 1):
            path = os.path.join(OUT_MODELS, f"rock_{k}{'_lod1' if lod else ''}.glb")
            write_glb(path, [(f"rock_{k}", boulder(40 + k, lod), rock_mat)])
            st = read_glb_stats(path)
            print(f"   {os.path.basename(path)}: {st['triangles']} треуг., размер {st['size']}")


if __name__ == "__main__":
    main()
