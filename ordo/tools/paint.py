"""Рисованные текстуры Ордо: одна «рука» для всех текстур (ТЗ 11.1).

Видимые мазки кисти, свет и тень частично нарисованы цветом, мягкие
градиенты, без фотошума и «пластика». Всё процедурно и воспроизводимо (seed).

    from paint import Canvas, fbm
    c = Canvas(512, 512, base="#e6dcc4", seed=3)
    c.underpaint(["#e6dcc4", "#d8ccb0", "#f0e8d2"], cell=96)
    c.strokes(1800, ["#efe6cf", "#d4c7a8"], length=(10, 26), width=(3, 6), angle=0, alpha=(0.25, 0.6))
    c.grain(0.04)
    c.save("felt.png")

Координаты в пикселях итоговой текстуры, начало — левый верхний угол
(v в glTF тоже растёт вниз, так что UV = x / w, y / h).
"""
from __future__ import annotations

import math
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

from palette import rgb8


# ---------------------------------------------------------------- шум

def value_noise(w, h, cell, seed=0, tile=True):
    """Гладкий шум 0..1, бесшовный при tile=True."""
    rs = np.random.default_rng(seed)
    gx, gy = _div_near(w, w / cell), _div_near(h, h / cell)
    g = rs.random((gy, gx)).astype(np.float32)
    if tile:
        cw, ch = w // gx, h // gy
        g = np.pad(g, 2, mode="wrap")
        big = Image.fromarray(g, mode="F").resize(((gx + 4) * cw, (gy + 4) * ch), Image.BICUBIC)
        a = np.asarray(big, dtype=np.float64)[2 * ch:2 * ch + h, 2 * cw:2 * cw + w]
    else:
        a = np.asarray(Image.fromarray(g, mode="F").resize((w, h), Image.BICUBIC), dtype=np.float64)
    return np.clip(a, 0, 1)


def _div_near(n, target):
    """Делитель n, ближайший к target (чтобы сетка шума ложилась ровно и шум был бесшовным)."""
    target = max(1.0, target)
    divs = [d for d in range(1, n + 1) if n % d == 0]
    return min(divs, key=lambda d: abs(math.log(d / target)))


def fbm(w, h, cell=64, octaves=4, gain=0.5, seed=0, tile=True):
    """Фрактальный шум 0..1."""
    acc, amp, tot = np.zeros((h, w)), 1.0, 0.0
    for o in range(octaves):
        c = max(2, cell / (2 ** o))
        acc += amp * value_noise(w, h, c, seed + 101 * o, tile)
        tot += amp
        amp *= gain
    a = acc / tot
    lo, hi = np.percentile(a, 1), np.percentile(a, 99)
    return np.clip((a - lo) / max(hi - lo, 1e-9), 0, 1)


# ---------------------------------------------------------------- холст

class Canvas:
    """Холст с суперсэмплингом (ss) для чистых краёв мазков."""

    def __init__(self, w, h, base="#808080", ss=2, tile=True, seed=0):
        self.w, self.h, self.ss, self.tile = w, h, ss, tile
        self.rs = np.random.default_rng(seed)
        self.seed = seed
        self.img = Image.new("RGB", (w * ss, h * ss), rgb8(base) if isinstance(base, str) else base)
        self.draw = ImageDraw.Draw(self.img, "RGBA")

    # --- основа: пятнистая подмалёвка из нескольких цветов
    def underpaint(self, colors, cell=96, octaves=3, seed=None, mask=None):
        s = self.seed if seed is None else seed
        W, H = self.w * self.ss, self.h * self.ss
        n = fbm(W, H, cell * self.ss, octaves, seed=s, tile=self.tile)
        cols = np.array([rgb8(c) for c in colors], dtype=np.float64)
        t = n * (len(cols) - 1)
        i = np.clip(t.astype(int), 0, len(cols) - 2)
        f = (t - i)[..., None]
        f = f * f * (3 - 2 * f)  # мягкие переходы, как растушёвка
        out = cols[i] * (1 - f) + cols[i + 1] * f
        self._blend(out, mask)
        return self

    def gradient(self, top, bottom, strength=1.0, axis="y", mask=None):
        """Нарисованный свет: тон сверху вниз (или слева направо). Умножение."""
        W, H = self.w * self.ss, self.h * self.ss
        t = np.linspace(0, 1, H if axis == "y" else W)
        a, b = np.array(rgb8(top), float) / 255, np.array(rgb8(bottom), float) / 255
        g = a[None] * (1 - t[:, None]) + b[None] * t[:, None]
        g = g[:, None, :] if axis == "y" else g[None, :, :]
        base = np.asarray(self.img, dtype=np.float64)
        out = base * (1 - strength + strength * g)
        self._blend(out, mask)
        return self

    def _blend(self, rgb_arr, mask=None):
        base = np.asarray(self.img, dtype=np.float64)
        if mask is not None:
            m = self._mask(mask)[..., None]
            rgb_arr = base * (1 - m) + rgb_arr * m
        self.img = Image.fromarray(np.clip(rgb_arr, 0, 255).astype(np.uint8), "RGB")
        self.draw = ImageDraw.Draw(self.img, "RGBA")

    def _mask(self, mask):
        m = np.asarray(mask, dtype=np.float64)
        if m.shape != (self.h * self.ss, self.w * self.ss):
            m = np.asarray(Image.fromarray((np.clip(m, 0, 1) * 255).astype(np.uint8)).resize(
                (self.w * self.ss, self.h * self.ss), Image.BILINEAR), dtype=np.float64) / 255
        return m

    # --- мазки
    def strokes(self, n, colors, length=(8, 24), width=(3, 7), angle=0.0, angle_jitter=12.0,
                alpha=(0.3, 0.75), value_jitter=0.07, curve=0.25, bristles=4, region=None,
                density_map=None, taper=0.55):
        """Мазки кисти. angle — градусы (0 = вправо) или функция (x, y) → градусы.
        region — (x0, y0, x1, y1) в пикселях. density_map — массив h×w 0..1 (где гуще)."""
        rs = self.rs
        x0, y0, x1, y1 = region or (0, 0, self.w, self.h)
        cols = [np.array(rgb8(c), float) for c in colors]
        placed = 0
        tries = 0
        while placed < n and tries < n * 20:
            tries += 1
            x, y = rs.uniform(x0, x1), rs.uniform(y0, y1)
            if density_map is not None:
                dm = density_map[min(int(y), density_map.shape[0] - 1), min(int(x), density_map.shape[1] - 1)]
                if rs.random() > dm:
                    continue
            placed += 1
            a = angle(x, y) if callable(angle) else angle
            a = math.radians(a + rs.normal(0, angle_jitter))
            L = rs.uniform(*length)
            W = rs.uniform(*width)
            c = cols[rs.integers(len(cols))] * (1 + rs.normal(0, value_jitter))
            c = c + rs.normal(0, value_jitter * 40, 3) * 0.3
            al = rs.uniform(*alpha)
            bend = rs.normal(0, curve)
            self._stroke(x, y, a, L, W, c, al, bend, bristles, taper)
        return self

    def _stroke(self, x, y, a, L, W, col, alpha, bend, bristles, taper):
        ss = self.ss
        k = 7
        t = np.linspace(-0.5, 0.5, k)
        dx, dy = math.cos(a), math.sin(a)
        nx, ny = -dy, dx
        off = bend * L * (t ** 2 - 0.25)
        px = x + dx * t * L + nx * off
        py = y + dy * t * L + ny * off
        # ширина: мазок толще в начале, сходит на нет к концу
        wprof = W * (1 - taper * np.clip((t + 0.5) ** 1.6, 0, 1)) * (0.75 + 0.25 * np.sin(np.pi * (t + 0.5)) ** 0.5)
        left = [(px[i] + nx * wprof[i] / 2, py[i] + ny * wprof[i] / 2) for i in range(k)]
        right = [(px[i] - nx * wprof[i] / 2, py[i] - ny * wprof[i] / 2) for i in range(k)][::-1]
        poly = left + right
        fill = tuple(int(np.clip(v, 0, 255)) for v in col) + (int(alpha * 255),)
        for ox, oy in self._wraps(x, y, L + W):
            self.draw.polygon([((u + ox) * ss, (v + oy) * ss) for u, v in poly], fill=fill)
        # щетина: тонкие полоски вдоль мазка светлее и темнее
        for b in range(bristles):
            s = self.rs.uniform(-0.45, 0.45)
            shade = self.rs.uniform(-0.12, 0.12)
            bc = np.clip(col * (1 + shade), 0, 255)
            bf = tuple(int(v) for v in bc) + (int(alpha * 255 * 0.55),)
            pts = [(px[i] + nx * wprof[i] * s, py[i] + ny * wprof[i] * s) for i in range(k - 1)]
            for ox, oy in self._wraps(x, y, L + W):
                self.draw.line([((u + ox) * ss, (v + oy) * ss) for u, v in pts], fill=bf,
                               width=max(1, int(W * ss * 0.12)))

    def _wraps(self, x, y, r):
        if not self.tile:
            return [(0, 0)]
        xs = [0] + ([self.w] if x - r < 0 else []) + ([-self.w] if x + r > self.w else [])
        ys = [0] + ([self.h] if y - r < 0 else []) + ([-self.h] if y + r > self.h else [])
        return [(a, b) for a in xs for b in ys]

    # --- линии «от руки» для орнамента
    def line(self, pts, width, color, alpha=1.0, wobble=0.6, width_jitter=0.25, seed=None):
        """Линия кистью: дрожь руки и переменная ширина. pts — ломаная в пикселях."""
        rs = np.random.default_rng(abs(self.seed + 7 if seed is None else seed))
        pts = np.asarray(pts, dtype=np.float64)
        seglen = np.linalg.norm(np.diff(pts, axis=0), axis=1)
        total = seglen.sum()
        if total <= 0:
            return self
        n = max(2, int(total / max(width * 0.25, 0.5)))
        s = np.linspace(0, total, n)
        cum = np.r_[0, np.cumsum(seglen)]
        x = np.interp(s, cum, pts[:, 0])
        y = np.interp(s, cum, pts[:, 1])
        ph = rs.uniform(0, 6.28, 3)
        w = width * (1 + width_jitter * np.sin(s / (width * 6) + ph[0]))
        x = x + wobble * np.sin(s / (width * 9) + ph[1])
        y = y + wobble * np.sin(s / (width * 11) + ph[2])
        fill = rgb8(color) + (int(alpha * 255),)
        ss = self.ss
        for xi, yi, wi in zip(x, y, w):
            r = wi * ss / 2
            for ox, oy in self._wraps(xi, yi, wi):
                cx, cy = (xi + ox) * ss, (yi + oy) * ss
                self.draw.ellipse([cx - r, cy - r, cx + r, cy + r], fill=fill)
        return self

    def polygon(self, pts, color, alpha=1.0, wobble=0.5, seed=None):
        rs = np.random.default_rng(abs(self.seed + 11 if seed is None else seed))
        p = np.asarray(pts, dtype=np.float64) + rs.normal(0, wobble, (len(pts), 2))
        fill = rgb8(color) + (int(alpha * 255),)
        cx, cy = p.mean(0)
        for ox, oy in self._wraps(cx, cy, np.ptp(p[:, 0]) + np.ptp(p[:, 1])):
            self.draw.polygon([((u + ox) * self.ss, (v + oy) * self.ss) for u, v in p], fill=fill)
        return self

    def ellipse(self, cx, cy, rx, ry, color, alpha=1.0):
        fill = rgb8(color) + (int(alpha * 255),)
        ss = self.ss
        self.draw.ellipse([(cx - rx) * ss, (cy - ry) * ss, (cx + rx) * ss, (cy + ry) * ss], fill=fill)
        return self

    def rect(self, x0, y0, x1, y1, color, alpha=1.0):
        fill = rgb8(color) + (int(alpha * 255),)
        ss = self.ss
        self.draw.rectangle([x0 * ss, y0 * ss, x1 * ss, y1 * ss], fill=fill)
        return self

    # --- отделка
    def grain(self, amount=0.04, cell=1.5):
        """Мелкая фактура холста/войлока поверх (без фотошума: мягкая, низкий контраст)."""
        W, H = self.w * self.ss, self.h * self.ss
        n = value_noise(W, H, cell * self.ss, seed=self.seed + 5, tile=self.tile) - 0.5
        base = np.asarray(self.img, dtype=np.float64)
        self._blend(base * (1 + amount * 2 * n[..., None]))
        return self

    def soften(self, radius=0.6):
        self.img = self.img.filter(ImageFilter.GaussianBlur(radius * self.ss))
        self.draw = ImageDraw.Draw(self.img, "RGBA")
        return self

    def image(self) -> Image.Image:
        return self.img.resize((self.w, self.h), Image.LANCZOS)

    def save(self, path):
        os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
        im = self.image()
        im.save(path, optimize=True)
        return im


# ---------------------------------------------------------------- орнаменты

def spiral_points(cx, cy, r, turns=1.5, start=0.0, direction=1, n=48):
    """Завиток (основа «кочкор мүйүз» — бараньих рогов): архимедова спираль внутрь."""
    t = np.linspace(0, 1, n)
    ang = start + direction * t * turns * 2 * np.pi
    rad = r * (1 - 0.85 * t)
    return np.column_stack([cx + rad * np.cos(ang), cy + rad * np.sin(ang)])


def ram_horn(c: Canvas, cx, cy, size, color, width, alpha=1.0, seed=0):
    """Мотив «кочкор мүйүз»: ствол и два рога, закрученных наружу."""
    stem = np.array([[cx, cy + size * 0.55], [cx, cy - size * 0.05]])
    c.line(stem, width, color, alpha, seed=seed)
    for d in (-1, 1):
        arc = np.array([[cx, cy - size * 0.05], [cx + d * size * 0.25, cy - size * 0.35],
                        [cx + d * size * 0.55, cy - size * 0.30]])
        sp = spiral_points(cx + d * size * 0.55, cy - size * 0.05, size * 0.26, turns=1.2,
                           start=-np.pi / 2, direction=d, n=40)
        c.line(np.vstack([arc, sp]), width, color, alpha, seed=seed * 2 + (d > 0))


def rhomb(c: Canvas, cx, cy, rx, ry, color, alpha=1.0, outline=None, width=2.0, wobble=0.5):
    pts = [(cx, cy - ry), (cx + rx, cy), (cx, cy + ry), (cx - rx, cy)]
    c.polygon(pts, color, alpha, wobble)
    if outline:
        c.line(pts + [pts[0]], width, outline, alpha, wobble=wobble * 0.5)


def to_rgba(img: Image.Image, alpha: np.ndarray) -> Image.Image:
    a = Image.fromarray((np.clip(alpha, 0, 1) * 255).astype(np.uint8), "L").resize(img.size, Image.BILINEAR)
    out = img.convert("RGBA")
    out.putalpha(a)
    return out
